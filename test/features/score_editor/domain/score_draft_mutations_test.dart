import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_mutations.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('ScoreDraft defaults and ScoreDraft.fromScore', () {
    test(
      'defaults to 4 empty 4/4 C Major bars at split 60 and quarter duration',
      () {
        final draft = ScoreDraft();
        expect(draft.measures, hasLength(4));
        expect(draft.scale, Scale.fromKeySignature(KeySignature.cMajor));
        expect(draft.timeSignature, TimeSignature.common);
        expect(draft.splitPointMidi, 60);
        expect(
          draft.selectedDuration,
          DurationValue(base: NoteBaseDuration.quarter),
        );
        expect(draft.cursor, const EditorCursor(measureIndex: 0));

        final score = draft.toScore();
        expect(score.measures, hasLength(4));
        expect(score.slices, hasLength(4));
        expect(score.slices.every((s) => s.isRestOnly), isTrue);
      },
    );

    test('fromScore preserves independent treble and bass note durations', () {
      final score = ScoreTimelineReducer.reduce(
        title: 'Independent Hands',
        initialScale: Scale.fromKeySignature(const KeySignature(1)),
        initialTimeSignature: TimeSignature.common,
        measures: <MeasureTimelineInput>[
          MeasureTimelineInput(
            measureNumber: 1,
            notes: <NoteTimelineInput>[
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.g,
                octave: 4,
                explicitAlter: 0,
                beatOffset: const RationalBeats.zero(),
                duration: DurationValue(base: NoteBaseDuration.quarter),
              ),
              NoteTimelineInput(
                clef: Clef.bass,
                diatonicNote: DiatonicNote.g,
                octave: 2,
                explicitAlter: 0,
                beatOffset: const RationalBeats.zero(),
                duration: DurationValue(base: NoteBaseDuration.whole),
              ),
            ],
          ),
        ],
      );

      final roundTripped = ScoreDraft.fromScore(score).toScore();
      final m1 = roundTripped.measures.single;
      expect(
        m1.slices[0].trebleNotes.single.duration.base,
        NoteBaseDuration.quarter,
      );
      expect(
        m1.slices[0].bassNotes.single.duration.base,
        NoteBaseDuration.whole,
      );
    });
  });

  group('ScoreDraftMutations MIDI & rhythm editing', () {
    test('enterMidiChord routes clefs, spells by key, preserves untouched clef, splits ties, and auto-appends bar', () {
      var draft = ScoreDraft(
        scale: Scale.fromKeySignature(
          const KeySignature(2),
        ), // D Major (F#, C#)
      );

      // Right-hand F#4 (66) + A4 (69) at beat 0.
      draft = draft.enterMidiChord(<MidiNote>{
        const MidiNote(66),
        const MidiNote(69),
      });
      expect(
        draft.cursor,
        EditorCursor(measureIndex: 0, beatOffset: RationalBeats(1)),
      );
      expect(
        draft.measures[0].notes
            .map((n) => (n.staffNote.pitchName, n.staffNote.clef))
            .toList(),
        <(String, Clef)>[('F#4', Clef.treble), ('A4', Clef.treble)],
      );

      // Step back to beat 0 and enter Bass D3 (50) only -> treble F#4 + A4 stay intact!
      draft = draft.moveCursorPrev().enterMidiChord(<MidiNote>{
        const MidiNote(50),
      });
      expect(draft.measures[0].notes, hasLength(3));
      expect(
        draft.measures[0].notes
            .where((n) => n.staffNote.clef == Clef.bass)
            .single
            .staffNote
            .pitchName,
        'D3',
      );

      // Move to beat 3 and enter half note (2 beats) -> splits across barline into measure 1!
      draft = draft
          .copyWith(
            cursor: EditorCursor(measureIndex: 0, beatOffset: RationalBeats(3)),
          )
          .setBaseDuration(NoteBaseDuration.half)
          .enterMidiChord(<MidiNote>{const MidiNote(62)});
      expect(
        draft.measures[0].notes
            .where((n) => n.beatOffset == RationalBeats(3))
            .single
            .tie,
        TieType.start,
      );
      expect(
        draft.measures[1].notes.where((n) => n.beatOffset.isZero).single.tie,
        TieType.stop,
      );
      expect(
        draft.cursor,
        EditorCursor(measureIndex: 1, beatOffset: RationalBeats(1)),
      );

      // Landing at end of final measure auto-appends 1 empty measure.
      final atLastBar = draft
          .copyWith(
            cursor: EditorCursor(measureIndex: draft.measures.length - 1),
          )
          .setBaseDuration(NoteBaseDuration.whole)
          .enterMidiChord(<MidiNote>{const MidiNote(64)});
      expect(atLastBar.measures, hasLength(5));
      expect(atLastBar.cursor, const EditorCursor(measureIndex: 4));
    });

    test('supports ClefAssignmentMode trebleOnly and bassOnly', () {
      final trebleOnly = ScoreDraft(clefMode: ClefAssignmentMode.trebleOnly)
          .enterMidiChord(<MidiNote>{const MidiNote(48)});
      expect(trebleOnly.measures[0].notes.single.staffNote.clef, Clef.treble);

      final bassOnly = ScoreDraft(clefMode: ClefAssignmentMode.bassOnly)
          .enterMidiChord(<MidiNote>{const MidiNote(72)});
      expect(bassOnly.measures[0].notes.single.staffNote.clef, Clef.bass);
    });

    test('supports setBaseDuration/toggleDot re-timing, insertRest, insertEmptySlice, deleteAtCursor, toggleTieAtCursor', () {
      var draft = ScoreDraft()
          .enterMidiChord(<MidiNote>{const MidiNote(60)})
          .moveCursorPrev()
          .setBaseDuration(NoteBaseDuration.half)
          .toggleDot();
      expect(
        draft.selectedDuration,
        DurationValue(base: NoteBaseDuration.half, dots: 1),
      );
      expect(
        draft.measures[0].notes.single.duration.quarterBeats,
        RationalBeats(3),
      );

      // insertEmptySlice shifts beat 0 note right by selected duration (reset to quarter first on empty beat).
      draft = draft
          .copyWith(
            selectedDuration: DurationValue(base: NoteBaseDuration.quarter),
            cursor: const EditorCursor(measureIndex: 0),
          )
          .insertEmptySlice();
      expect(draft.measures[0].notes.single.beatOffset, RationalBeats(1));

      // Navigate to beat 1, deleteAtCursor removes it cleanly.
      draft = draft.moveCursorNext().deleteAtCursor();
      expect(draft.measures[0].notes, isEmpty);

      // Two consecutive C4s tied and untied via toggleTieAtCursor.
      draft = draft
          .copyWith(cursor: const EditorCursor(measureIndex: 0))
          .enterMidiChord(<MidiNote>{const MidiNote(60)})
          .enterMidiChord(<MidiNote>{const MidiNote(60)})
          .moveCursorPrev()
          .moveCursorPrev()
          .toggleTieAtCursor();
      expect(draft.measures[0].notes[0].tie, TieType.start);
      expect(draft.measures[0].notes[1].tie, TieType.stop);

      draft = draft.toggleTieAtCursor();
      expect(draft.measures[0].notes[0].tie, TieType.none);
      expect(draft.measures[0].notes[1].tie, TieType.none);

      // insertRest clears beat 0 and advances to beat 1.
      draft = draft.insertRest();
      expect(draft.measures[0].notes, hasLength(1));
      expect(draft.measures[0].notes.single.beatOffset, RationalBeats(1));
      expect(draft.cursor.beatOffset, RationalBeats(1));
    });

    test('addMeasure, deleteCurrentMeasure keeps >=1 measure, and updateSetup/clearScore work', () {
      var draft = ScoreDraft().addMeasure();
      expect(draft.measures, hasLength(5));
      expect(draft.cursor.measureIndex, 4);

      draft = draft.deleteCurrentMeasure();
      expect(draft.measures, hasLength(4));

      // Deleting down to 1 bar keeps 1 bar and clears notes.
      for (var i = 0; i < 4; i += 1) {
        draft = draft.deleteCurrentMeasure();
      }
      expect(draft.measures, hasLength(1));

      // updateSetup clamps notes outside new 3/4 meter.
      draft = draft
          .copyWith(
            cursor: EditorCursor(measureIndex: 0, beatOffset: RationalBeats(3)),
          )
          .enterMidiChord(<MidiNote>{const MidiNote(60)})
          .updateSetup(
            scale: Scale.fromKeySignature(const KeySignature(-2)),
            timeSignature: TimeSignature(3, 4),
            splitPointMidi: 55,
            clefMode: ClefAssignmentMode.trebleOnly,
          );
      expect(draft.measures[0].notes, isEmpty);
      expect(draft.scale.keySignature.fifths, -2);
      expect(draft.splitPointMidi, 55);
      expect(draft.clefMode, ClefAssignmentMode.trebleOnly);

      final cleared = draft.clearScore();
      expect(cleared.measures, hasLength(4));
      expect(cleared.cursor, const EditorCursor(measureIndex: 0));
    });
  });

  group('ScoreDraftMutations touch pitch editing', () {
    test('addTouchNote, stepNotePitch, setNoteAccidental, and flipNoteClef work cleanly', () {
      // Rest slice -> places C4 on treble (or C3 on bassOnly), then stacks a diatonic 3rd (E4 / F#4).
      var draft = ScoreDraft(
        scale: Scale.fromKeySignature(const KeySignature(1)), // G Major (F#)
      ).addTouchNote();
      expect(draft.notesAtCursor.single.staffNote.pitchName, 'C4');

      draft = draft.addTouchNote();
      expect(
        draft.notesAtCursor.map((n) => n.staffNote.pitchName).toList(),
        <String>['C4', 'E4'],
      );

      // Step E4 -> F#4 (diatonic in G Major), then apply natural, then reset to key default.
      draft = draft.stepNotePitch(1, 1);
      expect(draft.notesAtCursor[1].staffNote.pitchName, 'F#4');

      draft = draft.setNoteAccidental(1, Accidental.natural);
      expect(draft.notesAtCursor[1].staffNote.pitchName, 'F4');
      expect(draft.notesAtCursor[1].explicitAccidental, Accidental.natural);

      draft = draft.setNoteAccidental(1, null);
      expect(draft.notesAtCursor[1].staffNote.pitchName, 'F#4');
      expect(draft.notesAtCursor[1].explicitAccidental, isNull);

      // Flip C4 to bass clef.
      draft = draft.flipNoteClef(0);
      expect(
        draft.notesAtCursor
            .where((n) => n.staffNote.clef == Clef.bass)
            .single
            .staffNote
            .pitchName,
        'C4',
      );
    });
  });
}
