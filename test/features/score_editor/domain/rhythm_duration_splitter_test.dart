import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/score_editor/domain/rhythm_duration_splitter.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('splitDuration', () {
    test('decomposes exact and composite durations largest-first', () {
      expect(splitDuration(const RationalBeats.zero()), isEmpty);
      expect(splitDuration(RationalBeats(3)), <DurationValue>[
        DurationValue(base: NoteBaseDuration.half, dots: 1),
      ]);
      expect(splitDuration(RationalBeats(5, 2)), <DurationValue>[
        DurationValue(base: NoteBaseDuration.half),
        DurationValue(base: NoteBaseDuration.eighth),
      ]);
      expect(splitDuration(RationalBeats(1, 32)), <DurationValue>[
        DurationValue(
          base: NoteBaseDuration.sixtyFourth,
          quarterBeats: RationalBeats(1, 32),
        ),
      ]);
    });
  });

  group('fillRestGaps', () {
    test('emits full-measure whole rest for completely empty bars', () {
      final rests = fillRestGaps(
        measureBeats: RationalBeats(3),
        occupiedSpans: const <BeatSpan>[],
        clef: Clef.treble,
      );
      expect(rests, hasLength(1));
      expect(rests.single.beatOffset, const RationalBeats.zero());
      expect(rests.single.duration.base, NoteBaseDuration.whole);
      expect(rests.single.duration.quarterBeats, RationalBeats(3));
    });

    test('splits uncovered gaps into beat-aligned rests', () {
      // Quarter note at beat 0..1 -> remaining 1..4 splits into quarter (1..2) + half (2..4).
      final restsAfterBeat0 = fillRestGaps(
        measureBeats: RationalBeats(4),
        occupiedSpans: <BeatSpan>[
          (start: const RationalBeats.zero(), end: RationalBeats(1)),
        ],
        clef: Clef.treble,
      );
      expect(
        restsAfterBeat0.map((r) => (r.beatOffset, r.duration.base)).toList(),
        <(RationalBeats, NoteBaseDuration)>[
          (RationalBeats(1), NoteBaseDuration.quarter),
          (RationalBeats(2), NoteBaseDuration.half),
        ],
      );

      // Eighth note at 0..1/2 -> remaining 1/2..2 splits into eighth (1/2..1) + quarter (1..2).
      final restsOffbeat = fillRestGaps(
        measureBeats: RationalBeats(2),
        occupiedSpans: <BeatSpan>[
          (start: const RationalBeats.zero(), end: RationalBeats(1, 2)),
        ],
        clef: Clef.bass,
      );
      expect(
        restsOffbeat.map((r) => (r.beatOffset, r.duration.base)).toList(),
        <(RationalBeats, NoteBaseDuration)>[
          (RationalBeats(1, 2), NoteBaseDuration.eighth),
          (RationalBeats(1), NoteBaseDuration.quarter),
        ],
      );
    });
  });
}
