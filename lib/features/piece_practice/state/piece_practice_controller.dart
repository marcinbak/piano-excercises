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
        practiceChordWindowProvider,
        practiceClockMsProvider,
        practiceHandModeProvider,
        practicePausedProvider,
        practiceSuccessHoldDurationProvider;

/// Orchestrates polyphonic Wait-Mode evaluation, cursor advancement, and measure loops.
class PiecePracticeController extends Notifier<PracticeSessionState> {
  PiecePracticeController(this.arg);

  final PracticeSessionKey arg;

  late MidiChordCoalescer _coalescer;
  late Duration _successHoldDuration;
  Timer? _correctHoldTimer;

  bool get isPaused => _coalescer.isPaused;

  @override
  PracticeSessionState build() {
    _successHoldDuration = ref.watch(practiceSuccessHoldDurationProvider);
    _coalescer = MidiChordCoalescer(
      chordWindow: ref.watch(practiceChordWindowProvider),
      clockMs: ref.watch(practiceClockMsProvider),
      onFlush: _onChordFlush,
    );
    _coalescer.setPaused(ref.read(practicePausedProvider));
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
    if (paused && state.isShowingCorrect) {
      _cancelCorrectHoldTimer();
      state = state.completeMatchHold(
        arg.score,
        ref.read(practiceHandModeProvider),
      );
    }
    _coalescer.setPaused(paused);
  }

  /// Restarts practice at the first playable slice (within any active loop).
  void restart() {
    if (!ref.mounted) {
      return;
    }
    _cancelCorrectHoldTimer();
    _coalescer.resetActivePrompt();
    state = state.restarted(arg.score, ref.read(practiceHandModeProvider));
  }

  /// Steps forward to the next playable slice in scope.
  void stepNext() {
    final current = state.activeSliceOrdinal;
    if (!ref.mounted || current == null) {
      return;
    }
    _cancelCorrectHoldTimer();
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
    _cancelCorrectHoldTimer();
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
    _cancelCorrectHoldTimer();
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
    final handMode = ref.read(practiceHandModeProvider);
    final base = _flushPendingHold(handMode);
    _coalescer.resetActivePrompt();
    state = base.withLoopRange(arg.score, range, handMode);
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
      isShowingCorrect: false,
    );
  }

  void _bindListeners() {
    final repository = ref.watch(midiRepositoryProvider);
    final noteSub = repository.noteEventsStream.listen(_coalescer.onNoteEvent);
    ref.onDispose(() {
      _cancelCorrectHoldTimer();
      unawaited(noteSub.cancel());
      _coalescer.dispose();
    });

    ref.listen<bool>(practicePausedProvider, (_, paused) => setPaused(paused));
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
        final base = _flushPendingHold(previous ?? next);
        _coalescer.resetActivePrompt();
        state = base.withHandMode(arg.score, next);
      }
    });
  }

  void _onChordFlush(MidiChordFlush flush) {
    if (!ref.mounted || _coalescer.isPaused) {
      return;
    }
    final handMode = ref.read(practiceHandModeProvider);
    if (state.isShowingCorrect) {
      state = _flushPendingHold(handMode);
    }
    final ordinal = state.activeSliceOrdinal;
    if (state.status != PracticeSessionStatus.active ||
        ordinal == null ||
        ordinal < 0 ||
        ordinal >= arg.score.slices.length) {
      return;
    }

    final slice = arg.score.slices[ordinal];
    final eval = PolyphonicEvaluator.evaluateSlice(
      slice: slice,
      handMode: handMode,
      playedPitches: flush.combinedNotes,
      activeKeySignature: ScorePracticeNavigator.activeKeySignatureAtSlice(
        arg.score,
        slice.sliceIndex,
      ),
    );
    final holdOnMatch = _successHoldDuration > Duration.zero;
    final outcome = state.applyEvaluation(
      arg.score,
      eval,
      handMode,
      holdOnMatch: holdOnMatch,
    );
    if (outcome.matched) {
      _coalescer.resetActivePrompt();
      state = outcome.nextState;
      if (holdOnMatch) {
        _cancelCorrectHoldTimer();
        _correctHoldTimer = Timer(_successHoldDuration, _onCorrectHoldComplete);
      }
      return;
    }
    state = outcome.nextState;
  }

  PracticeSessionState _flushPendingHold(HandMode handMode) {
    _cancelCorrectHoldTimer();
    return state.completeMatchHold(arg.score, handMode);
  }

  void _onCorrectHoldComplete() {
    _correctHoldTimer = null;
    if (!ref.mounted || !state.isShowingCorrect) {
      return;
    }
    state = state.completeMatchHold(
      arg.score,
      ref.read(practiceHandModeProvider),
    );
  }

  void _cancelCorrectHoldTimer() {
    _correctHoldTimer?.cancel();
    _correctHoldTimer = null;
  }
}

final piecePracticeControllerProvider = NotifierProvider.autoDispose
    .family<PiecePracticeController, PracticeSessionState, PracticeSessionKey>(
      PiecePracticeController.new,
    );
