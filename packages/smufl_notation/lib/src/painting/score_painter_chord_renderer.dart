import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'package:smufl_notation/src/glyphs/smufl_glyphs.dart';
import 'package:smufl_notation/src/layout/score_layout_geometry.dart';
import 'package:smufl_notation/src/layout/score_layout_types.dart';
import 'package:smufl_notation/src/painting/smufl_glyph_painter.dart';

/// Paints chords, ledger lines, stems, flags, rests, dots, and barlines.
abstract final class ScorePainterChordRenderer {
  static void paintChord(
    Canvas canvas,
    SystemGeometry system,
    PlacedChord? chord,
    ScoreStyle style,
    Color color, {
    bool isDimmed = false,
  }) {
    if (chord == null) {
      return;
    }
    final glyphStyle = style.glyphStyle(color);
    _paintNoteheads(
      canvas,
      system,
      chord,
      style,
      glyphStyle,
      isDimmed: isDimmed,
    );
    for (final acc in chord.accidentals) {
      paintSmuflGlyph(
        canvas: canvas,
        glyph: acc.glyph,
        anchor: Offset(acc.centerX, acc.centerY),
        style: glyphStyle,
      );
    }
    _paintStemAndFlag(canvas, chord, glyphStyle, color, system.staffSpace);
  }

  static void _paintNoteheads(
    Canvas canvas,
    SystemGeometry system,
    PlacedChord chord,
    ScoreStyle style,
    TextStyle glyphStyle, {
    required bool isDimmed,
  }) {
    final sp = system.staffSpace;
    final ledgerColor = isDimmed
        ? style.staffLineColor.withValues(alpha: style.dimmedOpacity)
        : (glyphStyle.color == style.successColor
              ? style.successColor
              : style.staffLineColor);
    final ledgerPaint = Paint()
      ..color = ledgerColor
      ..strokeWidth = math.max(1.0, sp * 0.10);

    for (final head in chord.noteheads) {
      final halfW =
          (head.glyph == SmuflGlyphs.noteheadWhole
              ? SmuflGlyphs.wholeNoteheadWidthSpaces
              : SmuflGlyphs.noteheadWidthSpaces) *
          0.72 *
          sp;
      for (final step in head.ledgerSteps) {
        final ly = system.yForStep(chord.clef, step);
        canvas.drawLine(
          Offset(head.centerX - halfW, ly),
          Offset(head.centerX + halfW, ly),
          ledgerPaint,
        );
      }
      paintSmuflGlyph(
        canvas: canvas,
        glyph: head.glyph,
        anchor: Offset(head.centerX, head.centerY),
        style: glyphStyle,
      );
      if (head.dots > 0 && head.dotStartX != null && head.dotY != null) {
        paintDots(
          canvas,
          (startX: head.dotStartX!, y: head.dotY!, count: head.dots),
          glyphStyle,
          sp,
        );
      }
    }
  }

  static void _paintStemAndFlag(
    Canvas canvas,
    PlacedChord chord,
    TextStyle glyphStyle,
    Color color,
    double sp,
  ) {
    if (chord.stemX == null ||
        chord.stemStartY == null ||
        chord.stemEndY == null) {
      return;
    }
    final stemWidth = math.max(1.0, SmuflGlyphs.stemThicknessSpaces * sp);
    canvas.drawLine(
      Offset(chord.stemX!, chord.stemStartY!),
      Offset(chord.stemX!, chord.stemEndY!),
      Paint()
        ..color = color
        ..strokeWidth = stemWidth,
    );
    if (chord.flagCount > 0) {
      final flagGlyph = _flagGlyph(chord.flagCount, chord.stemUp);
      paintSmuflGlyph(
        canvas: canvas,
        glyph: flagGlyph,
        anchor: Offset(chord.stemX! - (stemWidth * 0.5), chord.stemEndY!),
        style: glyphStyle,
        centerHorizontally: false,
      );
    }
  }

  static String _flagGlyph(int flagCount, bool stemUp) => switch (flagCount) {
    1 => stemUp ? SmuflGlyphs.flag8thUp : SmuflGlyphs.flag8thDown,
    2 => stemUp ? SmuflGlyphs.flag16thUp : SmuflGlyphs.flag16thDown,
    3 => stemUp ? SmuflGlyphs.flag32ndUp : SmuflGlyphs.flag32ndDown,
    _ => stemUp ? SmuflGlyphs.flag64thUp : SmuflGlyphs.flag64thDown,
  };

  static void paintRest(
    Canvas canvas,
    PlacedRest? rest,
    ScoreStyle style,
    Color color,
    double sp,
  ) {
    if (rest == null) {
      return;
    }
    final glyphStyle = style.glyphStyle(color);
    paintSmuflGlyph(
      canvas: canvas,
      glyph: rest.glyph,
      anchor: Offset(rest.centerX, rest.anchorY),
      style: glyphStyle,
    );
    if (rest.dots > 0 && rest.dotStartX != null && rest.dotY != null) {
      paintDots(
        canvas,
        (startX: rest.dotStartX!, y: rest.dotY!, count: rest.dots),
        glyphStyle,
        sp,
      );
    }
  }

  static void paintDots(
    Canvas canvas,
    ({double startX, double y, int count}) dots,
    TextStyle glyphStyle,
    double sp,
  ) {
    for (var i = 0; i < dots.count; i += 1) {
      paintSmuflGlyph(
        canvas: canvas,
        glyph: SmuflGlyphs.augmentationDot,
        anchor: Offset(dots.startX + (i * 0.55 * sp), dots.y),
        style: glyphStyle,
      );
    }
  }

  static void paintRightBarline(
    Canvas canvas,
    SystemGeometry system,
    MeasureGeometry measure,
    ScoreStyle style,
    double sp,
  ) {
    if (measure.isFinalMeasure) {
      final thinX = measure.rightX - (0.55 * sp);
      final thickX = measure.rightX - (0.18 * sp);
      canvas.drawLine(
        Offset(thinX, system.trebleTopY),
        Offset(thinX, system.bassBottomY),
        Paint()
          ..color = style.inkColor
          ..strokeWidth = math.max(1.1, sp * 0.13),
      );
      canvas.drawLine(
        Offset(thickX, system.trebleTopY),
        Offset(thickX, system.bassBottomY),
        Paint()
          ..color = style.inkColor
          ..strokeWidth = math.max(2.4, sp * 0.36),
      );
      return;
    }
    canvas.drawLine(
      Offset(measure.rightX, system.trebleTopY),
      Offset(measure.rightX, system.bassBottomY),
      Paint()
        ..color = style.inkColor
        ..strokeWidth = math.max(1.1, sp * 0.13),
    );
  }
}
