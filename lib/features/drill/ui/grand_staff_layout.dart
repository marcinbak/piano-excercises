import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Responsive staff coordinates and SMuFL rendering helpers for [GrandStaffPainter].
final class GrandStaffLayout {
  const GrandStaffLayout._({
    required this.staffSpace,
    required this.trebleTopY,
    required this.systemLeftX,
    required this.systemRightX,
    required this.targetNoteX,
  });

  factory GrandStaffLayout.fromSize(Size size) {
    final maxFromHeight = size.height / 21.0;
    final maxFromWidth = size.width / 20.0;
    final staffSpace = math.min(maxFromHeight, maxFromWidth).clamp(2.0, 18.0);

    final trebleTopY = (size.height - (13.0 * staffSpace)) / 2;

    final contentWidth = math.min(
      size.width - (2.0 * staffSpace),
      34.0 * staffSpace,
    );
    final leftEdge = (size.width - contentWidth) / 2;
    final systemLeftX = leftEdge + (1.60 * staffSpace);
    final systemRightX = leftEdge + contentWidth;

    final clefCenterX = systemLeftX + (2.2 * staffSpace);
    final noteAreaStart = clefCenterX + (2.8 * staffSpace);
    final noteAreaEnd = systemRightX - (1.6 * staffSpace);
    final targetNoteX = noteAreaStart + ((noteAreaEnd - noteAreaStart) * 0.30);

    return GrandStaffLayout._(
      staffSpace: staffSpace,
      trebleTopY: trebleTopY,
      systemLeftX: systemLeftX,
      systemRightX: systemRightX,
      targetNoteX: targetNoteX,
    );
  }

  static const String smuflFontFamily = 'Bravura';

  final double staffSpace;
  final double trebleTopY;
  final double systemLeftX;
  final double systemRightX;
  final double targetNoteX;

  double get trebleBottomY => trebleTopY + (4.0 * staffSpace);
  double get bassBottomY => trebleBottomY + (9.0 * staffSpace);
  double get clefCenterX => systemLeftX + (2.2 * staffSpace);
  double get wrongColumnX => targetNoteX + (staffSpace * 4.4);
  double get fontSize => staffSpace * 4.0;
  double get braceWidth => 1.05 * staffSpace;
  double get noteWidth => 1.69 * staffSpace;

  double yForStep(Clef clef, int stepsFromBottomLine) {
    final bottomY = clef == Clef.treble ? trebleBottomY : bassBottomY;
    return bottomY - (stepsFromBottomLine * 0.5 * staffSpace);
  }

  /// Horizontal center for an accidental to the left of [noteCenterX].
  double accidentalX(double noteCenterX, {int column = 0}) {
    final offset = 0.75 + (column * 1.10);
    return noteCenterX - (noteWidth * 0.5) - (staffSpace * offset);
  }

  /// Builds a tapered cubic-Bezier piano brace spanning treble top to bass bottom.
  Path buildPianoBracePath() {
    final y0 = trebleTopY;
    final y1 = bassBottomY;
    final yMid = (y0 + y1) / 2;
    final half = (y1 - y0) / 2;
    final xTip = systemLeftX - (staffSpace * 0.35);
    final w = braceWidth;

    return Path()
      ..moveTo(xTip, y0)
      ..cubicTo(
        xTip - (w * 0.95),
        y0 + (half * 0.18),
        xTip + (w * 0.12),
        y0 + (half * 0.72),
        xTip - w,
        yMid,
      )
      ..cubicTo(
        xTip + (w * 0.12),
        y1 - (half * 0.72),
        xTip - (w * 0.95),
        y1 - (half * 0.18),
        xTip,
        y1,
      )
      ..cubicTo(
        xTip - (w * 0.72),
        y1 - (half * 0.18),
        xTip + (w * 0.34),
        y1 - (half * 0.72),
        xTip - (w * 0.84),
        yMid,
      )
      ..cubicTo(
        xTip + (w * 0.34),
        y0 + (half * 0.72),
        xTip - (w * 0.72),
        y0 + (half * 0.18),
        xTip,
        y0,
      )
      ..close();
  }
}

/// Draws a SMuFL glyph with its alphabetic baseline aligned to [centerAnchor.dy].
void paintSmuflGlyph({
  required Canvas canvas,
  required String glyph,
  required Offset centerAnchor,
  required double fontSize,
  required Color color,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: glyph,
      style: TextStyle(
        fontFamily: GrandStaffLayout.smuflFontFamily,
        fontSize: fontSize,
        height: 1.0,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  try {
    painter.layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.paint(
      canvas,
      Offset(centerAnchor.dx - (painter.width / 2), centerAnchor.dy - baseline),
    );
  } finally {
    painter.dispose();
  }
}
