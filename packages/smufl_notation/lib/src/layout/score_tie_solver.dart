import 'dart:math' as math;

import 'package:smufl_notation/src/glyphs/smufl_glyphs.dart';
import 'package:smufl_notation/src/layout/score_layout_geometry.dart';
import 'package:smufl_notation/src/layout/score_layout_types.dart';
import 'package:smufl_notation/src/model/notation_model.dart';

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
          _emitTieArcs(ctx, start, (
            system: system,
            measure: measure,
            head: head,
            clef: chord.clef,
            curveUp: curveUp,
          ));
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
    ({
      SystemGeometry system,
      MeasureGeometry measure,
      PlacedNotehead head,
      SmuflClef clef,
      bool curveUp,
    })
    end,
  ) {
    if (start.system.systemIndex == end.system.systemIndex) {
      ctx.addArc(
        end.measure.measureNumber,
        PlacedTieArc(
          clef: end.clef,
          startX: start.x + ctx.headGap,
          endX: end.head.centerX - ctx.headGap,
          y: end.head.centerY,
          curveUp: start.curveUp,
        ),
      );
      return;
    }
    ctx.addArc(
      start.measureNumber,
      PlacedTieArc(
        clef: end.clef,
        startX: start.x + ctx.headGap,
        endX: start.system.rightX - (0.35 * ctx.staffSpace),
        y: start.y,
        curveUp: start.curveUp,
      ),
    );
    ctx.addArc(
      end.measure.measureNumber,
      PlacedTieArc(
        clef: end.clef,
        startX: math.max(
          end.measure.leftX + (0.35 * ctx.staffSpace),
          end.head.centerX - (2.2 * ctx.staffSpace),
        ),
        endX: end.head.centerX - ctx.headGap,
        y: end.head.centerY,
        curveUp: end.curveUp,
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
