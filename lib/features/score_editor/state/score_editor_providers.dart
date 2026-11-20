import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';

/// Coalescing window grouping near-simultaneous Note On bursts into step-time chords.
final scoreEditorChordWindowProvider = Provider<Duration>((ref) {
  return const Duration(milliseconds: 35);
});

/// Monotonic millisecond clock used by `ScoreEditorController`; overridable in tests.
final scoreEditorClockMsProvider = Provider<int Function()>((ref) {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsedMilliseconds;
});

/// Pause toggle gating live MIDI note entry while away from Compose or inside sheets.
class ScoreEditorPausedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setPaused(bool paused) => state = paused;
}

final scoreEditorPausedProvider =
    NotifierProvider.autoDispose<ScoreEditorPausedNotifier, bool>(
      ScoreEditorPausedNotifier.new,
    );

/// Locates the index of a newly added note inside [next] compared against [prev].
int? findAddedEditorNoteIndex(
  List<DraftNoteEvent> prev,
  List<DraftNoteEvent> next,
) {
  if (next.isEmpty) {
    return null;
  }
  for (var i = next.length - 1; i >= 0; i -= 1) {
    if (!prev.contains(next[i])) {
      return i;
    }
  }
  return next.length - 1;
}

/// Tracks a mutated note's index across canonical re-sorting in [next].
int? findChangedEditorNoteIndex(
  List<DraftNoteEvent> prev,
  List<DraftNoteEvent> next,
  int fallbackIndex,
) {
  if (next.isEmpty) {
    return null;
  }
  final remaining = List<DraftNoteEvent>.of(prev);
  for (var i = 0; i < next.length; i += 1) {
    if (!remaining.remove(next[i])) {
      return i;
    }
  }
  return fallbackIndex.clamp(0, next.length - 1);
}

/// Formats variant load/parse exceptions into concise user-facing text.
String formatEditorLoadError(Object error) {
  if (error is ScoreParseException) {
    return error.message;
  }
  if (error is CatalogStorageException) {
    return error.message;
  }
  return error.toString();
}
