import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/progression/domain/progression_rules.dart';
import 'package:piano_exercises/features/progression/domain/progression_stage.dart';

/// Configurable mastery thresholds controlling sequential stage unlocks.
final progressionCriteriaProvider = Provider<StageMasteryCriteria>((ref) {
  return StageMasteryCriteria.standard;
});

/// Holds active stage selection, attempt statistics, and unlocked stages.
class ProgressionController extends Notifier<ProgressionSnapshot> {
  @override
  ProgressionSnapshot build() {
    final criteria = ref.watch(progressionCriteriaProvider);
    return ProgressionSnapshot.initial(criteria: criteria);
  }

  ProgressionSnapshot recordAttempt({
    required bool correct,
    bool autoAdvance = false,
  }) {
    state = state.recordAttempt(correct: correct, autoAdvance: autoAdvance);
    return state;
  }

  void selectStage(StageId stageId, {bool requireUnlocked = false}) {
    state = state.selectStage(stageId, requireUnlocked: requireUnlocked);
  }

  void reset() {
    state = ProgressionSnapshot.initial(
      criteria: ref.read(progressionCriteriaProvider),
    );
  }
}

final progressionControllerProvider =
    NotifierProvider<ProgressionController, ProgressionSnapshot>(
      ProgressionController.new,
    );
