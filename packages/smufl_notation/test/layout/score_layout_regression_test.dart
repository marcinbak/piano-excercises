import 'package:flutter_test/flutter_test.dart';
import 'package:smufl_notation/smufl_notation.dart';

NotationChord _chord(
  SmuflClef clef,
  DurationKind d,
  List<int> steps, {
  int dots = 0,
  String? beam,
}) => NotationChord(
  notes: [for (final s in steps) NotationNote(staffStep: s, clef: clef)],
  clef: clef,
  duration: d,
  dots: dots,
  beamGroupId: beam,
);

void main() {
  group('N6 layout regressions (style, dots, rests)', () {
    test('n1: explicit rest on clef terminates beam group', () {
      final score = NotationScore(
        title: 'Rest breaks beam',
        measures: [
          NotationMeasure(
            measureNumber: 1,
            slices: [
              NotationSlice(
                sliceIndex: 0,
                beatDuration: 0.5,
                bassChord: _chord(SmuflClef.bass, DurationKind.eighth, [
                  2,
                ], beam: 'b'),
              ),
              NotationSlice(
                sliceIndex: 1,
                beatDuration: 0.5,
                bassRest: NotationRest(
                  clef: SmuflClef.bass,
                  duration: DurationKind.eighth,
                ),
              ),
              NotationSlice(
                sliceIndex: 2,
                beatDuration: 0.5,
                bassChord: _chord(SmuflClef.bass, DurationKind.eighth, [
                  4,
                ], beam: 'b'),
              ),
            ],
          ),
        ],
      );
      final m = ScoreLayoutEngine.layout(
        score: score,
        availableWidth: 500,
      ).systems.single.measures.single;
      expect(m.beamGroups, isEmpty);
      expect(m.slices[0].bassChord!.flagCount, 1);
      expect(m.slices[2].bassChord!.flagCount, 1);
    });

    test('n4/n5/n6: clamps staffSpace, clears whole seconds, splits dotted second dots', () {
      final score = NotationScore(
        title: 'Dots & Style',
        measures: [
          NotationMeasure(
            measureNumber: 1,
            slices: [
              NotationSlice(
                sliceIndex: 0,
                beatDuration: 6.0,
                trebleChord: _chord(SmuflClef.treble, DurationKind.whole, [
                  -2,
                  -1,
                ], dots: 1),
              ),
              NotationSlice(
                sliceIndex: 1,
                beatDuration: 1.5,
                trebleChord: _chord(SmuflClef.treble, DurationKind.quarter, [
                  0,
                  1,
                ], dots: 1),
              ),
            ],
          ),
        ],
      );
      final layout = ScoreLayoutEngine.layout(
        score: score,
        availableWidth: 500,
        style: const ScoreStyle(staffSpace: 2.0),
      );
      expect(layout.style.staffSpace, 4.0);
      expect(layout.style.fontSize, 16.0);
      final slices = layout.systems.single.measures.single.slices;
      final wholeHeads = slices[0].trebleChord!.noteheads;
      expect(
        wholeHeads[1].dotStartX!,
        greaterThan(
          wholeHeads[1].centerX + (SmuflGlyphs.wholeNoteheadWidthSpaces * 2.0),
        ),
      );
      final qHeads = slices[1].trebleChord!.noteheads;
      expect(qHeads[0].dotY, isNot(equals(qHeads[1].dotY)));
    });
  });
}
