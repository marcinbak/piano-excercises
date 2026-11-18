import 'package:piano_exercises/features/progression/domain/progression_rules.dart';

/// Persistence boundary for saving and restoring progression state locally.
abstract interface class ProgressionRepository {
  ProgressionSnapshot? load({
    StageMasteryCriteria criteria = StageMasteryCriteria.standard,
  });

  Future<void> save(ProgressionSnapshot snapshot);

  Future<void> clear();
}

/// Ephemeral in-memory [ProgressionRepository] used in tests and fallback boot.
final class InMemoryProgressionRepository implements ProgressionRepository {
  ProgressionSnapshot? _snapshot;

  @override
  ProgressionSnapshot? load({
    StageMasteryCriteria criteria = StageMasteryCriteria.standard,
  }) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return null;
    }
    if (snapshot.criteria == criteria) {
      return snapshot;
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
    _snapshot = snapshot;
    return Future<void>.value();
  }

  @override
  Future<void> clear() {
    _snapshot = null;
    return Future<void>.value();
  }
}
