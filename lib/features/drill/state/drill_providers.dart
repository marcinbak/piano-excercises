import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/drill/domain/drill_session.dart';
import 'package:piano_exercises/features/drill/domain/note_prompt_selector.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/progression/progression.dart';
import 'package:piano_exercises/shared/music/music.dart';

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
  late Duration _chordWindow;

  final Set<MidiNote> _promptHeldNotes = <MidiNote>{};
  final Set<MidiNote> _carryoverHeldNotes = <MidiNote>{};
  final Map<String, Set<MidiNote>> _heldByDevice = <String, Set<MidiNote>>{};
  final Set<String> _knownConnectedDeviceIds = <String>{};
  final Set<MidiNote> _pendingBatchNotes = <MidiNote>{};

  int? _pendingAttemptStartedAtMs;
  Timer? _coalesceTimer;
  bool _isResetting = false;
  bool _isPaused = false;

  bool get isPaused => _isPaused;

  @override
  DrillSessionState build() {
    _cancelPendingAttempt();
    _promptHeldNotes.clear();
    _carryoverHeldNotes.clear();
    _heldByDevice.clear();
    _knownConnectedDeviceIds.clear();
    _isResetting = false;
    _isPaused = false;

    _selector = NotePromptSelector(nextInt: ref.watch(drillRandomIntProvider));
    _clockMs = ref.watch(drillClockMsProvider);
    _chordWindow = ref.watch(drillChordWindowProvider);
    final repository = ref.watch(midiRepositoryProvider);

    // Subscribe directly instead of StreamProvider so rapid synchronous Note On/Off
    // events in the same microtask cannot coalesce and drop.
    final noteSubscription = repository.noteEventsStream.listen(
      _onMidiNoteEvent,
    );
    ref.onDispose(() {
      unawaited(noteSubscription.cancel());
      _cancelPendingAttempt();
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
        _syncConnectedDevices(devices);
      }
    }, fireImmediately: true);

    final initialStage = ref.read(progressionControllerProvider).activeStage;
    return DrillSessionState(
      targetNote: _selector.selectFromPool(initialStage.cumulativeNotes),
      promptStartedAtMs: _clockMs(),
    );
  }

  /// Pauses or resumes prompt evaluation while preserving held-key tracking.
  void setPaused(bool paused) {
    if (!ref.mounted || paused == _isPaused) {
      return;
    }
    if (paused) {
      _isPaused = true;
      _cancelPendingAttempt();
      _carryoverHeldNotes.addAll(_promptHeldNotes);
      _promptHeldNotes.clear();
      return;
    }
    _isPaused = false;
    _promptHeldNotes.clear();
    for (final held in _heldByDevice.values) {
      _carryoverHeldNotes.addAll(held);
    }
  }

  /// Resets drill progression to Stage 1 and starts a clean prompt.
  void resetSession() {
    _cancelPendingAttempt();
    _carryoverHeldNotes.addAll(_promptHeldNotes);
    _promptHeldNotes.clear();
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

  void _onStageChanged(StageId nextStageId) {
    _cancelPendingAttempt();
    _carryoverHeldNotes.addAll(_promptHeldNotes);
    _promptHeldNotes.clear();
    final nextStage = ProgressionCatalog.byId(nextStageId);
    state = DrillSessionState(
      targetNote: _selector.selectFromPool(
        nextStage.cumulativeNotes,
        previous: state.targetNote,
      ),
      promptStartedAtMs: _clockMs(),
    );
  }

  void _onMidiNoteEvent(MidiNoteEvent event) {
    if (!ref.mounted) {
      return;
    }
    final note = event.note;
    if (event.isNoteOn) {
      _heldByDevice.putIfAbsent(event.deviceId, () => <MidiNote>{}).add(note);
      if (_isPaused) {
        _carryoverHeldNotes.add(note);
        return;
      }
      _carryoverHeldNotes.remove(note);
      _promptHeldNotes.add(note);

      if (_coalesceTimer == null) {
        _pendingAttemptStartedAtMs = _clockMs();
        _pendingBatchNotes
          ..clear()
          ..addAll(_promptHeldNotes);
        if (_chordWindow <= Duration.zero) {
          _flushPendingAttempt();
        } else {
          _coalesceTimer = Timer(_chordWindow, _flushPendingAttempt);
        }
      } else {
        _pendingBatchNotes.add(note);
      }
      return;
    }

    final deviceHeld = _heldByDevice[event.deviceId];
    deviceHeld?.remove(note);
    if (deviceHeld != null && deviceHeld.isEmpty) {
      _heldByDevice.remove(event.deviceId);
    }
    final stillHeldElsewhere = _heldByDevice.values.any(
      (held) => held.contains(note),
    );
    if (!stillHeldElsewhere) {
      _promptHeldNotes.remove(note);
      _carryoverHeldNotes.remove(note);
    }
  }

  void _flushPendingAttempt() {
    _coalesceTimer = null;
    if (!ref.mounted || _pendingBatchNotes.isEmpty) {
      _pendingAttemptStartedAtMs = null;
      _pendingBatchNotes.clear();
      return;
    }

    final attemptStartedAtMs = _pendingAttemptStartedAtMs ?? _clockMs();
    final playedNotes = Set<MidiNote>.of(_pendingBatchNotes);
    _pendingBatchNotes.clear();
    _pendingAttemptStartedAtMs = null;

    final progressionNotifier = ref.read(
      progressionControllerProvider.notifier,
    );
    final evaluation = DrillEvaluator.evaluate(
      state: state,
      playedNotes: playedNotes,
      attemptStartedAtMs: attemptStartedAtMs,
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
      _carryoverHeldNotes.addAll(_promptHeldNotes);
      _promptHeldNotes.clear();
    }

    state = evaluation.nextState;
  }

  void _syncConnectedDevices(List<MidiDeviceInfo> devices) {
    final connectedIds = <String>{};
    final explicitlyDisconnectedIds = <String>{};
    for (final device in devices) {
      if (device.isConnected) {
        connectedIds.add(device.id);
      } else {
        explicitlyDisconnectedIds.add(device.id);
      }
    }

    final disconnectedIds = <String>{
      ...explicitlyDisconnectedIds,
      for (final knownId in _knownConnectedDeviceIds)
        if (!connectedIds.contains(knownId)) knownId,
    };

    _knownConnectedDeviceIds
      ..clear()
      ..addAll(connectedIds);

    for (final deviceId in disconnectedIds) {
      _releaseDeviceHeldNotes(deviceId);
    }
  }

  void _releaseDeviceHeldNotes(String deviceId) {
    final removed = _heldByDevice.remove(deviceId);
    if (removed == null || removed.isEmpty) {
      return;
    }
    final stillHeldElsewhere = <MidiNote>{
      for (final held in _heldByDevice.values) ...held,
    };
    for (final note in removed) {
      if (!stillHeldElsewhere.contains(note)) {
        _promptHeldNotes.remove(note);
        _carryoverHeldNotes.remove(note);
      }
    }
  }

  void _cancelPendingAttempt() {
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    _pendingBatchNotes.clear();
    _pendingAttemptStartedAtMs = null;
  }
}

final drillControllerProvider =
    NotifierProvider<DrillController, DrillSessionState>(DrillController.new);
