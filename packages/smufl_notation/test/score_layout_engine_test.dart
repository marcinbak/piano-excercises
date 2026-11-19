import 'package:flutter_test/flutter_test.dart';
import 'package:smufl_notation/smufl_notation.dart';

import '../example/spike_fixtures.dart';

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
                  trebleChord: NotationChord(
                    notes: [NotationNote(staffStep: 2, clef: SmuflClef.treble)],
                    clef: SmuflClef.treble,
                    duration: DurationKind.whole,
                  ),
                ),
              ],
            ),
          ],
        );
        final layout = ScoreLayoutEngine.layout(
          score: score,
          availableWidth: 420,
        );
        final m = layout.systems.first.measures.first;
        expect(m.keyAccidentals.length, fifths.abs() * 2);
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
                trebleChord: NotationChord(
                  notes: [NotationNote(staffStep: 1, clef: SmuflClef.treble)],
                  clef: SmuflClef.treble,
                  duration: DurationKind.eighth,
                  beamGroupId: 'g1',
                ),
              ),
              NotationSlice(
                sliceIndex: 1,
                beatDuration: 0.5,
                trebleChord: NotationChord(
                  notes: [NotationNote(staffStep: 5, clef: SmuflClef.treble)],
                  clef: SmuflClef.treble,
                  duration: DurationKind.eighth,
                  beamGroupId: 'g1',
                ),
              ),
              NotationSlice(
                sliceIndex: 2,
                beatDuration: 0.5,
                trebleChord: NotationChord(
                  notes: [NotationNote(staffStep: 2, clef: SmuflClef.treble)],
                  clef: SmuflClef.treble,
                  duration: DurationKind.eighth,
                ),
              ),
            ],
          ),
        ],
      );
      final layout = ScoreLayoutEngine.layout(
        score: score,
        availableWidth: 500,
      );
      final m = layout.systems.first.measures.first;
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
}
