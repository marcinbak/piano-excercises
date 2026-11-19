import 'dart:math' as math;
import 'dart:ui';

import 'package:smufl_notation/src/score_layout_types.dart';
import 'package:smufl_notation/src/smufl_glyphs.dart';

/// Paints chords, ledger lines, stems, flags, rests, dots, and barlines.
abstract final class ScorePainterChordRenderer {
  static void paintChord(
    Canvas canvas,
    SystemGeometry system,
    PlacedChord? chord,
    ScoreStyle style,
    Color color,
  ) {
    if (chord == null) {
      return;
    }
    final sp = system.staffSpace;
    final stemWidth = math.max(1.0, SmuflGlyphs.stemThicknessSpaces * sp);
    final ledgerPaint = Paint()
      ..color = style.staffLineColor
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
        fontSize: style.fontSize,
        color: color,
        fontFamily: style.fontFamily,
        fontPackage: style.fontPackage,
      );
      paintDots(canvas, head.dotStartX, head.dotY, head.dots, style, color, sp);
    }

    for (final acc in chord.accidentals) {
      paintSmuflGlyph(
        canvas: canvas,
        glyph: acc.glyph,
        anchor: Offset(acc.centerX, acc.centerY),
        fontSize: style.fontSize,
        color: color,
        fontFamily: style.fontFamily,
        fontPackage: style.fontPackage,
      );
    }

    if (chord.stemX != null &&
        chord.stemStartY != null &&
        chord.stemEndY != null) {
      canvas.drawLine(
        Offset(chord.stemX!, chord.stemStartY!),
        Offset(chord.stemX!, chord.stemEndY!),
        Paint()
          ..color = color
          ..strokeWidth = stemWidth,
      );
      if (chord.flagCount > 0) {
        final flagGlyph = chord.flagCount >= 2
            ? (chord.stemUp ? SmuflGlyphs.flag16thUp : SmuflGlyphs.flag16thDown)
            : (chord.stemUp ? SmuflGlyphs.flag8thUp : SmuflGlyphs.flag8thDown);
        paintSmuflGlyph(
          canvas: canvas,
          glyph: flagGlyph,
          anchor: Offset(chord.stemX! - (stemWidth * 0.5), chord.stemEndY!),
          fontSize: style.fontSize,
          color: color,
          fontFamily: style.fontFamily,
          fontPackage: style.fontPackage,
          centerHorizontally: false,
        );
      }
    }
  }

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
    paintSmuflGlyph(
      canvas: canvas,
      glyph: rest.glyph,
      anchor: Offset(rest.centerX, rest.anchorY),
      fontSize: style.fontSize,
      color: color,
      fontFamily: style.fontFamily,
      fontPackage: style.fontPackage,
    );
    paintDots(canvas, rest.dotStartX, rest.dotY, rest.dots, style, color, sp);
  }

  static void paintDots(
    Canvas canvas,
    double? startX,
    double? y,
    int dots,
    ScoreStyle style,
    Color color,
    double sp,
  ) {
    if (dots <= 0 || startX == null || y == null) {
      return;
    }
    for (var i = 0; i < dots; i += 1) {
      paintSmuflGlyph(
        canvas: canvas,
        glyph: SmuflGlyphs.augmentationDot,
        anchor: Offset(startX + (i * 0.55 * sp), y),
        fontSize: style.fontSize,
        color: color,
        fontFamily: style.fontFamily,
        fontPackage: style.fontPackage,
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
