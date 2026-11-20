import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('KeyPitchSpeller.spellMidiNote', () {
    test(
      'prefers diatonic key spellings across -7..+7 including Cb/Fb/E#/B#',
      () {
        // +6 (F# major): E#4 = MIDI 65.
        expect(
          KeyPitchSpeller.spellMidiNote(
            const MidiNote(65),
            clef: Clef.treble,
            keySignature: const KeySignature(6),
          ),
          const StaffNote(
            note: DiatonicNote.e,
            octave: 4,
            clef: Clef.treble,
            accidental: Accidental.sharp,
          ),
        );

        // +7 (C# major): B#3 = MIDI 60.
        expect(
          KeyPitchSpeller.spellMidiNote(
            const MidiNote(60),
            clef: Clef.treble,
            keySignature: const KeySignature(7),
          ),
          const StaffNote(
            note: DiatonicNote.b,
            octave: 3,
            clef: Clef.treble,
            accidental: Accidental.sharp,
          ),
        );

        // -6 (Gb major): Cb4 = MIDI 59.
        expect(
          KeyPitchSpeller.spellMidiNote(
            const MidiNote(59),
            clef: Clef.bass,
            keySignature: const KeySignature(-6),
          ),
          const StaffNote(
            note: DiatonicNote.c,
            octave: 4,
            clef: Clef.bass,
            accidental: Accidental.flat,
          ),
        );

        // -7 (Cb major): Fb4 = MIDI 64.
        expect(
          KeyPitchSpeller.spellMidiNote(
            const MidiNote(64),
            clef: Clef.treble,
            keySignature: const KeySignature(-7),
          ),
          const StaffNote(
            note: DiatonicNote.f,
            octave: 4,
            clef: Clef.treble,
            accidental: Accidental.flat,
          ),
        );
      },
    );

    test('falls back to naturals then chromatic sharps/flats by fifths sign', () {
      // C4 (MIDI 60) is outside D major (+2: F#, C#), falls back to C natural.
      expect(
        KeyPitchSpeller.spellMidiNote(
          const MidiNote(60),
          clef: Clef.treble,
          keySignature: const KeySignature(2),
        ),
        const StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble),
      );

      // Chromatic D#4/Eb4 (MIDI 63) in G major (+1) spells as D#4; in F major (-1) as Eb4.
      expect(
        KeyPitchSpeller.spellMidiNote(
          const MidiNote(63),
          clef: Clef.treble,
          keySignature: const KeySignature(1),
        ),
        const StaffNote(
          note: DiatonicNote.d,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.sharp,
        ),
      );
      expect(
        KeyPitchSpeller.spellMidiNote(
          const MidiNote(63),
          clef: Clef.treble,
          keySignature: const KeySignature(-1),
        ),
        const StaffNote(
          note: DiatonicNote.e,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.flat,
        ),
      );

      // Extreme MIDI boundaries (0 and 127) across sharp/flat keys never throw.
      for (var fifths = -7; fifths <= 7; fifths += 1) {
        final low = KeyPitchSpeller.spellMidiNote(
          const MidiNote(0),
          clef: Clef.bass,
          keySignature: KeySignature(fifths),
        );
        final high = KeyPitchSpeller.spellMidiNote(
          const MidiNote(127),
          clef: Clef.treble,
          keySignature: KeySignature(fifths),
        );
        expect(low.midiNote.number, 0);
        expect(high.midiNote.number, 127);
      }
    });
  });

  group('KeyPitchSpeller.stepDiatonic', () {
    test('steps up/down diatonically across octaves using key defaults', () {
      const fSharpKey = KeySignature(2); // D major: F#, C#
      const e4 = StaffNote(note: DiatonicNote.e, octave: 4, clef: Clef.treble);

      expect(
        KeyPitchSpeller.stepDiatonic(
          e4,
          deltaSteps: 1,
          keySignature: fSharpKey,
        ),
        const StaffNote(
          note: DiatonicNote.f,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.sharp,
        ),
      );

      const c4 = StaffNote(
        note: DiatonicNote.c,
        octave: 4,
        clef: Clef.bass,
        accidental: Accidental.sharp,
      );
      expect(
        KeyPitchSpeller.stepDiatonic(
          c4,
          deltaSteps: -1,
          keySignature: fSharpKey,
        ),
        const StaffNote(note: DiatonicNote.b, octave: 3, clef: Clef.bass),
      );
      expect(
        KeyPitchSpeller.stepDiatonic(
          c4,
          deltaSteps: 0,
          keySignature: fSharpKey,
        ),
        c4,
      );
    });

    test('returns current when stepping beyond MIDI 0..127 bounds', () {
      const lowC = StaffNote(note: DiatonicNote.c, octave: -1, clef: Clef.bass);
      expect(
        KeyPitchSpeller.stepDiatonic(
          lowC,
          deltaSteps: -1,
          keySignature: KeySignature.cMajor,
        ),
        lowC,
      );

      const highG = StaffNote(
        note: DiatonicNote.g,
        octave: 9,
        clef: Clef.treble,
      );
      expect(
        KeyPitchSpeller.stepDiatonic(
          highG,
          deltaSteps: 1,
          keySignature: KeySignature.cMajor,
        ),
        highG,
      );
    });
  });

  group('KeyPitchSpeller.withAccidental', () {
    test('applies valid accidentals and clamps out-of-range MIDI', () {
      const c4 = StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble);
      expect(
        KeyPitchSpeller.withAccidental(c4, Accidental.sharp),
        const StaffNote(
          note: DiatonicNote.c,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.sharp,
        ),
      );

      const lowC = StaffNote(note: DiatonicNote.c, octave: -1, clef: Clef.bass);
      expect(KeyPitchSpeller.withAccidental(lowC, Accidental.flat), lowC);

      const highG = StaffNote(
        note: DiatonicNote.g,
        octave: 9,
        clef: Clef.treble,
      );
      expect(KeyPitchSpeller.withAccidental(highG, Accidental.sharp), highG);
    });
  });
}
