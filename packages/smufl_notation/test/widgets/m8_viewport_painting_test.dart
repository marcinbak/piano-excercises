import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smufl_notation/smufl_notation.dart';

import '../../example/spike_fixtures.dart';
import '../test_font_loader.dart';

class _DrawnLine {
  const _DrawnLine(this.p1, this.p2, this.color);

  final Offset p1;
  final Offset p2;
  final Color color;
}

class _LineRecordingCanvas implements Canvas {
  final List<_DrawnLine> lines = <_DrawnLine>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lines.add(_DrawnLine(p1, p2, paint.color));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(loadBravuraTestFont);

  group('M8 viewport & painting', () {
    test('NotationHandFilter maps active hand to dimmedClef', () {
      expect(NotationHandFilter.both.dimmedClef, isNull);
      expect(NotationHandFilter.right.dimmedClef, SmuflClef.bass);
      expect(NotationHandFilter.left.dimmedClef, SmuflClef.treble);
    });

    test(
      'dims ledger lines and paints 32nd/64th flags and beam levels 3..4',
      () {
        final score = NotationScore(
          title: 'Flags & Dimming',
          measures: [
            NotationMeasure(
              measureNumber: 1,
              slices: [
                NotationSlice(
                  sliceIndex: 0,
                  beatDuration: 0.125,
                  trebleChord: NotationChord(
                    notes: [
                      NotationNote(staffStep: -2, clef: SmuflClef.treble),
                    ],
                    clef: SmuflClef.treble,
                    duration: DurationKind.thirtySecond,
                  ),
                  bassChord: NotationChord(
                    notes: [NotationNote(staffStep: -2, clef: SmuflClef.bass)],
                    clef: SmuflClef.bass,
                    duration: DurationKind.sixtyFourth,
                  ),
                ),
                NotationSlice(
                  sliceIndex: 1,
                  beatDuration: 0.0625,
                  trebleChord: NotationChord(
                    notes: [NotationNote(staffStep: 2, clef: SmuflClef.treble)],
                    clef: SmuflClef.treble,
                    duration: DurationKind.sixtyFourth,
                    beamGroupId: 't64',
                  ),
                ),
                NotationSlice(
                  sliceIndex: 2,
                  beatDuration: 0.0625,
                  trebleChord: NotationChord(
                    notes: [NotationNote(staffStep: 4, clef: SmuflClef.treble)],
                    clef: SmuflClef.treble,
                    duration: DurationKind.sixtyFourth,
                    beamGroupId: 't64',
                  ),
                ),
              ],
            ),
          ],
        );
        const style = ScoreStyle(dimmedOpacity: 0.32);
        final layout = ScoreLayoutEngine.layout(
          score: score,
          availableWidth: 420,
          style: style,
        );
        final canvas = _LineRecordingCanvas();
        final painter = GrandStaffScorePainter(
          layout: layout,
          activeHand: NotationHandFilter.right,
        );
        painter.paint(canvas, layout.totalSize);

        final sys = layout.systems.single;
        final trebleLedgerY = sys.yForStep(SmuflClef.treble, -2);
        final bassLedgerY = sys.yForStep(SmuflClef.bass, -2);
        final trebleLedger = canvas.lines.firstWhere(
          (l) =>
              (l.p1.dy - trebleLedgerY).abs() < 1e-4 &&
              (l.p2.dx - l.p1.dx) < 30,
        );
        final bassLedger = canvas.lines.firstWhere(
          (l) =>
              (l.p1.dy - bassLedgerY).abs() < 1e-4 && (l.p2.dx - l.p1.dx) < 30,
        );
        expect(trebleLedger.color.a, closeTo(style.staffLineColor.a, 1e-3));
        expect(
          bassLedger.color.a,
          closeTo(style.staffLineColor.a * 0.32, 1e-2),
        );
      },
    );

    testWidgets(
      'passes visibleRect == null inside unbounded SingleChildScrollView',
      (tester) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: GrandStaffScoreView(
                  score: SpikeFixtures.polyphonicGrandStaff,
                  activeHand: NotationHandFilter.left,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final paint = tester.widget<CustomPaint>(
          find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is GrandStaffScorePainter,
          ),
        );
        final painter = paint.painter! as GrandStaffScorePainter;
        expect(painter.visibleRect, isNull);
        expect(painter.effectiveDimmedClef, SmuflClef.treble);
        expect(painter.layout.totalSize.height, greaterThan(480));
      },
    );

    testWidgets(
      're-scrolls to keep activeSliceIndex visible when width wraps 800 -> 340',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final poly = SpikeFixtures.polyphonicGrandStaff;
        final lastSlice = poly.measures.last.slices.last.sliceIndex;

        Widget buildAtWidth(double width) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 320,
              child: GrandStaffScoreView(
                score: poly,
                controller: controller,
                activeSliceIndex: lastSlice,
              ),
            ),
          ),
        );

        await tester.pumpWidget(buildAtWidth(800));
        await tester.pumpAndSettle();
        final initialOffset = controller.offset;
        expect(initialOffset, greaterThan(0));

        await tester.pumpWidget(buildAtWidth(340));
        await tester.pumpAndSettle();
        expect(controller.offset, greaterThan(initialOffset));

        final narrowLayout = ScoreLayoutEngine.layout(
          score: poly,
          availableWidth: 340,
        );
        final targetSys = narrowLayout.slicePlacement(lastSlice)!.system;
        expect(targetSys.topY, greaterThanOrEqualTo(controller.offset));
        expect(targetSys.bottomY, lessThanOrEqualTo(controller.offset + 320));
      },
    );
  });
}
