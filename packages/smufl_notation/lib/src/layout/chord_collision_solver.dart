import 'dart:math' as math;

import 'package:smufl_notation/src/glyphs/smufl_glyphs.dart';
import 'package:smufl_notation/src/model/notation_model.dart';

/// Solved per-note horizontal shift and accidental column (`0..2`).
final class SolvedNotePlacement {
  const SolvedNotePlacement({
    required this.note,
    required this.horizontalShiftSpaces,
    this.accidentalColumn,
  });

  final NotationNote note;
  final double horizontalShiftSpaces;
  final int? accidentalColumn;
}

/// Solved chord engraving layout before converting staff steps to pixel coordinates.
final class SolvedChordLayout {
  const SolvedChordLayout({
    required this.placements,
    required this.stemUp,
    required this.stemStartStep,
    required this.stemTipStep,
    required this.accidentalColumnCount,
    required this.hasRightShiftedHead,
    required this.hasLeftShiftedHead,
  });

  final List<SolvedNotePlacement> placements;
  final bool stemUp;
  final int stemStartStep;
  final double stemTipStep;
  final int accidentalColumnCount;
  final bool hasRightShiftedHead;
  final bool hasLeftShiftedHead;
}

/// Solves stem direction, adjacent-second shifts, and non-overlapping accidentals.
abstract final class ChordCollisionSolver {
  static const int _middleLineStep = 4;
  static const int _minAccidentalClearanceSteps = 6;
  static const int _maxAccidentalColumns = 3;

  /// Computes stem direction (`step == 4` middle line) for [notes].
  static bool computeStemUp(List<NotationNote> notes) {
    if (notes.isEmpty) {
      return true;
    }
    var minStep = notes.first.staffStep;
    var maxStep = notes.first.staffStep;
    var stepSum = 0;
    for (final note in notes) {
      minStep = math.min(minStep, note.staffStep);
      maxStep = math.max(maxStep, note.staffStep);
      stepSum += note.staffStep;
    }
    final topDist = maxStep - _middleLineStep;
    final bottomDist = _middleLineStep - minStep;
    if (topDist != bottomDist) {
      return bottomDist > topDist;
    }
    return (stepSum / notes.length) < _middleLineStep;
  }

  /// Solves placements for a [NotationChord] (with optional [overrideStemUp]).
  static SolvedChordLayout solveChord(
    NotationChord chord, {
    bool? overrideStemUp,
  }) => solveNotes(
    chord.notes,
    hasStem: chord.duration.hasStem,
    beamCount: chord.duration.beamCount,
    overrideStemUp: overrideStemUp,
  );

  /// Solves notehead shifts and accidental columns (`0..2`) for [notes].
  static SolvedChordLayout solveNotes(
    List<NotationNote> notes, {
    required bool hasStem,
    int beamCount = 0,
    bool? overrideStemUp,
  }) {
    if (notes.isEmpty) {
      return const SolvedChordLayout(
        placements: <SolvedNotePlacement>[],
        stemUp: true,
        stemStartStep: 0,
        stemTipStep: 7.0,
        accidentalColumnCount: 0,
        hasRightShiftedHead: false,
        hasLeftShiftedHead: false,
      );
    }

    final sorted = List<NotationNote>.of(notes)
      ..sort((a, b) => a.staffStep.compareTo(b.staffStep));
    final stemUp = overrideStemUp ?? computeStemUp(sorted);
    final shifts = _solveSecondShifts(sorted, hasStem: hasStem, stemUp: stemUp);
    final columns = _solveAccidentalColumns(sorted);
    return _assembleLayout(
      sorted,
      shifts,
      columns,
      stemUp,
      beamCount: beamCount,
    );
  }

  static SolvedChordLayout _assembleLayout(
    List<NotationNote> sorted,
    List<double> shifts,
    List<int?> columns,
    bool stemUp, {
    required int beamCount,
  }) {
    var maxCol = -1;
    var hasRightShift = false;
    var hasLeftShift = false;
    final placements = <SolvedNotePlacement>[];
    for (var i = 0; i < sorted.length; i += 1) {
      final shift = shifts[i];
      if (shift > 0) {
        hasRightShift = true;
      } else if (shift < 0) {
        hasLeftShift = true;
      }
      final col = columns[i];
      if (col != null && col > maxCol) {
        maxCol = col;
      }
      placements.add(
        SolvedNotePlacement(
          note: sorted[i],
          horizontalShiftSpaces: shift,
          accidentalColumn: col,
        ),
      );
    }

    final minStep = sorted.first.staffStep;
    final maxStep = sorted.last.staffStep;
    final extraBeamSpaces = beamCount > 2 ? (beamCount - 2) * 0.85 : 0.0;
    final stemLengthSteps =
        (SmuflGlyphs.defaultStemLengthSpaces + extraBeamSpaces) * 2.0;
    return SolvedChordLayout(
      placements: List<SolvedNotePlacement>.unmodifiable(placements),
      stemUp: stemUp,
      stemStartStep: stemUp ? minStep : maxStep,
      stemTipStep: stemUp
          ? math.max(maxStep + stemLengthSteps, _middleLineStep.toDouble())
          : math.min(minStep - stemLengthSteps, _middleLineStep.toDouble()),
      accidentalColumnCount: maxCol + 1,
      hasRightShiftedHead: hasRightShift,
      hasLeftShiftedHead: hasLeftShift,
    );
  }

  static List<double> _solveSecondShifts(
    List<NotationNote> sorted, {
    required bool hasStem,
    required bool stemUp,
  }) {
    final shiftDist = hasStem
        ? SmuflGlyphs.secondShiftSpaces
        : SmuflGlyphs.wholeNoteheadWidthSpaces * 0.95;
    final shifts = List<double>.filled(sorted.length, 0.0);
    var prevShifted = false;

    if (stemUp || !hasStem) {
      for (var i = 1; i < sorted.length; i += 1) {
        final isSecond = (sorted[i].staffStep - sorted[i - 1].staffStep) <= 1;
        prevShifted = !prevShifted && isSecond;
        if (prevShifted) {
          shifts[i] = shiftDist;
        }
      }
    } else {
      for (var i = sorted.length - 2; i >= 0; i -= 1) {
        final isSecond = (sorted[i + 1].staffStep - sorted[i].staffStep) <= 1;
        prevShifted = !prevShifted && isSecond;
        if (prevShifted) {
          shifts[i] = -shiftDist;
        }
      }
    }
    return shifts;
  }

  static List<int?> _solveAccidentalColumns(List<NotationNote> sorted) {
    final columns = List<int?>.filled(sorted.length, null);
    // Sorted steps descend from index length-1 to 0, so last step per column is nearest.
    final lastStepInCol = List<int?>.filled(_maxAccidentalColumns, null);

    for (var i = sorted.length - 1; i >= 0; i -= 1) {
      final note = sorted[i];
      if (note.displayedAccidental == null) {
        continue;
      }
      final col = _pickColumn(note.staffStep, lastStepInCol);
      lastStepInCol[col] = note.staffStep;
      columns[i] = col;
    }
    return columns;
  }

  static int _pickColumn(int step, List<int?> lastStepInCol) {
    var bestCol = 0;
    var bestDist = -1;
    for (var col = 0; col < _maxAccidentalColumns; col += 1) {
      final lastStep = lastStepInCol[col];
      if (lastStep == null) {
        return col;
      }
      final dist = (lastStep - step).abs();
      if (dist >= _minAccidentalClearanceSteps) {
        return col;
      }
      if (dist > bestDist) {
        bestDist = dist;
        bestCol = col;
      }
    }
    return bestCol;
  }
}
