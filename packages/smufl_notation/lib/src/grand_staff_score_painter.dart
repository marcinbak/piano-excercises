import 'package:flutter/rendering.dart';
import 'package:smufl_notation/src/notation_model.dart';
import 'package:smufl_notation/src/score_layout_types.dart';
import 'package:smufl_notation/src/score_painter_chord_renderer.dart';
import 'package:smufl_notation/src/score_painter_ornaments.dart';
import 'package:smufl_notation/src/score_staff_backdrop_painter.dart';
import 'package:smufl_notation/src/score_wrong_note_painter.dart';
import 'package:smufl_notation/src/smufl_glyphs.dart';

/// Viewport-culled `CustomPainter` rendering an [EngravedScoreLayout].
class GrandStaffScorePainter extends CustomPainter {
  const GrandStaffScorePainter({
    required this.layout,
    this.activeSliceIndex,
    this.dimmedClef,
    this.wrongNoteOverlays = const <WrongNoteOverlay>[],
    this.visibleRect,
  });

  final EngravedScoreLayout layout;
  final int? activeSliceIndex;
  final SmuflClef? dimmedClef;
  final List<WrongNoteOverlay> wrongNoteOverlays;
  final Rect? visibleRect;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || layout.systems.isEmpty) {
      return;
    }
    final style = layout.style;
    final cullRect = visibleRect?.inflate(style.staffSpace * 8.0);
    final activePlacement = activeSliceIndex == null
        ? null
        : layout.slicePlacement(activeSliceIndex!);

    for (final system in layout.systems) {
      if (cullRect != null &&
          (system.bottomY < cullRect.top || system.topY > cullRect.bottom)) {
        continue;
      }
      if (activePlacement != null &&
          activePlacement.system.systemIndex == system.systemIndex) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            activePlacement.slice.cursorRect,
            const Radius.circular(4.0),
          ),
          Paint()..color = style.cursorColor,
        );
      }
      _paintSystem(canvas, system, style);
    }
    _paintOverlays(canvas, style, cullRect);
  }

  void _paintOverlays(Canvas canvas, ScoreStyle style, Rect? cullRect) {
    for (final overlay in wrongNoteOverlays) {
      final target = layout.slicePlacement(overlay.sliceIndex);
      if (target == null) {
        continue;
      }
      if (cullRect != null &&
          (target.system.bottomY < cullRect.top ||
              target.system.topY > cullRect.bottom)) {
        continue;
      }
      ScoreWrongNotePainter.paintOverlay(
        canvas: canvas,
        system: target.system,
        slice: target.slice,
        overlay: overlay,
        style: style,
      );
    }
  }

  void _paintSystem(Canvas canvas, SystemGeometry system, ScoreStyle style) {
    final colors = (
      treble: _clefInk(style, SmuflClef.treble),
      bass: _clefInk(style, SmuflClef.bass),
    );
    ScoreStaffBackdropPainter.paintSystemBackdrop(
      canvas: canvas,
      system: system,
      style: style,
      colors: colors,
    );
    for (final measure in system.measures) {
      _paintMeasure(canvas, system, measure, style, colors);
    }
  }

  void _paintMeasure(
    Canvas canvas,
    SystemGeometry system,
    MeasureGeometry measure,
    ScoreStyle style,
    ({Color treble, Color bass}) colors,
  ) {
    _paintMeasureHeader(canvas, system, measure, style, colors);
    _paintMeasureSlices(canvas, system, measure, style, colors);
    _paintMeasureOrnaments(canvas, measure, system.staffSpace, colors);
    ScorePainterChordRenderer.paintRightBarline(
      canvas,
      system,
      measure,
      style,
      system.staffSpace,
    );
  }

  void _paintMeasureHeader(
    Canvas canvas,
    SystemGeometry system,
    MeasureGeometry measure,
    ScoreStyle style,
    ({Color treble, Color bass}) colors,
  ) {
    for (final acc in measure.keyAccidentals) {
      paintSmuflGlyph(
        canvas: canvas,
        glyph: acc.glyph,
        anchor: Offset(acc.centerX, acc.centerY),
        fontSize: style.fontSize,
        color: acc.clef == SmuflClef.treble ? colors.treble : colors.bass,
        fontFamily: style.fontFamily,
        fontPackage: style.fontPackage,
      );
    }
    if (measure.showTimeSignature &&
        measure.timeSigCenterX != null &&
        measure.beats != null &&
        measure.beatType != null) {
      ScorePainterOrnaments.paintTimeSignature(
        canvas: canvas,
        system: system,
        measure: measure,
        style: style,
        colors: colors,
      );
    }
  }

  void _paintMeasureSlices(
    Canvas canvas,
    SystemGeometry system,
    MeasureGeometry measure,
    ScoreStyle style,
    ({Color treble, Color bass}) colors,
  ) {
    final sp = system.staffSpace;
    for (final slice in measure.slices) {
      ScorePainterChordRenderer.paintChord(
        canvas,
        system,
        slice.trebleChord,
        style,
        colors.treble,
      );
      ScorePainterChordRenderer.paintChord(
        canvas,
        system,
        slice.bassChord,
        style,
        colors.bass,
      );
      ScorePainterChordRenderer.paintRest(
        canvas,
        slice.trebleRest,
        style,
        colors.treble,
        sp,
      );
      ScorePainterChordRenderer.paintRest(
        canvas,
        slice.bassRest,
        style,
        colors.bass,
        sp,
      );
    }
  }

  void _paintMeasureOrnaments(
    Canvas canvas,
    MeasureGeometry measure,
    double sp,
    ({Color treble, Color bass}) colors,
  ) {
    for (final beam in measure.beamGroups) {
      ScorePainterOrnaments.paintBeamGroup(
        canvas: canvas,
        group: beam,
        staffSpace: sp,
        color: beam.clef == SmuflClef.treble ? colors.treble : colors.bass,
      );
    }
    for (final tie in measure.tieArcs) {
      ScorePainterOrnaments.paintTieArc(
        canvas: canvas,
        tie: tie,
        staffSpace: sp,
        color: tie.clef == SmuflClef.treble ? colors.treble : colors.bass,
      );
    }
  }

  Color _clefInk(ScoreStyle style, SmuflClef clef) => dimmedClef == clef
      ? style.inkColor.withValues(alpha: style.dimmedOpacity)
      : style.inkColor;

  @override
  bool shouldRepaint(covariant GrandStaffScorePainter oldDelegate) {
    return !identical(oldDelegate.layout, layout) ||
        oldDelegate.activeSliceIndex != activeSliceIndex ||
        oldDelegate.dimmedClef != dimmedClef ||
        oldDelegate.visibleRect != visibleRect ||
        !_overlaysEqual(oldDelegate.wrongNoteOverlays, wrongNoteOverlays);
  }
}

bool _overlaysEqual(List<WrongNoteOverlay> a, List<WrongNoteOverlay> b) {
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
