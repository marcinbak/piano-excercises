import 'dart:math' as math;

import 'package:piano_exercises/features/score_playback/domain/playback_models.dart';
import 'package:piano_exercises/features/score_playback/domain/score_playback_span_articulator.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Configuration for building a [ScorePlaybackSchedule] from a [Score].
final class ScorePlaybackOptions {
  const ScorePlaybackOptions({
    this.includeTreble = true,
    this.includeBass = true,
    this.startMeasureIndex,
    this.endMeasureIndex,
    this.startSliceOrdinal = 0,
    this.defaultBpm = 100,
    this.tempoScale = 1.0,
    this.trimTrailingEmptyMeasures = false,
  });

  final bool includeTreble;
  final bool includeBass;
  final int? startMeasureIndex;
  final int? endMeasureIndex;
  final int startSliceOrdinal;
  final int defaultBpm;
  final double tempoScale;
  final bool trimTrailingEmptyMeasures;

  ScorePlaybackOptions scaledBy(double speed) => ScorePlaybackOptions(
    includeTreble: includeTreble,
    includeBass: includeBass,
    startMeasureIndex: startMeasureIndex,
    endMeasureIndex: endMeasureIndex,
    startSliceOrdinal: startSliceOrdinal,
    defaultBpm: defaultBpm,
    tempoScale: tempoScale * speed,
    trimTrailingEmptyMeasures: trimTrailingEmptyMeasures,
  );
}

/// Precomputed tie-merged note spans and slice cursor windows for a [Score].
final class ScorePlaybackSchedule {
  ScorePlaybackSchedule._({
    required this.sliceWindows,
    required this.notes,
    required this.totalDurationMs,
    required this.initialBpm,
  });

  /// Compiles [score] into millisecond-accurate slice windows and note spans.
  factory ScorePlaybackSchedule.fromScore(
    Score score, {
    ScorePlaybackOptions options = const ScorePlaybackOptions(),
  }) {
    final fallbackBpm = score.initialTempo?.bpm ?? options.defaultBpm;
    final bounds = score.measures.isEmpty
        ? null
        : _resolveMeasureBounds(score, options);
    if (bounds == null) {
      return ScorePlaybackSchedule._(
        sliceWindows: const <PlaybackSliceWindow>[],
        notes: const <PlaybackNoteSpan>[],
        totalDurationMs: 0,
        initialBpm: fallbackBpm,
      );
    }

    final (startMeasure, endMeasure) = bounds;
    var activeBpm = fallbackBpm;
    var globalOrdinal = 0;
    for (var m = 0; m < startMeasure; m += 1) {
      activeBpm = score.measures[m].tempoMark?.bpm ?? activeBpm;
      globalOrdinal += score.measures[m].slices.length;
    }

    final initialResolvedBpm =
        score.measures[startMeasure].tempoMark?.bpm ?? activeBpm;
    final accumulated = _accumulateMeasures(
      score: score,
      options: options,
      startMeasure: startMeasure,
      endMeasure: endMeasure,
      initialBpm: activeBpm,
      initialOrdinal: globalOrdinal,
    );

    final finalizedNotes = articulateAndSortPlaybackSpans(accumulated.rawSpans);
    var maxEndMs = accumulated.sliceWindows.isEmpty
        ? 0
        : accumulated.sliceWindows.last.endMs;
    for (final note in finalizedNotes) {
      if (note.endMs > maxEndMs) {
        maxEndMs = note.endMs;
      }
    }

    return ScorePlaybackSchedule._(
      sliceWindows: List<PlaybackSliceWindow>.unmodifiable(
        accumulated.sliceWindows,
      ),
      notes: List<PlaybackNoteSpan>.unmodifiable(finalizedNotes),
      totalDurationMs: math.min(maxEndMs, maxScheduleDurationUs ~/ 1000),
      initialBpm: initialResolvedBpm,
    );
  }

  /// Upper bound (`1 hour`) preventing adversarial MusicXML `<forward>` durations from overflowing sample math.
  static const int maxScheduleDurationUs = 3600 * 1000 * 1000;

  final List<PlaybackSliceWindow> sliceWindows;
  final List<PlaybackNoteSpan> notes;
  final int totalDurationMs;
  final int initialBpm;

  bool get hasAudibleNotes => notes.isNotEmpty;

  /// Resolves the active [PlaybackSliceWindow] at [elapsedMs] via binary search.
  PlaybackSliceWindow? sliceAtMs(int elapsedMs) {
    if (sliceWindows.isEmpty) {
      return null;
    }
    var low = 0;
    var high = sliceWindows.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final window = sliceWindows[mid];
      if (elapsedMs < window.startMs) {
        high = mid - 1;
      } else if (elapsedMs >= window.endMs) {
        low = mid + 1;
      } else {
        return window;
      }
    }
    return elapsedMs < sliceWindows.first.startMs
        ? sliceWindows.first
        : sliceWindows.last;
  }

  static ({
    List<PlaybackSliceWindow> sliceWindows,
    List<MutablePlaybackSpan> rawSpans,
  })
  _accumulateMeasures({
    required Score score,
    required ScorePlaybackOptions options,
    required int startMeasure,
    required int endMeasure,
    required int initialBpm,
    required int initialOrdinal,
  }) {
    final safeScale = (options.tempoScale.isFinite && options.tempoScale > 0)
        ? options.tempoScale
        : 1.0;
    final sliceWindows = <PlaybackSliceWindow>[];
    final openTies = <(Clef, int), MutablePlaybackSpan>{};
    final rawSpans = <MutablePlaybackSpan>[];
    var activeBpm = initialBpm;
    var globalOrdinal = initialOrdinal;
    var cursorUs = 0;

    for (var m = startMeasure; m <= endMeasure; m += 1) {
      final measure = score.measures[m];
      activeBpm = measure.tempoMark?.bpm ?? activeBpm;
      final scaledBpm = (activeBpm * safeScale).clamp(15.0, 999.0);
      final usPerQuarter = 60000000.0 / scaledBpm;

      for (final slice in measure.slices) {
        final ordinal = globalOrdinal++;
        if (ordinal < options.startSliceOrdinal) {
          continue;
        }
        if (cursorUs >= maxScheduleDurationUs) {
          return (sliceWindows: sliceWindows, rawSpans: rawSpans);
        }
        final remainingUs = maxScheduleDurationUs - cursorUs;
        final rawSliceDurUs = math.max(
          1000,
          (slice.beatDuration.toDouble * usPerQuarter).round(),
        );
        final sliceDurUs = math.min(remainingUs, rawSliceDurUs);
        final sliceStartUs = cursorUs;
        final sliceEndUs = sliceStartUs + sliceDurUs;
        sliceWindows.add(
          PlaybackSliceWindow(
            sliceOrdinal: ordinal,
            sliceIndex: slice.sliceIndex,
            measureNumber: slice.measureNumber,
            startMs: sliceStartUs ~/ 1000,
            endMs: sliceEndUs ~/ 1000,
          ),
        );

        if (options.includeTreble) {
          _collectSliceNotes(
            slice.trebleNotes,
            sliceStartUs: sliceStartUs,
            usPerQuarter: usPerQuarter,
            defaultVelocity: 94,
            openTies: openTies,
            rawSpans: rawSpans,
          );
        }
        if (options.includeBass) {
          _collectSliceNotes(
            slice.bassNotes,
            sliceStartUs: sliceStartUs,
            usPerQuarter: usPerQuarter,
            defaultVelocity: 84,
            openTies: openTies,
            rawSpans: rawSpans,
          );
        }
        cursorUs = sliceEndUs;
      }
    }
    return (sliceWindows: sliceWindows, rawSpans: rawSpans);
  }

  static (int, int)? _resolveMeasureBounds(
    Score score,
    ScorePlaybackOptions options,
  ) {
    final maxIdx = score.measures.length - 1;
    final start = (options.startMeasureIndex ?? 0).clamp(0, maxIdx);
    var end = (options.endMeasureIndex ?? maxIdx).clamp(start, maxIdx);
    if (options.trimTrailingEmptyMeasures && options.endMeasureIndex == null) {
      var lastWithNotes = -1;
      for (var i = end; i >= start; i -= 1) {
        final hasNote = score.measures[i].slices.any(
          (s) =>
              (options.includeTreble && s.trebleNotes.isNotEmpty) ||
              (options.includeBass && s.bassNotes.isNotEmpty),
        );
        if (hasNote) {
          lastWithNotes = i;
          break;
        }
      }
      if (lastWithNotes < 0) {
        return null;
      }
      end = lastWithNotes;
    }
    return (start, end);
  }

  static void _collectSliceNotes(
    List<ScoreNote> notes, {
    required int sliceStartUs,
    required double usPerQuarter,
    required int defaultVelocity,
    required Map<(Clef, int), MutablePlaybackSpan> openTies,
    required List<MutablePlaybackSpan> rawSpans,
  }) {
    for (final note in notes) {
      final rawDurUs = (note.duration.quarterBeats.toDouble * usPerQuarter)
          .round();
      final noteDurUs = rawDurUs.clamp(25000, maxScheduleDurationUs);
      final noteEndUs = math.min(
        maxScheduleDurationUs,
        sliceStartUs + noteDurUs,
      );
      final key = (note.staffNote.clef, note.midiNote.number);

      if (!note.requiresAttack) {
        final tied = openTies[key];
        if (tied != null && (sliceStartUs - tied.endUs).abs() <= 5000) {
          if (noteEndUs > tied.endUs) {
            tied.endUs = noteEndUs;
          }
          if (note.tie == TieType.stop) {
            openTies.remove(key);
          }
        }
        continue;
      }

      final span = MutablePlaybackSpan(
        midiNote: note.midiNote,
        velocity: defaultVelocity,
        startUs: sliceStartUs,
        endUs: noteEndUs,
      );
      rawSpans.add(span);
      if (note.tie == TieType.start) {
        openTies[key] = span;
      } else {
        openTies.remove(key);
      }
    }
  }
}
