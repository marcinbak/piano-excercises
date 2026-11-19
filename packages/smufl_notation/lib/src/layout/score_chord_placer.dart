import 'package:smufl_notation/src/glyphs/smufl_glyphs.dart';
import 'package:smufl_notation/src/layout/chord_collision_solver.dart';
import 'package:smufl_notation/src/layout/score_layout_geometry.dart';
import 'package:smufl_notation/src/layout/score_layout_types.dart';
import 'package:smufl_notation/src/layout/score_measure_preparer.dart';
import 'package:smufl_notation/src/model/notation_model.dart';

/// Places solved [NotationChord]s and [NotationRest]s into pixel coordinates.
abstract final class ScoreChordPlacer {
  static PlacedChord? placeChord(
    NotationChord? chord,
    SolvedChordLayout? solved,
    SystemGeometry system,
    double centerX,
    double sp,
  ) {
    if (chord == null || solved == null) {
      return null;
    }
    final headWidth = chord.duration.hasStem
        ? SmuflGlyphs.noteheadWidthSpaces
        : SmuflGlyphs.wholeNoteheadWidthSpaces;
    final shiftWidth = chord.duration.hasStem
        ? SmuflGlyphs.secondShiftSpaces
        : SmuflGlyphs.wholeNoteheadWidthSpaces * 0.95;
    final rightShift = solved.hasRightShiftedHead ? shiftWidth : 0.0;
    final leftShift = solved.hasLeftShiftedHead ? shiftWidth : 0.0;
    final dotBaseX = centerX + ((headWidth * 0.5 + rightShift + 0.55) * sp);
    final accBaseLeft = centerX - ((headWidth * 0.5 + leftShift + 0.68) * sp);

    // Pre-claim odd space steps so adjacent even-step notes shift to step - 1.
    final usedDotSteps = <int>{
      if (chord.dots > 0)
        for (final p in solved.placements)
          if (p.note.staffStep.isOdd) p.note.staffStep,
    };

    final noteheads = <PlacedNotehead>[];
    final accidentals = <PlacedAccidental>[];
    for (final p in solved.placements) {
      final nx = centerX + (p.horizontalShiftSpaces * sp);
      final ny = system.yForStep(chord.clef, p.note.staffStep);
      noteheads.add(
        _buildNotehead(
          chord: chord,
          note: p.note,
          system: system,
          center: (nx, ny),
          dotBaseX: dotBaseX,
          usedDotSteps: usedDotSteps,
        ),
      );
      final acc = _buildAccidental(
        placement: p,
        clef: chord.clef,
        accBaseLeft: accBaseLeft,
        ny: ny,
        sp: sp,
      );
      if (acc != null) {
        accidentals.add(acc);
      }
    }

    return _assembleChord(
      chord: chord,
      solved: solved,
      system: system,
      noteheads: noteheads,
      accidentals: accidentals,
      centerX: centerX,
      sp: sp,
    );
  }

  static PlacedNotehead _buildNotehead({
    required NotationChord chord,
    required NotationNote note,
    required SystemGeometry system,
    required (double, double) center,
    required double dotBaseX,
    required Set<int> usedDotSteps,
  }) {
    double? dotY;
    if (chord.dots > 0) {
      var dotStep = note.staffStep.isEven ? note.staffStep + 1 : note.staffStep;
      if (note.staffStep.isEven && usedDotSteps.contains(dotStep)) {
        dotStep = note.staffStep - 1;
      }
      usedDotSteps.add(dotStep);
      dotY = system.yForStep(chord.clef, dotStep);
    }
    return PlacedNotehead(
      note: note,
      centerX: center.$1,
      centerY: center.$2,
      glyph: (note.noteheadDuration ?? chord.duration).noteheadGlyph,
      dots: chord.dots,
      ledgerSteps: ScoreMeasurePreparer.ledgerStepsFor(note.staffStep),
      dotStartX: chord.dots > 0 ? dotBaseX : null,
      dotY: dotY,
    );
  }

  static PlacedAccidental? _buildAccidental({
    required SolvedNotePlacement placement,
    required SmuflClef clef,
    required double accBaseLeft,
    required double ny,
    required double sp,
  }) {
    final acc = placement.note.displayedAccidental;
    if (placement.accidentalColumn == null || acc == null) {
      return null;
    }
    final ax =
        accBaseLeft -
        (placement.accidentalColumn! *
            SmuflGlyphs.accidentalColumnSpacingSpaces *
            sp);
    return PlacedAccidental(
      accidental: acc,
      clef: clef,
      centerX: ax,
      centerY: ny,
      glyph: acc.glyph,
    );
  }

  static PlacedChord _assembleChord({
    required NotationChord chord,
    required SolvedChordLayout solved,
    required SystemGeometry system,
    required List<PlacedNotehead> noteheads,
    required List<PlacedAccidental> accidentals,
    required double centerX,
    required double sp,
  }) {
    final hasStem = chord.duration.hasStem;
    return PlacedChord(
      clef: chord.clef,
      noteheads: List<PlacedNotehead>.unmodifiable(noteheads),
      accidentals: List<PlacedAccidental>.unmodifiable(accidentals),
      stemUp: solved.stemUp,
      flagCount: chord.duration.beamCount,
      stemX: hasStem
          ? centerX +
                ((solved.stemUp
                        ? SmuflGlyphs.stemUpXOffsetSpaces
                        : SmuflGlyphs.stemDownXOffsetSpaces) *
                    sp)
          : null,
      stemStartY: hasStem
          ? system.yForStep(chord.clef, solved.stemStartStep) +
                ((solved.stemUp
                        ? SmuflGlyphs.stemUpYOffsetSpaces
                        : SmuflGlyphs.stemDownYOffsetSpaces) *
                    sp)
          : null,
      stemEndY: hasStem
          ? system.yForStep(chord.clef, 0) - (solved.stemTipStep * 0.5 * sp)
          : null,
      beamGroupId: chord.beamGroupId,
    );
  }

  static PlacedRest? placeRest(
    NotationRest? rest,
    SystemGeometry system,
    double centerX,
    double sp,
  ) {
    if (rest == null) {
      return null;
    }
    final step = rest.duration == DurationKind.whole ? 6 : 4;
    return PlacedRest(
      clef: rest.clef,
      centerX: centerX,
      anchorY: system.yForStep(rest.clef, step),
      glyph: rest.duration.restGlyph,
      dots: rest.dots,
      dotStartX: rest.dots > 0 ? centerX + (0.9 * sp) : null,
      dotY: rest.dots > 0 ? system.yForStep(rest.clef, 5) : null,
    );
  }
}
