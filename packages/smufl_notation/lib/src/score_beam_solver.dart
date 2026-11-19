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
    var i = 0;
    while (i < slices.length) {
      final chord = _chordForClef(slices[i], clef);
      final groupId = chord?.beamGroupId;
      if (chord == null || chord.duration.beamCount == 0 || groupId == null) {
        i += 1;
        continue;
      }
      var end = i + 1;
      while (end < slices.length) {
        final next = _chordForClef(slices[end], clef);
        if (next == null ||
            next.duration.beamCount == 0 ||
            next.beamGroupId != groupId) {
          break;
        }
        end += 1;
      }
      if (end - i >= 2) {
        final notes = <NotationNote>[
          for (var j = i; j < end; j += 1)
            ..._chordForClef(slices[j], clef)!.notes,
        ];
        final stemUp = ChordCollisionSolver.computeStemUp(notes);
        for (var j = i; j < end; j += 1) {
          overrides[j] = stemUp;
        }
      }
      i = end;
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
    var i = 0;
    while (i < sourceSlices.length) {
      final chord = _chordForClef(sourceSlices[i], clef);
      final groupId = chord?.beamGroupId;
      if (chord == null || chord.duration.beamCount == 0 || groupId == null) {
        i += 1;
        continue;
      }
      var end = i + 1;
      while (end < sourceSlices.length) {
        final next = _chordForClef(sourceSlices[end], clef);
        if (next == null ||
            next.duration.beamCount == 0 ||
            next.beamGroupId != groupId) {
          break;
        }
        end += 1;
      }
      if (end - i >= 2) {
        groups.add(
          _finalizeBeamGroup(
            sourceSlices: sourceSlices,
            placedSlices: placedSlices,
            updatedChords: updatedChords,
            start: i,
            end: end,
            clef: clef,
            staffSpace: staffSpace,
          ),
        );
      }
      i = end;
    }
    return groups;
  }

  static PlacedBeamGroup _finalizeBeamGroup({
    required List<NotationSlice> sourceSlices,
    required List<SliceGeometry> placedSlices,
    required Map<int, PlacedChord> updatedChords,
    required int start,
    required int end,
    required SmuflClef clef,
    required double staffSpace,
  }) {
    final firstChord = _placedChordForClef(placedSlices[start], clef)!;
    final lastChord = _placedChordForClef(placedSlices[end - 1], clef)!;
    final stemUp = firstChord.stemUp;
    final firstX = firstChord.stemX!;
    final lastX = lastChord.stemX!;
    final dx = lastX - firstX;
    final rawSlope = dx > 0
        ? (lastChord.stemEndY! - firstChord.stemEndY!) / dx
        : 0.0;
    final slope = rawSlope.clamp(-_maxBeamSlope, _maxBeamSlope);
    final baseY = firstChord.stemEndY!;
    final minStemPx = 2.6 * staffSpace;

    var shiftY = 0.0;
    for (var j = start; j < end; j += 1) {
      final placed = _placedChordForClef(placedSlices[j], clef)!;
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

    final beamChords = <PlacedBeamChord>[];
    for (var j = start; j < end; j += 1) {
      final src = _chordForClef(sourceSlices[j], clef)!;
      final placed = _placedChordForClef(placedSlices[j], clef)!;
      final tipY = baseY + shiftY + (slope * (placed.stemX! - firstX));
      updatedChords[j] = PlacedChord(
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

  static NotationChord? _chordForClef(NotationSlice slice, SmuflClef clef) =>
      clef == SmuflClef.treble ? slice.trebleChord : slice.bassChord;

  static PlacedChord? _placedChordForClef(
    SliceGeometry slice,
    SmuflClef clef,
  ) => clef == SmuflClef.treble ? slice.trebleChord : slice.bassChord;
}
