import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/domain/measure_loop_range.dart';
import 'package:piano_exercises/features/piece_practice/domain/score_practice_navigator.dart';
import 'package:piano_exercises/shared/music/music.dart';

ScoreNote _note(
  DiatonicNote pitch,
  int octave,
  Clef clef, {
  TieType tie = TieType.none,
}) {
  return ScoreNote(
    staffNote: StaffNote(note: pitch, octave: octave, clef: clef),
    duration: DurationValue(base: NoteBaseDuration.quarter),
    tie: tie,
  );
}

ScoreSlice _slice({
  required int index,
  required int measureNumber,
  List<ScoreNote> treble = const <ScoreNote>[],
  List<ScoreNote> bass = const <ScoreNote>[],
}) {
  return ScoreSlice(
    sliceIndex: index,
    measureNumber: measureNumber,
    beatOffset: const RationalBeats.zero(),
    beatDuration: RationalBeats(1),
    trebleNotes: treble,
    bassNotes: bass,
    trebleRest: treble.isEmpty
        ? RestEvent(
            clef: Clef.treble,
            duration: DurationValue(base: NoteBaseDuration.quarter),
          )
        : null,
    bassRest: bass.isEmpty
        ? RestEvent(
            clef: Clef.bass,
            duration: DurationValue(base: NoteBaseDuration.quarter),
          )
        : null,
  );
}

void main() {
  group('MeasureLoopRange', () {
    test('contains, clamps, and formats written measure numbers', () {
      const range = MeasureLoopRange(startMeasureIndex: 1, endMeasureIndex: 3);
      expect(range.containsMeasureIndex(0), isFalse);
      expect(range.containsMeasureIndex(1), isTrue);
      expect(range.containsMeasureIndex(3), isTrue);
      expect(range.containsMeasureIndex(4), isFalse);

      expect(range.clampToMeasureCount(0), isNull);
      expect(
        range.clampToMeasureCount(2),
        const MeasureLoopRange(startMeasureIndex: 1, endMeasureIndex: 1),
      );
      expect(
        const MeasureLoopRange(
          startMeasureIndex: 4,
          endMeasureIndex: 6,
        ).clampToMeasureCount(2),
        const MeasureLoopRange(startMeasureIndex: 1, endMeasureIndex: 1),
      );

      final measures = <ScoreMeasure>[
        ScoreMeasure(measureNumber: 0, slices: const <ScoreSlice>[]),
        ScoreMeasure(measureNumber: 1, slices: const <ScoreSlice>[]),
        ScoreMeasure(measureNumber: 2, slices: const <ScoreSlice>[]),
        ScoreMeasure(measureNumber: 3, slices: const <ScoreSlice>[]),
      ];
      expect(range.formatLabel(measures), 'Loop M.1\u20133');
      expect(
        const MeasureLoopRange(
          startMeasureIndex: 0,
          endMeasureIndex: 0,
        ).formatLabel(measures),
        'Loop M.1',
      );
    });
  });

  group('ScorePracticeNavigator', () {
    // 4 measures:
    // M0 (pickup): slice 0 rest-only
    // M1: slice 1 treble C4 (tie start), slice 2 treble C4 (tie stop) + bass C3
    // M2: slice 3 treble D4, slice 4 rest-only
    // M3: slice 5 rest-only
    final score = Score(
      title: 'Navigator Test',
      scale: Scale.fromKeySignature(KeySignature.cMajor),
      timeSignature: TimeSignature.common,
      measures: <ScoreMeasure>[
        ScoreMeasure(
          measureNumber: 0,
          slices: <ScoreSlice>[_slice(index: 0, measureNumber: 0)],
        ),
        ScoreMeasure(
          measureNumber: 1,
          keySignature: const KeySignature(1), // G major starting at M1
          slices: <ScoreSlice>[
            _slice(
              index: 1,
              measureNumber: 1,
              treble: <ScoreNote>[
                _note(DiatonicNote.c, 4, Clef.treble, tie: TieType.start),
              ],
            ),
            _slice(
              index: 2,
              measureNumber: 1,
              treble: <ScoreNote>[
                _note(DiatonicNote.c, 4, Clef.treble, tie: TieType.stop),
              ],
              bass: <ScoreNote>[_note(DiatonicNote.c, 3, Clef.bass)],
            ),
          ],
        ),
        ScoreMeasure(
          measureNumber: 2,
          slices: <ScoreSlice>[
            _slice(
              index: 3,
              measureNumber: 2,
              treble: <ScoreNote>[_note(DiatonicNote.d, 4, Clef.treble)],
            ),
            _slice(index: 4, measureNumber: 2),
          ],
        ),
        ScoreMeasure(
          measureNumber: 3,
          slices: <ScoreSlice>[_slice(index: 5, measureNumber: 3)],
        ),
      ],
    );

    test('skips rests, inactive-hand slices, and tie continuations', () {
      expect(
        ScorePracticeNavigator.firstPlayableOrdinal(score, HandMode.both),
        1,
      );
      expect(
        ScorePracticeNavigator.lastPlayableOrdinal(score, HandMode.both),
        3,
      );
      expect(
        ScorePracticeNavigator.nextPlayableOrdinal(score, 1, HandMode.both),
        2,
      );
      expect(
        ScorePracticeNavigator.nextPlayableOrdinal(score, 3, HandMode.both),
        isNull,
      );

      // Right hand skips slice 2 because treble C4 is TieType.stop.
      expect(
        ScorePracticeNavigator.firstPlayableOrdinal(score, HandMode.right),
        1,
      );
      expect(
        ScorePracticeNavigator.nextPlayableOrdinal(score, 1, HandMode.right),
        3,
      );
      expect(
        ScorePracticeNavigator.previousPlayableOrdinal(
          score,
          3,
          HandMode.right,
        ),
        1,
      );

      // Left hand only plays slice 2.
      expect(
        ScorePracticeNavigator.firstPlayableOrdinal(score, HandMode.left),
        2,
      );
      expect(
        ScorePracticeNavigator.lastPlayableOrdinal(score, HandMode.left),
        2,
      );
      expect(
        ScorePracticeNavigator.nearestPlayableOrdinalAtOrAfter(
          score,
          3,
          HandMode.left,
        ),
        2,
      );
    });

    test(
      'bounds searches to MeasureLoopRange and resolves measure index & key',
      () {
        const m0Only = MeasureLoopRange(
          startMeasureIndex: 0,
          endMeasureIndex: 0,
        );
        expect(
          ScorePracticeNavigator.firstPlayableOrdinal(
            score,
            HandMode.both,
            loopRange: m0Only,
          ),
          isNull,
        );

        const m1To2 = MeasureLoopRange(
          startMeasureIndex: 1,
          endMeasureIndex: 2,
        );
        expect(
          ScorePracticeNavigator.firstPlayableOrdinal(
            score,
            HandMode.right,
            loopRange: m1To2,
          ),
          1,
        );
        expect(
          ScorePracticeNavigator.lastPlayableOrdinal(
            score,
            HandMode.right,
            loopRange: m1To2,
          ),
          3,
        );
        expect(ScorePracticeNavigator.measureIndexOfSliceOrdinal(score, 0), 0);
        expect(ScorePracticeNavigator.measureIndexOfSliceOrdinal(score, 2), 1);
        expect(ScorePracticeNavigator.measureIndexOfSliceOrdinal(score, 4), 2);
        expect(
          ScorePracticeNavigator.activeKeySignatureAtSlice(score, 0),
          KeySignature.cMajor,
        );
        expect(
          ScorePracticeNavigator.activeKeySignatureAtSlice(score, 2),
          const KeySignature(1),
        );
      },
    );
  });
}
