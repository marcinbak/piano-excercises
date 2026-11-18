import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/progression/progression.dart';

void main() {
  group('StageAttemptStats', () {
    test('tracks attempts, accuracy, current streak, and best streak', () {
      const empty = StageAttemptStats.empty;
      expect(empty.attempts, 0);
      expect(empty.correctAttempts, 0);
      expect(empty.currentStreak, 0);
      expect(empty.bestStreak, 0);
      expect(empty.accuracy, 0.0);

      final s1 = empty.recordAttempt(correct: true);
      final s2 = s1.recordAttempt(correct: true);
      final s3 = s2.recordAttempt(correct: false);
      final s4 = s3.recordAttempt(correct: true);

      expect(s4.attempts, 4);
      expect(s4.correctAttempts, 3);
      expect(s4.currentStreak, 1);
      expect(s4.bestStreak, 2);
      expect(s4.accuracy, closeTo(0.75, 1e-9));
      expect(
        s4,
        const StageAttemptStats(
          attempts: 4,
          correctAttempts: 3,
          currentStreak: 1,
          bestStreak: 2,
        ),
      );
      expect(
        s4.hashCode,
        const StageAttemptStats(
          attempts: 4,
          correctAttempts: 3,
          currentStreak: 1,
          bestStreak: 2,
        ).hashCode,
      );
    });
  });

  group('StageMasteryCriteria', () {
    test('enforces attempts, accuracy, and bestStreak boundaries', () {
      const criteria = StageMasteryCriteria.standard;

      expect(
        criteria.isSatisfiedBy(
          const StageAttemptStats(
            attempts: 9,
            correctAttempts: 9,
            currentStreak: 9,
            bestStreak: 9,
          ),
        ),
        isFalse,
      );
      expect(
        criteria.isSatisfiedBy(
          const StageAttemptStats(
            attempts: 10,
            correctAttempts: 8,
            currentStreak: 5,
            bestStreak: 5,
          ),
        ),
        isFalse,
      );
      // 12 attempts, 10 correct (83.3%) passes attempts & streak, fails accuracy.
      expect(
        criteria.isSatisfiedBy(
          const StageAttemptStats(
            attempts: 12,
            correctAttempts: 10,
            currentStreak: 6,
            bestStreak: 6,
          ),
        ),
        isFalse,
      );
      // 11 attempts, 10 correct (90.9%), alternating misses keep bestStreak at 4.
      expect(
        criteria.isSatisfiedBy(
          const StageAttemptStats(
            attempts: 11,
            correctAttempts: 10,
            currentStreak: 4,
            bestStreak: 4,
          ),
        ),
        isFalse,
      );
      // 9 right then 1 wrong gives 10 attempts, 90% accuracy, and bestStreak 9.
      expect(
        criteria.isSatisfiedBy(
          const StageAttemptStats(
            attempts: 10,
            correctAttempts: 9,
            currentStreak: 0,
            bestStreak: 9,
          ),
        ),
        isTrue,
      );
    });
  });

  group('ProgressionSnapshot', () {
    test('initial state starts at stage 1 with only stage 1 unlocked', () {
      final initial = ProgressionSnapshot.initial();

      expect(initial.activeStageId, StageId.stage1);
      expect(initial.activeStage.id, StageId.stage1);
      expect(initial.highestUnlockedStageId, StageId.stage1);
      expect(initial.isUnlocked(StageId.stage1), isTrue);
      for (final stageId in StageId.values.skip(1)) {
        expect(initial.isUnlocked(stageId), isFalse);
      }
      expect(initial.statsFor(StageId.stage1), StageAttemptStats.empty);
    });

    test('unlocks next stage on mastery with autoAdvance false or true', () {
      var manual = ProgressionSnapshot.initial();
      for (var i = 0; i < 9; i++) {
        manual = manual.recordAttempt(correct: true);
        expect(manual.highestUnlockedStageId, StageId.stage1);
      }
      manual = manual.recordAttempt(correct: true, autoAdvance: false);
      expect(manual.highestUnlockedStageId, StageId.stage2);
      expect(manual.activeStageId, StageId.stage1);
      expect(manual.isUnlocked(StageId.stage2), isTrue);

      var auto = ProgressionSnapshot.initial();
      for (var i = 0; i < 10; i++) {
        auto = auto.recordAttempt(correct: true, autoAdvance: true);
      }
      expect(auto.highestUnlockedStageId, StageId.stage2);
      expect(auto.activeStageId, StageId.stage2);
    });

    test(
      'unlocks sequentially from stage 1 through stage 4 and caps at stage 4',
      () {
        var snapshot = ProgressionSnapshot.initial(
          criteria: const StageMasteryCriteria(
            minAttempts: 2,
            minAccuracy: 1.0,
            minStreak: 2,
          ),
        );

        for (final expectedStage in StageId.values) {
          expect(snapshot.activeStageId, expectedStage);
          snapshot = snapshot.recordAttempt(correct: true, autoAdvance: true);
          snapshot = snapshot.recordAttempt(correct: true, autoAdvance: true);
        }

        expect(snapshot.highestUnlockedStageId, StageId.stage4);
        expect(snapshot.activeStageId, StageId.stage4);
        for (final stageId in StageId.values) {
          expect(snapshot.isUnlocked(stageId), isTrue);
          expect(snapshot.statsFor(stageId).attempts, 2);
        }
      },
    );

    test('does not jump activeStageId when re-practicing an earlier unlocked stage', () {
      var snapshot = ProgressionSnapshot.initial(
        criteria: const StageMasteryCriteria(
          minAttempts: 2,
          minAccuracy: 1.0,
          minStreak: 2,
        ),
      );
      snapshot = snapshot.recordAttempt(correct: true, autoAdvance: true);
      snapshot = snapshot.recordAttempt(correct: true, autoAdvance: true);
      expect(snapshot.highestUnlockedStageId, StageId.stage2);
      expect(snapshot.activeStageId, StageId.stage2);

      snapshot = snapshot.selectStage(StageId.stage1, requireUnlocked: true);
      snapshot = snapshot.recordAttempt(correct: true, autoAdvance: true);

      expect(snapshot.activeStageId, StageId.stage1);
      expect(snapshot.highestUnlockedStageId, StageId.stage2);
      expect(snapshot.statsFor(StageId.stage1).attempts, 3);
    });

    test('selectStage enforces requireUnlocked when true and allows free jump when false', () {
      final initial = ProgressionSnapshot.initial();

      expect(
        () => initial.selectStage(StageId.stage3, requireUnlocked: true),
        throwsStateError,
      );
      expect(
        initial.selectStage(StageId.stage1, requireUnlocked: true),
        same(initial),
      );

      final freeJump = initial.selectStage(StageId.stage4);
      expect(freeJump.activeStageId, StageId.stage4);
      expect(freeJump.highestUnlockedStageId, StageId.stage1);
      expect(freeJump.isUnlocked(StageId.stage4), isFalse);

      // Recording mastery on a free-practice stage above highestUnlockedStageId
      // does not bypass sequential unlocking.
      var afterPractice = freeJump;
      for (var i = 0; i < 10; i++) {
        afterPractice = afterPractice.recordAttempt(
          correct: true,
          autoAdvance: true,
        );
      }
      expect(afterPractice.highestUnlockedStageId, StageId.stage1);
      expect(afterPractice.activeStageId, StageId.stage4);
    });

    test('supports order-independent value equality and hashCode', () {
      final a = ProgressionSnapshot(
        activeStageId: StageId.stage2,
        highestUnlockedStageId: StageId.stage2,
        statsByStage: const <StageId, StageAttemptStats>{
          StageId.stage1: StageAttemptStats(
            attempts: 10,
            correctAttempts: 10,
            currentStreak: 10,
            bestStreak: 10,
          ),
          StageId.stage2: StageAttemptStats(
            attempts: 1,
            correctAttempts: 1,
            currentStreak: 1,
            bestStreak: 1,
          ),
        },
      );
      final b = ProgressionSnapshot(
        activeStageId: StageId.stage2,
        highestUnlockedStageId: StageId.stage2,
        statsByStage: const <StageId, StageAttemptStats>{
          StageId.stage2: StageAttemptStats(
            attempts: 1,
            correctAttempts: 1,
            currentStreak: 1,
            bestStreak: 1,
          ),
          StageId.stage1: StageAttemptStats(
            attempts: 10,
            correctAttempts: 10,
            currentStreak: 10,
            bestStreak: 10,
          ),
        },
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
