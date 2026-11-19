import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('KeySignature', () {
    test('validates fifths in -7..7 and exposes sharp/flat orders', () {
      expect(KeySignature.cMajor.fifths, 0);
      expect(KeySignature.cMajor.alteredNotes, isEmpty);
      expect(
        KeySignature.cMajor.defaultAccidentalFor(DiatonicNote.f),
        Accidental.natural,
      );

      final gMajor = KeySignature.validated(1);
      expect(gMajor.alteredNotes, const <DiatonicNote>[DiatonicNote.f]);
      expect(gMajor.defaultAccidentalFor(DiatonicNote.f), Accidental.sharp);
      expect(gMajor.defaultAccidentalFor(DiatonicNote.c), Accidental.natural);

      final ebMajor = KeySignature.validated(-3);
      expect(ebMajor.alteredNotes, const <DiatonicNote>[
        DiatonicNote.b,
        DiatonicNote.e,
        DiatonicNote.a,
      ]);
      expect(ebMajor.defaultAccidentalFor(DiatonicNote.b), Accidental.flat);
      expect(ebMajor.defaultAccidentalFor(DiatonicNote.e), Accidental.flat);
      expect(ebMajor.defaultAccidentalFor(DiatonicNote.a), Accidental.flat);
      expect(ebMajor.defaultAccidentalFor(DiatonicNote.d), Accidental.natural);

      expect(() => KeySignature.validated(-8), throwsRangeError);
      expect(() => KeySignature.validated(8), throwsRangeError);
      expect(
        () => gMajor.alteredNotes.add(DiatonicNote.c),
        throwsUnsupportedError,
      );
    });

    test('supports value equality and hashCode', () {
      const a = KeySignature(2);
      final b = KeySignature.validated(2);
      const c = KeySignature(-2);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('Scale', () {
    test('maps all fifths -7..+7 for major and minor modes', () {
      const expectedMajor = <String>[
        'Cb Major',
        'Gb Major',
        'Db Major',
        'Ab Major',
        'Eb Major',
        'Bb Major',
        'F Major',
        'C Major',
        'G Major',
        'D Major',
        'A Major',
        'E Major',
        'B Major',
        'F# Major',
        'C# Major',
      ];
      const expectedMinor = <String>[
        'Ab Minor',
        'Eb Minor',
        'Bb Minor',
        'F Minor',
        'C Minor',
        'G Minor',
        'D Minor',
        'A Minor',
        'E Minor',
        'B Minor',
        'F# Minor',
        'C# Minor',
        'G# Minor',
        'D# Minor',
        'A# Minor',
      ];

      for (var fifths = -7; fifths <= 7; fifths += 1) {
        final key = KeySignature(fifths);
        expect(
          Scale.fromKeySignature(key, mode: ScaleMode.major).label,
          expectedMajor[fifths + 7],
        );
        expect(
          Scale.fromKeySignature(key, mode: ScaleMode.minor).label,
          expectedMinor[fifths + 7],
        );
      }
    });

    test('computes degreeSpellings and value equality', () {
      final gMajor = Scale.fromKeySignature(const KeySignature(1));
      expect(gMajor.degreeSpellings, const <(DiatonicNote, Accidental)>[
        (DiatonicNote.g, Accidental.natural),
        (DiatonicNote.a, Accidental.natural),
        (DiatonicNote.b, Accidental.natural),
        (DiatonicNote.c, Accidental.natural),
        (DiatonicNote.d, Accidental.natural),
        (DiatonicNote.e, Accidental.natural),
        (DiatonicNote.f, Accidental.sharp),
      ]);
      expect(
        () => gMajor.degreeSpellings.add((DiatonicNote.c, Accidental.natural)),
        throwsUnsupportedError,
      );

      final cMinor = Scale.fromKeySignature(
        const KeySignature(-3),
        mode: ScaleMode.minor,
      );
      expect(cMinor.label, 'C Minor');
      expect(cMinor.degreeSpellings, const <(DiatonicNote, Accidental)>[
        (DiatonicNote.c, Accidental.natural),
        (DiatonicNote.d, Accidental.natural),
        (DiatonicNote.e, Accidental.flat),
        (DiatonicNote.f, Accidental.natural),
        (DiatonicNote.g, Accidental.natural),
        (DiatonicNote.a, Accidental.flat),
        (DiatonicNote.b, Accidental.flat),
      ]);

      final gMajorCopy = Scale.fromKeySignature(const KeySignature(1));
      expect(gMajor, equals(gMajorCopy));
      expect(gMajor.hashCode, equals(gMajorCopy.hashCode));
      expect(gMajor, isNot(equals(cMinor)));
    });
  });
}
