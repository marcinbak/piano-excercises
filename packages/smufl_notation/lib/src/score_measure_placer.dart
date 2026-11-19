import 'dart:math' as math;
import 'dart:ui';

import 'package:smufl_notation/src/notation_model.dart';
import 'package:smufl_notation/src/score_beam_solver.dart';
import 'package:smufl_notation/src/score_chord_placer.dart';
import 'package:smufl_notation/src/score_layout_types.dart';
import 'package:smufl_notation/src/score_measure_preparer.dart';

/// Places engraved measures and slices within a system row.
abstract final class ScoreMeasurePlacer {
  static MeasureGeometry placeMeasure({
    required PreparedMeasure prep,
    required SystemGeometry system,
    required double leftX,
    required double rightX,
    required double headerScale,
    required bool isSystemStart,
    required bool isFinalMeasure,
    required double sp,
  }) {
    var cursorX =
        leftX +
        (isSystemStart ? 3.5 * sp * headerScale : 0.6 * sp * headerScale);
    final showKey =
        (isSystemStart || prep.keyChanged) && prep.activeKeyFifths != 0;
    final keyAcc = <PlacedAccidental>[];
    if (showKey) {
      cursorX = _appendKeySignature(
        keyAcc: keyAcc,
        fifths: prep.activeKeyFifths,
        system: system,
        cursorX: cursorX,
        headerScale: headerScale,
        sp: sp,
      );
    }

    double? timeSigCenterX;
    if (prep.showTimeSignature) {
      timeSigCenterX = cursorX + (1.1 * sp * headerScale);
      cursorX += 2.35 * sp * headerScale;
    }

    final bodyStart = math.min(cursorX, rightX - 1.0);
    final bodyAvail = math.max(1.0, rightX - bodyStart);
    final minSum = prep.slices.fold<double>(0.0, (s, p) => s + p.minWidth);
    final scale = minSum > 0 ? bodyAvail / minSum : 1.0;

    final rawSlices = <SliceGeometry>[];
    var sliceX = bodyStart;
    for (var i = 0; i < prep.slices.length; i += 1) {
      final p = prep.slices[i];
      final sLeft = sliceX;
      final sRight = i == prep.slices.length - 1
          ? rightX
          : sliceX + (p.minWidth * scale);
      final centerX = (sLeft + (p.minLeftPad * scale)).clamp(
        sLeft + 0.5,
        sRight - 0.5,
      );
      rawSlices.add(
        SliceGeometry(
          sliceIndex: p.slice.sliceIndex,
          centerX: centerX,
          cursorRect: Rect.fromLTRB(
            sLeft,
            system.trebleTopY,
            math.max(sLeft + 1.0, sRight),
            system.bassBottomY,
          ),
          trebleChord: ScoreChordPlacer.placeChord(
            p.slice.trebleChord,
            p.trebleSolved,
            system,
            centerX,
            sp,
          ),
          bassChord: ScoreChordPlacer.placeChord(
            p.slice.bassChord,
            p.bassSolved,
            system,
            centerX,
            sp,
          ),
          trebleRest: ScoreChordPlacer.placeRest(
            p.slice.trebleRest,
            system,
            centerX,
            sp,
          ),
          bassRest: ScoreChordPlacer.placeRest(
            p.slice.bassRest,
            system,
            centerX,
            sp,
          ),
        ),
      );
      sliceX = sRight;
    }

    final upTreble = <int, PlacedChord>{};
    final upBass = <int, PlacedChord>{};
    final beamGroups = <PlacedBeamGroup>[
      ...ScoreBeamSolver.buildBeamsForMeasure(
        sourceSlices: prep.measure.slices,
        placedSlices: rawSlices,
        updatedChords: upTreble,
        clef: SmuflClef.treble,
        staffSpace: sp,
      ),
      ...ScoreBeamSolver.buildBeamsForMeasure(
        sourceSlices: prep.measure.slices,
        placedSlices: rawSlices,
        updatedChords: upBass,
        clef: SmuflClef.bass,
        staffSpace: sp,
      ),
    ];

    final finalSlices = List<SliceGeometry>.unmodifiable(<SliceGeometry>[
      for (var i = 0; i < rawSlices.length; i += 1)
        SliceGeometry(
          sliceIndex: rawSlices[i].sliceIndex,
          centerX: rawSlices[i].centerX,
          cursorRect: rawSlices[i].cursorRect,
          trebleChord: upTreble[i] ?? rawSlices[i].trebleChord,
          bassChord: upBass[i] ?? rawSlices[i].bassChord,
          trebleRest: rawSlices[i].trebleRest,
          bassRest: rawSlices[i].bassRest,
        ),
    ]);

    return MeasureGeometry(
      measureNumber: prep.measure.measureNumber,
      leftX: leftX,
      rightX: rightX,
      keyFifths: prep.activeKeyFifths,
      showKeySignature: showKey,
      keyAccidentals: List<PlacedAccidental>.unmodifiable(keyAcc),
      beats: prep.activeBeats,
      beatType: prep.activeBeatType,
      showTimeSignature: prep.showTimeSignature,
      timeSigCenterX: timeSigCenterX,
      slices: finalSlices,
      beamGroups: List<PlacedBeamGroup>.unmodifiable(beamGroups),
      tieArcs: const <PlacedTieArc>[],
      isSystemStart: isSystemStart,
      isFinalMeasure: isFinalMeasure,
    );
  }

  static double _appendKeySignature({
    required List<PlacedAccidental> keyAcc,
    required int fifths,
    required SystemGeometry system,
    required double cursorX,
    required double headerScale,
    required double sp,
  }) {
    final accType = fifths > 0 ? SmuflAccidental.sharp : SmuflAccidental.flat;
    final tSteps = ScoreMeasurePreparer.keySignatureSteps(
      SmuflClef.treble,
      fifths,
    );
    final bSteps = ScoreMeasurePreparer.keySignatureSteps(
      SmuflClef.bass,
      fifths,
    );
    for (var k = 0; k < tSteps.length; k += 1) {
      final ax = cursorX + ((0.45 + (k * 1.02)) * sp * headerScale);
      keyAcc
        ..add(
          PlacedAccidental(
            accidental: accType,
            clef: SmuflClef.treble,
            centerX: ax,
            centerY: system.yForStep(SmuflClef.treble, tSteps[k]),
            glyph: accType.glyph,
          ),
        )
        ..add(
          PlacedAccidental(
            accidental: accType,
            clef: SmuflClef.bass,
            centerX: ax,
            centerY: system.yForStep(SmuflClef.bass, bSteps[k]),
            glyph: accType.glyph,
          ),
        );
    }
    return cursorX + (((tSteps.length * 1.02) + 0.55) * sp * headerScale);
  }
}
