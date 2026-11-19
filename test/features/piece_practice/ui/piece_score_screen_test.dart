import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/midi/midi.dart';
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

class _FakeMidiRepository implements MidiRepository {
  final StreamController<List<MidiDeviceInfo>> devicesController =
      StreamController<List<MidiDeviceInfo>>.broadcast();
  final StreamController<MidiNoteEvent> noteEventsController =
      StreamController<MidiNoteEvent>.broadcast();
  final StreamController<MidiBluetoothStatus> bluetoothController =
      StreamController<MidiBluetoothStatus>.broadcast();

  @override
  Stream<List<MidiDeviceInfo>> get devicesStream => devicesController.stream;

  @override
  Stream<MidiNoteEvent> get noteEventsStream => noteEventsController.stream;

  @override
  Stream<MidiBluetoothStatus> get bluetoothStateStream =>
      bluetoothController.stream;

  @override
  MidiBluetoothStatus get currentBluetoothStatus =>
      MidiBluetoothStatus.poweredOn;

  @override
  Future<List<MidiDeviceInfo>> currentDevices() async =>
      const <MidiDeviceInfo>[];

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(MidiDeviceInfo device) async {}

  @override
  Future<void> disconnect(MidiDeviceInfo device) async {}

  @override
  Future<void> dispose() async {
    await devicesController.close();
    await noteEventsController.close();
    await bluetoothController.close();
  }
}

MidiNoteEvent _noteOn(int number) => MidiNoteEvent.fromChannelMessage(
  noteNumber: number,
  velocity: 96,
  isNoteOn: true,
  channel: 0,
  deviceId: 'ble-1',
  timestampMs: 0,
);

MidiNoteEvent _noteOff(int number) => MidiNoteEvent.fromChannelMessage(
  noteNumber: number,
  velocity: 0,
  isNoteOn: false,
  channel: 0,
  deviceId: 'ble-1',
  timestampMs: 0,
);

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

Score _twoSliceScore() {
  return Score(
    title: 'Short Etude',
    scale: Scale.fromKeySignature(KeySignature.cMajor),
    timeSignature: TimeSignature.common,
    measures: <ScoreMeasure>[
      ScoreMeasure(
        measureNumber: 1,
        slices: <ScoreSlice>[
          ScoreSlice(
            sliceIndex: 0,
            measureNumber: 1,
            beatOffset: const RationalBeats.zero(),
            beatDuration: RationalBeats(2),
            trebleNotes: <ScoreNote>[
              ScoreNote(
                staffNote: const StaffNote(
                  note: DiatonicNote.c,
                  octave: 4,
                  clef: Clef.treble,
                ),
                duration: DurationValue(base: NoteBaseDuration.half),
              ),
            ],
          ),
          ScoreSlice(
            sliceIndex: 1,
            measureNumber: 1,
            beatOffset: RationalBeats(2),
            beatDuration: RationalBeats(2),
            trebleNotes: <ScoreNote>[
              ScoreNote(
                staffNote: const StaffNote(
                  note: DiatonicNote.e,
                  octave: 4,
                  clef: Clef.treble,
                ),
                duration: DurationValue(base: NoteBaseDuration.half),
              ),
            ],
          ),
        ],
      ),
    ],
  );
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
          final midiRepo = _FakeMidiRepository();
          addTearDown(midiRepo.dispose);
          tester.view.physicalSize = viewport;
          tester.view.devicePixelRatio = 1.0;
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(() {
            tester.view.reset();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });

          await tester.pumpWidget(
            ProviderScope(
              overrides: [midiRepositoryProvider.overrideWithValue(midiRepo)],
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
        final midiRepo = _FakeMidiRepository();
        addTearDown(midiRepo.dispose);
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
              midiRepositoryProvider.overrideWithValue(midiRepo),
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
      final midiRepo = _FakeMidiRepository();
      addTearDown(midiRepo.dispose);
      final store = InMemoryScoreFileStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            midiRepositoryProvider.overrideWithValue(midiRepo),
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
        final midiRepo = _FakeMidiRepository();
        addTearDown(midiRepo.dispose);
        final store = InMemoryScoreFileStore();
        await store.saveScoreBytes(
          variantId: 'v_simple',
          format: ScoreFormat.musicXml,
          bytes: simpleBytes,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              midiRepositoryProvider.overrideWithValue(midiRepo),
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

        await tester.tap(
          find.byKey(const ValueKey<String>('variant_chip_v_poly')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('score_error_view')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('variant_chip_v_simple')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('score_error_view')),
          findsNothing,
        );
        expect(find.text('Measure 1 / 8'), findsOneWidget);
      },
    );

    testWidgets(
      'renders multi-variant error view with zero overflow at 800x360 @ 1.6x text scale',
      (tester) async {
        final midiRepo = _FakeMidiRepository();
        addTearDown(midiRepo.dispose);
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
              midiRepositoryProvider.overrideWithValue(midiRepo),
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

    testWidgets(
      'Wait Mode renders wrong-note overlays, advances to completion, and restarts on Play Again',
      (tester) async {
        final midiRepo = _FakeMidiRepository();
        addTearDown(midiRepo.dispose);
        final shortScore = _twoSliceScore();
        final vShort = ScoreVariant(
          id: 'v_short',
          pieceId: 'p_short',
          difficultyTier: DifficultyTier.beginner,
          label: 'Short',
          fileName: 'short.musicxml',
          storedRelativePath: 'scores/v_short.musicxml',
          importedAtMs: 1,
        );
        final shortPiece = Piece(
          id: 'p_short',
          title: 'Short Etude',
          artist: 'Tester',
          scale: shortScore.scale,
          variants: <ScoreVariant>[vShort],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [midiRepositoryProvider.overrideWithValue(midiRepo)],
            child: MaterialApp(
              home: PieceScoreScreen(
                piece: shortPiece,
                initialVariant: vShort,
                initialScore: shortScore,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(_findScorePainter(tester).activeSliceIndex, 0);
        expect(_findScorePainter(tester).wrongNoteOverlays, isEmpty);

        // Wrong note D4 (62) draws red overlay on slice 0.
        midiRepo.noteEventsController.add(_noteOn(62));
        await tester.pump(const Duration(milliseconds: 35));
        midiRepo.noteEventsController.add(_noteOff(62));
        await tester.pump();
        expect(_findScorePainter(tester).activeSliceIndex, 0);
        expect(_findScorePainter(tester).wrongNoteOverlays, hasLength(1));

        // Correct note C4 (60) clears wrong overlay and advances to slice 1.
        midiRepo.noteEventsController.add(_noteOn(60));
        await tester.pump(const Duration(milliseconds: 35));
        midiRepo.noteEventsController.add(_noteOff(60));
        await tester.pump();
        expect(_findScorePainter(tester).activeSliceIndex, 1);
        expect(_findScorePainter(tester).wrongNoteOverlays, isEmpty);

        // Correct note E4 (64) completes piece and displays completion banner.
        midiRepo.noteEventsController.add(_noteOn(64));
        await tester.pump(const Duration(milliseconds: 35));
        midiRepo.noteEventsController.add(_noteOff(64));
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('practice_completed_banner')),
          findsOneWidget,
        );

        // Tap Play Again -> resets cursor to slice 0 and dismisses banner.
        await tester.tap(
          find.byKey(const ValueKey<String>('practice_play_again_button')),
        );
        await tester.pump();
        expect(_findScorePainter(tester).activeSliceIndex, 0);
        expect(
          find.byKey(const ValueKey<String>('practice_completed_banner')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'MeasureLoopSheet applies, wraps, clears, resets on variant switch, and MidiConnectionScreen pauses practice',
      (tester) async {
        final midiRepo = _FakeMidiRepository();
        addTearDown(midiRepo.dispose);
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
              midiRepositoryProvider.overrideWithValue(midiRepo),
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

        // Open MeasureLoopSheet and configure Loop M.2-4 (start inc x1 -> M.2, end inc x2 -> M.4).
        await tester.tap(
          find.byKey(const ValueKey<String>('score_loop_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('loop_start_inc')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('loop_end_inc')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('loop_end_inc')));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey<String>('loop_apply_button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Measure 2 / 32'), findsOneWidget);
        expect(find.text('Loop M.2\u20134'), findsOneWidget);

        // Open MidiConnectionScreen -> MIDI notes must not affect practice cursor.
        final sliceBeforeMidi = _findScorePainter(tester).activeSliceIndex;
        await tester.tap(
          find.byKey(const ValueKey<String>('midi-status-button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('BLE-MIDI Connection'), findsOneWidget);

        midiRepo.noteEventsController.add(_noteOn(61));
        await tester.pump(const Duration(milliseconds: 50));
        midiRepo.noteEventsController.add(_noteOff(61));
        await tester.pump();

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(_findScorePainter(tester).activeSliceIndex, sliceBeforeMidi);
        expect(_findScorePainter(tester).wrongNoteOverlays, isEmpty);

        // Clear loop via header close button, re-apply loop, then verify variant switch resets loop.
        await tester.tap(
          find.byKey(const ValueKey<String>('score_clear_loop_button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Loop'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('score_loop_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('loop_apply_button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Loop M.2'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('variant_chip_v_simple')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Measure 1 / 8'), findsOneWidget);
        expect(find.text('Loop'), findsOneWidget);
      },
    );

    testWidgets(
      'syncs livePieceProvider variants and renders MeasureLoopSheet + completion banner with zero overflow at 800x360 @ 1.6x',
      (tester) async {
        final midiRepo = _FakeMidiRepository();
        final catalogRepo = InMemoryCatalogRepository();
        addTearDown(() async {
          await midiRepo.dispose();
          await catalogRepo.close();
        });
        await catalogRepo.createPiece(piece);

        tester.view.physicalSize = const Size(800, 360);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });

        final shortScore = _twoSliceScore();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              midiRepositoryProvider.overrideWithValue(midiRepo),
              catalogRepositoryProvider.overrideWithValue(catalogRepo),
            ],
            child: MaterialApp(
              home: PieceScoreScreen(
                piece: Piece(
                  id: 'p1',
                  title: 'Test Sonata',
                  artist: 'Test Composer',
                  scale: polyScore.scale,
                  variants: <ScoreVariant>[vSimple],
                ),
                initialVariant: vSimple,
                initialScore: shortScore,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // livePieceProvider surfaces both variants stored in catalogRepo.
        expect(
          find.byKey(const ValueKey<String>('variant_chip_v_poly')),
          findsOneWidget,
        );

        // Open MeasureLoopSheet at 800x360 @ 1.6x, apply loop, then clear via sheet button.
        final loopButton = find.byKey(
          const ValueKey<String>('score_loop_button'),
        );
        await tester.ensureVisible(loopButton);
        await tester.tap(loopButton);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final applyButton = find.byKey(
          const ValueKey<String>('loop_apply_button'),
        );
        await tester.ensureVisible(applyButton);
        await tester.tap(applyButton);
        await tester.pumpAndSettle();
        expect(find.text('Loop M.1'), findsOneWidget);

        await tester.ensureVisible(loopButton);
        await tester.tap(loopButton);
        await tester.pumpAndSettle();
        final clearButton = find.byKey(
          const ValueKey<String>('loop_clear_button'),
        );
        await tester.ensureVisible(clearButton);
        await tester.tap(clearButton);
        await tester.pumpAndSettle();
        expect(find.text('Loop'), findsOneWidget);

        // Complete shortScore -> completion banner fits with zero overflow.
        midiRepo.noteEventsController.add(_noteOn(60));
        await tester.pump(const Duration(milliseconds: 35));
        midiRepo.noteEventsController.add(_noteOn(64));
        await tester.pump(const Duration(milliseconds: 35));
        expect(
          find.byKey(const ValueKey<String>('practice_completed_banner')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'retains pause across AsyncLoading score resolution while MidiConnectionScreen is open and guards loop-sheet double taps',
      (tester) async {
        final midiRepo = _FakeMidiRepository();
        final delayedStore = _CompleterScoreFileStore();
        addTearDown(midiRepo.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              midiRepositoryProvider.overrideWithValue(midiRepo),
              scoreFileStoreProvider.overrideWithValue(delayedStore),
              scoreParserProvider.overrideWithValue(
                const MusicXmlScoreParser(),
              ),
            ],
            child: MaterialApp(
              home: PieceScoreScreen(piece: piece, initialVariant: vSimple),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('score_loading_indicator')),
          findsOneWidget,
        );

        // Open MidiConnectionScreen while variantScoreProvider is still AsyncLoading.
        await tester.tap(
          find.byKey(const ValueKey<String>('midi-status-button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MidiConnectionScreen), findsOneWidget);

        // Resolve score behind MidiConnectionScreen -> controller mounts paused.
        delayedStore.readCompleter.complete(simpleBytes);
        await tester.pumpAndSettle();

        // Wrong & matching MIDI inputs on MidiInputCheckCard must NOT affect practice.
        midiRepo.noteEventsController.add(_noteOn(61));
        await tester.pump(const Duration(milliseconds: 40));
        midiRepo.noteEventsController.add(_noteOff(61));
        midiRepo.noteEventsController.add(_noteOn(67));
        midiRepo.noteEventsController.add(_noteOn(43));
        await tester.pump(const Duration(milliseconds: 40));
        midiRepo.noteEventsController.add(_noteOff(67));
        midiRepo.noteEventsController.add(_noteOff(43));
        await tester.pump();

        // Pop back to PieceScoreScreen -> slice stays at 0 with zero wrong overlays.
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(MidiConnectionScreen), findsNothing);
        expect(_findScorePainter(tester).activeSliceIndex, 0);
        expect(_findScorePainter(tester).wrongNoteOverlays, isEmpty);

        // Resumes after pop: G4 (67) + G2 (43) advances slice 0 -> slice 1.
        midiRepo.noteEventsController.add(_noteOn(67));
        midiRepo.noteEventsController.add(_noteOn(43));
        await tester.pump(const Duration(milliseconds: 40));
        midiRepo.noteEventsController.add(_noteOff(67));
        midiRepo.noteEventsController.add(_noteOff(43));
        await tester.pump();
        expect(_findScorePainter(tester).activeSliceIndex, 1);

        // Double-tap score_loop_button opens only one MeasureLoopSheet and unpauses on dismiss.
        final loopBtn = find.byKey(const ValueKey<String>('score_loop_button'));
        await tester.tap(loopBtn);
        await tester.tap(loopBtn, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(MeasureLoopSheet), findsOneWidget);

        Navigator.of(tester.element(find.byType(MeasureLoopSheet))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(MeasureLoopSheet), findsNothing);

        // Practice resumes cleanly after dismissing MeasureLoopSheet: B4 (71) advances 1 -> 2.
        midiRepo.noteEventsController.add(_noteOn(71));
        await tester.pump(const Duration(milliseconds: 40));
        midiRepo.noteEventsController.add(_noteOff(71));
        await tester.pump();
        expect(_findScorePainter(tester).activeSliceIndex, 2);

        // Same-frame overlap (score_loop_button + midi-status-button) keeps pause active until both close.
        final midiBtn = find.byKey(
          const ValueKey<String>('midi-status-button'),
        );
        tester.widget<ActionChip>(loopBtn).onPressed!();
        tester.widget<TextButton>(midiBtn).onPressed!();
        await tester.pumpAndSettle();
        expect(find.byType(MidiConnectionScreen), findsOneWidget);
        expect(
          find.byType(MeasureLoopSheet, skipOffstage: false),
          findsOneWidget,
        );

        // Close MidiConnectionScreen -> MeasureLoopSheet remains open and paused.
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(MeasureLoopSheet), findsOneWidget);
        midiRepo.noteEventsController.add(_noteOn(74)); // D5
        midiRepo.noteEventsController.add(_noteOn(50)); // D3
        await tester.pump(const Duration(milliseconds: 40));
        midiRepo.noteEventsController.add(_noteOff(74));
        midiRepo.noteEventsController.add(_noteOff(50));
        await tester.pump();
        expect(_findScorePainter(tester).activeSliceIndex, 2);

        // Dismiss MeasureLoopSheet -> unpauses and evaluates D5 (74) + D3 (50) -> slice 3.
        Navigator.of(tester.element(find.byType(MeasureLoopSheet))).pop();
        await tester.pumpAndSettle();
        midiRepo.noteEventsController.add(_noteOn(74));
        midiRepo.noteEventsController.add(_noteOn(50));
        await tester.pump(const Duration(milliseconds: 40));
        midiRepo.noteEventsController.add(_noteOff(74));
        midiRepo.noteEventsController.add(_noteOff(50));
        await tester.pump();
        expect(_findScorePainter(tester).activeSliceIndex, 3);
      },
    );
  });
}

class _CompleterScoreFileStore implements ScoreFileStore {
  final Completer<Uint8List> readCompleter = Completer<Uint8List>();

  @override
  Future<Uint8List> readScoreBytes(String storedRelativePath) =>
      readCompleter.future;

  @override
  Future<String> saveScoreBytes({
    required String variantId,
    required ScoreFormat format,
    required Uint8List bytes,
  }) async => 'scores/$variantId.musicxml';

  @override
  Future<void> deleteScoreFile(String storedRelativePath) async {}

  @override
  Future<int> purgeOrphans(Set<String> activeRelativePaths) async => 0;
}
