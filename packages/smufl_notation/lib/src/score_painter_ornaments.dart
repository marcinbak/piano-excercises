import 'dart:math' as math;
import 'dart:ui';

import 'package:smufl_notation/src/notation_model.dart';
import 'package:smufl_notation/src/score_layout_types.dart';
import 'package:smufl_notation/src/smufl_glyphs.dart';

/// Canvas helpers for braces, time signatures, beams, and tie arcs.
abstract final class ScorePainterOrnaments {
  static Path buildPianoBracePath({
    required double xTip,
    required double topY,
    required double bottomY,
    required double width,
  }) {
    final yMid = (topY + bottomY) / 2;
    final half = (bottomY - topY) / 2;
    return Path()
      ..moveTo(xTip, topY)
      ..cubicTo(
        xTip - (width * 0.95),
        topY + (half * 0.18),
        xTip + (width * 0.12),
        topY + (half * 0.72),
        xTip - width,
        yMid,
      )
      ..cubicTo(
        xTip + (width * 0.12),
        bottomY - (half * 0.72),
        xTip - (width * 0.95),
        bottomY - (half * 0.18),
        xTip,
        bottomY,
      )
      ..cubicTo(
        xTip - (width * 0.72),
        bottomY - (half * 0.18),
        xTip + (width * 0.34),
        bottomY - (half * 0.72),
        xTip - (width * 0.84),
        yMid,
      )
      ..cubicTo(
        xTip + (width * 0.34),
        topY + (half * 0.72),
        xTip - (width * 0.72),
        topY + (half * 0.18),
        xTip,
        topY,
      )
      ..close();
  }

  static void paintTimeSignature({
    required Canvas canvas,
    required SystemGeometry system,
    required double centerX,
    required int beats,
    required int beatType,
    required ScoreStyle style,
    required Color trebleColor,
    required Color bassColor,
  }) {
    for (final entry in <(SmuflClef, Color)>[
      (SmuflClef.treble, trebleColor),
      (SmuflClef.bass, bassColor),
    ]) {
      _paintDigits(
        canvas: canvas,
        number: beats,
        centerX: centerX,
        y: system.yForStep(entry.$1, 6),
        style: style,
        color: entry.$2,
      );
      _paintDigits(
        canvas: canvas,
        number: beatType,
        centerX: centerX,
        y: system.yForStep(entry.$1, 2),
        style: style,
        color: entry.$2,
      );
    }
  }

  static void _paintDigits({
    required Canvas canvas,
    required int number,
    required double centerX,
    required double y,
    required ScoreStyle style,
    required Color color,
  }) {
    final text = number.toString();
    final stepX = style.staffSpace * 1.35;
    final startX = centerX - ((text.length - 1) * stepX * 0.5);
    for (var i = 0; i < text.length; i += 1) {
      paintSmuflGlyph(
        canvas: canvas,
        glyph: SmuflGlyphs.timeSigDigit(int.parse(text[i])),
        anchor: Offset(startX + (i * stepX), y),
        fontSize: style.fontSize,
        color: color,
        fontFamily: style.fontFamily,
        fontPackage: style.fontPackage,
      );
    }
  }

  static void paintBeamGroup({
    required Canvas canvas,
    required PlacedBeamGroup group,
    required double staffSpace,
    required Color color,
  }) {
    if (group.chords.length < 2) {
      return;
    }
    final cFirst = group.chords.first;
    final cLast = group.chords.last;
    final dx = cLast.stemX - cFirst.stemX;
    if (dx <= 0) {
      return;
    }
    final slope = (cLast.stemTipY - cFirst.stemTipY) / dx;
    final thick = SmuflGlyphs.beamThicknessSpaces * staffSpace;
    final stepOff =
        (SmuflGlyphs.beamThicknessSpaces + SmuflGlyphs.beamSpacingSpaces) *
        staffSpace;
    final dir = group.stemUp ? 1.0 : -1.0;
    final stemHalf =
        math.max(1.0, SmuflGlyphs.stemThicknessSpaces * staffSpace) * 0.5;
    final paint = Paint()..color = color;
    double yAt(double x) => cFirst.stemTipY + (slope * (x - cFirst.stemX));

    _drawQuad(
      canvas,
      cFirst.stemX - stemHalf,
      cLast.stemX + stemHalf,
      yAt(cFirst.stemX - stemHalf),
      yAt(cLast.stemX + stemHalf),
      dir * thick,
      paint,
    );

    var i = 0;
    while (i < group.chords.length) {
      if (group.chords[i].beamCount < 2) {
        i += 1;
        continue;
      }
      var end = i + 1;
      while (end < group.chords.length && group.chords[end].beamCount >= 2) {
        end += 1;
      }
      final shift = dir * stepOff;
      final sx0 = end - i >= 2
          ? group.chords[i].stemX - stemHalf
          : (i == 0
                ? group.chords[i].stemX
                : group.chords[i].stemX -
                      math.min(staffSpace * 0.95, dx * 0.45));
      final sx1 = end - i >= 2
          ? group.chords[end - 1].stemX + stemHalf
          : (i == 0
                ? group.chords[i].stemX + math.min(staffSpace * 0.95, dx * 0.45)
                : group.chords[i].stemX);
      _drawQuad(
        canvas,
        sx0,
        sx1,
        yAt(sx0) + shift,
        yAt(sx1) + shift,
        dir * thick,
        paint,
      );
      i = end;
    }
  }

  static void _drawQuad(
    Canvas canvas,
    double x0,
    double x1,
    double y0,
    double y1,
    double dy,
    Paint paint,
  ) {
    final path = Path()
      ..moveTo(x0, y0)
      ..lineTo(x1, y1)
      ..lineTo(x1, y1 + dy)
      ..lineTo(x0, y0 + dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void paintTieArc({
    required Canvas canvas,
    required PlacedTieArc tie,
    required double staffSpace,
    required Color color,
  }) {
    final span = tie.endX - tie.startX;
    if (span <= 1.0) {
      return;
    }
    final dir = tie.curveUp ? -1.0 : 1.0;
    final midX = (tie.startX + tie.endX) * 0.5;
    final arch = (span * 0.16).clamp(0.55 * staffSpace, 1.65 * staffSpace);
    final thick = math.max(1.3, 0.22 * staffSpace);
    final y0 = tie.y + (dir * 0.35 * staffSpace);
    final path = Path()
      ..moveTo(tie.startX, y0)
      ..quadraticBezierTo(midX, y0 + (dir * (arch + thick)), tie.endX, y0)
      ..quadraticBezierTo(midX, y0 + (dir * arch), tie.startX, y0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }
}
