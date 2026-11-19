import 'dart:math' as math;

import 'package:smufl_notation/src/glyphs/smufl_glyphs.dart';
import 'package:smufl_notation/src/layout/chord_collision_solver.dart';
import 'package:smufl_notation/src/layout/score_beam_solver.dart';
import 'package:smufl_notation/src/model/notation_model.dart';
import 'package:smufl_notation/src/model/notation_score_model.dart';

/// Pre-solved slice spacing metadata before horizontal justification.
final class PreparedSlice {
  const PreparedSlice({
    required this.slice,
    required this.minLeftPad,
    required this.minRightPad,
    this.trebleSolved,
    this.bassSolved,
  });

  final NotationSlice slice;
  final double minLeftPad;
  final double minRightPad;
  final SolvedChordLayout? trebleSolved;
  final SolvedChordLayout? bassSolved;

  double get minWidth => minLeftPad + minRightPad;
}

/// Pre-analyzed measure metadata used during greedy system wrapping.
final class PreparedMeasure {
  const PreparedMeasure({
    required this.index,
    required this.measure,
    required this.previousKeyFifths,
    required this.activeKeyFifths,
    required this.keyChanged,
    required this.activeBeats,
    required this.activeBeatType,
    required this.showTimeSignature,
    required this.slices,
    required this.bodyMinWidth,
  });

  final int index;
  final NotationMeasure measure;
  final int previousKeyFifths;
  final int activeKeyFifths;
  final bool keyChanged;
  final int activeBeats;
  final int activeBeatType;
  final bool showTimeSignature;
  final List<PreparedSlice> slices;
  final double bodyMinWidth;

  double headerWidth({required bool isSystemStart, required double sp}) {
    var width = isSystemStart ? 3.5 * sp : 0.6 * sp;
    final keyCount = ScoreMeasurePreparer.keySignatureEntries(
      isSystemStart: isSystemStart,
      keyChanged: keyChanged,
      previousKeyFifths: previousKeyFifths,
      activeKeyFifths: activeKeyFifths,
    ).length;
    if (keyCount > 0) {
      width += ((keyCount * 1.02) + 0.55) * sp;
    }
    if (showTimeSignature) {
      width += 2.35 * sp;
    }
    return width;
  }

  double minWidth({required bool isSystemStart, required double sp}) =>
      headerWidth(isSystemStart: isSystemStart, sp: sp) + bodyMinWidth;
}

/// Pure pre-layout preparation for key signatures, ledger steps, and slice widths.
abstract final class ScoreMeasurePreparer {
  static const List<int> trebleSharpSteps = <int>[8, 5, 9, 6, 3, 7, 4];
  static const List<int> trebleFlatSteps = <int>[4, 7, 3, 6, 2, 5, 1];

  /// Computes ledger-line steps for [staffStep] (capped at 8).
  static List<int> ledgerStepsFor(int staffStep) {
    if (staffStep <= -2) {
      final count = math.min(8, (-staffStep) ~/ 2);
      return List<int>.generate(count, (i) => -2 * (i + 1));
    }
    if (staffStep >= 10) {
      final count = math.min(8, (staffStep - 8) ~/ 2);
      return List<int>.generate(count, (i) => 8 + (2 * (i + 1)));
    }
    return const <int>[];
  }

  /// Returns key-signature staff steps for [clef] and [fifths] (`-7..+7`).
  static List<int> keySignatureSteps(SmuflClef clef, int fifths) {
    RangeError.checkValueInInterval(fifths, -7, 7, 'fifths');
    if (fifths == 0) {
      return const <int>[];
    }
    final base = fifths > 0 ? trebleSharpSteps : trebleFlatSteps;
    final clefOffset = clef == SmuflClef.treble ? 0 : -2;
    return List<int>.unmodifiable(
      List<int>.generate(fifths.abs(), (i) => base[i] + clefOffset),
    );
  }

  /// Returns key-signature columns (including naturals on key modulation).
  static List<({SmuflAccidental accidental, int trebleStep, int bassStep})>
  keySignatureEntries({
    required bool isSystemStart,
    required bool keyChanged,
    required int previousKeyFifths,
    required int activeKeyFifths,
  }) {
    if (!isSystemStart && !keyChanged) {
      return const [];
    }
    if (keyChanged && activeKeyFifths == 0) {
      return _accidentalEntries(previousKeyFifths, SmuflAccidental.natural);
    }
    if (keyChanged &&
        previousKeyFifths != 0 &&
        (previousKeyFifths > 0) != (activeKeyFifths > 0)) {
      return [
        ..._accidentalEntries(previousKeyFifths, SmuflAccidental.natural),
        ..._accidentalEntries(
          activeKeyFifths,
          activeKeyFifths > 0 ? SmuflAccidental.sharp : SmuflAccidental.flat,
        ),
      ];
    }
    final activeAcc = activeKeyFifths > 0
        ? SmuflAccidental.sharp
        : SmuflAccidental.flat;
    final entries = _accidentalEntries(activeKeyFifths, activeAcc);
    if (keyChanged &&
        previousKeyFifths != 0 &&
        previousKeyFifths.abs() > activeKeyFifths.abs()) {
      final cancel = _accidentalEntries(
        previousKeyFifths,
        SmuflAccidental.natural,
      );
      return [...entries, ...cancel.sublist(activeKeyFifths.abs())];
    }
    return entries;
  }

  static List<({SmuflAccidental accidental, int trebleStep, int bassStep})>
  _accidentalEntries(int fifths, SmuflAccidental accidental) {
    final tSteps = keySignatureSteps(SmuflClef.treble, fifths);
    final bSteps = keySignatureSteps(SmuflClef.bass, fifths);
    return [
      for (var i = 0; i < tSteps.length; i += 1)
        (accidental: accidental, trebleStep: tSteps[i], bassStep: bSteps[i]),
    ];
  }

  static List<PreparedMeasure> prepareMeasures(
    List<NotationMeasure> measures,
    double sp,
  ) {
    final result = <PreparedMeasure>[];
    var activeKey = 0;
    var activeBeats = 4;
    var activeBeatType = 4;

    for (var i = 0; i < measures.length; i += 1) {
      final m = measures[i];
      final previousKey = i == 0 ? 0 : activeKey;
      final keyChanged =
          (i == 0 && (m.keyFifths ?? 0) != 0) ||
          (i > 0 && m.keyFifths != null && m.keyFifths != activeKey);
      if (m.keyFifths != null) {
        activeKey = m.keyFifths!;
      }
      final timeChanged =
          (i == 0 && m.beats != null) ||
          (i > 0 &&
              m.beats != null &&
              (m.beats != activeBeats || m.beatType != activeBeatType));
      if (m.beats != null && m.beatType != null) {
        activeBeats = m.beats!;
        activeBeatType = m.beatType!;
      }
      result.add(
        _prepareSingleMeasure(
          index: i,
          measure: m,
          header: (
            previousKey: previousKey,
            activeKey: activeKey,
            keyChanged: keyChanged,
            activeBeats: activeBeats,
            activeBeatType: activeBeatType,
            timeChanged: timeChanged,
          ),
          sp: sp,
        ),
      );
    }
    return result;
  }

  static PreparedMeasure _prepareSingleMeasure({
    required int index,
    required NotationMeasure measure,
    required ({
      int previousKey,
      int activeKey,
      bool keyChanged,
      int activeBeats,
      int activeBeatType,
      bool timeChanged,
    })
    header,
    required double sp,
  }) {
    final tStems = ScoreBeamSolver.resolveBeamStemDirections(
      measure.slices,
      SmuflClef.treble,
    );
    final bStems = ScoreBeamSolver.resolveBeamStemDirections(
      measure.slices,
      SmuflClef.bass,
    );
    final slices = <PreparedSlice>[];
    var bodyMinWidth = 0.0;
    for (var s = 0; s < measure.slices.length; s += 1) {
      final slice = measure.slices[s];
      final tSolved = slice.trebleChord == null
          ? null
          : ChordCollisionSolver.solveChord(
              slice.trebleChord!,
              overrideStemUp: tStems[s],
            );
      final bSolved = slice.bassChord == null
          ? null
          : ChordCollisionSolver.solveChord(
              slice.bassChord!,
              overrideStemUp: bStems[s],
            );
      final prep = _prepareSlice(slice, tSolved, bSolved, sp);
      slices.add(prep);
      bodyMinWidth += prep.minWidth;
    }
    return PreparedMeasure(
      index: index,
      measure: measure,
      previousKeyFifths: header.previousKey,
      activeKeyFifths: header.activeKey,
      keyChanged: header.keyChanged,
      activeBeats: header.activeBeats,
      activeBeatType: header.activeBeatType,
      showTimeSignature: header.timeChanged,
      slices: slices,
      bodyMinWidth: math.max(4.5 * sp, bodyMinWidth + (0.8 * sp)),
    );
  }

  static PreparedSlice _prepareSlice(
    NotationSlice slice,
    SolvedChordLayout? tSolved,
    SolvedChordLayout? bSolved,
    double sp,
  ) {
    final accCols = math.max(
      tSolved?.accidentalColumnCount ?? 0,
      bSolved?.accidentalColumnCount ?? 0,
    );
    final leftShift =
        (tSolved?.hasLeftShiftedHead ?? false) ||
        (bSolved?.hasLeftShiftedHead ?? false);
    final rightShift =
        (tSolved?.hasRightShiftedHead ?? false) ||
        (bSolved?.hasRightShiftedHead ?? false);
    final maxDots = math.max(
      slice.trebleChord?.dots ?? slice.trebleRest?.dots ?? 0,
      slice.bassChord?.dots ?? slice.bassRest?.dots ?? 0,
    );
    final minLeft =
        (0.95 +
            (leftShift ? SmuflGlyphs.secondShiftSpaces : 0.0) +
            (accCols * SmuflGlyphs.accidentalColumnSpacingSpaces)) *
        sp;
    final durBase = math.max(1.9, 2.75 * math.sqrt(slice.beatDuration)) * sp;
    final minRight = math.max(
      durBase,
      (1.1 +
              (rightShift ? SmuflGlyphs.secondShiftSpaces : 0.0) +
              (maxDots > 0 ? 0.65 + (maxDots * 0.5) : 0.0)) *
          sp,
    );
    return PreparedSlice(
      slice: slice,
      minLeftPad: minLeft,
      minRightPad: minRight,
      trebleSolved: tSolved,
      bassSolved: bSolved,
    );
  }
}
