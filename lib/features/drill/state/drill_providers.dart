import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/drill/domain/drill_session.dart';
import 'package:piano_exercises/features/drill/domain/note_prompt_selector.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/progression/progression.dart';

/// Random index generator used by [NotePromptSelector]; overridable in tests.
final drillRandomIntProvider = Provider<NextInt>((ref) {
  final random = math.Random();
  return random.nextInt;
});

/// Monotonic millisecond clock used for reaction times; overridable in tests.
final drillClockMsProvider = Provider<int Function()>((ref) {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsedMilliseconds;
});

/// Coalescing window grouping near-simultaneous Note On events into chords.
final drillChordWindowProvider = Provider<Duration>((ref) {
  return const Duration(milliseconds: 35);
});

/// Orchestrates active prompts, 35ms chord coalescing, and progression updates.
class DrillController extends Notifier<DrillSessionState> {
  late NotePromptSelector _selector;
  late int Function() _clockMs;
  late MidiChordCoalescer _coalescer;
  bool _isResetting = false;

  bool get isPaused => _coalescer.isPaused;

  @override
  DrillSessionState build() {
    _isResetting = false;
    _selector = NotePromptSelector(nextInt: ref.watch(drillRandomIntProvider));
    _clockMs = ref.watch(drillClockMsProvider);
    _coalescer = MidiChordCoalescer(
      chordWindow: ref.watch(drillChordWindowProvider),
      clockMs: _clockMs,
      onFlush: _onChordFlush,
    );

    _bindListeners();

    final initialStage = ref.read(progressionControllerProvider).activeStage;
    return DrillSessionState(
      targetNote: _selector.selectFromPool(initialStage.cumulativeNotes),
      promptStartedAtMs: _clockMs(),
    );
  }

  /// Pauses or resumes prompt evaluation while preserving held-key tracking.
  void setPaused(bool paused) {
    if (!ref.mounted) {
      return;
    }
    _coalescer.setPaused(paused);
  }

  /// Resets drill progression to Stage 1 and starts a clean prompt.
  void resetSession() {
    _coalescer.resetActivePrompt();
    _isResetting = true;
    try {
      ref.read(progressionControllerProvider.notifier).reset();
    } finally {
      _isResetting = false;
    }
    final stage1 = ProgressionCatalog.byId(StageId.stage1);
    state = DrillSessionState(
      targetNote: _selector.selectFromPool(stage1.cumulativeNotes),
      promptStartedAtMs: _clockMs(),
    );
  }

  void _bindListeners() {
    final repository = ref.watch(midiRepositoryProvider);
    // Subscribe directly instead of StreamProvider so rapid synchronous Note On/Off
    // events in the same microtask cannot coalesce and drop.
    final noteSubscription = repository.noteEventsStream.listen(
      _coalescer.onNoteEvent,
    );
    ref.onDispose(() {
      unawaited(noteSubscription.cancel());
      _coalescer.dispose();
    });

    ref.listen<StageId>(
      progressionControllerProvider.select(
        (snapshot) => snapshot.activeStageId,
      ),
      (previousStageId, nextStageId) {
        if (previousStageId != nextStageId && !_isResetting) {
          _onStageChanged(nextStageId);
        }
      },
    );

    ref.listen<AsyncValue<List<MidiDeviceInfo>>>(midiDevicesProvider, (
      _,
      next,
    ) {
      final devices = next.value;
      if (devices != null) {
        _coalescer.syncConnectedDevices(devices);
      }
    }, fireImmediately: true);
  }

  void _onStageChanged(StageId nextStageId) {
    _coalescer.resetActivePrompt();
    final nextStage = ProgressionCatalog.byId(nextStageId);
    state = DrillSessionState(
      targetNote: _selector.selectFromPool(
        nextStage.cumulativeNotes,
        previous: state.targetNote,
      ),
      promptStartedAtMs: _clockMs(),
    );
  }

  void _onChordFlush(MidiChordFlush flush) {
    if (!ref.mounted || flush.batchNotes.isEmpty) {
      return;
    }

    final progressionNotifier = ref.read(
      progressionControllerProvider.notifier,
    );
    final evaluation = DrillEvaluator.evaluate(
      state: state,
      playedNotes: flush.batchNotes,
      attemptStartedAtMs: flush.startedAtMs,
      evaluatedAtMs: _clockMs(),
      selectNextTarget: (previousTarget) {
        final activeStage = ref.read(progressionControllerProvider).activeStage;
        return _selector.selectFromPool(
          activeStage.cumulativeNotes,
          previous: previousTarget,
        );
      },
    );

    switch (evaluation.result.progressionAction) {
      case DrillProgressionAction.recordCleanHit:
        progressionNotifier.recordAttempt(correct: true);
      case DrillProgressionAction.recordMistake:
        progressionNotifier.recordAttempt(correct: false);
      case DrillProgressionAction.none:
        break;
    }

    if (evaluation.result.status == DrillFeedbackStatus.correct) {
      // Carry still-held keys across prompt boundaries so legato releases do
      // not count as chords on the next prompt.
      _coalescer.resetActivePrompt();
    }

    state = evaluation.nextState;
  }
}

final drillControllerProvider =
    NotifierProvider<DrillController, DrillSessionState>(DrillController.new);
