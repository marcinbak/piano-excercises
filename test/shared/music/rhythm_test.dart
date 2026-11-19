import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('RationalBeats', () {
    test('normalizes fractions by GCD and supports arithmetic & ordering', () {
      const zero = RationalBeats.zero();
      expect(zero.isZero, isTrue);
      expect(zero.numerator, 0);
      expect(zero.denominator, 1);
      expect(RationalBeats(0, 7), equals(zero));

      final half = RationalBeats(2, 4);
      expect(half.numerator, 1);
      expect(half.denominator, 2);
      expect(half.toDouble, 0.5);

      final third = RationalBeats(1, 3);
      final sum = half + third;
      expect(sum, RationalBeats(5, 6));
      expect(sum - third, half);
      expect(third * 3, RationalBeats(1));
      expect(third < half, isTrue);
      expect(half > third, isTrue);
      expect(half >= RationalBeats(1, 2), isTrue);
      expect(third.compareTo(half), lessThan(0));

      expect(() => RationalBeats(-1, 2), throwsRangeError);
      expect(() => RationalBeats(1, 0), throwsRangeError);
      expect(() => third - half, throwsRangeError);
      expect(() => half * -1, throwsRangeError);
    });
  });

  group('DurationValue', () {
    test(
      'computes dotted beats for 0..2 dots and accepts tuplet overrides',
      () {
        final quarter = DurationValue(base: NoteBaseDuration.quarter);
        expect(quarter.quarterBeats, RationalBeats(1));

        final dottedHalf = DurationValue(base: NoteBaseDuration.half, dots: 1);
        expect(dottedHalf.quarterBeats, RationalBeats(3));

        final doubleDottedQuarter = DurationValue(
          base: NoteBaseDuration.quarter,
          dots: 2,
        );
        expect(doubleDottedQuarter.quarterBeats, RationalBeats(7, 4));

        final tripletEighth = DurationValue(
          base: NoteBaseDuration.eighth,
          quarterBeats: RationalBeats(1, 3),
        );
        expect(tripletEighth.quarterBeats, RationalBeats(1, 3));
        expect(
          tripletEighth,
          equals(
            DurationValue(
              base: NoteBaseDuration.eighth,
              quarterBeats: RationalBeats(1, 3),
            ),
          ),
        );

        expect(
          () => DurationValue(base: NoteBaseDuration.quarter, dots: 3),
          throwsRangeError,
        );
        expect(
          () => DurationValue(
            base: NoteBaseDuration.quarter,
            quarterBeats: const RationalBeats.zero(),
          ),
          throwsRangeError,
        );
      },
    );
  });

  group('TimeSignature & TempoMark', () {
    test('validates meters and tempo bounds', () {
      expect(TimeSignature.common.label, '4/4');
      expect(TimeSignature.common.measureQuarterBeats, RationalBeats(4));

      final threeFour = TimeSignature(3, 4);
      expect(threeFour.measureQuarterBeats, RationalBeats(3));
      expect(threeFour.label, '3/4');

      final sixEight = TimeSignature(6, 8);
      expect(sixEight.measureQuarterBeats, RationalBeats(3));

      expect(() => TimeSignature(0, 4), throwsRangeError);
      expect(() => TimeSignature(33, 4), throwsRangeError);
      expect(() => TimeSignature(4, 3), throwsArgumentError);
      expect(() => TimeSignature(4, 64), throwsArgumentError);

      final tempo = TempoMark(120);
      expect(tempo.bpm, 120);
      expect(tempo, equals(TempoMark(120)));
      expect(tempo.hashCode, TempoMark(120).hashCode);
      expect(() => TempoMark(0), throwsRangeError);
      expect(() => TempoMark(1000), throwsRangeError);
    });
  });
}
