import 'dart:math' as math;
import 'dart:ui';

import 'package:smufl_notation/src/layout/score_layout_geometry.dart';
import 'package:smufl_notation/src/layout/score_layout_types.dart';
import 'package:smufl_notation/src/layout/score_measure_placer.dart';
import 'package:smufl_notation/src/layout/score_measure_preparer.dart';
import 'package:smufl_notation/src/layout/score_tie_solver.dart';
import 'package:smufl_notation/src/model/notation_model.dart';
import 'package:smufl_notation/src/model/notation_score_model.dart';

/// Pure-Dart multi-system grand-staff engraving and layout engine.
abstract final class ScoreLayoutEngine {
  /// Computes ledger-line staff steps for [staffStep] (capped at 8).
  static List<int> ledgerStepsFor(int staffStep) =>
      ScoreMeasurePreparer.ledgerStepsFor(staffStep);

  /// Returns standard key-signature staff steps for [clef] and [fifths] (`-7..+7`).
  static List<int> keySignatureSteps(SmuflClef clef, int fifths) =>
      ScoreMeasurePreparer.keySignatureSteps(clef, fifths);

  /// Lays out [score] across wrapped systems within [availableWidth].
  static EngravedScoreLayout layout({
    required NotationScore score,
    required double availableWidth,
    ScoreStyle style = const ScoreStyle(),
  }) {
    final sp = math.max(4.0, style.staffSpace);
    final normalizedStyle = style.staffSpace == sp
        ? style
        : style.copyWith(staffSpace: sp);
    final safeWidth = availableWidth.isFinite
        ? math.max(availableWidth, 120.0)
        : 360.0;
    final systemLeftX = math.max(
      math.min(2.0 * sp, safeWidth * 0.08),
      1.8 * sp,
    );
    final systemRightX = math.max(
      systemLeftX + (8.0 * sp),
      safeWidth - math.min(1.2 * sp, safeWidth * 0.04),
    );

    if (score.measures.isEmpty) {
      return EngravedScoreLayout(
        totalSize: Size(safeWidth, (18.0 * sp) + normalizedStyle.systemGap),
        style: normalizedStyle,
        systems: const <SystemGeometry>[],
      );
    }

    final prepared = ScoreMeasurePreparer.prepareMeasures(score.measures, sp);
    final rows = _wrapSystems(prepared, systemRightX - systemLeftX, sp);
    final rawSystems = _buildRawSystems(
      rows: rows,
      style: normalizedStyle,
      systemLeftX: systemLeftX,
      systemRightX: systemRightX,
      totalMeasures: prepared.length,
    );

    final tiesByMeasure = <int, List<PlacedTieArc>>{};
    ScoreTieSolver.resolveTies(
      systems: rawSystems,
      tiesByMeasureNumber: tiesByMeasure,
      staffSpace: sp,
    );

    final lastBottom = rawSystems.last.bottomY;
    return EngravedScoreLayout(
      totalSize: Size(safeWidth, math.max(1.0, lastBottom + sp)),
      style: normalizedStyle,
      systems: _attachTies(rawSystems, tiesByMeasure),
    );
  }

  static List<SystemGeometry> _buildRawSystems({
    required List<List<PreparedMeasure>> rows,
    required ScoreStyle style,
    required double systemLeftX,
    required double systemRightX,
    required int totalMeasures,
  }) {
    final sp = style.staffSpace;
    final systemTopPad = 3.0 * sp;
    final staffSpan = (8.0 + style.trebleToBassGapSpaces) * sp;
    final systemHeight = systemTopPad + staffSpan + (3.0 * sp);

    final rawSystems = <SystemGeometry>[];
    var currentTopY = sp;
    for (var sIdx = 0; sIdx < rows.length; sIdx += 1) {
      final trebleTopY = currentTopY + systemTopPad;
      final sysTemplate = SystemGeometry(
        systemIndex: sIdx,
        topY: currentTopY,
        bottomY: currentTopY + systemHeight,
        trebleTopY: trebleTopY,
        bassBottomY: trebleTopY + staffSpan,
        leftX: systemLeftX,
        rightX: systemRightX,
        clefCenterX: systemLeftX + (1.85 * sp),
        staffSpace: sp,
        trebleToBassGapSpaces: style.trebleToBassGapSpaces,
        measures: const <MeasureGeometry>[],
      );
      rawSystems.add(
        SystemGeometry(
          systemIndex: sIdx,
          topY: sysTemplate.topY,
          bottomY: sysTemplate.bottomY,
          trebleTopY: sysTemplate.trebleTopY,
          bassBottomY: sysTemplate.bassBottomY,
          leftX: systemLeftX,
          rightX: systemRightX,
          clefCenterX: sysTemplate.clefCenterX,
          staffSpace: sp,
          trebleToBassGapSpaces: style.trebleToBassGapSpaces,
          measures: _layoutSystemRow(
            row: rows[sIdx],
            system: sysTemplate,
            totalMeasureCount: totalMeasures,
            sp: sp,
          ),
        ),
      );
      currentTopY = sysTemplate.bottomY + style.systemGap;
    }
    return rawSystems;
  }

  static List<List<PreparedMeasure>> _wrapSystems(
    List<PreparedMeasure> measures,
    double systemWidth,
    double sp,
  ) {
    final rows = <List<PreparedMeasure>>[];
    var currentRow = <PreparedMeasure>[];
    var usedWidth = 0.0;

    for (final m in measures) {
      final isFirstInRow = currentRow.isEmpty;
      final neededWidth = m.minWidth(isSystemStart: isFirstInRow, sp: sp);
      if (!isFirstInRow && usedWidth + neededWidth > systemWidth) {
        rows.add(currentRow);
        currentRow = <PreparedMeasure>[m];
        usedWidth = m.minWidth(isSystemStart: true, sp: sp);
      } else {
        currentRow.add(m);
        usedWidth += neededWidth;
      }
    }
    if (currentRow.isNotEmpty) {
      rows.add(currentRow);
    }
    return rows;
  }

  static List<MeasureGeometry> _layoutSystemRow({
    required List<PreparedMeasure> row,
    required SystemGeometry system,
    required int totalMeasureCount,
    required double sp,
  }) {
    final totalWidth = system.rightX - system.leftX;
    var sumHeader = 0.0;
    var sumBody = 0.0;
    for (var i = 0; i < row.length; i += 1) {
      sumHeader += row[i].headerWidth(isSystemStart: i == 0, sp: sp);
      sumBody += row[i].bodyMinWidth;
    }

    final headerScale = sumHeader > totalWidth * 0.72 && sumHeader > 0
        ? (totalWidth * 0.72) / sumHeader
        : 1.0;
    final availableBody = math.max(
      row.length * 4.0,
      totalWidth - (sumHeader * headerScale),
    );
    final bodyScale = sumBody > 0 ? availableBody / sumBody : 1.0;

    final out = <MeasureGeometry>[];
    var cursorX = system.leftX;
    for (var i = 0; i < row.length; i += 1) {
      final prep = row[i];
      final isSystemStart = i == 0;
      final headerW =
          prep.headerWidth(isSystemStart: isSystemStart, sp: sp) * headerScale;
      final bodyW = prep.bodyMinWidth * bodyScale;
      final mRight = i == row.length - 1
          ? system.rightX
          : cursorX + headerW + bodyW;

      out.add(
        ScoreMeasurePlacer.placeMeasure(
          MeasurePlacementSpec(
            prep: prep,
            system: system,
            leftX: cursorX,
            rightX: math.max(cursorX + 2.0, mRight),
            headerScale: headerScale,
            isSystemStart: isSystemStart,
            isFinalMeasure: prep.index == totalMeasureCount - 1,
            sp: sp,
          ),
        ),
      );
      cursorX = out.last.rightX;
    }
    return List<MeasureGeometry>.unmodifiable(out);
  }

  static List<SystemGeometry> _attachTies(
    List<SystemGeometry> rawSystems,
    Map<int, List<PlacedTieArc>> tiesByMeasure,
  ) {
    return <SystemGeometry>[
      for (final sys in rawSystems)
        SystemGeometry(
          systemIndex: sys.systemIndex,
          topY: sys.topY,
          bottomY: sys.bottomY,
          trebleTopY: sys.trebleTopY,
          bassBottomY: sys.bassBottomY,
          leftX: sys.leftX,
          rightX: sys.rightX,
          clefCenterX: sys.clefCenterX,
          staffSpace: sys.staffSpace,
          trebleToBassGapSpaces: sys.trebleToBassGapSpaces,
          measures: List<MeasureGeometry>.unmodifiable(<MeasureGeometry>[
            for (final m in sys.measures)
              MeasureGeometry(
                measureNumber: m.measureNumber,
                leftX: m.leftX,
                rightX: m.rightX,
                keyFifths: m.keyFifths,
                showKeySignature: m.showKeySignature,
                keyAccidentals: m.keyAccidentals,
                beats: m.beats,
                beatType: m.beatType,
                showTimeSignature: m.showTimeSignature,
                timeSigCenterX: m.timeSigCenterX,
                slices: m.slices,
                beamGroups: m.beamGroups,
                tieArcs: List<PlacedTieArc>.unmodifiable(
                  tiesByMeasure[m.measureNumber] ?? const <PlacedTieArc>[],
                ),
                isSystemStart: m.isSystemStart,
                isFinalMeasure: m.isFinalMeasure,
              ),
          ]),
        ),
    ];
  }
}
