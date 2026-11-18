import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/progression/domain/progression_repository.dart';
import 'package:piano_exercises/features/progression/domain/progression_rules.dart';
import 'package:piano_exercises/features/progression/domain/progression_stage.dart';

/// Configurable mastery thresholds controlling sequential stage unlocks.
final progressionCriteriaProvider = Provider<StageMasteryCriteria>((ref) {
  return StageMasteryCriteria.standard;
});

/// Persistence boundary for progression state; overridden in `app/` and tests.
final progressionRepositoryProvider = Provider<ProgressionRepository>((ref) {
  return InMemoryProgressionRepository();
});

/// Holds active stage selection, attempt statistics, and unlocked stages.
class ProgressionController extends Notifier<ProgressionSnapshot> {
  @override
  ProgressionSnapshot build() {
    final criteria = ref.watch(progressionCriteriaProvider);
    final repository = ref.watch(progressionRepositoryProvider);
    return repository.load(criteria: criteria) ??
        ProgressionSnapshot.initial(criteria: criteria);
  }

  ProgressionSnapshot recordAttempt({
    required bool correct,
    bool autoAdvance = false,
  }) {
    final nextState = state.recordAttempt(
      correct: correct,
      autoAdvance: autoAdvance,
    );
    state = nextState;
    unawaited(ref.read(progressionRepositoryProvider).save(nextState));
    return nextState;
  }

  void selectStage(StageId stageId, {bool requireUnlocked = false}) {
    final nextState = state.selectStage(
      stageId,
      requireUnlocked: requireUnlocked,
    );
    if (identical(nextState, state)) {
      return;
    }
    state = nextState;
    unawaited(ref.read(progressionRepositoryProvider).save(nextState));
  }

  void reset() {
    state = ProgressionSnapshot.initial(
      criteria: ref.read(progressionCriteriaProvider),
    );
    unawaited(ref.read(progressionRepositoryProvider).clear());
  }
}

final progressionControllerProvider =
    NotifierProvider<ProgressionController, ProgressionSnapshot>(
      ProgressionController.new,
    );
