import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/domain/measure_loop_range.dart';
import 'package:piano_exercises/features/piece_practice/domain/polyphonic_evaluator.dart';
import 'package:piano_exercises/features/piece_practice/domain/score_practice_navigator.dart';
import 'package:piano_exercises/features/piece_practice/state/piece_score_providers.dart';
import 'package:piano_exercises/features/piece_practice/state/practice_session_state.dart';
import 'package:piano_exercises/shared/music/music.dart';

export 'package:piano_exercises/features/piece_practice/state/piece_score_providers.dart'
    show
        PracticeHandModeNotifier,
        PracticePausedNotifier,
        PracticeRoutePausedNotifier,
        practiceChordWindowProvider,
        practiceClockMsProvider,
        practiceHandModeProvider,
        practicePausedProvider,
        practiceRoutePausedProvider;

/// Orchestrates polyphonic Wait-Mode evaluation, cursor advancement, and measure loops.
class PiecePracticeController extends Notifier<PracticeSessionState> {
  PiecePracticeController(this.arg);

  final PracticeSessionKey arg;

  late MidiChordCoalescer _coalescer;

  bool get isPaused => _coalescer.isPaused;

  @override
  PracticeSessionState build() {
    _coalescer = MidiChordCoalescer(
      chordWindow: ref.watch(practiceChordWindowProvider),
      clockMs: ref.watch(practiceClockMsProvider),
      onFlush: _onChordFlush,
    );
    _coalescer.setPaused(_computeEffectivePaused());
    _bindListeners();
    return PracticeSessionState.initial(
      arg.score,
      ref.read(practiceHandModeProvider),
    );
  }

  /// Pauses or resumes Wait-Mode evaluation while preserving held-key carryover.
  void setPaused(bool paused) {
    if (!ref.mounted) {
      return;
    }
    _coalescer.setPaused(paused);
  }

  /// Restarts practice at the first playable slice (within any active loop).
  void restart() {
    if (!ref.mounted) {
      return;
    }
    _coalescer.resetActivePrompt();
    state = state.restarted(arg.score, ref.read(practiceHandModeProvider));
  }

  /// Steps forward to the next playable slice in scope.
  void stepNext() {
    final current = state.activeSliceOrdinal;
    if (!ref.mounted || current == null) {
      return;
    }
    _moveCursorTo(
      ScorePracticeNavigator.nextPlayableOrdinal(
        arg.score,
        current,
        ref.read(practiceHandModeProvider),
        loopRange: state.loopRange,
      ),
    );
  }

  /// Steps backward to the previous playable slice in scope.
  void stepPrevious() {
    final current = state.activeSliceOrdinal;
    if (!ref.mounted || current == null) {
      return;
    }
    _moveCursorTo(
      ScorePracticeNavigator.previousPlayableOrdinal(
        arg.score,
        current,
        ref.read(practiceHandModeProvider),
        loopRange: state.loopRange,
      ),
    );
  }

  /// Seeks to [sliceOrdinal] (snapping to nearest playable slice and clearing out-of-range loops).
  void seekToSlice(int sliceOrdinal) {
    if (!ref.mounted || arg.score.slices.isEmpty) {
      return;
    }
    _coalescer.resetActivePrompt();
    state = state.soughtTo(
      arg.score,
      sliceOrdinal,
      ref.read(practiceHandModeProvider),
    );
  }

  /// Applies or clears a [MeasureLoopRange], clamping bounds to the active score.
  void setLoopRange(MeasureLoopRange? range) {
    if (!ref.mounted) {
      return;
    }
    _coalescer.resetActivePrompt();
    state = state.withLoopRange(
      arg.score,
      range,
      ref.read(practiceHandModeProvider),
    );
  }

  void _moveCursorTo(int? ordinal) {
    if (ordinal == null) {
      return;
    }
    _coalescer.resetActivePrompt();
    state = state.copyWith(
      activeSliceOrdinal: ordinal,
      status: PracticeSessionStatus.active,
      wrongPlayedNotes: const <StaffNote>[],
    );
  }

  void _bindListeners() {
    final repository = ref.watch(midiRepositoryProvider);
    final noteSub = repository.noteEventsStream.listen(_coalescer.onNoteEvent);
    ref.onDispose(() {
      unawaited(noteSub.cancel());
      _coalescer.dispose();
    });

    ref.listen<bool>(practicePausedProvider, (_, _) {
      setPaused(_computeEffectivePaused());
    });
    ref.listen<bool>(practiceRoutePausedProvider(arg.routeId), (_, _) {
      setPaused(_computeEffectivePaused());
    });
    ref.listen<AsyncValue<List<MidiDeviceInfo>>>(midiDevicesProvider, (
      _,
      next,
    ) {
      final devices = next.value;
      if (devices != null) {
        _coalescer.syncConnectedDevices(devices);
      }
    }, fireImmediately: true);
    ref.listen<HandMode>(practiceHandModeProvider, (previous, next) {
      if (previous != next && ref.mounted) {
        _coalescer.resetActivePrompt();
        state = state.withHandMode(arg.score, next);
      }
    });
  }

  void _onChordFlush(MidiChordFlush flush) {
    final ordinal = state.activeSliceOrdinal;
    if (!ref.mounted ||
        _coalescer.isPaused ||
        state.status != PracticeSessionStatus.active ||
        ordinal == null ||
        ordinal < 0 ||
        ordinal >= arg.score.slices.length) {
      return;
    }

    final slice = arg.score.slices[ordinal];
    final handMode = ref.read(practiceHandModeProvider);
    final eval = PolyphonicEvaluator.evaluateSlice(
      slice: slice,
      handMode: handMode,
      playedPitches: flush.combinedNotes,
      activeKeySignature: ScorePracticeNavigator.activeKeySignatureAtSlice(
        arg.score,
        slice.sliceIndex,
      ),
    );
    final outcome = state.applyEvaluation(arg.score, eval, handMode);
    if (outcome.matched) {
      _coalescer.resetActivePrompt();
    }
    state = outcome.nextState;
  }

  bool _computeEffectivePaused() =>
      ref.read(practicePausedProvider) ||
      ref.read(practiceRoutePausedProvider(arg.routeId));
}

final piecePracticeControllerProvider = NotifierProvider.autoDispose
    .family<PiecePracticeController, PracticeSessionState, PracticeSessionKey>(
      PiecePracticeController.new,
    );
