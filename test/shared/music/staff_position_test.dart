import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('Clef', () {
    test('defines treble and bass anchor steps', () {
      expect(Clef.treble.bottomLineDiatonicStep, 30);
      expect(Clef.treble.topLineDiatonicStep, 38);
      expect(Clef.treble.referenceLineOffset, 2);
      expect(Clef.treble.referenceDiatonicStep, 32);

      expect(Clef.bass.bottomLineDiatonicStep, 18);
      expect(Clef.bass.topLineDiatonicStep, 26);
      expect(Clef.bass.referenceLineOffset, 6);
      expect(Clef.bass.referenceDiatonicStep, 24);
    });
  });

  group('StaffPosition', () {
    test('maps treble inside-staff lines and spaces accurately', () {
      const e4 = StaffNote(note: DiatonicNote.e, octave: 4, clef: Clef.treble);
      const f4 = StaffNote(note: DiatonicNote.f, octave: 4, clef: Clef.treble);
      const g4 = StaffNote(note: DiatonicNote.g, octave: 4, clef: Clef.treble);
      const f5 = StaffNote(note: DiatonicNote.f, octave: 5, clef: Clef.treble);

      expect(e4.staffPosition.stepsFromBottomLine, 0);
      expect(e4.staffPosition.isOnLine, isTrue);
      expect(e4.staffPosition.isInSpace, isFalse);
      expect(e4.staffPosition.isInsideStaff, isTrue);
      expect(e4.staffPosition.ledgerDirection, LedgerDirection.none);
      expect(e4.staffPosition.ledgerLineCount, 0);
      expect(e4.staffPosition.ledgerLineSteps, isEmpty);

      expect(f4.staffPosition.stepsFromBottomLine, 1);
      expect(f4.staffPosition.isOnLine, isFalse);
      expect(f4.staffPosition.isInSpace, isTrue);
      expect(f4.staffPosition.isInsideStaff, isTrue);

      expect(g4.staffPosition.stepsFromBottomLine, 2);
      expect(f5.staffPosition.stepsFromBottomLine, 8);
      expect(f5.staffPosition.isOnLine, isTrue);
      expect(f5.staffPosition.isInsideStaff, isTrue);
    });

    test('maps bass inside-staff lines and spaces accurately', () {
      const g2 = StaffNote(note: DiatonicNote.g, octave: 2, clef: Clef.bass);
      const c3 = StaffNote(note: DiatonicNote.c, octave: 3, clef: Clef.bass);
      const f3 = StaffNote(note: DiatonicNote.f, octave: 3, clef: Clef.bass);
      const a3 = StaffNote(note: DiatonicNote.a, octave: 3, clef: Clef.bass);

      expect(g2.staffPosition.stepsFromBottomLine, 0);
      expect(g2.staffPosition.isOnLine, isTrue);
      expect(g2.staffPosition.isInsideStaff, isTrue);

      expect(c3.staffPosition.stepsFromBottomLine, 3);
      expect(c3.staffPosition.isInSpace, isTrue);
      expect(c3.staffPosition.isInsideStaff, isTrue);

      expect(f3.staffPosition.stepsFromBottomLine, 6);
      expect(f3.staffPosition.isOnLine, isTrue);

      expect(a3.staffPosition.stepsFromBottomLine, 8);
      expect(a3.staffPosition.isOnLine, isTrue);
      expect(a3.staffPosition.ledgerLineCount, 0);
    });

    test('handles Middle C (C4) on both clefs', () {
      const trebleC4 = StaffNote(
        note: DiatonicNote.c,
        octave: 4,
        clef: Clef.treble,
      );
      const bassC4 = StaffNote(
        note: DiatonicNote.c,
        octave: 4,
        clef: Clef.bass,
      );

      expect(trebleC4.staffPosition.stepsFromBottomLine, -2);
      expect(trebleC4.staffPosition.isOnLine, isTrue);
      expect(trebleC4.staffPosition.isInsideStaff, isFalse);
      expect(trebleC4.staffPosition.ledgerDirection, LedgerDirection.below);
      expect(trebleC4.staffPosition.ledgerLineCount, 1);
      expect(trebleC4.staffPosition.ledgerLineSteps, <int>[-2]);

      expect(bassC4.staffPosition.stepsFromBottomLine, 10);
      expect(bassC4.staffPosition.isOnLine, isTrue);
      expect(bassC4.staffPosition.isInsideStaff, isFalse);
      expect(bassC4.staffPosition.ledgerDirection, LedgerDirection.above);
      expect(bassC4.staffPosition.ledgerLineCount, 1);
      expect(bassC4.staffPosition.ledgerLineSteps, <int>[10]);
    });

    test('requires zero ledger lines for adjacent outer spaces', () {
      const trebleD4 = StaffNote(
        note: DiatonicNote.d,
        octave: 4,
        clef: Clef.treble,
      );
      const trebleG5 = StaffNote(
        note: DiatonicNote.g,
        octave: 5,
        clef: Clef.treble,
      );
      const bassF2 = StaffNote(
        note: DiatonicNote.f,
        octave: 2,
        clef: Clef.bass,
      );
      const bassB3 = StaffNote(
        note: DiatonicNote.b,
        octave: 3,
        clef: Clef.bass,
      );

      for (final staffNote in <StaffNote>[trebleD4, bassF2]) {
        expect(staffNote.staffPosition.stepsFromBottomLine, -1);
        expect(staffNote.staffPosition.isInSpace, isTrue);
        expect(staffNote.staffPosition.isInsideStaff, isFalse);
        expect(staffNote.staffPosition.ledgerDirection, LedgerDirection.none);
        expect(staffNote.staffPosition.ledgerLineCount, 0);
        expect(staffNote.staffPosition.ledgerLineSteps, isEmpty);
      }

      for (final staffNote in <StaffNote>[trebleG5, bassB3]) {
        expect(staffNote.staffPosition.stepsFromBottomLine, 9);
        expect(staffNote.staffPosition.isInSpace, isTrue);
        expect(staffNote.staffPosition.isInsideStaff, isFalse);
        expect(staffNote.staffPosition.ledgerDirection, LedgerDirection.none);
        expect(staffNote.staffPosition.ledgerLineCount, 0);
        expect(staffNote.staffPosition.ledgerLineSteps, isEmpty);
      }
    });

    test('computes multi-ledger outer Cs and outer ledger spaces', () {
      const bassC2 = StaffNote(
        note: DiatonicNote.c,
        octave: 2,
        clef: Clef.bass,
      );
      const bassD2 = StaffNote(
        note: DiatonicNote.d,
        octave: 2,
        clef: Clef.bass,
      );
      const trebleB5 = StaffNote(
        note: DiatonicNote.b,
        octave: 5,
        clef: Clef.treble,
      );
      const trebleC6 = StaffNote(
        note: DiatonicNote.c,
        octave: 6,
        clef: Clef.treble,
      );

      expect(bassC2.staffPosition.stepsFromBottomLine, -4);
      expect(bassC2.staffPosition.ledgerDirection, LedgerDirection.below);
      expect(bassC2.staffPosition.ledgerLineCount, 2);
      expect(bassC2.staffPosition.ledgerLineSteps, <int>[-2, -4]);

      expect(bassD2.staffPosition.stepsFromBottomLine, -3);
      expect(bassD2.staffPosition.isInSpace, isTrue);
      expect(bassD2.staffPosition.ledgerDirection, LedgerDirection.below);
      expect(bassD2.staffPosition.ledgerLineCount, 1);
      expect(bassD2.staffPosition.ledgerLineSteps, <int>[-2]);

      expect(trebleB5.staffPosition.stepsFromBottomLine, 11);
      expect(trebleB5.staffPosition.isInSpace, isTrue);
      expect(trebleB5.staffPosition.ledgerDirection, LedgerDirection.above);
      expect(trebleB5.staffPosition.ledgerLineCount, 1);
      expect(trebleB5.staffPosition.ledgerLineSteps, <int>[10]);

      expect(trebleC6.staffPosition.stepsFromBottomLine, 12);
      expect(trebleC6.staffPosition.ledgerDirection, LedgerDirection.above);
      expect(trebleC6.staffPosition.ledgerLineCount, 2);
      expect(trebleC6.staffPosition.ledgerLineSteps, <int>[10, 12]);
      expect(
        () => trebleC6.staffPosition.ledgerLineSteps.add(14),
        throwsUnsupportedError,
      );
    });

    test('StaffPosition supports value equality and hashCode', () {
      const a = StaffPosition(clef: Clef.treble, stepsFromBottomLine: -2);
      const b = StaffPosition(clef: Clef.treble, stepsFromBottomLine: -2);
      const c = StaffPosition(clef: Clef.bass, stepsFromBottomLine: -2);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('StaffNote', () {
    test(
      'matches MIDI pitches, formats pitch names, and checks clef identity',
      () {
        const trebleC4 = StaffNote(
          note: DiatonicNote.c,
          octave: 4,
          clef: Clef.treble,
        );
        const bassC4 = StaffNote(
          note: DiatonicNote.c,
          octave: 4,
          clef: Clef.bass,
        );
        const cSharp4 = StaffNote(
          note: DiatonicNote.c,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.sharp,
        );
        const dFlat4 = StaffNote(
          note: DiatonicNote.d,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.flat,
        );

        expect(trebleC4.diatonicStep, 28);
        expect(trebleC4.midiNote, MidiNote.middleC);
        expect(trebleC4.pitchName, 'C4');
        expect(trebleC4.matchesMidi(MidiNote.middleC), isTrue);
        expect(trebleC4.matchesNoteNumber(60), isTrue);
        expect(trebleC4.matchesNoteNumber(61), isFalse);
        expect(trebleC4.matchesNoteNumber(-1), isFalse);

        expect(trebleC4, isNot(equals(bassC4)));
        expect(cSharp4.pitchName, 'C#4');
        expect(dFlat4.pitchName, 'Db4');
        expect(cSharp4.matchesMidi(const MidiNote(61)), isTrue);
        expect(dFlat4.matchesMidi(const MidiNote(61)), isTrue);
        expect(cSharp4, isNot(equals(dFlat4)));

        final sameTrebleC4 = StaffNote.validated(
          note: DiatonicNote.c,
          octave: 4,
          clef: Clef.treble,
        );
        expect(sameTrebleC4, equals(trebleC4));
        expect(sameTrebleC4.hashCode, equals(trebleC4.hashCode));
      },
    );

    test('validated factory rejects notes outside MIDI 0..127', () {
      expect(
        () => StaffNote.validated(
          note: DiatonicNote.c,
          octave: -1,
          clef: Clef.bass,
          accidental: Accidental.flat,
        ),
        throwsRangeError,
      );
      expect(
        () => StaffNote.validated(
          note: DiatonicNote.g,
          octave: 9,
          clef: Clef.treble,
          accidental: Accidental.sharp,
        ),
        throwsRangeError,
      );
    });
  });
}
