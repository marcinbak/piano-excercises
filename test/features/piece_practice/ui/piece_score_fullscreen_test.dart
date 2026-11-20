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

int _currentQuarterTurns(WidgetTester tester) {
  return tester
      .widget<RotatedBox>(
        find.byKey(const ValueKey<String>('score_fullscreen_rotated_box')),
      )
      .quarterTurns;
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

  group('defaultFullscreenQuarterTurns', () {
    test(
      'returns 1 on portrait phones and 0 on tablets or landscape viewports',
      () {
        expect(defaultFullscreenQuarterTurns(const Size(390, 844)), 1);
        expect(defaultFullscreenQuarterTurns(const Size(360, 640)), 1);
        expect(defaultFullscreenQuarterTurns(const Size(844, 390)), 0);
        expect(defaultFullscreenQuarterTurns(const Size(768, 1024)), 0);
        expect(defaultFullscreenQuarterTurns(const Size(1024, 768)), 0);
      },
    );
  });

  group('PieceScoreScreen fullscreen and 90-degree rotation', () {
    late Score polyScore;
    late ScoreVariant vPoly;
    late Piece piece;

    setUpAll(() {
      const parser = MusicXmlScoreParser();
      final polyBytes = Uint8List.fromList(
        File('test/fixtures/polyphonic_grand_staff.musicxml').readAsBytesSync(),
      );
      polyScore = parser
          .parseBytes(polyBytes, fileName: 'polyphonic.musicxml')
          .score;
      vPoly = ScoreVariant(
        id: 'v_poly',
        pieceId: 'p1',
        difficultyTier: DifficultyTier.advanced,
        label: 'Full 32m',
        fileName: 'polyphonic.musicxml',
        storedRelativePath: 'scores/v_poly.musicxml',
        importedAtMs: 1,
      );
      piece = Piece(
        id: 'p1',
        title: 'Test Sonata',
        artist: 'Test Composer',
        scale: polyScore.scale,
        variants: <ScoreVariant>[vPoly],
      );
    });

    testWidgets(
      'portrait iPhone opens fullscreen in landscape (90 deg), cycles 90-deg steps, remembers angle, and toggles SystemUiMode',
      (tester) async {
        final midiRepo = _FakeMidiRepository();
        addTearDown(midiRepo.dispose);

        final systemUiModes = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
                systemUiModes.add(call.arguments as String);
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        tester.view.physicalSize = const Size(390, 844);
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
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final portraitWidth = _findScorePainter(tester).layout.totalSize.width;
        expect(portraitWidth, lessThan(390));
        expect(find.byType(PieceScoreHeaderBar), findsOneWidget);

        // Enter fullscreen on portrait phone -> auto-rotates to 90° landscape.
        await tester.tap(
          find.byKey(const ValueKey<String>('score_fullscreen_button')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(PieceScoreHeaderBar), findsNothing);
        expect(find.byType(AppBar), findsNothing);
        expect(_currentQuarterTurns(tester), 1);
        expect(systemUiModes, <String>['SystemUiMode.immersiveSticky']);

        final landscapeWidth = _findScorePainter(tester).layout.totalSize.width;
        expect(landscapeWidth, greaterThan(800));

        // Cycle 90° button across 180°, 270°, 0°, and back to 270°.
        final rotateBtn = find.byKey(
          const ValueKey<String>('score_rotate_button'),
        );
        await tester.tap(rotateBtn);
        await tester.pumpAndSettle();
        expect(_currentQuarterTurns(tester), 2);
        expect(_findScorePainter(tester).layout.totalSize.width, lessThan(390));

        await tester.tap(rotateBtn);
        await tester.pumpAndSettle();
        expect(_currentQuarterTurns(tester), 3);
        expect(
          _findScorePainter(tester).layout.totalSize.width,
          greaterThan(800),
        );

        await tester.tap(rotateBtn);
        await tester.pumpAndSettle();
        expect(_currentQuarterTurns(tester), 0);
        expect(_findScorePainter(tester).layout.totalSize.width, lessThan(390));

        await tester.tap(rotateBtn);
        await tester.pumpAndSettle();
        expect(_currentQuarterTurns(tester), 1);

        await tester.tap(rotateBtn);
        await tester.pumpAndSettle();
        expect(_currentQuarterTurns(tester), 2);

        // Exit fullscreen -> restores AppBar, header, and SystemUiMode.edgeToEdge.
        await tester.tap(
          find.byKey(const ValueKey<String>('score_exit_fullscreen_button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byType(PieceScoreHeaderBar), findsOneWidget);
        expect(systemUiModes.last, 'SystemUiMode.edgeToEdge');

        // Re-entering fullscreen preserves user's chosen rotation (2 = 180°).
        await tester.tap(
          find.byKey(const ValueKey<String>('score_fullscreen_button')),
        );
        await tester.pumpAndSettle();
        expect(_currentQuarterTurns(tester), 2);
      },
    );

    testWidgets(
      'portrait iPad starts fullscreen at 0 deg and rotates 90 deg on demand',
      (tester) async {
        final midiRepo = _FakeMidiRepository();
        addTearDown(midiRepo.dispose);
        tester.view.physicalSize = const Size(768, 1024);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [midiRepositoryProvider.overrideWithValue(midiRepo)],
            child: MaterialApp(
              home: PieceScoreScreen(
                piece: piece,
                initialVariant: vPoly,
                initialScore: polyScore,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('score_fullscreen_button')),
        );
        await tester.pumpAndSettle();
        expect(_currentQuarterTurns(tester), 0);
        expect(
          _findScorePainter(tester).layout.totalSize.width,
          inInclusiveRange(740, 768),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('score_rotate_button')),
        );
        await tester.pumpAndSettle();
        expect(_currentQuarterTurns(tester), 1);
        expect(
          _findScorePainter(tester).layout.totalSize.width,
          greaterThan(1000),
        );
      },
    );

    testWidgets(
      'supports rotated slice tap, Wait-Mode completion, system-back exit, and dispose cleanup',
      (tester) async {
        final midiRepo = _FakeMidiRepository();
        addTearDown(midiRepo.dispose);

        final systemUiModes = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
                systemUiModes.add(call.arguments as String);
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });

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
              home: Builder(
                builder: (context) => Scaffold(
                  body: FilledButton(
                    key: const ValueKey<String>('open_piece'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PieceScoreScreen(
                          piece: shortPiece,
                          initialVariant: vShort,
                          initialScore: shortScore,
                        ),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey<String>('open_piece')));
        await tester.pumpAndSettle();

        // Enter fullscreen (quarterTurns = 1).
        await tester.tap(
          find.byKey(const ValueKey<String>('score_fullscreen_button')),
        );
        await tester.pumpAndSettle();
        expect(_currentQuarterTurns(tester), 1);

        // Tap slice 1 through rotated coordinates -> seeks activeSliceIndex to 1.
        final rect1 = _findScorePainter(tester).layout.sliceRect(1)!;
        final scoreBox = tester.renderObject<RenderBox>(
          find.byType(GrandStaffScoreView),
        );
        await tester.tapAt(scoreBox.localToGlobal(rect1.center));
        await tester.pumpAndSettle();
        expect(_findScorePainter(tester).activeSliceIndex, 1);

        // Play E4 (64) to complete piece -> banner + Play Again work in rotated fullscreen.
        midiRepo.noteEventsController.add(_noteOn(64));
        await tester.pump(const Duration(milliseconds: 35));
        midiRepo.noteEventsController.add(_noteOff(64));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.byKey(const ValueKey<String>('practice_completed_banner')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(const ValueKey<String>('practice_play_again_button')),
        );
        await tester.pumpAndSettle();
        expect(_findScorePainter(tester).activeSliceIndex, 0);

        // System back exits fullscreen without popping PieceScoreScreen route.
        await Navigator.of(tester.element(find.byType(PieceScoreScreen)))
            .maybePop();
        await tester.pumpAndSettle();
        expect(find.byType(PieceScoreScreen), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        expect(systemUiModes.last, 'SystemUiMode.edgeToEdge');

        // Re-enter fullscreen and pop parent route directly -> dispose restores edgeToEdge.
        await tester.tap(
          find.byKey(const ValueKey<String>('score_fullscreen_button')),
        );
        await tester.pumpAndSettle();
        expect(systemUiModes.last, 'SystemUiMode.immersiveSticky');

        Navigator.of(tester.element(find.byType(PieceScoreScreen))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(PieceScoreScreen), findsNothing);
        expect(systemUiModes.last, 'SystemUiMode.edgeToEdge');
      },
    );
  });
}
