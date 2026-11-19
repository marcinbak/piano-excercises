import 'dart:math' as math;

import 'package:smufl_notation/src/notation_model.dart';
import 'package:smufl_notation/src/score_layout_types.dart';
import 'package:smufl_notation/src/smufl_glyphs.dart';

/// Resolves intra-system and cross-system half-ties across all measures.
abstract final class ScoreTieSolver {
  /// Populates [tiesByMeasureNumber] for all tie chains across [systems].
  static void resolveTies({
    required List<SystemGeometry> systems,
    required Map<int, List<PlacedTieArc>> tiesByMeasureNumber,
    required double staffSpace,
  }) {
    final ctx = _TieContext(
      tiesByMeasureNumber: tiesByMeasureNumber,
      staffSpace: staffSpace,
      headGap: (SmuflGlyphs.noteheadWidthSpaces * 0.52) * staffSpace,
    );
    for (final system in systems) {
      for (final measure in system.measures) {
        for (final slice in measure.slices) {
          _processChordTies(ctx, slice.trebleChord, system, measure);
          _processChordTies(ctx, slice.bassChord, system, measure);
        }
      }
    }
  }

  static void _processChordTies(
    _TieContext ctx,
    PlacedChord? chord,
    SystemGeometry system,
    MeasureGeometry measure,
  ) {
    if (chord == null) {
      return;
    }
    final curveUp = !chord.stemUp;
    for (final head in chord.noteheads) {
      final tie = head.note.tie;
      if (tie == TieFlag.none) {
        continue;
      }
      final key = head.note.noteId != null
          ? '${chord.clef.name}:${head.note.noteId}'
          : '${chord.clef.name}:${head.note.staffStep}';
      if (tie == TieFlag.stop || tie == TieFlag.continueTie) {
        final start = ctx.pending.remove(key);
        if (start != null) {
          _emitTieArcs(ctx, start, system, measure, head, chord.clef, curveUp);
        }
      }
      if (tie == TieFlag.start || tie == TieFlag.continueTie) {
        ctx.pending[key] = _PendingTie(
          system: system,
          measureNumber: measure.measureNumber,
          x: head.centerX,
          y: head.centerY,
          curveUp: curveUp,
        );
      }
    }
  }

  static void _emitTieArcs(
    _TieContext ctx,
    _PendingTie start,
    SystemGeometry endSystem,
    MeasureGeometry endMeasure,
    PlacedNotehead endHead,
    SmuflClef clef,
    bool curveUp,
  ) {
    if (start.system.systemIndex == endSystem.systemIndex) {
      ctx.addArc(
        endMeasure.measureNumber,
        PlacedTieArc(
          clef: clef,
          startX: start.x + ctx.headGap,
          endX: endHead.centerX - ctx.headGap,
          y: endHead.centerY,
          curveUp: start.curveUp,
        ),
      );
      return;
    }
    ctx.addArc(
      start.measureNumber,
      PlacedTieArc(
        clef: clef,
        startX: start.x + ctx.headGap,
        endX: start.system.rightX - (0.35 * ctx.staffSpace),
        y: start.y,
        curveUp: start.curveUp,
      ),
    );
    ctx.addArc(
      endMeasure.measureNumber,
      PlacedTieArc(
        clef: clef,
        startX: math.max(
          endMeasure.leftX + (0.35 * ctx.staffSpace),
          endHead.centerX - (2.2 * ctx.staffSpace),
        ),
        endX: endHead.centerX - ctx.headGap,
        y: endHead.centerY,
        curveUp: curveUp,
      ),
    );
  }
}

final class _TieContext {
  _TieContext({
    required this.tiesByMeasureNumber,
    required this.staffSpace,
    required this.headGap,
  });

  final Map<int, List<PlacedTieArc>> tiesByMeasureNumber;
  final Map<String, _PendingTie> pending = <String, _PendingTie>{};
  final double staffSpace;
  final double headGap;

  void addArc(int measureNumber, PlacedTieArc arc) {
    tiesByMeasureNumber
        .putIfAbsent(measureNumber, () => <PlacedTieArc>[])
        .add(arc);
  }
}

final class _PendingTie {
  const _PendingTie({
    required this.system,
    required this.measureNumber,
    required this.x,
    required this.y,
    required this.curveUp,
  });

  final SystemGeometry system;
  final int measureNumber;
  final double x;
  final double y;
  final bool curveUp;
}
