import 'dart:math' as math;

import 'package:smufl_notation/src/chord_collision_solver.dart';
import 'package:smufl_notation/src/notation_model.dart';
import 'package:smufl_notation/src/score_layout_types.dart';

/// Resolves unified stem directions and sloped beams for 8th/16th chord runs.
abstract final class ScoreBeamSolver {
  static const double _maxBeamSlope = 0.22;

  /// Computes unified stem direction overrides for beamed runs on [clef].
  static Map<int, bool> resolveBeamStemDirections(
    List<NotationSlice> slices,
    SmuflClef clef,
  ) {
    final overrides = <int, bool>{};
    for (final members in _collectBeamRuns(slices, clef)) {
      final notes = <NotationNote>[
        for (final idx in members) ..._chordForClef(slices[idx], clef)!.notes,
      ];
      final stemUp = ChordCollisionSolver.computeStemUp(notes);
      for (final idx in members) {
        overrides[idx] = stemUp;
      }
    }
    return overrides;
  }

  /// Builds [PlacedBeamGroup]s and updates beamed chord stem tips for [clef].
  static List<PlacedBeamGroup> buildBeamsForMeasure({
    required List<NotationSlice> sourceSlices,
    required List<SliceGeometry> placedSlices,
    required Map<int, PlacedChord> updatedChords,
    required SmuflClef clef,
    required double staffSpace,
  }) {
    final groups = <PlacedBeamGroup>[];
    for (final members in _collectBeamRuns(sourceSlices, clef)) {
      groups.add(
        _finalizeBeamGroup(
          sourceSlices: sourceSlices,
          placedSlices: placedSlices,
          updatedChords: updatedChords,
          members: members,
          clef: clef,
          staffSpace: staffSpace,
        ),
      );
    }
    return groups;
  }

  static List<List<int>> _collectBeamRuns(
    List<NotationSlice> slices,
    SmuflClef clef,
  ) {
    final runs = <List<int>>[];
    var i = 0;
    while (i < slices.length) {
      final chord = _chordForClef(slices[i], clef);
      final groupId = chord?.beamGroupId;
      if (chord == null || chord.duration.beamCount == 0 || groupId == null) {
        i += 1;
        continue;
      }
      final members = <int>[i];
      var scan = i + 1;
      while (scan < slices.length) {
        if (_restForClef(slices[scan], clef) != null) {
          break;
        }
        final next = _chordForClef(slices[scan], clef);
        if (next == null) {
          // Opposite staff subdivides this beat while current clef holds; skip slice.
          scan += 1;
          continue;
        }
        if (next.duration.beamCount == 0 || next.beamGroupId != groupId) {
          break;
        }
        members.add(scan);
        scan += 1;
      }
      if (members.length >= 2) {
        runs.add(members);
      }
      i = scan;
    }
    return runs;
  }

  static PlacedBeamGroup _finalizeBeamGroup({
    required List<NotationSlice> sourceSlices,
    required List<SliceGeometry> placedSlices,
    required Map<int, PlacedChord> updatedChords,
    required List<int> members,
    required SmuflClef clef,
    required double staffSpace,
  }) {
    final firstChord = _placedChordForClef(placedSlices[members.first], clef)!;
    final lastChord = _placedChordForClef(placedSlices[members.last], clef)!;
    final stemUp = firstChord.stemUp;
    final firstX = firstChord.stemX!;
    final dx = lastChord.stemX! - firstX;
    final slope =
        (dx > 0 ? (lastChord.stemEndY! - firstChord.stemEndY!) / dx : 0.0)
            .clamp(-_maxBeamSlope, _maxBeamSlope);
    final baseY = firstChord.stemEndY!;
    final shiftY = _computeClearanceShift(
      placedSlices: placedSlices,
      members: members,
      clef: clef,
      stemUp: stemUp,
      firstX: firstX,
      baseY: baseY,
      slope: slope,
      minStemPx: 2.6 * staffSpace,
    );

    final beamChords = <PlacedBeamChord>[];
    for (final idx in members) {
      final src = _chordForClef(sourceSlices[idx], clef)!;
      final placed = _placedChordForClef(placedSlices[idx], clef)!;
      final tipY = baseY + shiftY + (slope * (placed.stemX! - firstX));
      updatedChords[idx] = PlacedChord(
        clef: placed.clef,
        noteheads: placed.noteheads,
        accidentals: placed.accidentals,
        stemUp: placed.stemUp,
        flagCount: 0,
        stemX: placed.stemX,
        stemStartY: placed.stemStartY,
        stemEndY: tipY,
        beamGroupId: placed.beamGroupId,
      );
      beamChords.add(
        PlacedBeamChord(
          stemX: placed.stemX!,
          stemTipY: tipY,
          beamCount: src.duration.beamCount,
        ),
      );
    }

    return PlacedBeamGroup(
      clef: clef,
      stemUp: stemUp,
      chords: List<PlacedBeamChord>.unmodifiable(beamChords),
    );
  }

  static double _computeClearanceShift({
    required List<SliceGeometry> placedSlices,
    required List<int> members,
    required SmuflClef clef,
    required bool stemUp,
    required double firstX,
    required double baseY,
    required double slope,
    required double minStemPx,
  }) {
    var shiftY = 0.0;
    for (final idx in members) {
      final placed = _placedChordForClef(placedSlices[idx], clef)!;
      final lineY = baseY + (slope * (placed.stemX! - firstX));
      final extremeY = stemUp
          ? placed.noteheads.map((n) => n.centerY).reduce(math.min)
          : placed.noteheads.map((n) => n.centerY).reduce(math.max);
      final delta = stemUp
          ? (extremeY - minStemPx) - lineY
          : (extremeY + minStemPx) - lineY;
      if ((stemUp && delta < shiftY) || (!stemUp && delta > shiftY)) {
        shiftY = delta;
      }
    }
    return shiftY;
  }

  static NotationChord? _chordForClef(NotationSlice slice, SmuflClef clef) =>
      clef == SmuflClef.treble ? slice.trebleChord : slice.bassChord;

  static NotationRest? _restForClef(NotationSlice slice, SmuflClef clef) =>
      clef == SmuflClef.treble ? slice.trebleRest : slice.bassRest;

  static PlacedChord? _placedChordForClef(
    SliceGeometry slice,
    SmuflClef clef,
  ) => clef == SmuflClef.treble ? slice.trebleChord : slice.bassChord;
}
