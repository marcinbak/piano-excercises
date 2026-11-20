import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_mutations.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_tie_and_ripple_ops.dart';
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

  group('ScoreDraft tie healing and pickup bar regressions', () {
    test('writeSegmentedChord heals neighbor ties on full and partial overwrite', () {
      // Build C4 [2,4) (start) -> M1 [0,1) C4 (stop) via dotted half at beat 2.
      final draft =
          ScoreDraft(
            cursor: EditorCursor(measureIndex: 0, beatOffset: RationalBeats(2)),
          ).setBaseDuration(NoteBaseDuration.half).toggleDot().enterMidiChord(
            <MidiNote>{const MidiNote(60)},
          );
      expect(draft.measures[0].notes.single.tie, TieType.start);
      expect(draft.measures[1].notes.single.tie, TieType.stop);

      // Full overwrite of M0 [2,4) directly via enterMidiChord heals M1 [0,1) incoming tie.
      final fullOverwrite = draft
          .copyWith(
            cursor: EditorCursor(measureIndex: 0, beatOffset: RationalBeats(2)),
            selectedDuration: DurationValue(base: NoteBaseDuration.half),
          )
          .enterMidiChord(<MidiNote>{const MidiNote(62)});
      expect(fullOverwrite.measures[1].notes.single.tie, TieType.none);

      // Chain C4 [1,2) (start) -> C4 [2,4) (continueTie) -> M1 [0,1) C4 (stop).
      final chained = draft
          .copyWith(
            cursor: EditorCursor(measureIndex: 0, beatOffset: RationalBeats(1)),
            selectedDuration: DurationValue(base: NoteBaseDuration.quarter),
          )
          .enterMidiChord(<MidiNote>{const MidiNote(60)})
          .copyWith(
            cursor: EditorCursor(measureIndex: 0, beatOffset: RationalBeats(1)),
          )
          .toggleTieAtCursor();
      expect(chained.measures[0].notes[0].tie, TieType.start);
      expect(chained.measures[0].notes[1].tie, TieType.continueTie);
      expect(chained.measures[1].notes.single.tie, TieType.stop);

      // Partial overwrite at beat 3 trims [2,4) -> [2,3), preserving its incoming tie (stop)
      // while healing M1 [0,1) outgoing tie to none.
      final partial = chained
          .copyWith(
            cursor: EditorCursor(measureIndex: 0, beatOffset: RationalBeats(3)),
            selectedDuration: DurationValue(base: NoteBaseDuration.quarter),
          )
          .enterMidiChord(<MidiNote>{const MidiNote(62)});
      final m0C4Beat1 = partial.measures[0].notes.firstWhere(
        (n) => n.beatOffset == RationalBeats(1),
      );
      final m0C4Beat2 = partial.measures[0].notes.firstWhere(
        (n) => n.beatOffset == RationalBeats(2),
      );
      expect(m0C4Beat1.tie, TieType.start);
      expect(m0C4Beat2.duration.quarterBeats, RationalBeats(1));
      expect(m0C4Beat2.tie, TieType.stop);
      expect(partial.measures[1].notes.single.tie, TieType.none);
    });

    test('setNoteAccidental and flipNoteClef heal neighbor ties when pitch or clef changes', () {
      final base =
          ScoreDraft(
            cursor: EditorCursor(measureIndex: 0, beatOffset: RationalBeats(2)),
          ).setBaseDuration(NoteBaseDuration.half).toggleDot().enterMidiChord(
            <MidiNote>{const MidiNote(60)},
          );

      // Cautionary natural on already-natural C4 keeps tie intact.
      final samePitch = base
          .copyWith(cursor: const EditorCursor(measureIndex: 1))
          .setNoteAccidental(0, Accidental.natural);
      expect(samePitch.measures[0].notes.single.tie, TieType.start);
      expect(samePitch.measures[1].notes.single.tie, TieType.stop);

      // Accidental change to C#4 breaks and heals tie on predecessor.
      final sharpChanged = base
          .copyWith(cursor: const EditorCursor(measureIndex: 1))
          .setNoteAccidental(0, Accidental.sharp);
      expect(sharpChanged.measures[0].notes.single.tie, TieType.none);
      expect(sharpChanged.measures[1].notes.single.tie, TieType.none);
      expect(sharpChanged.measures[1].notes.single.staffNote.pitchName, 'C#4');

      // Flipping clef breaks and heals tie on predecessor.
      final clefFlipped = base
          .copyWith(cursor: const EditorCursor(measureIndex: 1))
          .flipNoteClef(0);
      expect(clefFlipped.measures[0].notes.single.tie, TieType.none);
      expect(clefFlipped.measures[1].notes.single.tie, TieType.none);
      expect(clefFlipped.measures[1].notes.single.staffNote.clef, Clef.bass);
    });

    test('updateSetup meter shrink heals dropped/trimmed ties and chains multi-part splits', () {
      // Case 1: M0 [3,4) (start) -> M1 [0,1) (stop) dropped on 4/4 -> 3/4.
      final beat3Tie =
          ScoreDraft(
                cursor: EditorCursor(
                  measureIndex: 0,
                  beatOffset: RationalBeats(3),
                ),
              )
              .setBaseDuration(NoteBaseDuration.half)
              .enterMidiChord(<MidiNote>{const MidiNote(60)})
              .updateSetup(timeSignature: TimeSignature(3, 4));
      expect(beat3Tie.measures[0].notes, isEmpty);
      expect(beat3Tie.measures[1].notes.single.tie, TieType.none);

      // Case 2: M0 [0, 0.5) (start) -> M0 [0.5, 4) (continueTie) -> M1 [0, 1) (stop)
      // shrinking 4/4 -> 3/4 trims [0.5, 4) to 2.5 beats ([half, eighth]) preserving
      // incoming tie from beat 0, chaining start->stop/continueTie->stop, and healing M1.
      const c4 = StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble);
      final chainedShrink = ScoreDraft(
        measures: <DraftMeasure>[
          DraftMeasure(
            measureNumber: 1,
            notes: <DraftNoteEvent>[
              DraftNoteEvent(
                staffNote: c4,
                beatOffset: const RationalBeats.zero(),
                duration: DurationValue(base: NoteBaseDuration.eighth),
                tie: TieType.start,
              ),
              DraftNoteEvent(
                staffNote: c4,
                beatOffset: RationalBeats(1, 2),
                duration: DurationValue(
                  base: NoteBaseDuration.half,
                  dots: 1,
                  quarterBeats: RationalBeats(7, 2),
                ),
                tie: TieType.continueTie,
              ),
            ],
          ),
          DraftMeasure(
            measureNumber: 2,
            notes: <DraftNoteEvent>[
              DraftNoteEvent(
                staffNote: c4,
                beatOffset: const RationalBeats.zero(),
                duration: DurationValue(base: NoteBaseDuration.quarter),
                tie: TieType.stop,
              ),
            ],
          ),
        ],
      ).updateSetup(timeSignature: TimeSignature(3, 4));

      expect(chainedShrink.measures[0].notes, hasLength(3));
      expect(chainedShrink.measures[0].notes[0].tie, TieType.start);
      expect(chainedShrink.measures[0].notes[1].tie, TieType.continueTie);
      expect(
        chainedShrink.measures[0].notes[1].duration.quarterBeats,
        RationalBeats(2),
      );
      expect(chainedShrink.measures[0].notes[2].tie, TieType.stop);
      expect(
        chainedShrink.measures[0].notes[2].duration.quarterBeats,
        RationalBeats(1, 2),
      );
      expect(chainedShrink.measures[1].notes.single.tie, TieType.none);
    });

    test('rippleInsertGap builds valid multi-part continueTie chains across barlines', () {
      // Whole note C4 at [0,4) shifted by 1.5 beats (dotted quarter):
      // inParts = [half (2), eighth (0.5)] at [1.5, 3.5) and [3.5, 4),
      // outParts = [dotted quarter (1.5)] at M1 [0, 1.5).
      final shifted = ScoreDraft()
          .setBaseDuration(NoteBaseDuration.whole)
          .enterMidiChord(<MidiNote>{const MidiNote(60)})
          .copyWith(
            cursor: const EditorCursor(measureIndex: 0),
            selectedDuration: DurationValue(
              base: NoteBaseDuration.quarter,
              dots: 1,
            ),
          )
          .insertEmptySlice();

      expect(shifted.measures[0].notes, hasLength(2));
      expect(shifted.measures[0].notes[0].tie, TieType.start);
      expect(
        shifted.measures[0].notes[0].duration.quarterBeats,
        RationalBeats(2),
      );
      expect(shifted.measures[0].notes[1].tie, TieType.continueTie);
      expect(
        shifted.measures[0].notes[1].duration.quarterBeats,
        RationalBeats(1, 2),
      );
      expect(shifted.measures[1].notes.single.tie, TieType.stop);
      expect(
        shifted.measures[1].notes.single.duration.quarterBeats,
        RationalBeats(3, 2),
      );

      // Verify 2 inParts + 2 outParts preserves both plain and double-tied boundaries.
      const c4 = StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble);
      final plainMeasures = rippleInsertGap(
        ScoreDraft(
          measures: <DraftMeasure>[
            DraftMeasure(
              measureNumber: 1,
              notes: <DraftNoteEvent>[
                DraftNoteEvent(
                  staffNote: c4,
                  beatOffset: const RationalBeats.zero(),
                  duration: DurationValue(base: NoteBaseDuration.whole),
                ),
              ],
            ),
          ],
        ),
        cursor: const EditorCursor(measureIndex: 0),
        delta: RationalBeats(5, 4),
      );
      expect(plainMeasures[0].notes.map((n) => n.tie).toList(), <TieType>[
        TieType.start,
        TieType.continueTie,
      ]);
      expect(plainMeasures[1].notes.map((n) => n.tie).toList(), <TieType>[
        TieType.continueTie,
        TieType.stop,
      ]);

      final doubleTiedMeasures = rippleInsertGap(
        ScoreDraft(
          measures: <DraftMeasure>[
            DraftMeasure(
              measureNumber: 1,
              notes: <DraftNoteEvent>[
                DraftNoteEvent(
                  staffNote: c4,
                  beatOffset: const RationalBeats.zero(),
                  duration: DurationValue(base: NoteBaseDuration.whole),
                  tie: TieType.continueTie,
                ),
              ],
            ),
          ],
        ),
        cursor: const EditorCursor(measureIndex: 0),
        delta: RationalBeats(5, 4),
      );
      expect(doubleTiedMeasures[0].notes.map((n) => n.tie).toList(), <TieType>[
        TieType.continueTie,
        TieType.continueTie,
      ]);
      expect(doubleTiedMeasures[1].notes.map((n) => n.tie).toList(), <TieType>[
        TieType.continueTie,
        TieType.continueTie,
      ]);
    });

    test('ScoreDraft.toScore preserves measureNumber == 0 pickup duration without full-bar rest padding', () {
      final quarter = DurationValue(base: NoteBaseDuration.quarter);
      final pickupScore = ScoreTimelineReducer.reduce(
        title: 'Anacrusis',
        initialScale: Scale.fromKeySignature(KeySignature.cMajor),
        initialTimeSignature: TimeSignature.common,
        measures: <MeasureTimelineInput>[
          MeasureTimelineInput(
            measureNumber: 0,
            notes: <NoteTimelineInput>[
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.g,
                octave: 4,
                explicitAlter: 0,
                beatOffset: const RationalBeats.zero(),
                duration: quarter,
              ),
            ],
            rests: <RestTimelineInput>[
              RestTimelineInput(
                clef: Clef.bass,
                beatOffset: const RationalBeats.zero(),
                duration: quarter,
              ),
            ],
          ),
          MeasureTimelineInput(
            measureNumber: 1,
            notes: <NoteTimelineInput>[
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.c,
                octave: 5,
                explicitAlter: 0,
                beatOffset: const RationalBeats.zero(),
                duration: DurationValue(base: NoteBaseDuration.whole),
              ),
            ],
          ),
        ],
      );

      final redraftedScore = ScoreDraft.fromScore(pickupScore).toScore();
      expect(redraftedScore.measures[0].measureNumber, 0);
      expect(redraftedScore.measures[0].slices, hasLength(1));
      expect(
        redraftedScore.measures[0].slices.single.beatDuration,
        RationalBeats(1),
      );

      final bytes = const MusicXmlScoreSerializer().serialize(redraftedScore);
      final reparsed = const MusicXmlScoreParser()
          .parseBytes(bytes, fileName: 'pickup.musicxml')
          .score;
      expect(reparsed.measures[0].measureNumber, 0);
      expect(reparsed.measures[0].slices, hasLength(1));
      expect(reparsed.measures[0].slices.single.beatDuration, RationalBeats(1));
    });
  });
}
