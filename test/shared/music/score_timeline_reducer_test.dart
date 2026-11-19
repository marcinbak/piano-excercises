import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  final quarter = DurationValue(base: NoteBaseDuration.quarter);
  final half = DurationValue(base: NoteBaseDuration.half);

  group('ScoreTimelineReducer', () {
    test(
      'resolves key defaults, intra-measure carry-over, and barline resets',
      () {
        final score = ScoreTimelineReducer.reduce(
          title: 'Accidental Scoping',
          initialScale: Scale.fromKeySignature(const KeySignature(1)),
          initialTimeSignature: TimeSignature(4, 4),
          measures: <MeasureTimelineInput>[
            MeasureTimelineInput(
              measureNumber: 1,
              keySignature: const KeySignature(1),
              notes: <NoteTimelineInput>[
                // F#5 implied by G Major -> showAccidental == false.
                NoteTimelineInput(
                  clef: Clef.treble,
                  diatonicNote: DiatonicNote.f,
                  octave: 5,
                  explicitAlter: 1,
                  beatOffset: const RationalBeats.zero(),
                  duration: quarter,
                ),
                // Explicit C#4 in treble -> showAccidental == true.
                NoteTimelineInput(
                  clef: Clef.treble,
                  diatonicNote: DiatonicNote.c,
                  octave: 4,
                  explicitAlter: 1,
                  writtenAccidental: Accidental.sharp,
                  beatOffset: const RationalBeats.zero(),
                  duration: quarter,
                ),
                // C4 without alter later in same bar inherits C#4 (show == false).
                NoteTimelineInput(
                  clef: Clef.treble,
                  diatonicNote: DiatonicNote.c,
                  octave: 4,
                  beatOffset: RationalBeats(1),
                  duration: quarter,
                ),
                // C5 in treble does NOT inherit C#4 from octave 4.
                NoteTimelineInput(
                  clef: Clef.treble,
                  diatonicNote: DiatonicNote.c,
                  octave: 5,
                  beatOffset: RationalBeats(1),
                  duration: quarter,
                ),
                // C4 on bass staff does NOT inherit C#4 from treble staff.
                NoteTimelineInput(
                  clef: Clef.bass,
                  diatonicNote: DiatonicNote.c,
                  octave: 4,
                  beatOffset: RationalBeats(1),
                  duration: quarter,
                ),
              ],
            ),
            MeasureTimelineInput(
              measureNumber: 2,
              notes: <NoteTimelineInput>[
                // Barline resets C4 back to natural in G Major.
                NoteTimelineInput(
                  clef: Clef.treble,
                  diatonicNote: DiatonicNote.c,
                  octave: 4,
                  beatOffset: const RationalBeats.zero(),
                  duration: quarter,
                ),
              ],
            ),
          ],
        );

        expect(score.measures, hasLength(2));
        expect(score.slices, hasLength(3));

        final slice0 = score.slices[0];
        expect(slice0.trebleNotes[0].staffNote.pitchName, 'C#4');
        expect(slice0.trebleNotes[0].showAccidental, isTrue);
        expect(slice0.trebleNotes[1].staffNote.pitchName, 'F#5');
        expect(slice0.trebleNotes[1].showAccidental, isFalse);

        final slice1 = score.slices[1];
        expect(slice1.trebleNotes[0].staffNote.pitchName, 'C#4');
        expect(slice1.trebleNotes[0].showAccidental, isFalse);
        expect(slice1.trebleNotes[1].staffNote.pitchName, 'C5');
        expect(slice1.trebleNotes[1].showAccidental, isFalse);
        expect(slice1.bassNotes[0].staffNote.pitchName, 'C4');
        expect(slice1.bassNotes[0].showAccidental, isFalse);

        final slice2 = score.slices[2];
        expect(slice2.trebleNotes[0].staffNote.pitchName, 'C4');
        expect(slice2.trebleNotes[0].showAccidental, isFalse);
      },
    );

    test(
      'computes pickup beatDurations, multi-voice alignment, rests, and ties',
      () {
        final score = ScoreTimelineReducer.reduce(
          title: 'Pickup & Ties',
          initialTimeSignature: TimeSignature(3, 4),
          measures: <MeasureTimelineInput>[
            // Pickup bar of 1 quarter beat total.
            MeasureTimelineInput(
              measureNumber: 0,
              timeSignature: TimeSignature(3, 4),
              notes: <NoteTimelineInput>[
                NoteTimelineInput(
                  clef: Clef.treble,
                  diatonicNote: DiatonicNote.g,
                  octave: 4,
                  beatOffset: const RationalBeats.zero(),
                  duration: quarter,
                  tie: TieType.start,
                ),
              ],
            ),
            MeasureTimelineInput(
              measureNumber: 1,
              notes: <NoteTimelineInput>[
                NoteTimelineInput(
                  clef: Clef.treble,
                  diatonicNote: DiatonicNote.g,
                  octave: 4,
                  beatOffset: const RationalBeats.zero(),
                  duration: half,
                  tie: TieType.stop,
                ),
                NoteTimelineInput(
                  clef: Clef.bass,
                  diatonicNote: DiatonicNote.c,
                  octave: 3,
                  beatOffset: RationalBeats(1),
                  duration: quarter,
                  voice: 2,
                ),
              ],
              rests: <RestTimelineInput>[
                // Suppressed on treble because treble has a note at offset 0.
                RestTimelineInput(
                  clef: Clef.treble,
                  beatOffset: const RationalBeats.zero(),
                  duration: quarter,
                ),
                // Attached to slice at offset 0 on bass.
                RestTimelineInput(
                  clef: Clef.bass,
                  beatOffset: const RationalBeats.zero(),
                  duration: quarter,
                  voice: 2,
                ),
                // Rest-only slice at offset 2.
                RestTimelineInput(
                  clef: Clef.treble,
                  beatOffset: RationalBeats(2),
                  duration: quarter,
                ),
                RestTimelineInput(
                  clef: Clef.bass,
                  beatOffset: RationalBeats(2),
                  duration: quarter,
                  voice: 2,
                ),
              ],
            ),
          ],
        );

        expect(score.slices, hasLength(4));
        // Pickup slice ends at 1 beat rather than 3.
        expect(score.slices[0].beatDuration, RationalBeats(1));
        expect(score.slices[0].requiresAnyAttack, isTrue);

        // Slice 1: tied-stop G4 on treble (requiresAttack == false), bass rest.
        final s1 = score.slices[1];
        expect(s1.beatDuration, RationalBeats(1));
        expect(s1.trebleNotes.single.requiresAttack, isFalse);
        expect(s1.requiredTrebleNotes, isEmpty);
        expect(s1.trebleRest, isNull);
        expect(s1.bassRest, isNotNull);
        expect(s1.requiresAnyAttack, isFalse);

        // Slice 2: bass C3 enters on beat 2.
        final s2 = score.slices[2];
        expect(s2.beatOffset, RationalBeats(1));
        expect(s2.beatDuration, RationalBeats(1));
        expect(s2.requiredBassNotes, hasLength(1));
        expect(s2.requiresAnyAttack, isTrue);

        // Slice 3: rest-only on beat 3.
        final s3 = score.slices[3];
        expect(s3.isRestOnly, isTrue);
        expect(s3.trebleRest, isNotNull);
        expect(s3.bassRest, isNotNull);
        expect(s3.requiresAnyAttack, isFalse);
      },
    );
  });
}
