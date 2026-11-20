import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/domain/measure_loop_range.dart';
import 'package:piano_exercises/features/piece_practice/domain/polyphonic_evaluator.dart';
import 'package:piano_exercises/features/piece_practice/domain/score_practice_navigator.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Family key scoping a [PiecePracticeController] to a variant, [Score], and route.
final class PracticeSessionKey {
  const PracticeSessionKey({
    required this.variantId,
    required this.score,
    this.routeId = 0,
  });

  final String variantId;
  final Score score;
  final int routeId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PracticeSessionKey &&
            other.variantId == variantId &&
            other.routeId == routeId &&
            identical(other.score, score));
  }

  @override
  int get hashCode => Object.hash(variantId, routeId, identityHashCode(score));
}

/// Lifecycle status of a Wait-Mode piece practice session.
enum PracticeSessionStatus { active, completed, noPlayableNotes }

/// Immutable state and pure transitions for a Wait-Mode piece practice session.
final class PracticeSessionState {
  PracticeSessionState({
    this.activeSliceOrdinal,
    this.status = PracticeSessionStatus.active,
    this.loopRange,
    List<StaffNote> wrongPlayedNotes = const <StaffNote>[],
    this.completedSlicesCount = 0,
    this.isShowingCorrect = false,
  }) : wrongPlayedNotes = List<StaffNote>.unmodifiable(wrongPlayedNotes);

  /// Creates initial state pointing to the first playable slice for [handMode].
  factory PracticeSessionState.initial(Score score, HandMode handMode) {
    final first = ScorePracticeNavigator.firstPlayableOrdinal(score, handMode);
    return PracticeSessionState(
      activeSliceOrdinal: first,
      status: first == null
          ? PracticeSessionStatus.noPlayableNotes
          : PracticeSessionStatus.active,
    );
  }

  final int? activeSliceOrdinal;
  final PracticeSessionStatus status;
  final MeasureLoopRange? loopRange;
  final List<StaffNote> wrongPlayedNotes;
  final int completedSlicesCount;
  final bool isShowingCorrect;

  PracticeSessionState copyWith({
    int? activeSliceOrdinal,
    PracticeSessionStatus? status,
    MeasureLoopRange? loopRange,
    List<StaffNote>? wrongPlayedNotes,
    int? completedSlicesCount,
    bool? isShowingCorrect,
  }) {
    return PracticeSessionState(
      activeSliceOrdinal: activeSliceOrdinal ?? this.activeSliceOrdinal,
      status: status ?? this.status,
      loopRange: loopRange ?? this.loopRange,
      wrongPlayedNotes: wrongPlayedNotes ?? this.wrongPlayedNotes,
      completedSlicesCount: completedSlicesCount ?? this.completedSlicesCount,
      isShowingCorrect: isShowingCorrect ?? this.isShowingCorrect,
    );
  }

  /// Resets progress to the first playable slice within the active [loopRange].
  PracticeSessionState restarted(Score score, HandMode handMode) {
    final first = ScorePracticeNavigator.firstPlayableOrdinal(
      score,
      handMode,
      loopRange: loopRange,
    );
    return PracticeSessionState(
      activeSliceOrdinal: first,
      status: first == null
          ? PracticeSessionStatus.noPlayableNotes
          : PracticeSessionStatus.active,
      loopRange: loopRange,
    );
  }

  /// Resolves cursor state after seeking to [sliceOrdinal], clearing out-of-range loops.
  PracticeSessionState soughtTo(
    Score score,
    int sliceOrdinal,
    HandMode handMode,
  ) {
    final clamped = sliceOrdinal.clamp(0, score.slices.length - 1);
    final measureIdx = ScorePracticeNavigator.measureIndexOfSliceOrdinal(
      score,
      clamped,
    );
    final nextLoop =
        (loopRange != null && !loopRange!.containsMeasureIndex(measureIdx))
        ? null
        : loopRange;
    final resolved = ScorePracticeNavigator.nearestPlayableOrdinalAtOrAfter(
      score,
      clamped,
      handMode,
      loopRange: nextLoop,
    );
    return _resolved(ordinal: resolved, nextLoop: nextLoop);
  }

  /// Resolves cursor state after applying or clearing [range].
  PracticeSessionState withLoopRange(
    Score score,
    MeasureLoopRange? range,
    HandMode handMode,
  ) {
    final clamped = range?.clampToMeasureCount(score.measures.length);
    final ordinal = _resolveOrdinalForLoop(score, clamped, handMode);
    return _resolved(ordinal: ordinal, nextLoop: clamped);
  }

  /// Resolves cursor state after changing [handMode].
  PracticeSessionState withHandMode(Score score, HandMode nextMode) {
    final resolved = ScorePracticeNavigator.nearestPlayableOrdinalAtOrAfter(
      score,
      activeSliceOrdinal ?? 0,
      nextMode,
      loopRange: loopRange,
    );
    return _resolved(ordinal: resolved, nextLoop: loopRange);
  }

  /// Applies an evaluator [result] to the current active slice.
  ({PracticeSessionState nextState, bool matched}) applyEvaluation(
    Score score,
    ChordEvaluationResult result,
    HandMode handMode, {
    bool holdOnMatch = false,
  }) {
    switch (result.status) {
      case ChordEvaluationStatus.partialChord:
        final next = wrongPlayedNotes.isEmpty
            ? this
            : copyWith(wrongPlayedNotes: const <StaffNote>[]);
        return (nextState: next, matched: false);
      case ChordEvaluationStatus.wrongNotes:
        return (
          nextState: copyWith(wrongPlayedNotes: result.wrongStaffNotes),
          matched: false,
        );
      case ChordEvaluationStatus.completeMatch:
        if (holdOnMatch) {
          return (
            nextState: copyWith(
              wrongPlayedNotes: const <StaffNote>[],
              completedSlicesCount: completedSlicesCount + 1,
              isShowingCorrect: true,
            ),
            matched: true,
          );
        }
        return (
          nextState: _advanceAfterMatch(
            score,
            handMode,
            nextCompleted: completedSlicesCount + 1,
          ),
          matched: true,
        );
    }
  }

  /// Completes a green matched hold by advancing to the next slice or completion.
  PracticeSessionState completeMatchHold(Score score, HandMode handMode) {
    if (!isShowingCorrect || activeSliceOrdinal == null) {
      return this;
    }
    return _advanceAfterMatch(
      score,
      handMode,
      nextCompleted: completedSlicesCount,
    );
  }

  PracticeSessionState _advanceAfterMatch(
    Score score,
    HandMode handMode, {
    required int nextCompleted,
  }) {
    final nextOrdinal = ScorePracticeNavigator.nextPlayableOrdinal(
      score,
      activeSliceOrdinal!,
      handMode,
      loopRange: loopRange,
    );
    if (nextOrdinal != null) {
      return copyWith(
        activeSliceOrdinal: nextOrdinal,
        wrongPlayedNotes: const <StaffNote>[],
        completedSlicesCount: nextCompleted,
        isShowingCorrect: false,
      );
    }
    if (loopRange != null) {
      final loopStart = ScorePracticeNavigator.firstPlayableOrdinal(
        score,
        handMode,
        loopRange: loopRange,
      );
      return PracticeSessionState(
        activeSliceOrdinal: loopStart,
        status: loopStart == null
            ? PracticeSessionStatus.noPlayableNotes
            : PracticeSessionStatus.active,
        loopRange: loopRange,
        completedSlicesCount: nextCompleted,
      );
    }
    return copyWith(
      status: PracticeSessionStatus.completed,
      wrongPlayedNotes: const <StaffNote>[],
      completedSlicesCount: nextCompleted,
      isShowingCorrect: false,
    );
  }

  int? _resolveOrdinalForLoop(
    Score score,
    MeasureLoopRange? clamped,
    HandMode handMode,
  ) {
    final current = activeSliceOrdinal;
    final currentPlayable =
        current != null &&
        status == PracticeSessionStatus.active &&
        ScorePracticeNavigator.isPlayableSlice(score.slices[current], handMode);
    if (clamped == null) {
      return currentPlayable
          ? current
          : ScorePracticeNavigator.nearestPlayableOrdinalAtOrAfter(
              score,
              current ?? 0,
              handMode,
            );
    }
    final measureIdx = current == null
        ? -1
        : ScorePracticeNavigator.measureIndexOfSliceOrdinal(score, current);
    if (currentPlayable && clamped.containsMeasureIndex(measureIdx)) {
      return current;
    }
    return ScorePracticeNavigator.firstPlayableOrdinal(
      score,
      handMode,
      loopRange: clamped,
    );
  }

  PracticeSessionState _resolved({int? ordinal, MeasureLoopRange? nextLoop}) {
    return PracticeSessionState(
      activeSliceOrdinal: ordinal,
      status: ordinal == null
          ? PracticeSessionStatus.noPlayableNotes
          : PracticeSessionStatus.active,
      loopRange: nextLoop,
      completedSlicesCount: completedSlicesCount,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PracticeSessionState &&
            other.activeSliceOrdinal == activeSliceOrdinal &&
            other.status == status &&
            other.loopRange == loopRange &&
            _listEquals(other.wrongPlayedNotes, wrongPlayedNotes) &&
            other.completedSlicesCount == completedSlicesCount &&
            other.isShowingCorrect == isShowingCorrect);
  }

  @override
  int get hashCode => Object.hash(
    activeSliceOrdinal,
    status,
    loopRange,
    Object.hashAll(wrongPlayedNotes),
    completedSlicesCount,
    isShowingCorrect,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
