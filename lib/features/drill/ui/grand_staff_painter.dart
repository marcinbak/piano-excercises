import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/drill/ui/grand_staff_layout.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Paints a responsive SMuFL grand staff with target and wrong played notes.
class GrandStaffPainter extends CustomPainter {
  const GrandStaffPainter({
    required this.targetNote,
    required this.wrongPlayedNotes,
    required this.inkColor,
    required this.errorColor,
    required this.staffLineColor,
  });

  static const String _gClefGlyph = '\uE050';
  static const String _fClefGlyph = '\uE062';
  static const String _wholeNoteGlyph = '\uE0A2';
  static const String _sharpGlyph = '\uE262';
  static const String _flatGlyph = '\uE260';
  static const String _doubleSharpGlyph = '\uE263';
  static const String _doubleFlatGlyph = '\uE264';
  static const int _maxLedgerLines = 8;

  final StaffNote targetNote;
  final List<StaffNote> wrongPlayedNotes;
  final Color inkColor;
  final Color errorColor;
  final Color staffLineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final layout = GrandStaffLayout.fromSize(size);
    _paintStavesAndBarlines(canvas, layout);
    canvas.drawPath(layout.buildPianoBracePath(), Paint()..color = inkColor);
    _paintClefs(canvas, layout);
    _paintNote(
      canvas,
      layout,
      size: size,
      note: targetNote,
      centerX: layout.targetNoteX,
      color: inkColor,
    );
    _paintWrongNotes(canvas, layout, size);
  }

  void _paintStavesAndBarlines(Canvas canvas, GrandStaffLayout layout) {
    final staffPaint = Paint()
      ..color = staffLineColor
      ..strokeWidth = math.max(1.0, layout.staffSpace * 0.09);

    for (var line = 0; line < 5; line += 1) {
      final step = line * 2;
      final trebleY = layout.yForStep(Clef.treble, step);
      final bassY = layout.yForStep(Clef.bass, step);
      canvas.drawLine(
        Offset(layout.systemLeftX, trebleY),
        Offset(layout.systemRightX, trebleY),
        staffPaint,
      );
      canvas.drawLine(
        Offset(layout.systemLeftX, bassY),
        Offset(layout.systemRightX, bassY),
        staffPaint,
      );
    }

    final barPaint = Paint()
      ..color = inkColor
      ..strokeWidth = math.max(1.2, layout.staffSpace * 0.14);
    canvas.drawLine(
      Offset(layout.systemLeftX, layout.trebleTopY),
      Offset(layout.systemLeftX, layout.bassBottomY),
      barPaint,
    );
    canvas.drawLine(
      Offset(layout.systemRightX, layout.trebleTopY),
      Offset(layout.systemRightX, layout.bassBottomY),
      barPaint,
    );
  }

  void _paintClefs(Canvas canvas, GrandStaffLayout layout) {
    paintSmuflGlyph(
      canvas: canvas,
      glyph: _gClefGlyph,
      centerAnchor: Offset(
        layout.clefCenterX,
        layout.yForStep(Clef.treble, Clef.treble.referenceLineOffset),
      ),
      fontSize: layout.fontSize,
      color: inkColor,
    );
    paintSmuflGlyph(
      canvas: canvas,
      glyph: _fClefGlyph,
      centerAnchor: Offset(
        layout.clefCenterX,
        layout.yForStep(Clef.bass, Clef.bass.referenceLineOffset),
      ),
      fontSize: layout.fontSize,
      color: inkColor,
    );
  }

  void _paintWrongNotes(Canvas canvas, GrandStaffLayout layout, Size size) {
    for (final placement in layout.computeWrongNotePlacements(
      wrongPlayedNotes,
    )) {
      _paintNote(
        canvas,
        layout,
        size: size,
        note: placement.note,
        centerX: placement.noteX,
        accidentalCenterX: placement.accidentalX,
        color: errorColor,
      );
    }
  }

  void _paintNote(
    Canvas canvas,
    GrandStaffLayout layout, {
    required Size size,
    required StaffNote note,
    required double centerX,
    required Color color,
    double? accidentalCenterX,
  }) {
    final minY = layout.staffSpace;
    final maxY = math.max(minY, size.height - layout.staffSpace);
    final rawY = layout.yForStep(
      note.clef,
      note.staffPosition.stepsFromBottomLine,
    );
    final noteY = rawY.clamp(minY, maxY);

    _paintLedgerLines(
      canvas,
      layout,
      note: note,
      centerX: centerX,
      minY: minY,
      maxY: maxY,
      color: color,
    );

    paintSmuflGlyph(
      canvas: canvas,
      glyph: _wholeNoteGlyph,
      centerAnchor: Offset(centerX, noteY),
      fontSize: layout.fontSize,
      color: color,
    );

    _paintAccidental(
      canvas,
      layout,
      note: note,
      centerX: centerX,
      noteY: noteY,
      color: color,
      accidentalCenterX: accidentalCenterX,
    );
  }

  void _paintLedgerLines(
    Canvas canvas,
    GrandStaffLayout layout, {
    required StaffNote note,
    required double centerX,
    required double minY,
    required double maxY,
    required Color color,
  }) {
    final ledgerPaint = Paint()
      ..color = color == inkColor ? staffLineColor : color
      ..strokeWidth = math.max(1.0, layout.staffSpace * 0.10);
    final ledgerHalfWidth = layout.noteWidth * 0.72;
    for (final step in note.staffPosition.ledgerLineSteps.take(
      _maxLedgerLines,
    )) {
      final ledgerY = layout.yForStep(note.clef, step);
      if (ledgerY < minY || ledgerY > maxY) {
        continue;
      }
      canvas.drawLine(
        Offset(centerX - ledgerHalfWidth, ledgerY),
        Offset(centerX + ledgerHalfWidth, ledgerY),
        ledgerPaint,
      );
    }
  }

  void _paintAccidental(
    Canvas canvas,
    GrandStaffLayout layout, {
    required StaffNote note,
    required double centerX,
    required double noteY,
    required Color color,
    double? accidentalCenterX,
  }) {
    final accidentalGlyph = switch (note.accidental) {
      Accidental.doubleSharp => _doubleSharpGlyph,
      Accidental.sharp => _sharpGlyph,
      Accidental.flat => _flatGlyph,
      Accidental.doubleFlat => _doubleFlatGlyph,
      Accidental.natural => null,
    };
    if (accidentalGlyph == null) {
      return;
    }
    final accX = accidentalCenterX ?? layout.accidentalX(centerX);
    paintSmuflGlyph(
      canvas: canvas,
      glyph: accidentalGlyph,
      centerAnchor: Offset(accX, noteY),
      fontSize: layout.fontSize,
      color: color,
    );
  }

  @override
  bool shouldRepaint(covariant GrandStaffPainter oldDelegate) {
    return oldDelegate.targetNote != targetNote ||
        !_noteListsEqual(oldDelegate.wrongPlayedNotes, wrongPlayedNotes) ||
        oldDelegate.inkColor != inkColor ||
        oldDelegate.errorColor != errorColor ||
        oldDelegate.staffLineColor != staffLineColor;
  }
}

bool _noteListsEqual(List<StaffNote> a, List<StaffNote> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
