import 'dart:math' as math;
import 'dart:ui';

import 'package:smufl_notation/src/glyphs/smufl_glyphs.dart';
import 'package:smufl_notation/src/layout/chord_collision_solver.dart';
import 'package:smufl_notation/src/layout/score_layout_engine.dart';
import 'package:smufl_notation/src/layout/score_layout_geometry.dart';
import 'package:smufl_notation/src/layout/score_layout_types.dart';
import 'package:smufl_notation/src/model/notation_model.dart';
import 'package:smufl_notation/src/model/notation_score_model.dart';
import 'package:smufl_notation/src/painting/smufl_glyph_painter.dart';

/// Resolved coordinates for one wrong-note glyph, its ledger lines, and accidental.
final class PlacedWrongNoteSpec {
  const PlacedWrongNoteSpec({
    required this.noteX,
    required this.noteY,
    required this.ledgerYs,
    this.accidentalX,
    this.accidentalGlyph,
  });

  final double noteX;
  final double noteY;
  final List<double> ledgerYs;
  final double? accidentalX;
  final String? accidentalGlyph;
}

/// Paints red [WrongNoteOverlay] chords with ledger lines and accidentals.
abstract final class ScoreWrongNotePainter {
  /// Computes unclamped notehead, ledger-line, and accidental coordinates.
  static List<PlacedWrongNoteSpec> computeOverlaySpecs({
    required SystemGeometry system,
    required SliceGeometry slice,
    required WrongNoteOverlay overlay,
  }) {
    final sp = system.staffSpace;
    final availRight = math.max(0.0, slice.cursorRect.right - slice.centerX);
    final wrongX = slice.centerX + math.min(1.25 * sp, availRight * 0.4);
    final accBase =
        wrongX - ((SmuflGlyphs.wholeNoteheadWidthSpaces * 0.5 + 0.65) * sp);

    final specs = <PlacedWrongNoteSpec>[];
    for (final clef in SmuflClef.values) {
      final clefNotes = overlay.notes
          .where((note) => note.clef == clef)
          .toList(growable: false);
      if (clefNotes.isEmpty) {
        continue;
      }
      final solved = ChordCollisionSolver.solveNotes(clefNotes, hasStem: false);
      for (final p in solved.placements) {
        final nx = wrongX + (p.horizontalShiftSpaces * sp);
        final ny = system.yForStep(clef, p.note.staffStep);
        final ledgerYs = <double>[
          for (final step in ScoreLayoutEngine.ledgerStepsFor(p.note.staffStep))
            system.yForStep(clef, step),
        ];
        final acc = p.note.displayedAccidental;
        final ax = p.accidentalColumn != null && acc != null
            ? accBase -
                  (p.accidentalColumn! *
                      SmuflGlyphs.accidentalColumnSpacingSpaces *
                      sp)
            : null;
        specs.add(
          PlacedWrongNoteSpec(
            noteX: nx,
            noteY: ny,
            ledgerYs: ledgerYs,
            accidentalX: ax,
            accidentalGlyph: acc?.glyph,
          ),
        );
      }
    }
    return specs;
  }

  static void paintOverlay({
    required Canvas canvas,
    required SystemGeometry system,
    required SliceGeometry slice,
    required WrongNoteOverlay overlay,
    required ScoreStyle style,
  }) {
    final sp = system.staffSpace;
    final specs = computeOverlaySpecs(
      system: system,
      slice: slice,
      overlay: overlay,
    );
    final ledgerPaint = Paint()
      ..color = style.errorColor
      ..strokeWidth = math.max(1.0, sp * 0.10);
    final ledgerHalf = (SmuflGlyphs.wholeNoteheadWidthSpaces * 0.72) * sp;
    final errorStyle = style.glyphStyle(style.errorColor);

    for (final spec in specs) {
      for (final ly in spec.ledgerYs) {
        canvas.drawLine(
          Offset(spec.noteX - ledgerHalf, ly),
          Offset(spec.noteX + ledgerHalf, ly),
          ledgerPaint,
        );
      }
      paintSmuflGlyph(
        canvas: canvas,
        glyph: SmuflGlyphs.noteheadWhole,
        anchor: Offset(spec.noteX, spec.noteY),
        style: errorStyle,
      );
      if (spec.accidentalX != null && spec.accidentalGlyph != null) {
        paintSmuflGlyph(
          canvas: canvas,
          glyph: spec.accidentalGlyph!,
          anchor: Offset(spec.accidentalX!, spec.noteY),
          style: errorStyle,
        );
      }
    }
  }
}
