import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/piece_practice/piece_practice.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:smufl_notation/smufl_notation.dart';

void main() {
  group('ScoreNotationMapper', () {
    test('maps golden fixtures and lays out cleanly via ScoreLayoutEngine', () {
      const parser = MusicXmlScoreParser();
      for (final path in const <String>[
        'test/fixtures/simplified_melody_bass.musicxml',
        'test/fixtures/polyphonic_grand_staff.musicxml',
      ]) {
        final bytes = Uint8List.fromList(File(path).readAsBytesSync());
        final score = parser.parseBytes(bytes, fileName: path).score;
        final notation = ScoreNotationMapper.mapScore(score);
        expect(notation.measures.length, score.measures.length);
        final layout = ScoreLayoutEngine.layout(
          score: notation,
          availableWidth: 360,
        );
        expect(layout.systems, isNotEmpty);
        expect(layout.slicePlacement(score.slices.last.sliceIndex), isNotNull);
      }
    });

    test('falls back measure 0 key/time, maps pickup bars, accidentals, and mixed voices', () {
      final halfDur = DurationValue(base: NoteBaseDuration.half);
      final eighthDur = DurationValue(base: NoteBaseDuration.eighth);
      final quarterDur = DurationValue(base: NoteBaseDuration.quarter);

      final score = Score(
        title: 'Mixed Voices',
        artist: 'Composer',
        scale: Scale.fromKeySignature(const KeySignature(2)),
        timeSignature: TimeSignature(3, 4),
        measures: <ScoreMeasure>[
          ScoreMeasure(
            measureNumber: 0,
            slices: <ScoreSlice>[
              ScoreSlice(
                sliceIndex: 0,
                measureNumber: 0,
                beatOffset: const RationalBeats.zero(),
                beatDuration: RationalBeats(1, 2),
                trebleNotes: <ScoreNote>[
                  ScoreNote(
                    staffNote: const StaffNote(
                      note: DiatonicNote.a,
                      octave: 5,
                      clef: Clef.treble,
                    ),
                    duration: halfDur,
                    voice: 1,
                  ),
                  ScoreNote(
                    staffNote: const StaffNote(
                      note: DiatonicNote.f,
                      octave: 4,
                      clef: Clef.treble,
                      accidental: Accidental.sharp,
                    ),
                    duration: eighthDur,
                    showAccidental: false,
                    voice: 2,
                    beamGroupId: 'b1',
                  ),
                  ScoreNote(
                    staffNote: const StaffNote(
                      note: DiatonicNote.c,
                      octave: 5,
                      clef: Clef.treble,
                      accidental: Accidental.natural,
                    ),
                    duration: eighthDur,
                    showAccidental: true,
                    voice: 2,
                  ),
                ],
                bassRest: RestEvent(clef: Clef.bass, duration: quarterDur),
              ),
            ],
          ),
        ],
      );

      final notation = ScoreNotationMapper.mapScore(score);
      final m0 = notation.measures.single;
      expect(m0.measureNumber, 0);
      expect(m0.keyFifths, 2);
      expect(m0.beats, 3);
      expect(m0.beatType, 4);

      final chord = m0.slices.single.trebleChord!;
      expect(chord.duration, DurationKind.eighth);
      expect(chord.beamGroupId, 'b1');
      expect(chord.notes[0].staffStep, 1); // F#4
      expect(chord.notes[0].accidental, isNull);
      expect(chord.notes[0].showAccidental, isFalse);
      expect(chord.notes[0].noteheadDuration, isNull);
      expect(chord.notes[1].staffStep, 5); // C5 natural
      expect(chord.notes[1].accidental, SmuflAccidental.natural);
      expect(chord.notes[1].showAccidental, isTrue);
      expect(chord.notes[2].staffStep, 10); // A5 half
      expect(chord.notes[2].noteheadDuration, DurationKind.half);
      expect(m0.slices.single.bassRest!.duration, DurationKind.quarter);
    });

    test(
      'connects 3-measure cross-barline tie chains via deterministic noteId',
      () {
        final wholeDur = DurationValue(base: NoteBaseDuration.whole);
        ScoreMeasure tieMeasure(int num, int sliceIdx, TieType tie) =>
            ScoreMeasure(
              measureNumber: num,
              slices: <ScoreSlice>[
                ScoreSlice(
                  sliceIndex: sliceIdx,
                  measureNumber: num,
                  beatOffset: const RationalBeats.zero(),
                  beatDuration: RationalBeats(4),
                  trebleNotes: <ScoreNote>[
                    ScoreNote(
                      staffNote: const StaffNote(
                        note: DiatonicNote.g,
                        octave: 4,
                        clef: Clef.treble,
                      ),
                      duration: wholeDur,
                      tie: tie,
                    ),
                  ],
                ),
              ],
            );

        final score = Score(
          title: '3-Bar Tie',
          scale: Scale.fromKeySignature(KeySignature.cMajor),
          timeSignature: TimeSignature.common,
          measures: <ScoreMeasure>[
            tieMeasure(1, 0, TieType.start),
            tieMeasure(2, 1, TieType.continueTie),
            tieMeasure(3, 2, TieType.stop),
          ],
        );
        final notation = ScoreNotationMapper.mapScore(score);
        final layout = ScoreLayoutEngine.layout(
          score: notation,
          availableWidth: 900,
        );
        final ms = layout.systems.single.measures;
        expect(ms[0].tieArcs, isEmpty);
        expect(ms[1].tieArcs, hasLength(1));
        expect(ms[2].tieArcs, hasLength(1));
      },
    );

    test('maps HandMode and key-aware WrongNoteOverlay accidentals', () {
      expect(
        ScoreNotationMapper.mapHandMode(HandMode.both),
        NotationHandFilter.both,
      );
      expect(
        ScoreNotationMapper.mapHandMode(HandMode.right),
        NotationHandFilter.right,
      );
      expect(
        ScoreNotationMapper.mapHandMode(HandMode.left),
        NotationHandFilter.left,
      );

      const gMajor = KeySignature(1);
      final overlay = ScoreNotationMapper.mapWrongNotes(
        sliceIndex: 3,
        clef: SmuflClef.treble,
        wrongNotes: const <StaffNote>[
          // F5 natural against F# in G Major -> show natural!
          StaffNote(note: DiatonicNote.f, octave: 5, clef: Clef.treble),
          // F#5 matches key -> hide accidental!
          StaffNote(
            note: DiatonicNote.f,
            octave: 5,
            clef: Clef.treble,
            accidental: Accidental.sharp,
          ),
          // C#6 outside key -> show sharp!
          StaffNote(
            note: DiatonicNote.c,
            octave: 6,
            clef: Clef.treble,
            accidental: Accidental.sharp,
          ),
        ],
        activeKeySignature: gMajor,
      );
      expect(overlay.sliceIndex, 3);
      expect(overlay.notes, hasLength(3));
      expect(overlay.notes[0].accidental, SmuflAccidental.natural);
      expect(overlay.notes[0].showAccidental, isTrue);
      expect(overlay.notes[1].accidental, isNull);
      expect(overlay.notes[1].showAccidental, isFalse);
      expect(overlay.notes[2].accidental, SmuflAccidental.sharp);
      expect(overlay.notes[2].showAccidental, isTrue);
    });
  });
}
