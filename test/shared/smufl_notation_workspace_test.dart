import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smufl_notation/smufl_notation.dart';

void main() {
  test('workspace package resolves and pubspec ships zero score assets', () {
    final score = NotationScore(
      title: 'Workspace Check',
      measures: <NotationMeasure>[
        NotationMeasure(
          measureNumber: 1,
          keyFifths: 0,
          beats: 4,
          beatType: 4,
          slices: <NotationSlice>[
            NotationSlice(
              sliceIndex: 0,
              beatDuration: 4.0,
              trebleChord: NotationChord(
                notes: <NotationNote>[
                  NotationNote(staffStep: -2, clef: SmuflClef.treble),
                ],
                clef: SmuflClef.treble,
                duration: DurationKind.whole,
              ),
            ),
          ],
        ),
      ],
    );

    final layout = ScoreLayoutEngine.layout(score: score, availableWidth: 400);
    expect(layout.systems.length, 1);
    expect(layout.sliceRect(0), isNotNull);

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('packages/smufl_notation'));
    expect(pubspec, contains('assets/fonts/Bravura-OFL.txt'));
    expect(pubspec, isNot(contains('.mxl')));
    expect(pubspec, isNot(contains('.musicxml')));
  });
}
