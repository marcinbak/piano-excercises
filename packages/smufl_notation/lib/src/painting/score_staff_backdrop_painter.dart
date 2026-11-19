import 'dart:math' as math;
import 'dart:ui';

import 'package:smufl_notation/src/glyphs/smufl_glyphs.dart';
import 'package:smufl_notation/src/layout/score_layout_geometry.dart';
import 'package:smufl_notation/src/layout/score_layout_types.dart';
import 'package:smufl_notation/src/model/notation_model.dart';
import 'package:smufl_notation/src/painting/score_painter_ornaments.dart';
import 'package:smufl_notation/src/painting/smufl_glyph_painter.dart';

/// Paints five-line grand staves, piano brace, left barline, and clefs.
abstract final class ScoreStaffBackdropPainter {
  static void paintSystemBackdrop({
    required Canvas canvas,
    required SystemGeometry system,
    required ScoreStyle style,
    required ({Color treble, Color bass}) colors,
  }) {
    _paintStaffLinesAndBrace(canvas, system, style);
    _paintClefs(canvas, system, style, colors);
  }

  static void _paintStaffLinesAndBrace(
    Canvas canvas,
    SystemGeometry system,
    ScoreStyle style,
  ) {
    final sp = system.staffSpace;
    final staffPaint = Paint()
      ..color = style.staffLineColor
      ..strokeWidth = math.max(1.0, sp * 0.09);

    for (var line = 0; line < 5; line += 1) {
      final step = line * 2;
      final ty = system.yForStep(SmuflClef.treble, step);
      final by = system.yForStep(SmuflClef.bass, step);
      canvas.drawLine(
        Offset(system.leftX, ty),
        Offset(system.rightX, ty),
        staffPaint,
      );
      canvas.drawLine(
        Offset(system.leftX, by),
        Offset(system.rightX, by),
        staffPaint,
      );
    }

    canvas.drawPath(
      ScorePainterOrnaments.buildPianoBracePath(
        xTip: system.leftX - (sp * 0.35),
        topY: system.trebleTopY,
        bottomY: system.bassBottomY,
        width: sp * 1.05,
      ),
      Paint()..color = style.inkColor,
    );

    canvas.drawLine(
      Offset(system.leftX, system.trebleTopY),
      Offset(system.leftX, system.bassBottomY),
      Paint()
        ..color = style.inkColor
        ..strokeWidth = math.max(1.2, sp * 0.14),
    );
  }

  static void _paintClefs(
    Canvas canvas,
    SystemGeometry system,
    ScoreStyle style,
    ({Color treble, Color bass}) colors,
  ) {
    paintSmuflGlyph(
      canvas: canvas,
      glyph: SmuflGlyphs.gClef,
      anchor: Offset(
        system.clefCenterX,
        system.yForStep(SmuflClef.treble, SmuflClef.treble.referenceStep),
      ),
      style: style.glyphStyle(colors.treble),
    );
    paintSmuflGlyph(
      canvas: canvas,
      glyph: SmuflGlyphs.fClef,
      anchor: Offset(
        system.clefCenterX,
        system.yForStep(SmuflClef.bass, SmuflClef.bass.referenceStep),
      ),
      style: style.glyphStyle(colors.bass),
    );
  }
}
