import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/progression/progression.dart';

final class _SpyProgressionRepository implements ProgressionRepository {
  ProgressionSnapshot? stored;
  int saveCalls = 0;
  int clearCalls = 0;

  @override
  ProgressionSnapshot? load({
    StageMasteryCriteria criteria = StageMasteryCriteria.standard,
  }) {
    final snapshot = stored;
    if (snapshot == null) {
      return null;
    }
    return ProgressionSnapshot(
      activeStageId: snapshot.activeStageId,
      highestUnlockedStageId: snapshot.highestUnlockedStageId,
      statsByStage: snapshot.statsByStage,
      criteria: criteria,
    );
  }

  @override
  Future<void> save(ProgressionSnapshot snapshot) {
    saveCalls += 1;
    stored = snapshot;
    return Future<void>.value();
  }

  @override
  Future<void> clear() {
    clearCalls += 1;
    stored = null;
    return Future<void>.value();
  }
}

void main() {
  test('starts at Stage 1 with only Stage 1 unlocked', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final snapshot = container.read(progressionControllerProvider);
    expect(snapshot.activeStageId, StageId.stage1);
    expect(snapshot.highestUnlockedStageId, StageId.stage1);
    expect(snapshot.isUnlocked(StageId.stage1), isTrue);
    expect(snapshot.isUnlocked(StageId.stage2), isFalse);
    expect(snapshot.statsFor(StageId.stage1), StageAttemptStats.empty);
  });

  test('records attempts and unlocks Stage 2 on mastery', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(progressionControllerProvider.notifier);
    for (var i = 0; i < 9; i += 1) {
      final mid = controller.recordAttempt(correct: true);
      expect(mid.highestUnlockedStageId, StageId.stage1);
    }

    final mastered = controller.recordAttempt(correct: true);
    expect(mastered.highestUnlockedStageId, StageId.stage2);
    expect(mastered.activeStageId, StageId.stage1);
    expect(mastered.isUnlocked(StageId.stage2), isTrue);

    final stats = mastered.statsFor(StageId.stage1);
    expect(stats.attempts, 10);
    expect(stats.currentStreak, 10);
    expect(stats.bestStreak, 10);
    expect(stats.accuracy, 1.0);
  });

  test('selectStage supports free practice and requireUnlocked enforcement', () {
    final container = ProviderContainer(
      overrides: [
        progressionCriteriaProvider.overrideWithValue(
          const StageMasteryCriteria(
            minAttempts: 2,
            minAccuracy: 1.0,
            minStreak: 2,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(progressionControllerProvider.notifier);
    expect(
      () => controller.selectStage(StageId.stage3, requireUnlocked: true),
      throwsStateError,
    );

    // Free practice allows selecting locked stages without unlocking them.
    controller.selectStage(StageId.stage4);
    expect(
      container.read(progressionControllerProvider).activeStageId,
      StageId.stage4,
    );
    expect(
      container.read(progressionControllerProvider).isUnlocked(StageId.stage4),
      isFalse,
    );

    // Unlock Stage 2 via Stage 1 mastery, then select Stage 2 with enforcement.
    controller.selectStage(StageId.stage1, requireUnlocked: true);
    controller.recordAttempt(correct: true);
    controller.recordAttempt(correct: true);
    controller.selectStage(StageId.stage2, requireUnlocked: true);
    expect(
      container.read(progressionControllerProvider).activeStageId,
      StageId.stage2,
    );

    controller.reset();
    final resetSnapshot = container.read(progressionControllerProvider);
    expect(resetSnapshot.activeStageId, StageId.stage1);
    expect(resetSnapshot.highestUnlockedStageId, StageId.stage1);
    expect(resetSnapshot.statsByStage, isEmpty);
  });

  test('hydrates synchronously on frame 0 and persists recordAttempt, selectStage, and reset', () {
    const customCriteria = StageMasteryCriteria(
      minAttempts: 2,
      minAccuracy: 1.0,
      minStreak: 2,
    );
    final repository = _SpyProgressionRepository()
      ..stored = ProgressionSnapshot(
        activeStageId: StageId.stage3,
        highestUnlockedStageId: StageId.stage2,
        statsByStage: const <StageId, StageAttemptStats>{
          StageId.stage1: StageAttemptStats(
            attempts: 2,
            correctAttempts: 2,
            currentStreak: 2,
            bestStreak: 2,
          ),
        },
      );

    final container = ProviderContainer(
      overrides: [
        progressionCriteriaProvider.overrideWithValue(customCriteria),
        progressionRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    // Frame 0 reads hydrated state synchronously with overridden criteria.
    final hydrated = container.read(progressionControllerProvider);
    expect(hydrated.activeStageId, StageId.stage3);
    expect(hydrated.highestUnlockedStageId, StageId.stage2);
    expect(hydrated.criteria, customCriteria);
    expect(repository.saveCalls, 0);

    final controller = container.read(progressionControllerProvider.notifier);

    // Re-selecting the active stage does not trigger a redundant write.
    controller.selectStage(StageId.stage3);
    expect(repository.saveCalls, 0);

    controller.selectStage(StageId.stage4);
    expect(repository.saveCalls, 1);
    expect(repository.stored?.activeStageId, StageId.stage4);

    controller.recordAttempt(correct: true);
    expect(repository.saveCalls, 2);
    expect(repository.stored?.statsFor(StageId.stage4).attempts, 1);

    controller.reset();
    expect(repository.clearCalls, 1);
    expect(repository.stored, isNull);
  });
}
