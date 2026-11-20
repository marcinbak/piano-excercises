import 'package:piano_exercises/shared/music/music.dart';

/// Beat-span interval `[start, end)` occupied by one or more notes on a staff.
typedef BeatSpan = ({RationalBeats start, RationalBeats end});

/// Standard durations sorted descending for greedy rhythmic decomposition.
final List<DurationValue> _standardDurationsDesc = (() {
  final list = <DurationValue>[
    for (final base in NoteBaseDuration.values)
      for (var dots = 2; dots >= 0; dots -= 1)
        DurationValue(base: base, dots: dots),
  ]..sort((a, b) => b.quarterBeats.compareTo(a.quarterBeats));
  return List<DurationValue>.unmodifiable(list);
})();

/// Decomposes [beats] into standard [DurationValue] pieces (largest fitting first).
List<DurationValue> splitDuration(RationalBeats beats) {
  if (beats.isZero) {
    return const <DurationValue>[];
  }
  final parts = <DurationValue>[];
  var remaining = beats;
  while (!remaining.isZero) {
    DurationValue? match;
    for (final candidate in _standardDurationsDesc) {
      if (candidate.quarterBeats <= remaining) {
        match = candidate;
        break;
      }
    }
    if (match == null) {
      parts.add(
        DurationValue(
          base: NoteBaseDuration.sixtyFourth,
          quarterBeats: remaining,
        ),
      );
      break;
    }
    parts.add(match);
    remaining = remaining - match.quarterBeats;
  }
  return List<DurationValue>.unmodifiable(parts);
}

/// Fills uncovered intervals inside `[0, measureBeats)` with beat-aligned rests.
List<RestTimelineInput> fillRestGaps({
  required RationalBeats measureBeats,
  required Iterable<BeatSpan> occupiedSpans,
  required Clef clef,
  int voice = 1,
}) {
  if (measureBeats.isZero) {
    return const <RestTimelineInput>[];
  }
  final merged = _mergeSpans(occupiedSpans, measureBeats);
  if (merged.isEmpty) {
    return <RestTimelineInput>[
      RestTimelineInput(
        clef: clef,
        beatOffset: const RationalBeats.zero(),
        duration: DurationValue(
          base: NoteBaseDuration.whole,
          quarterBeats: measureBeats,
        ),
        voice: voice,
      ),
    ];
  }

  final rests = <RestTimelineInput>[];
  var cursor = const RationalBeats.zero();
  for (final span in merged) {
    if (span.start > cursor) {
      _appendBeatAlignedRests(
        rests,
        clef: clef,
        voice: voice,
        from: cursor,
        to: span.start,
        measureBeats: measureBeats,
      );
    }
    if (span.end > cursor) {
      cursor = span.end;
    }
  }
  if (cursor < measureBeats) {
    _appendBeatAlignedRests(
      rests,
      clef: clef,
      voice: voice,
      from: cursor,
      to: measureBeats,
      measureBeats: measureBeats,
    );
  }
  return List<RestTimelineInput>.unmodifiable(rests);
}

List<BeatSpan> _mergeSpans(
  Iterable<BeatSpan> rawSpans,
  RationalBeats measureBeats,
) {
  final clamped = <BeatSpan>[];
  for (final span in rawSpans) {
    final start = span.start < const RationalBeats.zero()
        ? const RationalBeats.zero()
        : span.start;
    final end = span.end > measureBeats ? measureBeats : span.end;
    if (end > start) {
      clamped.add((start: start, end: end));
    }
  }
  if (clamped.isEmpty) {
    return const <BeatSpan>[];
  }
  clamped.sort((a, b) {
    final startCmp = a.start.compareTo(b.start);
    return startCmp != 0 ? startCmp : a.end.compareTo(b.end);
  });

  final merged = <BeatSpan>[clamped.first];
  for (final next in clamped.skip(1)) {
    final prev = merged.last;
    if (next.start <= prev.end) {
      final combinedEnd = next.end > prev.end ? next.end : prev.end;
      merged[merged.length - 1] = (start: prev.start, end: combinedEnd);
    } else {
      merged.add(next);
    }
  }
  return merged;
}

void _appendBeatAlignedRests(
  List<RestTimelineInput> out, {
  required Clef clef,
  required int voice,
  required RationalBeats from,
  required RationalBeats to,
  required RationalBeats measureBeats,
}) {
  var cursor = from;
  while (cursor < to) {
    final remaining = to - cursor;
    final dur = _pickBeatAlignedRest(cursor, remaining, measureBeats);
    out.add(
      RestTimelineInput(
        clef: clef,
        beatOffset: cursor,
        duration: dur,
        voice: voice,
      ),
    );
    cursor = cursor + dur.quarterBeats;
  }
}

DurationValue _pickBeatAlignedRest(
  RationalBeats cursor,
  RationalBeats remaining,
  RationalBeats measureBeats,
) {
  for (final base in NoteBaseDuration.values) {
    final unit = base.quarterBeats;
    if (unit > remaining) {
      continue;
    }
    if (base == NoteBaseDuration.whole &&
        !(cursor.isZero && unit == measureBeats)) {
      continue;
    }
    if (_isRationalMultiple(cursor, unit)) {
      return DurationValue(base: base);
    }
  }
  for (final base in NoteBaseDuration.values) {
    if (base.quarterBeats <= remaining) {
      return DurationValue(base: base);
    }
  }
  return DurationValue(
    base: NoteBaseDuration.sixtyFourth,
    quarterBeats: remaining,
  );
}

bool _isRationalMultiple(RationalBeats value, RationalBeats unit) {
  if (value.isZero) {
    return true;
  }
  final lhs = BigInt.from(value.numerator) * BigInt.from(unit.denominator);
  final rhs = BigInt.from(value.denominator) * BigInt.from(unit.numerator);
  return (lhs % rhs) == BigInt.zero;
}
