import 'package:piano_exercises/features/progression/progression.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Random integer source returning an integer in `0 ..< max`.
typedef NextInt = int Function(int max);

/// Selects sight-reading prompt notes while preventing immediate repeats.
final class NotePromptSelector {
  const NotePromptSelector({required this.nextInt});

  final NextInt nextInt;

  /// Picks the next [StaffNote] from [stage.cumulativeNotes].
  StaffNote selectFromStage(ProgressionStage stage, {StaffNote? previous}) {
    return selectFromPool(stage.cumulativeNotes, previous: previous);
  }

  /// Picks the next [StaffNote] from [pool], avoiding [previous] when possible.
  StaffNote selectFromPool(List<StaffNote> pool, {StaffNote? previous}) {
    if (pool.isEmpty) {
      throw ArgumentError.value(pool, 'pool', 'Note pool must not be empty.');
    }
    if (pool.length == 1) {
      return pool.first;
    }

    final candidates = previous == null
        ? pool
        : pool.where((note) => note != previous).toList(growable: false);
    final effectivePool = candidates.isEmpty ? pool : candidates;
    return effectivePool[nextInt(effectivePool.length)];
  }
}
