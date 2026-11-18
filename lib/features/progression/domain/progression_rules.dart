import 'package:piano_exercises/features/progression/domain/progression_stage.dart';

/// Thresholds required to master a stage and unlock the next stage.
final class StageMasteryCriteria {
  const StageMasteryCriteria({
    this.minAttempts = 10,
    this.minAccuracy = 0.90,
    this.minStreak = 5,
  }) : assert(minAttempts >= 1),
       assert(minAccuracy >= 0.0 && minAccuracy <= 1.0),
       assert(minStreak >= 0);

  static const StageMasteryCriteria standard = StageMasteryCriteria();

  final int minAttempts;
  final double minAccuracy;
  final int minStreak;

  bool isSatisfiedBy(StageAttemptStats stats) {
    return stats.attempts >= minAttempts &&
        stats.accuracy >= minAccuracy &&
        stats.bestStreak >= minStreak;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is StageMasteryCriteria &&
            other.minAttempts == minAttempts &&
            other.minAccuracy == minAccuracy &&
            other.minStreak == minStreak);
  }

  @override
  int get hashCode => Object.hash(minAttempts, minAccuracy, minStreak);
}

/// Immutable per-stage attempt and streak statistics.
final class StageAttemptStats {
  const StageAttemptStats({
    this.attempts = 0,
    this.correctAttempts = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
  }) : assert(attempts >= 0),
       assert(correctAttempts >= 0 && correctAttempts <= attempts),
       assert(currentStreak >= 0 && currentStreak <= bestStreak),
       assert(bestStreak <= correctAttempts);

  static const StageAttemptStats empty = StageAttemptStats();

  final int attempts;
  final int correctAttempts;
  final int currentStreak;
  final int bestStreak;

  double get accuracy => attempts == 0 ? 0.0 : correctAttempts / attempts;

  StageAttemptStats recordAttempt({required bool correct}) {
    final nextCurrentStreak = correct ? currentStreak + 1 : 0;
    final nextBestStreak = nextCurrentStreak > bestStreak
        ? nextCurrentStreak
        : bestStreak;
    return StageAttemptStats(
      attempts: attempts + 1,
      correctAttempts: correct ? correctAttempts + 1 : correctAttempts,
      currentStreak: nextCurrentStreak,
      bestStreak: nextBestStreak,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is StageAttemptStats &&
            other.attempts == attempts &&
            other.correctAttempts == correctAttempts &&
            other.currentStreak == currentStreak &&
            other.bestStreak == bestStreak);
  }

  @override
  int get hashCode =>
      Object.hash(attempts, correctAttempts, currentStreak, bestStreak);
}

/// Immutable progression state across all stages and mastery unlocks.
final class ProgressionSnapshot {
  ProgressionSnapshot({
    required this.activeStageId,
    required this.highestUnlockedStageId,
    Map<StageId, StageAttemptStats> statsByStage =
        const <StageId, StageAttemptStats>{},
    this.criteria = StageMasteryCriteria.standard,
  }) : statsByStage = Map<StageId, StageAttemptStats>.unmodifiable(
         statsByStage,
       );

  factory ProgressionSnapshot.initial({
    StageMasteryCriteria criteria = StageMasteryCriteria.standard,
  }) {
    return ProgressionSnapshot(
      activeStageId: StageId.stage1,
      highestUnlockedStageId: StageId.stage1,
      criteria: criteria,
    );
  }

  final StageId activeStageId;
  final StageId highestUnlockedStageId;
  final Map<StageId, StageAttemptStats> statsByStage;
  final StageMasteryCriteria criteria;

  ProgressionStage get activeStage => ProgressionCatalog.byId(activeStageId);

  bool isUnlocked(StageId stageId) =>
      stageId.number <= highestUnlockedStageId.number;

  StageAttemptStats statsFor(StageId stageId) =>
      statsByStage[stageId] ?? StageAttemptStats.empty;

  /// Records an attempt on [activeStageId], unlocking the next stage on mastery.
  ProgressionSnapshot recordAttempt({
    required bool correct,
    bool autoAdvance = false,
  }) {
    final updatedStats = statsFor(activeStageId)
        .recordAttempt(correct: correct);
    final nextStatsByStage = Map<StageId, StageAttemptStats>.of(statsByStage)
      ..[activeStageId] = updatedStats;

    var nextHighestUnlocked = highestUnlockedStageId;
    var nextActiveStage = activeStageId;
    final nextStage = activeStageId.next;

    // Only unlock sequentially from the frontier stage so re-practicing earlier
    // stages or free-practice jumps do not skip intermediate unlocks.
    if (criteria.isSatisfiedBy(updatedStats) &&
        activeStageId == highestUnlockedStageId &&
        nextStage != null) {
      nextHighestUnlocked = nextStage;
      if (autoAdvance) {
        nextActiveStage = nextStage;
      }
    }

    return ProgressionSnapshot(
      activeStageId: nextActiveStage,
      highestUnlockedStageId: nextHighestUnlocked,
      statsByStage: nextStatsByStage,
      criteria: criteria,
    );
  }

  /// Selects [stageId], enforcing unlock status when [requireUnlocked] is true.
  ProgressionSnapshot selectStage(
    StageId stageId, {
    bool requireUnlocked = false,
  }) {
    if (requireUnlocked && !isUnlocked(stageId)) {
      throw StateError('Stage ${stageId.number} is locked.');
    }
    if (stageId == activeStageId) {
      return this;
    }
    return ProgressionSnapshot(
      activeStageId: stageId,
      highestUnlockedStageId: highestUnlockedStageId,
      statsByStage: statsByStage,
      criteria: criteria,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ProgressionSnapshot &&
            other.activeStageId == activeStageId &&
            other.highestUnlockedStageId == highestUnlockedStageId &&
            other.criteria == criteria &&
            _statsMapsEqual(other.statsByStage, statsByStage));
  }

  @override
  int get hashCode => Object.hash(
    activeStageId,
    highestUnlockedStageId,
    criteria,
    Object.hashAll(<Object?>[
      for (final stageId in StageId.values)
        if (statsByStage.containsKey(stageId))
          Object.hash(stageId, statsByStage[stageId]),
    ]),
  );

  static bool _statsMapsEqual(
    Map<StageId, StageAttemptStats> a,
    Map<StageId, StageAttemptStats> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
