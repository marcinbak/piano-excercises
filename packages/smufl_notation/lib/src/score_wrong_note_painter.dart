import 'dart:math' as math;
import 'dart:ui';

import 'package:smufl_notation/src/chord_collision_solver.dart';
import 'package:smufl_notation/src/notation_model.dart';
import 'package:smufl_notation/src/score_layout_engine.dart';
import 'package:smufl_notation/src/score_layout_types.dart';
import 'package:smufl_notation/src/smufl_glyphs.dart';

/// Paints red [WrongNoteOverlay] chords with ledger lines and accidentals.
abstract final class ScoreWrongNotePainter {
  static void paintOverlay({
    required Canvas canvas,
    required SystemGeometry system,
    required SliceGeometry slice,
    required WrongNoteOverlay overlay,
    required ScoreStyle style,
  }) {
    final sp = system.staffSpace;
    final availRight = math.max(0.0, slice.cursorRect.right - slice.centerX);
    final wrongX = slice.centerX + math.min(1.25 * sp, availRight * 0.4);

    for (final clef in SmuflClef.values) {
      final clefNotes = overlay.notes
          .where((note) => note.clef == clef)
          .toList(growable: false);
      if (clefNotes.isEmpty) {
        continue;
      }
      final solved = ChordCollisionSolver.solveNotes(clefNotes, hasStem: false);
      final ledgerPaint = Paint()
        ..color = style.errorColor
        ..strokeWidth = math.max(1.0, sp * 0.10);
      final ledgerHalf = (SmuflGlyphs.wholeNoteheadWidthSpaces * 0.72) * sp;
      final accBase =
          wrongX - ((SmuflGlyphs.wholeNoteheadWidthSpaces * 0.5 + 0.65) * sp);

      for (final p in solved.placements) {
        final nx = wrongX + (p.horizontalShiftSpaces * sp);
        final ny = system
            .yForStep(clef, p.note.staffStep)
            .clamp(system.topY + (0.5 * sp), system.bottomY - (0.5 * sp));
        for (final step in ScoreLayoutEngine.ledgerStepsFor(p.note.staffStep)) {
          final ly = system.yForStep(clef, step);
          if (ly >= system.topY && ly <= system.bottomY) {
            canvas.drawLine(
              Offset(nx - ledgerHalf, ly),
              Offset(nx + ledgerHalf, ly),
              ledgerPaint,
            );
          }
        }
        paintSmuflGlyph(
          canvas: canvas,
          glyph: SmuflGlyphs.noteheadWhole,
          anchor: Offset(nx, ny),
          fontSize: style.fontSize,
          color: style.errorColor,
          fontFamily: style.fontFamily,
          fontPackage: style.fontPackage,
        );
        final acc = p.note.displayedAccidental;
        if (p.accidentalColumn != null && acc != null) {
          final ax =
              accBase -
              (p.accidentalColumn! *
                  SmuflGlyphs.accidentalColumnSpacingSpaces *
                  sp);
          paintSmuflGlyph(
            canvas: canvas,
            glyph: acc.glyph,
            anchor: Offset(ax, ny),
            fontSize: style.fontSize,
            color: style.errorColor,
            fontFamily: style.fontFamily,
            fontPackage: style.fontPackage,
          );
        }
      }
    }
  }
}
