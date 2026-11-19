import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/piece_practice/piece_practice.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:smufl_notation/smufl_notation.dart';

bool _bravuraLoaded = false;

Future<void> _loadBravura() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_bravuraLoaded) {
    return;
  }
  final bytes = File('assets/fonts/Bravura.otf').readAsBytesSync();
  final loader = FontLoader('Bravura')
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
  _bravuraLoaded = true;
}

GrandStaffScorePainter _findScorePainter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byKey(const ValueKey<String>('piece_score_viewport')),
      matching: find.byType(CustomPaint),
    ),
  );
  return paints
      .map((w) => w.painter)
      .whereType<GrandStaffScorePainter>()
      .single;
}

void main() {
  setUpAll(_loadBravura);

  group('PieceScoreScreen', () {
    late Uint8List simpleBytes;
    late Uint8List polyBytes;
    late Score simpleScore;
    late Score polyScore;
    late ScoreVariant vSimple;
    late ScoreVariant vPoly;
    late Piece piece;

    setUpAll(() {
      const parser = MusicXmlScoreParser();
      simpleBytes = Uint8List.fromList(
        File('test/fixtures/simplified_melody_bass.musicxml').readAsBytesSync(),
      );
      polyBytes = Uint8List.fromList(
        File('test/fixtures/polyphonic_grand_staff.musicxml').readAsBytesSync(),
      );
      simpleScore = parser
          .parseBytes(simpleBytes, fileName: 'simplified.musicxml')
          .score;
      polyScore = parser
          .parseBytes(polyBytes, fileName: 'polyphonic.musicxml')
          .score;
      vSimple = ScoreVariant(
        id: 'v_simple',
        pieceId: 'p1',
        difficultyTier: DifficultyTier.beginner,
        label: 'Easy',
        fileName: 'simplified.musicxml',
        storedRelativePath: 'scores/v_simple.musicxml',
        importedAtMs: 1,
      );
      vPoly = ScoreVariant(
        id: 'v_poly',
        pieceId: 'p1',
        difficultyTier: DifficultyTier.advanced,
        label: 'Full 32m',
        fileName: 'polyphonic.musicxml',
        storedRelativePath: 'scores/v_poly.musicxml',
        importedAtMs: 2,
      );
      piece = Piece(
        id: 'p1',
        title: 'Test Sonata',
        artist: 'Test Composer',
        scale: polyScore.scale,
        variants: <ScoreVariant>[vSimple, vPoly],
      );
    });

    for (final viewport in const <Size>[Size(360, 640), Size(800, 360)]) {
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

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: PieceScoreScreen(
                  piece: piece,
                  initialVariant: vPoly,
                  initialScore: polyScore,
                  wrongNoteOverlays: <WrongNoteOverlay>[
                    ScoreNotationMapper.mapWrongNotes(
                      sliceIndex: 0,
                      clef: SmuflClef.treble,
                      wrongNotes: const <StaffNote>[
                        StaffNote(
                          note: DiatonicNote.c,
                          octave: 6,
                          clef: Clef.treble,
                          accidental: Accidental.sharp,
                        ),
                      ],
                      activeKeySignature: polyScore.scale.keySignature,
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey<String>('piece_score_viewport')),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets(
      'supports hand mode chips, step controls, slice tap, and 32m -> 8m variant shrink clamp',
      (tester) async {
        final store = InMemoryScoreFileStore();
        await store.saveScoreBytes(
          variantId: 'v_simple',
          format: ScoreFormat.musicXml,
          bytes: simpleBytes,
        );
        await store.saveScoreBytes(
          variantId: 'v_poly',
          format: ScoreFormat.musicXml,
          bytes: polyBytes,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scoreFileStoreProvider.overrideWithValue(store),
              scoreParserProvider.overrideWithValue(
                const MusicXmlScoreParser(),
              ),
            ],
            child: MaterialApp(
              home: PieceScoreScreen(piece: piece, initialVariant: vPoly),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Measure 1 / 32'), findsOneWidget);
        final initialLayout = _findScorePainter(tester).layout;

        // Toggle hand modes.
        await tester.tap(find.byKey(const ValueKey<String>('hand_mode_right')));
        await tester.pump();
        expect(_findScorePainter(tester).activeHand, NotationHandFilter.right);
        expect(
          identical(_findScorePainter(tester).layout, initialLayout),
          isTrue,
        );

        await tester.tap(find.byKey(const ValueKey<String>('hand_mode_left')));
        await tester.pump();
        expect(_findScorePainter(tester).activeHand, NotationHandFilter.left);

        await tester.tap(find.byKey(const ValueKey<String>('hand_mode_both')));
        await tester.pump();
        expect(_findScorePainter(tester).activeHand, NotationHandFilter.both);

        // Step next & reset cursor.
        await tester.tap(
          find.byKey(const ValueKey<String>('score_next_slice')),
        );
        await tester.pumpAndSettle();
        expect(_findScorePainter(tester).activeSliceIndex, 1);
        expect(
          identical(_findScorePainter(tester).layout, initialLayout),
          isTrue,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('score_prev_slice')),
        );
        await tester.pumpAndSettle();
        expect(_findScorePainter(tester).activeSliceIndex, 0);

        // Tap slice 2 directly on canvas.
        final painterBeforeTap = _findScorePainter(tester);
        final rect2 = painterBeforeTap.layout.sliceRect(2)!;
        final scoreBoxTopLeft = tester.getTopLeft(
          find.byType(GrandStaffScoreView),
        );
        await tester.tapAt(scoreBoxTopLeft + rect2.center);
        await tester.pumpAndSettle();
        expect(_findScorePainter(tester).activeSliceIndex, 2);

        await tester.tap(
          find.byKey(const ValueKey<String>('score_reset_slice')),
        );
        await tester.pumpAndSettle();
        expect(_findScorePainter(tester).activeSliceIndex, 0);

        // Scroll to bottom of 32-measure variant, then switch to 8-measure variant.
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(GrandStaffScoreView),
            matching: find.byType(Scrollable),
          ),
        );
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, greaterThan(400));

        await tester.tap(
          find.byKey(const ValueKey<String>('variant_chip_v_simple')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Measure 1 / 8'), findsOneWidget);
        final shrunkPainter = _findScorePainter(tester);
        expect(shrunkPainter.layout.systems.length, lessThan(10));
        expect(shrunkPainter.visibleRect?.top, 0.0);
        expect(shrunkPainter.activeSliceIndex, 0);
        expect(simpleScore.measures, hasLength(8));
      },
    );

    testWidgets('shows retry view on score load failure and recovers', (
      tester,
    ) async {
      final store = InMemoryScoreFileStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scoreFileStoreProvider.overrideWithValue(store),
            scoreParserProvider.overrideWithValue(const MusicXmlScoreParser()),
          ],
          child: MaterialApp(
            home: PieceScoreScreen(piece: piece, initialVariant: vSimple),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('score_error_view')),
        findsOneWidget,
      );

      await store.saveScoreBytes(
        variantId: 'v_simple',
        format: ScoreFormat.musicXml,
        bytes: simpleBytes,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('score_retry_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Measure 1 / 8'), findsOneWidget);
    });

    testWidgets(
      'keeps variant chips accessible in error state so user can switch back to valid variant',
      (tester) async {
        final store = InMemoryScoreFileStore();
        await store.saveScoreBytes(
          variantId: 'v_simple',
          format: ScoreFormat.musicXml,
          bytes: simpleBytes,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scoreFileStoreProvider.overrideWithValue(store),
              scoreParserProvider.overrideWithValue(
                const MusicXmlScoreParser(),
              ),
            ],
            child: MaterialApp(
              home: PieceScoreScreen(piece: piece, initialVariant: vSimple),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Measure 1 / 8'), findsOneWidget);

        // Select broken/missing variant -> error view appears, variant chips remain usable.
        await tester.tap(
          find.byKey(const ValueKey<String>('variant_chip_v_poly')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('score_error_view')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('variant_chip_v_simple')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('variant_chip_v_poly')),
          findsOneWidget,
        );

        // Switch back to valid variant -> recovers back to rendered score.
        await tester.tap(
          find.byKey(const ValueKey<String>('variant_chip_v_simple')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('score_error_view')),
          findsNothing,
        );
        expect(find.text('Measure 1 / 8'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('piece_score_viewport')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'renders multi-variant error view with zero overflow at 800x360 @ 1.6x text scale',
      (tester) async {
        tester.view.physicalSize = const Size(800, 360);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final store = InMemoryScoreFileStore();
        await store.saveScoreBytes(
          variantId: 'v_simple',
          format: ScoreFormat.musicXml,
          bytes: simpleBytes,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scoreFileStoreProvider.overrideWithValue(store),
              scoreParserProvider.overrideWithValue(
                const MusicXmlScoreParser(),
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: PieceScoreScreen(piece: piece, initialVariant: vPoly),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey<String>('score_error_view')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('score_retry_button')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('score_retry_button')),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('variant_chip_v_simple')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Measure 1 / 8'), findsOneWidget);
      },
    );
  });
}
