import 'dart:math' as math;
import 'dart:ui';

import 'package:smufl_notation/src/layout/score_beam_solver.dart';
import 'package:smufl_notation/src/layout/score_chord_placer.dart';
import 'package:smufl_notation/src/layout/score_layout_geometry.dart';
import 'package:smufl_notation/src/layout/score_layout_types.dart';
import 'package:smufl_notation/src/layout/score_measure_preparer.dart';
import 'package:smufl_notation/src/model/notation_model.dart';

/// Bounds and flags needed to lay out a single [PreparedMeasure].
final class MeasurePlacementSpec {
  const MeasurePlacementSpec({
    required this.prep,
    required this.system,
    required this.leftX,
    required this.rightX,
    required this.headerScale,
    required this.isSystemStart,
    required this.isFinalMeasure,
    required this.sp,
  });

  final PreparedMeasure prep;
  final SystemGeometry system;
  final double leftX;
  final double rightX;
  final double headerScale;
  final bool isSystemStart;
  final bool isFinalMeasure;
  final double sp;
}

/// Places engraved measures and slices within a system row.
abstract final class ScoreMeasurePlacer {
  static MeasureGeometry placeMeasure(MeasurePlacementSpec spec) {
    final header = _placeHeader(spec);
    final rawSlices = _buildRawSlices(spec, header.bodyStart);
    final beamed = _buildBeamedSlices(spec, rawSlices);
    final prep = spec.prep;

    return MeasureGeometry(
      measureNumber: prep.measure.measureNumber,
      leftX: spec.leftX,
      rightX: spec.rightX,
      keyFifths: prep.activeKeyFifths,
      showKeySignature: header.showKey,
      keyAccidentals: List<PlacedAccidental>.unmodifiable(header.keyAcc),
      beats: prep.activeBeats,
      beatType: prep.activeBeatType,
      showTimeSignature: prep.showTimeSignature,
      timeSigCenterX: header.timeSigCenterX,
      slices: beamed.slices,
      beamGroups: beamed.beamGroups,
      tieArcs: const <PlacedTieArc>[],
      isSystemStart: spec.isSystemStart,
      isFinalMeasure: spec.isFinalMeasure,
    );
  }

  static ({
    bool showKey,
    List<PlacedAccidental> keyAcc,
    double? timeSigCenterX,
    double bodyStart,
  })
  _placeHeader(MeasurePlacementSpec spec) {
    final prep = spec.prep;
    final sp = spec.sp;
    final scale = spec.headerScale;
    var cursorX =
        spec.leftX + (spec.isSystemStart ? 3.5 * sp * scale : 0.6 * sp * scale);
    final entries = ScoreMeasurePreparer.keySignatureEntries(
      isSystemStart: spec.isSystemStart,
      keyChanged: prep.keyChanged,
      previousKeyFifths: prep.previousKeyFifths,
      activeKeyFifths: prep.activeKeyFifths,
    );
    final showKey = entries.isNotEmpty;
    final keyAcc = <PlacedAccidental>[];
    if (showKey) {
      cursorX = _appendKeySignature(
        keyAcc: keyAcc,
        entries: entries,
        system: spec.system,
        cursorX: cursorX,
        headerScale: scale,
        sp: sp,
      );
    }

    double? timeSigCenterX;
    if (prep.showTimeSignature) {
      timeSigCenterX = cursorX + (1.1 * sp * scale);
      cursorX += 2.35 * sp * scale;
    }
    return (
      showKey: showKey,
      keyAcc: keyAcc,
      timeSigCenterX: timeSigCenterX,
      bodyStart: math.min(cursorX, spec.rightX - 1.0),
    );
  }

  static List<SliceGeometry> _buildRawSlices(
    MeasurePlacementSpec spec,
    double bodyStart,
  ) {
    final slices = spec.prep.slices;
    final bodyAvail = math.max(1.0, spec.rightX - bodyStart);
    final bodyCenterX = (bodyStart + spec.rightX) * 0.5;
    final isSingleRestOnlySlice =
        slices.length == 1 &&
        slices.single.slice.trebleChord == null &&
        slices.single.slice.bassChord == null &&
        (slices.single.slice.trebleRest != null ||
            slices.single.slice.bassRest != null);
    final centerTrebleWholeRest = _hasSingleWholeRestOnly(
      slices,
      SmuflClef.treble,
    );
    final centerBassWholeRest = _hasSingleWholeRestOnly(slices, SmuflClef.bass);
    final minSum = slices.fold<double>(0.0, (sum, p) => sum + p.minWidth);
    final scale = minSum > 0 ? bodyAvail / minSum : 1.0;

    final rawSlices = <SliceGeometry>[];
    var sliceX = bodyStart;
    for (var i = 0; i < slices.length; i += 1) {
      final p = slices[i];
      final sLeft = sliceX;
      final sRight = i == slices.length - 1
          ? spec.rightX
          : sliceX + (p.minWidth * scale);
      final sliceWidth = sRight - sLeft;
      final centerX = isSingleRestOnlySlice
          ? bodyCenterX
          : (sliceWidth <= 1.0
                ? (sLeft + sRight) * 0.5
                : (sLeft + (p.minLeftPad * scale)).clamp(
                    sLeft + 0.5,
                    sRight - 0.5,
                  ));
      rawSlices.add(
        _placeSingleSlice(p, spec.system, spec.sp, (
          left: sLeft,
          right: sRight,
          centerX: centerX,
          trebleRestCenterX: centerTrebleWholeRest ? bodyCenterX : centerX,
          bassRestCenterX: centerBassWholeRest ? bodyCenterX : centerX,
        )),
      );
      sliceX = sRight;
    }
    return rawSlices;
  }

  static bool _hasSingleWholeRestOnly(
    List<PreparedSlice> slices,
    SmuflClef clef,
  ) {
    var restCount = 0;
    var hasWholeRest = false;
    for (final p in slices) {
      final chord = clef == SmuflClef.treble
          ? p.slice.trebleChord
          : p.slice.bassChord;
      if (chord != null) {
        return false;
      }
      final rest = clef == SmuflClef.treble
          ? p.slice.trebleRest
          : p.slice.bassRest;
      if (rest != null) {
        restCount += 1;
        hasWholeRest = rest.duration == DurationKind.whole;
      }
    }
    return restCount == 1 && hasWholeRest;
  }

  static SliceGeometry _placeSingleSlice(
    PreparedSlice p,
    SystemGeometry system,
    double sp,
    ({
      double left,
      double right,
      double centerX,
      double trebleRestCenterX,
      double bassRestCenterX,
    })
    xBounds,
  ) {
    return SliceGeometry(
      sliceIndex: p.slice.sliceIndex,
      centerX: xBounds.centerX,
      cursorRect: Rect.fromLTRB(
        xBounds.left,
        system.trebleTopY,
        math.max(xBounds.left + 1.0, xBounds.right),
        system.bassBottomY,
      ),
      trebleChord: ScoreChordPlacer.placeChord(
        p.slice.trebleChord,
        p.trebleSolved,
        system,
        xBounds.centerX,
        sp,
      ),
      bassChord: ScoreChordPlacer.placeChord(
        p.slice.bassChord,
        p.bassSolved,
        system,
        xBounds.centerX,
        sp,
      ),
      trebleRest: ScoreChordPlacer.placeRest(
        p.slice.trebleRest,
        system,
        xBounds.trebleRestCenterX,
        sp,
      ),
      bassRest: ScoreChordPlacer.placeRest(
        p.slice.bassRest,
        system,
        xBounds.bassRestCenterX,
        sp,
      ),
    );
  }

  static ({List<SliceGeometry> slices, List<PlacedBeamGroup> beamGroups})
  _buildBeamedSlices(MeasurePlacementSpec spec, List<SliceGeometry> rawSlices) {
    final upTreble = <int, PlacedChord>{};
    final upBass = <int, PlacedChord>{};
    final beamGroups = <PlacedBeamGroup>[
      ...ScoreBeamSolver.buildBeamsForMeasure(
        sourceSlices: spec.prep.measure.slices,
        placedSlices: rawSlices,
        updatedChords: upTreble,
        clef: SmuflClef.treble,
        staffSpace: spec.sp,
      ),
      ...ScoreBeamSolver.buildBeamsForMeasure(
        sourceSlices: spec.prep.measure.slices,
        placedSlices: rawSlices,
        updatedChords: upBass,
        clef: SmuflClef.bass,
        staffSpace: spec.sp,
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
    return (
      slices: finalSlices,
      beamGroups: List<PlacedBeamGroup>.unmodifiable(beamGroups),
    );
  }

  static double _appendKeySignature({
    required List<PlacedAccidental> keyAcc,
    required List<({SmuflAccidental accidental, int trebleStep, int bassStep})>
    entries,
    required SystemGeometry system,
    required double cursorX,
    required double headerScale,
    required double sp,
  }) {
    for (var k = 0; k < entries.length; k += 1) {
      final entry = entries[k];
      final ax = cursorX + ((0.45 + (k * 1.02)) * sp * headerScale);
      keyAcc
        ..add(
          PlacedAccidental(
            accidental: entry.accidental,
            clef: SmuflClef.treble,
            centerX: ax,
            centerY: system.yForStep(SmuflClef.treble, entry.trebleStep),
            glyph: entry.accidental.glyph,
          ),
        )
        ..add(
          PlacedAccidental(
            accidental: entry.accidental,
            clef: SmuflClef.bass,
            centerX: ax,
            centerY: system.yForStep(SmuflClef.bass, entry.bassStep),
            glyph: entry.accidental.glyph,
          ),
        );
    }
    return cursorX + (((entries.length * 1.02) + 0.55) * sp * headerScale);
  }
}
