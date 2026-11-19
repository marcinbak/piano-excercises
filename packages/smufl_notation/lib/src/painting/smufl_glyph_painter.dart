import 'package:flutter/painting.dart';

import 'package:smufl_notation/src/layout/score_layout_geometry.dart';

/// SMuFL `TextStyle` builder on [ScoreStyle] for `painting/` renderers.
extension ScoreStyleGlyphExtension on ScoreStyle {
  /// Builds a SMuFL `TextStyle` sized to [fontSize] with [color].
  TextStyle glyphStyle(Color color) => TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: fontSize,
    height: 1.0,
    color: color,
  );
}

/// Paints a SMuFL glyph with its alphabetic baseline aligned to [anchor.dy].
void paintSmuflGlyph({
  required Canvas canvas,
  required String glyph,
  required Offset anchor,
  required TextStyle style,
  bool centerHorizontally = true,
}) {
  final painter = TextPainter(
    text: TextSpan(text: glyph, style: style),
    textDirection: TextDirection.ltr,
  );
  // SMuFL aligns glyphs via alphabetic baseline; always dispose TextPainter.
  try {
    painter.layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final dx = centerHorizontally ? anchor.dx - (painter.width / 2) : anchor.dx;
    painter.paint(canvas, Offset(dx, anchor.dy - baseline));
  } finally {
    painter.dispose();
  }
}
