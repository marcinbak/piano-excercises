import 'dart:convert';

import 'package:piano_exercises/features/progression/domain/progression_rules.dart';
import 'package:piano_exercises/features/progression/domain/progression_stage.dart';

/// Versioned JSON codec for serializing and validating [ProgressionSnapshot]s.
abstract final class ProgressionCodec {
  static const int currentVersion = 1;

  static String encode(ProgressionSnapshot snapshot) {
    return jsonEncode(<String, Object?>{
      'version': currentVersion,
      'activeStage': snapshot.activeStageId.number,
      'highestUnlockedStage': snapshot.highestUnlockedStageId.number,
      'statsByStage': <String, Object?>{
        for (final stageId in StageId.values)
          if (snapshot.statsByStage[stageId] case final stats?)
            '${stageId.number}': <String, Object?>{
              'attempts': stats.attempts,
              'correctAttempts': stats.correctAttempts,
              'currentStreak': stats.currentStreak,
              'bestStreak': stats.bestStreak,
            },
      },
    });
  }

  /// Decodes [rawJson] into a [ProgressionSnapshot], returning `null` on invalid data.
  static ProgressionSnapshot? tryDecode(
    String rawJson, {
    StageMasteryCriteria criteria = StageMasteryCriteria.standard,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on Object {
      return null;
    }

    if (decoded is! Map<String, Object?>) {
      return null;
    }

    final version = decoded['version'];
    if (version is! int || version != currentVersion) {
      return null;
    }

    final activeStageId = _tryParseStageId(decoded['activeStage']);
    final highestUnlockedStageId = _tryParseStageId(
      decoded['highestUnlockedStage'],
    );
    if (activeStageId == null || highestUnlockedStageId == null) {
      return null;
    }

    final rawStatsByStage = decoded['statsByStage'];
    if (rawStatsByStage is! Map<String, Object?>) {
      return null;
    }

    final statsByStage = <StageId, StageAttemptStats>{};
    for (final entry in rawStatsByStage.entries) {
      final stageId = _tryParseStageKey(entry.key);
      final stats = _tryParseStats(entry.value);
      if (stageId == null || stats == null) {
        return null;
      }
      statsByStage[stageId] = stats;
    }

    return ProgressionSnapshot(
      activeStageId: activeStageId,
      highestUnlockedStageId: highestUnlockedStageId,
      statsByStage: statsByStage,
      criteria: criteria,
    );
  }

  static StageId? _tryParseStageId(Object? value) {
    if (value is! int || value < 1 || value > StageId.values.length) {
      return null;
    }
    return StageId.fromNumber(value);
  }

  static StageId? _tryParseStageKey(String key) {
    final number = int.tryParse(key);
    if (number == null ||
        '$number' != key ||
        number < 1 ||
        number > StageId.values.length) {
      return null;
    }
    return StageId.fromNumber(number);
  }

  static StageAttemptStats? _tryParseStats(Object? value) {
    if (value is! Map<String, Object?>) {
      return null;
    }
    final attempts = value['attempts'];
    final correctAttempts = value['correctAttempts'];
    final currentStreak = value['currentStreak'];
    final bestStreak = value['bestStreak'];
    if (attempts is! int ||
        correctAttempts is! int ||
        currentStreak is! int ||
        bestStreak is! int) {
      return null;
    }
    // Enforce invariants explicitly at runtime because assert() is stripped in release builds.
    if (attempts < 0 ||
        correctAttempts < 0 ||
        correctAttempts > attempts ||
        bestStreak < 0 ||
        bestStreak > correctAttempts ||
        currentStreak < 0 ||
        currentStreak > bestStreak) {
      return null;
    }
    return StageAttemptStats(
      attempts: attempts,
      correctAttempts: correctAttempts,
      currentStreak: currentStreak,
      bestStreak: bestStreak,
    );
  }
}
