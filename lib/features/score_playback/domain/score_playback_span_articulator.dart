import 'dart:math' as math;

import 'package:piano_exercises/features/score_playback/domain/playback_models.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Mutable microsecond note span accumulated while resolving ties across bars.
final class MutablePlaybackSpan {
  MutablePlaybackSpan({
    required this.midiNote,
    required this.velocity,
    required this.startUs,
    required this.endUs,
  });

  final MidiNote midiNote;
  int velocity;
  final int startUs;
  int endUs;
}

/// Merges simultaneous unisons and inserts clean re-attack gaps on repeated pitches.
List<PlaybackNoteSpan> articulateAndSortPlaybackSpans(
  List<MutablePlaybackSpan> rawSpans,
) {
  if (rawSpans.isEmpty) {
    return const <PlaybackNoteSpan>[];
  }
  final byPitch = <int, List<MutablePlaybackSpan>>{};
  for (final span in rawSpans) {
    byPitch
        .putIfAbsent(span.midiNote.number, () => <MutablePlaybackSpan>[])
        .add(span);
  }

  final result = <PlaybackNoteSpan>[];
  for (final pitchSpans in byPitch.values) {
    pitchSpans.sort((a, b) => a.startUs.compareTo(b.startUs));
    final merged = <MutablePlaybackSpan>[];
    for (final current in pitchSpans) {
      if (merged.isNotEmpty && merged.last.startUs == current.startUs) {
        if (current.endUs > merged.last.endUs) {
          merged.last.endUs = current.endUs;
        }
        if (current.velocity > merged.last.velocity) {
          merged.last.velocity = current.velocity;
        }
      } else {
        merged.add(current);
      }
    }
    for (var i = 0; i < merged.length; i += 1) {
      final cur = merged[i];
      final startMs = cur.startUs ~/ 1000;
      var endMs = math.max(startMs + 20, cur.endUs ~/ 1000);
      if (i + 1 < merged.length) {
        final nextStartMs = merged[i + 1].startUs ~/ 1000;
        if (nextStartMs > startMs && endMs >= nextStartMs) {
          final gap = math.min(20, math.max(1, (nextStartMs - startMs) ~/ 6));
          endMs = math.min(
            nextStartMs - 1,
            math.max(startMs + 1, nextStartMs - gap),
          );
        }
      }
      result.add(
        PlaybackNoteSpan(
          midiNote: cur.midiNote,
          velocity: cur.velocity,
          startMs: startMs,
          endMs: endMs,
        ),
      );
    }
  }

  result.sort((a, b) {
    final cmp = a.startMs.compareTo(b.startMs);
    return cmp != 0 ? cmp : a.midiNote.number.compareTo(b.midiNote.number);
  });
  return result;
}
