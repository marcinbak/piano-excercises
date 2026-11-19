import 'package:smufl_notation/src/chord_collision_solver.dart';
import 'package:smufl_notation/src/notation_model.dart';
import 'package:smufl_notation/src/score_layout_types.dart';
import 'package:smufl_notation/src/score_measure_preparer.dart';
import 'package:smufl_notation/src/smufl_glyphs.dart';

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
    final rightShift = solved.hasRightShiftedHead
        ? SmuflGlyphs.secondShiftSpaces
        : 0.0;
    final leftShift = solved.hasLeftShiftedHead
        ? SmuflGlyphs.secondShiftSpaces
        : 0.0;
    final dotBaseX =
        centerX +
        ((SmuflGlyphs.noteheadWidthSpaces * 0.5 + rightShift + 0.55) * sp);
    final accBaseLeft =
        centerX -
        ((SmuflGlyphs.noteheadWidthSpaces * 0.5 + leftShift + 0.68) * sp);

    final usedDotSteps = <int>{};
    final noteheads = <PlacedNotehead>[];
    final accidentals = <PlacedAccidental>[];
    for (final p in solved.placements) {
      final nx = centerX + (p.horizontalShiftSpaces * sp);
      final ny = system.yForStep(chord.clef, p.note.staffStep);
      double? dotY;
      if (chord.dots > 0) {
        var dotStep = p.note.staffStep.isEven
            ? p.note.staffStep + 1
            : p.note.staffStep;
        if (usedDotSteps.contains(dotStep) && p.note.staffStep.isEven) {
          dotStep = p.note.staffStep - 1;
        }
        usedDotSteps.add(dotStep);
        dotY = system.yForStep(chord.clef, dotStep);
      }
      noteheads.add(
        PlacedNotehead(
          note: p.note,
          centerX: nx,
          centerY: ny,
          glyph: chord.duration.noteheadGlyph,
          dots: chord.dots,
          ledgerSteps: ScoreMeasurePreparer.ledgerStepsFor(p.note.staffStep),
          dotStartX: chord.dots > 0 ? dotBaseX : null,
          dotY: dotY,
        ),
      );
      final acc = p.note.displayedAccidental;
      if (p.accidentalColumn != null && acc != null) {
        final ax =
            accBaseLeft -
            (p.accidentalColumn! *
                SmuflGlyphs.accidentalColumnSpacingSpaces *
                sp);
        accidentals.add(
          PlacedAccidental(
            accidental: acc,
            clef: chord.clef,
            centerX: ax,
            centerY: ny,
            glyph: acc.glyph,
          ),
        );
      }
    }

    return PlacedChord(
      clef: chord.clef,
      noteheads: List<PlacedNotehead>.unmodifiable(noteheads),
      accidentals: List<PlacedAccidental>.unmodifiable(accidentals),
      stemUp: solved.stemUp,
      flagCount: chord.duration.beamCount,
      stemX: chord.duration.hasStem
          ? centerX +
                ((solved.stemUp
                        ? SmuflGlyphs.stemUpXOffsetSpaces
                        : SmuflGlyphs.stemDownXOffsetSpaces) *
                    sp)
          : null,
      stemStartY: chord.duration.hasStem
          ? system.yForStep(chord.clef, solved.stemStartStep) +
                ((solved.stemUp
                        ? SmuflGlyphs.stemUpYOffsetSpaces
                        : SmuflGlyphs.stemDownYOffsetSpaces) *
                    sp)
          : null,
      stemEndY: chord.duration.hasStem
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
