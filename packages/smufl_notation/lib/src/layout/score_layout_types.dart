import 'dart:ui';

import 'package:smufl_notation/src/layout/score_layout_geometry.dart';
import 'package:smufl_notation/src/model/notation_model.dart';

/// Vertical/horizontal coordinates for one rhythmic slice within a measure.
final class SliceGeometry {
  const SliceGeometry({
    required this.sliceIndex,
    required this.centerX,
    required this.cursorRect,
    this.trebleChord,
    this.bassChord,
    this.trebleRest,
    this.bassRest,
  });

  final int sliceIndex;
  final double centerX;
  final Rect cursorRect;
  final PlacedChord? trebleChord;
  final PlacedChord? bassChord;
  final PlacedRest? trebleRest;
  final PlacedRest? bassRest;
}

/// Engraved measure coordinates, header glyphs, slices, beams, and ties.
final class MeasureGeometry {
  const MeasureGeometry({
    required this.measureNumber,
    required this.leftX,
    required this.rightX,
    required this.keyFifths,
    required this.showKeySignature,
    required this.keyAccidentals,
    required this.showTimeSignature,
    required this.slices,
    required this.beamGroups,
    required this.tieArcs,
    required this.isSystemStart,
    required this.isFinalMeasure,
    this.beats,
    this.beatType,
    this.timeSigCenterX,
  });

  final int measureNumber;
  final double leftX;
  final double rightX;
  final int keyFifths;
  final bool showKeySignature;
  final List<PlacedAccidental> keyAccidentals;
  final int? beats;
  final int? beatType;
  final bool showTimeSignature;
  final double? timeSigCenterX;
  final List<SliceGeometry> slices;
  final List<PlacedBeamGroup> beamGroups;
  final List<PlacedTieArc> tieArcs;
  final bool isSystemStart;
  final bool isFinalMeasure;
}

/// Single engraved grand-staff line system spanning one or more measures.
final class SystemGeometry {
  const SystemGeometry({
    required this.systemIndex,
    required this.topY,
    required this.bottomY,
    required this.trebleTopY,
    required this.bassBottomY,
    required this.leftX,
    required this.rightX,
    required this.clefCenterX,
    required this.staffSpace,
    required this.trebleToBassGapSpaces,
    required this.measures,
  });

  final int systemIndex;
  final double topY;
  final double bottomY;
  final double trebleTopY;
  final double bassBottomY;
  final double leftX;
  final double rightX;
  final double clefCenterX;
  final double staffSpace;
  final double trebleToBassGapSpaces;
  final List<MeasureGeometry> measures;

  double get trebleBottomY => trebleTopY + (4.0 * staffSpace);

  double get bassTopY => trebleBottomY + (trebleToBassGapSpaces * staffSpace);

  /// Vertical canvas Y for [staffStep] relative to [clef] bottom line (`0..8`).
  double yForStep(SmuflClef clef, int staffStep) {
    final bottomY = clef == SmuflClef.treble ? trebleBottomY : bassBottomY;
    return bottomY - (staffStep * 0.5 * staffSpace);
  }
}

/// Cached O(1)-lookup result of [ScoreLayoutEngine.layout].
final class EngravedScoreLayout {
  EngravedScoreLayout({
    required this.totalSize,
    required this.style,
    required List<SystemGeometry> systems,
  }) : systems = List<SystemGeometry>.unmodifiable(systems),
       _sliceMap = _buildSliceMap(systems);

  final Size totalSize;
  final ScoreStyle style;
  final List<SystemGeometry> systems;
  final Map<int, ({SystemGeometry system, SliceGeometry slice})> _sliceMap;

  static Map<int, ({SystemGeometry system, SliceGeometry slice})>
  _buildSliceMap(List<SystemGeometry> systems) {
    final map = <int, ({SystemGeometry system, SliceGeometry slice})>{};
    for (final system in systems) {
      for (final measure in system.measures) {
        for (final slice in measure.slices) {
          map[slice.sliceIndex] = (system: system, slice: slice);
        }
      }
    }
    return Map<
      int,
      ({SystemGeometry system, SliceGeometry slice})
    >.unmodifiable(map);
  }

  /// Returns `O(1)` bounding cursor rectangle for [sliceIndex], if present.
  Rect? sliceRect(int sliceIndex) => _sliceMap[sliceIndex]?.slice.cursorRect;

  /// Returns `O(1)` system and slice placement for [sliceIndex], if present.
  ({SystemGeometry system, SliceGeometry slice})? slicePlacement(
    int sliceIndex,
  ) => _sliceMap[sliceIndex];

  /// Finds the slice at [position], or `null` outside active slice horizontal bounds.
  int? sliceAtOffset(Offset position) {
    for (final system in systems) {
      if (position.dy < system.topY || position.dy > system.bottomY) {
        continue;
      }
      for (final measure in system.measures) {
        for (final slice in measure.slices) {
          if (position.dx >= slice.cursorRect.left &&
              position.dx <= slice.cursorRect.right) {
            return slice.sliceIndex;
          }
        }
      }
    }
    return null;
  }
}
