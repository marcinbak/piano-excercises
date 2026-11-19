import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smufl_notation/smufl_notation.dart';

import '../example/main.dart';
import '../example/spike_fixtures.dart';
import 'test_font_loader.dart';

void main() {
  setUpAll(loadBravuraTestFont);

  group('GrandStaffScoreView', () {
    testWidgets('renders simplified and polyphonic scores with culling & tap', (
      tester,
    ) async {
      int? tappedSlice;
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 360,
              child: GrandStaffScoreView(
                score: SpikeFixtures.polyphonicGrandStaff,
                controller: controller,
                activeSliceIndex: 0,
                dimmedClef: SmuflClef.bass,
                onSliceTapped: (idx) => tappedSlice = idx,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      controller.jumpTo(300);
      await tester.pump();
      expect(tester.takeException(), isNull);

      final expectedLayout = ScoreLayoutEngine.layout(
        score: SpikeFixtures.polyphonicGrandStaff,
        availableWidth: 400,
      );
      final targetIdx =
          expectedLayout.systems[2].measures.first.slices.first.sliceIndex;
      final targetRect = expectedLayout.sliceRect(targetIdx)!;
      controller.jumpTo(targetRect.top - 40);
      await tester.pump();
      await tester.tapAt(targetRect.center - Offset(0, controller.offset));
      await tester.pump();
      expect(tappedSlice, targetIdx);
    });

    test('paints culled visibleRect and WrongNoteOverlay with Bravura', () {
      final layout = ScoreLayoutEngine.layout(
        score: SpikeFixtures.polyphonicGrandStaff,
        availableWidth: 420,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = GrandStaffScorePainter(
        layout: layout,
        activeSliceIndex: 1,
        dimmedClef: SmuflClef.treble,
        visibleRect: const Rect.fromLTWH(0, 0, 420, 320),
        wrongNoteOverlays: <WrongNoteOverlay>[
          WrongNoteOverlay(
            sliceIndex: 1,
            notes: <NotationNote>[
              NotationNote(
                staffStep: 12,
                clef: SmuflClef.treble,
                accidental: SmuflAccidental.sharp,
                showAccidental: true,
              ),
              NotationNote(
                staffStep: -5,
                clef: SmuflClef.bass,
                accidental: SmuflAccidental.flat,
                showAccidental: true,
              ),
            ],
          ),
        ],
      );
      painter.paint(canvas, layout.totalSize);
      final picture = recorder.endRecording();
      picture.dispose();
    });
  });

  group('SmuflSpikeApp harness', () {
    for (final viewport in <Size>[const Size(360, 420), const Size(780, 340)]) {
      testWidgets(
        'renders zero overflow at ${viewport.width}x${viewport.height} @ 1.6x text scale',
        (tester) async {
          tester.view.physicalSize = viewport;
          tester.view.devicePixelRatio = 1.0;
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(() {
            tester.view.reset();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });

          await tester.pumpWidget(const SmuflSpikeApp());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('spike-frame-metrics')), findsOneWidget);

          await tester.tap(find.byKey(const Key('spike-fixture-polyphonic')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          for (var i = 0; i < 20; i += 1) {
            await tester.tap(find.byKey(const Key('spike-next-slice')));
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final scrollable = tester.state<ScrollableState>(
            find.descendant(
              of: find.byType(GrandStaffScoreView),
              matching: find.byType(Scrollable),
            ),
          );
          expect(scrollable.position.pixels, greaterThan(0));

          await tester.tap(find.byKey(const Key('spike-prev-slice')));
          await tester.tap(find.byKey(const Key('spike-hand-right')));
          await tester.tap(find.byKey(const Key('spike-hand-left')));
          await tester.tap(find.byKey(const Key('spike-hand-both')));
          await tester.tap(find.byKey(const Key('spike-wrong-note-toggle')));
          await tester.tap(find.byKey(const Key('spike-width-compact')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(GrandStaffScoreView)).width,
            lessThanOrEqualTo(340.0),
          );

          await tester.tap(find.byKey(const Key('spike-width-full')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
