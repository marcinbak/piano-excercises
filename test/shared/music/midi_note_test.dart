import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('PitchClass', () {
    test('maps natural and sharp classes across 0..11', () {
      expect(PitchClass.values, hasLength(12));
      expect(PitchClass.c.semitone, 0);
      expect(PitchClass.c.label, 'C');
      expect(PitchClass.c.isNatural, isTrue);
      expect(PitchClass.c.naturalNote, DiatonicNote.c);

      expect(PitchClass.cSharp.semitone, 1);
      expect(PitchClass.cSharp.label, 'C#');
      expect(PitchClass.cSharp.isNatural, isFalse);
      expect(PitchClass.cSharp.naturalNote, isNull);
    });

    test('fromSemitone wraps negative and multi-octave values modulo 12', () {
      expect(PitchClass.fromSemitone(0), PitchClass.c);
      expect(PitchClass.fromSemitone(11), PitchClass.b);
      expect(PitchClass.fromSemitone(12), PitchClass.c);
      expect(PitchClass.fromSemitone(-1), PitchClass.b);
      expect(PitchClass.fromSemitone(61), PitchClass.cSharp);
    });
  });

  group('MidiNote', () {
    test('exposes boundary values and scientific pitch properties', () {
      const cMinus1 = MidiNote(0);
      const a0 = MidiNote(21);
      const middleC = MidiNote.middleC;
      const cSharp4 = MidiNote(61);
      const c8 = MidiNote(108);
      const g9 = MidiNote(127);

      expect(cMinus1.number, 0);
      expect(cMinus1.octave, -1);
      expect(cMinus1.pitchClass, PitchClass.c);
      expect(cMinus1.isNatural, isTrue);
      expect(cMinus1.naturalNote, DiatonicNote.c);
      expect(cMinus1.name, 'C-1');

      expect(a0.name, 'A0');
      expect(middleC.number, 60);
      expect(middleC.name, 'C4');
      expect(middleC.octave, 4);

      expect(cSharp4.name, 'C#4');
      expect(cSharp4.isNatural, isFalse);
      expect(cSharp4.naturalNote, isNull);

      expect(c8.name, 'C8');
      expect(g9.name, 'G9');
      expect(g9.octave, 9);
    });

    test(
      'fromNumber validates 0..127 and tryFromNumber returns null outside',
      () {
        expect(MidiNote.fromNumber(0), const MidiNote(0));
        expect(MidiNote.fromNumber(127), const MidiNote(127));
        expect(() => MidiNote.fromNumber(-1), throwsRangeError);
        expect(() => MidiNote.fromNumber(128), throwsRangeError);

        expect(MidiNote.tryFromNumber(-1), isNull);
        expect(MidiNote.tryFromNumber(128), isNull);
        expect(MidiNote.tryFromNumber(60), MidiNote.middleC);
      },
    );

    test(
      'fromPitch computes MIDI number with accidentals and validates range',
      () {
        expect(
          MidiNote.fromPitch(DiatonicNote.c, octave: -1),
          const MidiNote(0),
        );
        expect(
          MidiNote.fromPitch(DiatonicNote.a, octave: 0),
          const MidiNote(21),
        );
        expect(MidiNote.fromPitch(DiatonicNote.c, octave: 4), MidiNote.middleC);
        expect(
          MidiNote.fromPitch(DiatonicNote.g, octave: 9),
          const MidiNote(127),
        );

        expect(
          MidiNote.fromPitch(
            DiatonicNote.c,
            octave: 4,
            accidental: Accidental.sharp,
          ),
          const MidiNote(61),
        );
        expect(
          MidiNote.fromPitch(
            DiatonicNote.d,
            octave: 4,
            accidental: Accidental.flat,
          ),
          const MidiNote(61),
        );
        expect(
          MidiNote.fromPitch(
            DiatonicNote.c,
            octave: 4,
            accidental: Accidental.flat,
          ),
          const MidiNote(59),
        );
        expect(
          MidiNote.fromPitch(
            DiatonicNote.b,
            octave: 3,
            accidental: Accidental.sharp,
          ),
          MidiNote.middleC,
        );

        expect(
          () => MidiNote.fromPitch(
            DiatonicNote.c,
            octave: -1,
            accidental: Accidental.flat,
          ),
          throwsRangeError,
        );
        expect(
          () => MidiNote.fromPitch(
            DiatonicNote.g,
            octave: 9,
            accidental: Accidental.sharp,
          ),
          throwsRangeError,
        );
        expect(
          () => MidiNote.fromPitch(DiatonicNote.c, octave: -2),
          throwsRangeError,
        );
      },
    );

    test('supports Comparable ordering and value equality', () {
      const low = MidiNote(36);
      const midA = MidiNote(60);
      const midB = MidiNote(60);
      const high = MidiNote(84);

      expect(midA, equals(midB));
      expect(midA.hashCode, equals(midB.hashCode));
      expect(low, isNot(equals(midA)));
      expect(low.compareTo(midA), lessThan(0));
      expect(high.compareTo(midA), greaterThan(0));
      expect(midA.compareTo(midB), 0);

      final notes = <MidiNote>[high, low, midA]..sort();
      expect(notes, <MidiNote>[low, midA, high]);
    });
  });
}
