import 'package:flutter_test/flutter_test.dart';
import 'package:smufl_notation/smufl_notation.dart';

import '../example/spike_fixtures.dart';

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
  group('ScoreLayoutEngine wrapping & geometry', () {
    test('wraps into more systems at 320px than at 900px', () {
      final poly = SpikeFixtures.polyphonicGrandStaff;
      final narrow = ScoreLayoutEngine.layout(score: poly, availableWidth: 320);
      final wide = ScoreLayoutEngine.layout(score: poly, availableWidth: 900);
      expect(narrow.systems.length, greaterThan(wide.systems.length));
      expect(narrow.totalSize.height, greaterThan(wide.totalSize.height));
    });

    test('provides O(1) sliceRect and sliceAtOffset hit lookup', () {
      final simplified = SpikeFixtures.simplifiedMelodyBass;
      final layout = ScoreLayoutEngine.layout(
        score: simplified,
        availableWidth: 640,
      );
      final totalSlices = simplified.measures.expand((m) => m.slices).length;
      for (var i = 0; i < totalSlices; i += 1) {
        final rect = layout.sliceRect(i);
        expect(rect, isNotNull);
        expect(rect!.width, greaterThan(0));
        expect(rect.height, greaterThan(0));
        expect(layout.sliceAtOffset(rect.center), i);
      }
      expect(layout.sliceRect(9999), isNull);
      expect(layout.sliceAtOffset(const Offset(-10, -10)), isNull);
    });

    test('handles degenerate widths (0px, 120px, negative, NaN) safely', () {
      final simplified = SpikeFixtures.simplifiedMelodyBass;
      for (final w in <double>[0, 120, -40, double.nan]) {
        final layout = ScoreLayoutEngine.layout(
          score: simplified,
          availableWidth: w,
        );
        expect(layout.totalSize.width.isFinite, isTrue);
        expect(layout.totalSize.height.isFinite, isTrue);
        expect(layout.totalSize.width, greaterThan(0));
        expect(layout.totalSize.height, greaterThan(0));
        for (final sys in layout.systems) {
          expect(sys.rightX, greaterThan(sys.leftX));
          expect(sys.bottomY, greaterThan(sys.topY));
          for (final m in sys.measures) {
            expect(m.rightX, greaterThan(m.leftX));
            for (final s in m.slices) {
              expect(s.cursorRect.width, greaterThan(0));
              expect(s.cursorRect.height, greaterThan(0));
            }
          }
        }
      }
    });
  });

  group('ScoreLayoutEngine key signatures, beams & ties', () {
    test('places exact key-signature accidental counts across -7..+7', () {
      for (var fifths = -7; fifths <= 7; fifths += 1) {
        final score = NotationScore(
          title: 'Key $fifths',
          measures: <NotationMeasure>[
            NotationMeasure(
              measureNumber: 1,
              keyFifths: fifths,
              beats: 4,
              beatType: 4,
              slices: <NotationSlice>[
                NotationSlice(
                  sliceIndex: 0,
                  beatDuration: 4.0,
                  trebleChord: _chord(SmuflClef.treble, DurationKind.whole, [
                    2,
                  ]),
                ),
              ],
            ),
          ],
        );
        final layout = ScoreLayoutEngine.layout(
          score: score,
          availableWidth: 420,
        );
        expect(
          layout.systems.first.measures.first.keyAccidentals.length,
          fifths.abs() * 2,
        );
      }
    });

    test('groups beamed runs and preserves flags on isolated 8ths', () {
      final score = NotationScore(
        title: 'Beams',
        measures: <NotationMeasure>[
          NotationMeasure(
            measureNumber: 1,
            slices: <NotationSlice>[
              NotationSlice(
                sliceIndex: 0,
                beatDuration: 0.5,
                trebleChord: _chord(SmuflClef.treble, DurationKind.eighth, [
                  1,
                ], beam: 'g1'),
              ),
              NotationSlice(
                sliceIndex: 1,
                beatDuration: 0.5,
                trebleChord: _chord(SmuflClef.treble, DurationKind.eighth, [
                  5,
                ], beam: 'g1'),
              ),
              NotationSlice(
                sliceIndex: 2,
                beatDuration: 0.5,
                trebleChord: _chord(SmuflClef.treble, DurationKind.eighth, [2]),
              ),
            ],
          ),
        ],
      );
      final m = ScoreLayoutEngine.layout(
        score: score,
        availableWidth: 500,
      ).systems.first.measures.first;
      expect(m.beamGroups.length, 1);
      expect(m.beamGroups.single.chords.length, 2);
      expect(m.slices[0].trebleChord!.flagCount, 0);
      expect(m.slices[1].trebleChord!.flagCount, 0);
      expect(m.slices[2].trebleChord!.flagCount, 1);
    });

    test('emits cross-system half-ties when tied measures wrap', () {
      final poly = SpikeFixtures.polyphonicGrandStaff;
      final layout = ScoreLayoutEngine.layout(score: poly, availableWidth: 340);
      expect(layout.systems.length, greaterThan(2));
      final totalTies = layout.systems
          .expand((s) => s.measures)
          .expand((m) => m.tieArcs)
          .length;
      expect(totalTies, greaterThan(10));
    });
  });

  group('N6 layout regressions', () {
    test(
      's1: guards slice centerX when skewed beatDuration compresses slices',
      () {
        final slices = <NotationSlice>[
          NotationSlice(
            sliceIndex: 0,
            beatDuration: 1e6,
            trebleChord: _chord(SmuflClef.treble, DurationKind.whole, [2]),
          ),
          for (var i = 1; i <= 20; i += 1)
            NotationSlice(
              sliceIndex: i,
              beatDuration: 0.25,
              trebleChord: _chord(SmuflClef.treble, DurationKind.sixteenth, [
                4,
              ]),
            ),
        ];
        final score = NotationScore(
          title: 'Skewed',
          measures: [NotationMeasure(measureNumber: 1, slices: slices)],
        );
        final layout = ScoreLayoutEngine.layout(
          score: score,
          availableWidth: 120,
        );
        for (final s in layout.systems.single.measures.single.slices) {
          expect(s.centerX.isFinite, isTrue);
          expect(s.cursorRect.width, greaterThan(0));
        }
      },
    );

    test('n1: beams bass 8ths across intervening treble 16th subdivisions', () {
      final score = NotationScore(
        title: 'Cross-staff beam',
        measures: [
          NotationMeasure(
            measureNumber: 1,
            slices: [
              NotationSlice(
                sliceIndex: 0,
                beatDuration: 0.25,
                trebleChord: _chord(SmuflClef.treble, DurationKind.sixteenth, [
                  4,
                ], beam: 't'),
                bassChord: _chord(SmuflClef.bass, DurationKind.eighth, [
                  2,
                ], beam: 'b'),
              ),
              NotationSlice(
                sliceIndex: 1,
                beatDuration: 0.25,
                trebleChord: _chord(SmuflClef.treble, DurationKind.sixteenth, [
                  5,
                ], beam: 't'),
              ),
              NotationSlice(
                sliceIndex: 2,
                beatDuration: 0.25,
                trebleChord: _chord(SmuflClef.treble, DurationKind.sixteenth, [
                  6,
                ], beam: 't'),
                bassChord: _chord(SmuflClef.bass, DurationKind.eighth, [
                  4,
                ], beam: 'b'),
              ),
              NotationSlice(
                sliceIndex: 3,
                beatDuration: 0.25,
                trebleChord: _chord(SmuflClef.treble, DurationKind.sixteenth, [
                  7,
                ], beam: 't'),
              ),
            ],
          ),
        ],
      );
      final m = ScoreLayoutEngine.layout(
        score: score,
        availableWidth: 500,
      ).systems.single.measures.single;
      final bassBeams = m.beamGroups.where((g) => g.clef == SmuflClef.bass);
      expect(bassBeams.length, 1);
      expect(bassBeams.single.chords.length, 2);
      expect(m.slices[0].bassChord!.flagCount, 0);
      expect(m.slices[2].bassChord!.flagCount, 0);
    });
  });
}
