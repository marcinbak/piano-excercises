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
    final pending = <String, _PendingTie>{};
    final headGap = (SmuflGlyphs.noteheadWidthSpaces * 0.52) * staffSpace;

    for (final system in systems) {
      for (final measure in system.measures) {
        for (final slice in measure.slices) {
          _processChordTies(
            chord: slice.trebleChord,
            clef: SmuflClef.treble,
            system: system,
            measure: measure,
            headGap: headGap,
            staffSpace: staffSpace,
            pending: pending,
            tiesByMeasureNumber: tiesByMeasureNumber,
          );
          _processChordTies(
            chord: slice.bassChord,
            clef: SmuflClef.bass,
            system: system,
            measure: measure,
            headGap: headGap,
            staffSpace: staffSpace,
            pending: pending,
            tiesByMeasureNumber: tiesByMeasureNumber,
          );
        }
      }
    }
  }

  static void _processChordTies({
    required PlacedChord? chord,
    required SmuflClef clef,
    required SystemGeometry system,
    required MeasureGeometry measure,
    required double headGap,
    required double staffSpace,
    required Map<String, _PendingTie> pending,
    required Map<int, List<PlacedTieArc>> tiesByMeasureNumber,
  }) {
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
          ? '${clef.name}:${head.note.noteId}'
          : '${clef.name}:${head.note.staffStep}';
      if (tie == TieFlag.stop || tie == TieFlag.continueTie) {
        final start = pending.remove(key);
        if (start != null) {
          _emitTieArcs(
            start: start,
            endSystem: system,
            endMeasure: measure,
            endHead: head,
            clef: clef,
            headGap: headGap,
            staffSpace: staffSpace,
            curveUp: curveUp,
            tiesByMeasureNumber: tiesByMeasureNumber,
          );
        }
      }
      if (tie == TieFlag.start || tie == TieFlag.continueTie) {
        pending[key] = _PendingTie(
          system: system,
          measureNumber: measure.measureNumber,
          x: head.centerX,
          y: head.centerY,
          curveUp: curveUp,
        );
      }
    }
  }

  static void _emitTieArcs({
    required _PendingTie start,
    required SystemGeometry endSystem,
    required MeasureGeometry endMeasure,
    required PlacedNotehead endHead,
    required SmuflClef clef,
    required double headGap,
    required double staffSpace,
    required bool curveUp,
    required Map<int, List<PlacedTieArc>> tiesByMeasureNumber,
  }) {
    if (start.system.systemIndex == endSystem.systemIndex) {
      tiesByMeasureNumber
          .putIfAbsent(endMeasure.measureNumber, () => <PlacedTieArc>[])
          .add(
            PlacedTieArc(
              clef: clef,
              startX: start.x + headGap,
              endX: endHead.centerX - headGap,
              y: endHead.centerY,
              curveUp: start.curveUp,
            ),
          );
      return;
    }
    tiesByMeasureNumber
        .putIfAbsent(start.measureNumber, () => <PlacedTieArc>[])
        .add(
          PlacedTieArc(
            clef: clef,
            startX: start.x + headGap,
            endX: start.system.rightX - (0.35 * staffSpace),
            y: start.y,
            curveUp: start.curveUp,
          ),
        );
    tiesByMeasureNumber
        .putIfAbsent(endMeasure.measureNumber, () => <PlacedTieArc>[])
        .add(
          PlacedTieArc(
            clef: clef,
            startX: math.max(
              endMeasure.leftX + (0.35 * staffSpace),
              endHead.centerX - (2.2 * staffSpace),
            ),
            endX: endHead.centerX - headGap,
            y: endHead.centerY,
            curveUp: curveUp,
          ),
        );
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
