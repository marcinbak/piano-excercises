import 'dart:math' as math;

import 'package:smufl_notation/src/glyphs/smufl_glyphs.dart';
import 'package:smufl_notation/src/layout/score_layout_geometry.dart';
import 'package:smufl_notation/src/layout/score_layout_types.dart';
import 'package:smufl_notation/src/model/notation_model.dart';

/// Resolves intra-system and cross-system half-ties across all measures.
abstract final class ScoreTieSolver {
  /// Populates [tiesByMeasureIndex] for all tie chains across [systems].
  static void resolveTies({
    required List<SystemGeometry> systems,
    required Map<int, List<PlacedTieArc>> tiesByMeasureIndex,
    required double staffSpace,
  }) {
    final ctx = _TieContext(
      tiesByMeasureIndex: tiesByMeasureIndex,
      staffSpace: staffSpace,
      headGap: (SmuflGlyphs.noteheadWidthSpaces * 0.52) * staffSpace,
    );
    var measureIndex = 0;
    for (final system in systems) {
      for (final measure in system.measures) {
        for (final slice in measure.slices) {
          _processChordTies(
            ctx,
            slice.trebleChord,
            system,
            slice,
            measureIndex,
          );
          _processChordTies(ctx, slice.bassChord, system, slice, measureIndex);
        }
        measureIndex += 1;
      }
    }
  }

  static void _processChordTies(
    _TieContext ctx,
    PlacedChord? chord,
    SystemGeometry system,
    SliceGeometry slice,
    int measureIndex,
  ) {
    if (chord == null) {
      return;
    }
    final defaultCurveUp = !chord.stemUp;
    final heads = chord.noteheads;
    for (var i = 0; i < heads.length; i += 1) {
      final head = heads[i];
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
          final endCurveUp = _resolveTieCurveUp(
            heads,
            i,
            isOutgoing: false,
            defaultCurveUp: defaultCurveUp,
          );
          _emitTieArcs(ctx, start, (
            system: system,
            slice: slice,
            measureIndex: measureIndex,
            head: head,
            clef: chord.clef,
            curveUp: endCurveUp,
          ));
        }
      }
      if (tie == TieFlag.start || tie == TieFlag.continueTie) {
        final startCurveUp = _resolveTieCurveUp(
          heads,
          i,
          isOutgoing: true,
          defaultCurveUp: defaultCurveUp,
        );
        ctx.pending[key] = _PendingTie(
          system: system,
          measureIndex: measureIndex,
          x: head.centerX,
          y: head.centerY,
          curveUp: startCurveUp,
        );
      }
    }
  }

  static bool _resolveTieCurveUp(
    List<PlacedNotehead> heads,
    int index, {
    required bool isOutgoing,
    required bool defaultCurveUp,
  }) {
    var firstTied = -1;
    var lastTied = -1;
    var count = 0;
    for (var i = 0; i < heads.length; i += 1) {
      final tie = heads[i].note.tie;
      final matches = isOutgoing
          ? (tie == TieFlag.start || tie == TieFlag.continueTie)
          : (tie == TieFlag.stop || tie == TieFlag.continueTie);
      if (matches) {
        if (firstTied == -1) {
          firstTied = i;
        }
        lastTied = i;
        count += 1;
      }
    }
    if (count < 2) {
      return defaultCurveUp;
    }
    if (index == firstTied) {
      return false;
    }
    if (index == lastTied) {
      return true;
    }
    return defaultCurveUp;
  }

  static void _emitTieArcs(
    _TieContext ctx,
    _PendingTie start,
    ({
      SystemGeometry system,
      SliceGeometry slice,
      int measureIndex,
      PlacedNotehead head,
      SmuflClef clef,
      bool curveUp,
    })
    end,
  ) {
    if (start.system.systemIndex == end.system.systemIndex) {
      ctx.addArc(
        end.measureIndex,
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
      start.measureIndex,
      PlacedTieArc(
        clef: end.clef,
        startX: start.x + ctx.headGap,
        endX: start.system.rightX - (0.35 * ctx.staffSpace),
        y: start.y,
        curveUp: start.curveUp,
      ),
    );
    ctx.addArc(
      end.measureIndex,
      PlacedTieArc(
        clef: end.clef,
        startX: math.max(
          end.slice.cursorRect.left,
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
    required this.tiesByMeasureIndex,
    required this.staffSpace,
    required this.headGap,
  });

  final Map<int, List<PlacedTieArc>> tiesByMeasureIndex;
  final Map<String, _PendingTie> pending = <String, _PendingTie>{};
  final double staffSpace;
  final double headGap;

  void addArc(int measureIndex, PlacedTieArc arc) {
    tiesByMeasureIndex
        .putIfAbsent(measureIndex, () => <PlacedTieArc>[])
        .add(arc);
  }
}

final class _PendingTie {
  const _PendingTie({
    required this.system,
    required this.measureIndex,
    required this.x,
    required this.y,
    required this.curveUp,
  });

  final SystemGeometry system;
  final int measureIndex;
  final double x;
  final double y;
  final bool curveUp;
}
