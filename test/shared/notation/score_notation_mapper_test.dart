import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:piano_exercises/shared/notation/notation.dart';

void main() {
  test('ScoreNotationMapper.activeKeySignatureAtSlice tracks mid-score key changes', () {
    final quarter = DurationValue(base: NoteBaseDuration.quarter);
    final score = Score(
      title: 'Modulating',
      scale: Scale.fromKeySignature(const KeySignature(1)),
      timeSignature: TimeSignature.common,
      measures: <ScoreMeasure>[
        ScoreMeasure(
          measureNumber: 1,
          slices: <ScoreSlice>[
            ScoreSlice(
              sliceIndex: 0,
              measureNumber: 1,
              beatOffset: const RationalBeats.zero(),
              beatDuration: RationalBeats(1),
              trebleRest: RestEvent(clef: Clef.treble, duration: quarter),
            ),
          ],
        ),
        ScoreMeasure(
          measureNumber: 2,
          keySignature: const KeySignature(-2),
          slices: <ScoreSlice>[
            ScoreSlice(
              sliceIndex: 1,
              measureNumber: 2,
              beatOffset: const RationalBeats.zero(),
              beatDuration: RationalBeats(1),
              trebleRest: RestEvent(clef: Clef.treble, duration: quarter),
            ),
          ],
        ),
      ],
    );

    expect(
      ScoreNotationMapper.activeKeySignatureAtSlice(score, 0),
      const KeySignature(1),
    );
    expect(
      ScoreNotationMapper.activeKeySignatureAtSlice(score, 1),
      const KeySignature(-2),
    );
  });
}
