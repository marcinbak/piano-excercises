import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/domain/polyphonic_evaluator.dart';
import 'package:piano_exercises/shared/music/music.dart';

ScoreNote _scoreNote({
  required DiatonicNote note,
  required int octave,
  required Clef clef,
  Accidental accidental = Accidental.natural,
  TieType tie = TieType.none,
}) {
  return ScoreNote(
    staffNote: StaffNote(
      note: note,
      octave: octave,
      clef: clef,
      accidental: accidental,
    ),
    duration: DurationValue(base: NoteBaseDuration.quarter),
    tie: tie,
  );
}

ScoreSlice _slice({
  int sliceIndex = 0,
  List<ScoreNote> trebleNotes = const <ScoreNote>[],
  List<ScoreNote> bassNotes = const <ScoreNote>[],
}) {
  return ScoreSlice(
    sliceIndex: sliceIndex,
    measureNumber: 1,
    beatOffset: const RationalBeats.zero(),
    beatDuration: RationalBeats(1),
    trebleNotes: trebleNotes,
    bassNotes: bassNotes,
  );
}

void main() {
  group('PolyphonicEvaluator', () {
    final grandSlice = _slice(
      trebleNotes: <ScoreNote>[
        _scoreNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble),
        _scoreNote(note: DiatonicNote.e, octave: 4, clef: Clef.treble),
      ],
      bassNotes: <ScoreNote>[
        _scoreNote(note: DiatonicNote.c, octave: 3, clef: Clef.bass),
      ],
    );

    test(
      'evaluates completeMatch, partialChord, and wrongNotes per HandMode',
      () {
        final completeBoth = PolyphonicEvaluator.evaluateSlice(
          slice: grandSlice,
          handMode: HandMode.both,
          playedPitches: <MidiNote>{
            const MidiNote(48),
            const MidiNote(60),
            const MidiNote(64),
          },
          activeKeySignature: KeySignature.cMajor,
        );
        expect(completeBoth.status, ChordEvaluationStatus.completeMatch);
        expect(completeBoth.wrongPitches, isEmpty);
        expect(completeBoth.missingPitches, isEmpty);
        expect(completeBoth.wrongStaffNotes, isEmpty);

        final partialRight = PolyphonicEvaluator.evaluateSlice(
          slice: grandSlice,
          handMode: HandMode.right,
          playedPitches: <MidiNote>{const MidiNote(60)},
          activeKeySignature: KeySignature.cMajor,
        );
        expect(partialRight.status, ChordEvaluationStatus.partialChord);
        expect(partialRight.missingPitches, <MidiNote>{const MidiNote(64)});
        expect(partialRight.wrongPitches, isEmpty);

        // Left hand only requires C3 (48); playing E4 (64) counts as wrong.
        final wrongInLeftMode = PolyphonicEvaluator.evaluateSlice(
          slice: grandSlice,
          handMode: HandMode.left,
          playedPitches: <MidiNote>{const MidiNote(48), const MidiNote(64)},
          activeKeySignature: KeySignature.cMajor,
        );
        expect(wrongInLeftMode.status, ChordEvaluationStatus.wrongNotes);
        expect(wrongInLeftMode.wrongPitches, <MidiNote>{const MidiNote(64)});
        expect(wrongInLeftMode.wrongStaffNotes, const <StaffNote>[
          StaffNote(note: DiatonicNote.e, octave: 4, clef: Clef.treble),
        ]);
      },
    );

    test('allows sustained tied notes without requiring re-strike', () {
      final tiedSlice = _slice(
        trebleNotes: <ScoreNote>[
          _scoreNote(
            note: DiatonicNote.g,
            octave: 4,
            clef: Clef.treble,
            tie: TieType.continueTie,
          ),
          _scoreNote(note: DiatonicNote.e, octave: 4, clef: Clef.treble),
        ],
        bassNotes: <ScoreNote>[
          _scoreNote(
            note: DiatonicNote.c,
            octave: 3,
            clef: Clef.bass,
            tie: TieType.stop,
          ),
        ],
      );

      final attackOnly = PolyphonicEvaluator.evaluateSlice(
        slice: tiedSlice,
        handMode: HandMode.both,
        playedPitches: <MidiNote>{const MidiNote(64)},
        activeKeySignature: KeySignature.cMajor,
      );
      expect(attackOnly.status, ChordEvaluationStatus.completeMatch);

      // Keeping tied G4 (67) and C3 (48) depressed/re-struck produces zero wrong notes.
      final withSustained = PolyphonicEvaluator.evaluateSlice(
        slice: tiedSlice,
        handMode: HandMode.both,
        playedPitches: <MidiNote>{
          const MidiNote(48),
          const MidiNote(64),
          const MidiNote(67),
        },
        activeKeySignature: KeySignature.cMajor,
      );
      expect(withSustained.status, ChordEvaluationStatus.completeMatch);
      expect(withSustained.wrongStaffNotes, isEmpty);
    });

    test('spells wrong notes with key-signature diatonic preference, accidental direction, and Middle C clef', () {
      final bassOnlySlice = _slice(
        bassNotes: <ScoreNote>[
          _scoreNote(note: DiatonicNote.c, octave: 4, clef: Clef.bass),
        ],
      );

      // Middle C (60) adopts bass clef when HandMode.both slice has only bass attacks.
      final middleCBass = PolyphonicEvaluator.evaluateSlice(
        slice: _slice(
          bassNotes: <ScoreNote>[
            _scoreNote(note: DiatonicNote.g, octave: 3, clef: Clef.bass),
          ],
        ),
        handMode: HandMode.both,
        playedPitches: <MidiNote>{const MidiNote(60), const MidiNote(66)},
        activeKeySignature: const KeySignature(2), // D major (F#, C#)
      );
      expect(middleCBass.wrongStaffNotes, const <StaffNote>[
        StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.bass),
        StaffNote(
          note: DiatonicNote.f,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.sharp,
        ),
      ]);

      // Flat key (-3: Bb, Eb, Ab) spells diatonic Bb4 as Bb and chromatic Db4 as Db.
      final flatEval = PolyphonicEvaluator.evaluateSlice(
        slice: bassOnlySlice,
        handMode: HandMode.left,
        playedPitches: <MidiNote>{const MidiNote(61), const MidiNote(70)},
        activeKeySignature: const KeySignature(-3),
      );
      expect(flatEval.wrongStaffNotes, const <StaffNote>[
        StaffNote(
          note: DiatonicNote.d,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.flat,
        ),
        StaffNote(
          note: DiatonicNote.b,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.flat,
        ),
      ]);

      // Enharmonic key boundaries across octave-1..octave+1: E#4 (65 in +6), Cb4 (59 in -6).
      expect(
        PolyphonicEvaluator.spellMidiNoteForScore(
          midiNote: const MidiNote(65),
          referenceClef: Clef.treble,
          activeKeySignature: const KeySignature(6),
        ),
        const StaffNote(
          note: DiatonicNote.e,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.sharp,
        ),
      );
      expect(
        PolyphonicEvaluator.spellMidiNoteForScore(
          midiNote: const MidiNote(59),
          referenceClef: Clef.treble,
          activeKeySignature: const KeySignature(-6),
        ),
        const StaffNote(
          note: DiatonicNote.c,
          octave: 4,
          clef: Clef.bass,
          accidental: Accidental.flat,
        ),
      );
    });
  });
}
