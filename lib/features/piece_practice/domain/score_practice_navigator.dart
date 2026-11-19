import 'dart:math' as math;

import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/domain/measure_loop_range.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Bounded `O(N)` cursor and active-hand note lookup helpers across a [Score].
abstract final class ScorePracticeNavigator {
  /// Notes in [slice] requiring a fresh MIDI Note On for [handMode].
  static List<ScoreNote> requiredNotesFor(ScoreSlice slice, HandMode handMode) {
    return switch (handMode) {
      HandMode.right => slice.requiredTrebleNotes,
      HandMode.left => slice.requiredBassNotes,
      HandMode.both => List<ScoreNote>.unmodifiable(<ScoreNote>[
        ...slice.requiredTrebleNotes,
        ...slice.requiredBassNotes,
      ]),
    };
  }

  /// Notes in [slice] carried by a tie (`!requiresAttack`) for [handMode].
  static List<ScoreNote> sustainedNotesFor(
    ScoreSlice slice,
    HandMode handMode,
  ) {
    return switch (handMode) {
      HandMode.right => List<ScoreNote>.unmodifiable(
        slice.trebleNotes.where((note) => !note.requiresAttack),
      ),
      HandMode.left => List<ScoreNote>.unmodifiable(
        slice.bassNotes.where((note) => !note.requiresAttack),
      ),
      HandMode.both => List<ScoreNote>.unmodifiable(<ScoreNote>[
        ...slice.trebleNotes.where((note) => !note.requiresAttack),
        ...slice.bassNotes.where((note) => !note.requiresAttack),
      ]),
    };
  }

  /// Whether [slice] requires at least one key attack under [handMode].
  static bool isPlayableSlice(ScoreSlice slice, HandMode handMode) {
    return switch (handMode) {
      HandMode.right => slice.trebleNotes.any((note) => note.requiresAttack),
      HandMode.left => slice.bassNotes.any((note) => note.requiresAttack),
      HandMode.both => slice.requiresAnyAttack,
    };
  }

  /// First playable slice ordinal in [score] (within [loopRange] when non-null).
  static int? firstPlayableOrdinal(
    Score score,
    HandMode handMode, {
    MeasureLoopRange? loopRange,
  }) {
    final bounds = _ordinalBounds(score, loopRange);
    if (bounds == null) {
      return null;
    }
    return _scanForward(score, bounds.$1, bounds.$2, handMode);
  }

  /// Last playable slice ordinal in [score] (within [loopRange] when non-null).
  static int? lastPlayableOrdinal(
    Score score,
    HandMode handMode, {
    MeasureLoopRange? loopRange,
  }) {
    final bounds = _ordinalBounds(score, loopRange);
    if (bounds == null) {
      return null;
    }
    return _scanBackward(score, bounds.$2, bounds.$1, handMode);
  }

  /// Next playable slice ordinal strictly after [afterOrdinal].
  static int? nextPlayableOrdinal(
    Score score,
    int afterOrdinal,
    HandMode handMode, {
    MeasureLoopRange? loopRange,
  }) {
    final bounds = _ordinalBounds(score, loopRange);
    if (bounds == null) {
      return null;
    }
    final start = math.max(bounds.$1, afterOrdinal + 1);
    return _scanForward(score, start, bounds.$2, handMode);
  }

  /// Previous playable slice ordinal strictly before [beforeOrdinal].
  static int? previousPlayableOrdinal(
    Score score,
    int beforeOrdinal,
    HandMode handMode, {
    MeasureLoopRange? loopRange,
  }) {
    final bounds = _ordinalBounds(score, loopRange);
    if (bounds == null) {
      return null;
    }
    final start = math.min(bounds.$2, beforeOrdinal - 1);
    return _scanBackward(score, start, bounds.$1, handMode);
  }

  /// Nearest playable slice at or after [fromOrdinal], falling back earlier inside bounds.
  static int? nearestPlayableOrdinalAtOrAfter(
    Score score,
    int fromOrdinal,
    HandMode handMode, {
    MeasureLoopRange? loopRange,
  }) {
    final bounds = _ordinalBounds(score, loopRange);
    if (bounds == null) {
      return null;
    }
    final forwardStart = math.max(bounds.$1, fromOrdinal);
    final forwardMatch = _scanForward(score, forwardStart, bounds.$2, handMode);
    if (forwardMatch != null) {
      return forwardMatch;
    }
    final backwardStart = math.min(bounds.$2, fromOrdinal - 1);
    return _scanBackward(score, backwardStart, bounds.$1, handMode);
  }

  /// Returns the 0-based measure index in [score.measures] containing [sliceOrdinal].
  static int measureIndexOfSliceOrdinal(Score score, int sliceOrdinal) {
    if (score.measures.isEmpty || score.slices.isEmpty) {
      return 0;
    }
    final target = math.max(0, sliceOrdinal);
    var offset = 0;
    for (var i = 0; i < score.measures.length; i += 1) {
      final count = score.measures[i].slices.length;
      if (count > 0 && target < offset + count) {
        return i;
      }
      offset += count;
    }
    return score.measures.length - 1;
  }

  /// Resolves the active [KeySignature] at chronological [sliceIndex].
  static KeySignature activeKeySignatureAtSlice(Score score, int sliceIndex) {
    var activeKey = score.scale.keySignature;
    for (final measure in score.measures) {
      if (measure.keySignature != null) {
        activeKey = measure.keySignature!;
      }
      if (measure.slices.any((slice) => slice.sliceIndex == sliceIndex)) {
        return activeKey;
      }
    }
    return activeKey;
  }

  static (int, int)? _ordinalBounds(Score score, MeasureLoopRange? loopRange) {
    final totalSlices = score.slices.length;
    if (totalSlices == 0) {
      return null;
    }
    if (loopRange == null) {
      return (0, totalSlices - 1);
    }
    final clamped = loopRange.clampToMeasureCount(score.measures.length);
    if (clamped == null) {
      return null;
    }
    var startOrdinal = 0;
    for (var i = 0; i < clamped.startMeasureIndex; i += 1) {
      startOrdinal += score.measures[i].slices.length;
    }
    var endOrdinal = startOrdinal - 1;
    for (
      var i = clamped.startMeasureIndex;
      i <= clamped.endMeasureIndex;
      i += 1
    ) {
      endOrdinal += score.measures[i].slices.length;
    }
    if (startOrdinal > endOrdinal || startOrdinal >= totalSlices) {
      return null;
    }
    return (startOrdinal, math.min(endOrdinal, totalSlices - 1));
  }

  static int? _scanForward(
    Score score,
    int startOrdinal,
    int endOrdinal,
    HandMode handMode,
  ) {
    for (var i = startOrdinal; i <= endOrdinal; i += 1) {
      if (isPlayableSlice(score.slices[i], handMode)) {
        return i;
      }
    }
    return null;
  }

  static int? _scanBackward(
    Score score,
    int startOrdinal,
    int minOrdinal,
    HandMode handMode,
  ) {
    for (var i = startOrdinal; i >= minOrdinal; i -= 1) {
      if (isPlayableSlice(score.slices[i], handMode)) {
        return i;
      }
    }
    return null;
  }
}
