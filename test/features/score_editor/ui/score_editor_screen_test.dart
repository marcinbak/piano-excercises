import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/piece_practice/piece_practice.dart';
import 'package:piano_exercises/features/score_editor/score_editor.dart';
import 'package:piano_exercises/shared/music/music.dart';

class _TestMidiRepository implements MidiRepository {
  final StreamController<List<MidiDeviceInfo>> devicesController =
      StreamController<List<MidiDeviceInfo>>.broadcast();
  final StreamController<MidiNoteEvent> noteEventsController =
      StreamController<MidiNoteEvent>.broadcast();
  final StreamController<MidiBluetoothStatus> bluetoothController =
      StreamController<MidiBluetoothStatus>.broadcast();

  void emitNoteOn(int number) {
    noteEventsController.add(
      MidiNoteEvent.fromChannelMessage(
        noteNumber: number,
        velocity: 96,
        isNoteOn: true,
        channel: 0,
        deviceId: 'ble-1',
        timestampMs: 0,
      ),
    );
  }

  void emitNoteOff(int number) {
    noteEventsController.add(
      MidiNoteEvent.fromChannelMessage(
        noteNumber: number,
        velocity: 0,
        isNoteOn: false,
        channel: 0,
        deviceId: 'ble-1',
        timestampMs: 0,
      ),
    );
  }

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

Future<void> _tapByKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required _TestMidiRepository midiRepo,
  required InMemoryCatalogRepository catalogRepo,
  required InMemoryScoreFileStore fileStore,
  Size surfaceSize = const Size(420, 760),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        midiRepositoryProvider.overrideWithValue(midiRepo),
        catalogRepositoryProvider.overrideWithValue(catalogRepo),
        scoreFileStoreProvider.overrideWithValue(fileStore),
        scoreParserProvider.overrideWithValue(const MusicXmlScoreParser()),
        scoreSerializerProvider.overrideWithValue(
          const MusicXmlScoreSerializer(),
        ),
        scoreEditorChordWindowProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
      child: const MaterialApp(home: ScoreEditorScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ScoreEditorScreen widget flows', () {
    late _TestMidiRepository midiRepo;
    late InMemoryCatalogRepository catalogRepo;
    late InMemoryScoreFileStore fileStore;

    setUp(() {
      midiRepo = _TestMidiRepository();
      catalogRepo = InMemoryCatalogRepository();
      fileStore = InMemoryScoreFileStore();
    });

    tearDown(() async {
      await midiRepo.dispose();
      await catalogRepo.close();
    });

    testWidgets(
      'renders zero RenderFlex overflow at 360x640 @ 1.0x and 800x360 @ 1.6x',
      (tester) async {
        await _pumpEditor(
          tester,
          midiRepo: midiRepo,
          catalogRepo: catalogRepo,
          fileStore: fileStore,
          surfaceSize: const Size(360, 640),
          textScale: 1.0,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey<String>('editor-score-viewport')),
          findsOneWidget,
        );

        await _pumpEditor(
          tester,
          midiRepo: midiRepo,
          catalogRepo: catalogRepo,
          fileStore: fileStore,
          surfaceSize: const Size(360, 640),
          textScale: 1.6,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey<String>('editor-score-viewport')),
          findsOneWidget,
        );

        await _pumpEditor(
          tester,
          midiRepo: midiRepo,
          catalogRepo: catalogRepo,
          fileStore: fileStore,
          surfaceSize: const Size(800, 360),
          textScale: 1.6,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey<String>('editor-score-viewport')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'supports MIDI chord entry, touch pitch editing, undo/redo, and practice preview pause gating',
      (tester) async {
        await _pumpEditor(
          tester,
          midiRepo: midiRepo,
          catalogRepo: catalogRepo,
          fileStore: fileStore,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ScoreEditorScreen)),
        );

        // MIDI chord entry.
        midiRepo.emitNoteOn(60);
        midiRepo.emitNoteOn(64);
        await tester.pump(const Duration(milliseconds: 30));
        midiRepo.emitNoteOff(60);
        midiRepo.emitNoteOff(64);
        await tester.pump();
        var state = container.read(
          scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
        );
        expect(state.draft.measures[0].notes, hasLength(2));
        expect(state.draft.cursor.beatOffset, RationalBeats(1));

        // Step back and exercise touch pitch editing + duration + tie + rest.
        await _tapByKey(tester, 'editor-prev-slice');
        await _tapByKey(tester, 'editor-cycle-note');
        await _tapByKey(tester, 'editor-pitch-up');
        await _tapByKey(tester, 'editor-accidental-sharp');
        await _tapByKey(tester, 'editor-flip-clef');
        await _tapByKey(tester, 'editor-duration-half');
        await _tapByKey(tester, 'editor-dot-toggle');

        state = container.read(
          scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
        );
        expect(state.draft.selectedDuration.base, NoteBaseDuration.half);
        expect(state.draft.selectedDuration.dots, 1);

        // Undo & redo.
        await _tapByKey(tester, 'editor-undo-button');
        expect(
          container
              .read(
                scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
              )
              .draft
              .selectedDuration
              .dots,
          0,
        );
        await _tapByKey(tester, 'editor-redo-button');

        // Add touch note & add/delete measure.
        await _tapByKey(tester, 'editor-add-measure-button');
        expect(
          container
              .read(
                scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
              )
              .draft
              .measures,
          hasLength(5),
        );
        await _tapByKey(tester, 'editor-delete-measure-button');
        expect(
          container
              .read(
                scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
              )
              .draft
              .measures,
          hasLength(4),
        );

        // Open practice preview -> editor MIDI coalescer pauses while preview is pushed.
        await _tapByKey(tester, 'editor-practice-button');
        await tester.pumpAndSettle();
        expect(find.byType(PieceScoreScreen), findsOneWidget);
        expect(
          container
              .read(
                scoreEditorControllerProvider(ScoreEditorSessionId.composeTab)
                    .notifier,
              )
              .isPaused,
          isTrue,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          container
              .read(
                scoreEditorControllerProvider(ScoreEditorSessionId.composeTab)
                    .notifier,
              )
              .isPaused,
          isFalse,
        );
      },
    );

    testWidgets(
      'ScoreSetupSheet and ScoreSaveSheet configure and persist scores',
      (tester) async {
        await _pumpEditor(
          tester,
          midiRepo: midiRepo,
          catalogRepo: catalogRepo,
          fileStore: fileStore,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ScoreEditorScreen)),
        );

        // Add a touch note so score isn't empty.
        await _tapByKey(tester, 'editor-add-note');

        // Open Setup sheet, change mode to minor + 3/4 + trebleOnly, apply.
        await _tapByKey(tester, 'editor-open-setup-button');
        await tester.pumpAndSettle();
        await _tapByKey(tester, 'setup-scale-mode-minor');
        await _tapByKey(tester, 'setup-time-sig-3-4');
        await _tapByKey(tester, 'setup-clef-mode-trebleOnly');
        await _tapByKey(tester, 'setup-apply-button');
        await tester.pumpAndSettle();

        var state = container.read(
          scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
        );
        expect(state.draft.scale.mode, ScaleMode.minor);
        expect(state.draft.timeSignature, TimeSignature(3, 4));
        expect(state.draft.clefMode, ClefAssignmentMode.trebleOnly);

        // Open Save sheet -> save as New piece.
        await _tapByKey(tester, 'editor-open-save-button');
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('save-title-field')),
          'Nocturne Sketch',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('save-artist-field')),
          'F. Chopin',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('save-variant-label-field')),
          'Draft 1',
        );
        await _tapByKey(tester, 'save-submit-button');
        await tester.pumpAndSettle();

        state = container.read(
          scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
        );
        expect(state.isDirty, isFalse);
        expect(state.binding, isNotNull);
        expect(state.binding!.piece.title, 'Nocturne Sketch');
        expect(await catalogRepo.countPieces(), 1);

        // Open Save sheet again -> defaults to Update arrangement and updates in place.
        await _tapByKey(tester, 'editor-pitch-up');
        expect(
          container
              .read(
                scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
              )
              .isDirty,
          isTrue,
        );
        await _tapByKey(tester, 'editor-open-save-button');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('save-mode-update')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('save-title-field')),
          'Nocturne Op. 9',
        );
        await _tapByKey(tester, 'save-submit-button');
        await tester.pumpAndSettle();

        state = container.read(
          scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
        );
        expect(state.isDirty, isFalse);
        expect(state.binding!.piece.title, 'Nocturne Op. 9');
        expect(await catalogRepo.countPieces(), 1);

        // Attach as second arrangement to existing piece, then clear score via Setup sheet.
        await _tapByKey(tester, 'editor-open-save-button');
        await tester.pumpAndSettle();
        await _tapByKey(tester, 'save-mode-attach-piece');
        await tester.enterText(
          find.byKey(const ValueKey<String>('save-variant-label-field')),
          'Simplified',
        );
        await _tapByKey(tester, 'save-submit-button');
        await tester.pumpAndSettle();
        final pieces = await catalogRepo.queryPieces();
        expect(pieces.single.variants, hasLength(2));

        await _tapByKey(tester, 'editor-open-setup-button');
        await tester.pumpAndSettle();
        await _tapByKey(tester, 'setup-clear-score-button');
        await tester.pumpAndSettle();
        expect(
          container
              .read(
                scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
              )
              .draft
              .measures
              .every((m) => m.notes.isEmpty),
          isTrue,
        );
      },
    );

    testWidgets(
      'PieceScoreScreen -> Edit -> Practice preview evaluates MIDI while parent PieceScoreScreen stays paused',
      (tester) async {
        final twoNoteScore = ScoreTimelineReducer.reduce(
          title: 'Two Note Study',
          initialScale: Scale.fromKeySignature(KeySignature.cMajor),
          initialTimeSignature: TimeSignature.common,
          measures: <MeasureTimelineInput>[
            MeasureTimelineInput(
              measureNumber: 1,
              notes: <NoteTimelineInput>[
                NoteTimelineInput(
                  clef: Clef.treble,
                  diatonicNote: DiatonicNote.c,
                  octave: 4,
                  explicitAlter: 0,
                  beatOffset: const RationalBeats.zero(),
                  duration: DurationValue(base: NoteBaseDuration.quarter),
                ),
                NoteTimelineInput(
                  clef: Clef.treble,
                  diatonicNote: DiatonicNote.d,
                  octave: 4,
                  explicitAlter: 0,
                  beatOffset: RationalBeats(1),
                  duration: DurationValue(base: NoteBaseDuration.quarter),
                ),
              ],
            ),
          ],
        );
        final bytes = const MusicXmlScoreSerializer().serialize(twoNoteScore);
        final relPath = await fileStore.saveScoreBytes(
          variantId: 'v_nested',
          format: ScoreFormat.musicXml,
          bytes: bytes,
        );
        final variant = ScoreVariant(
          id: 'v_nested',
          pieceId: 'p_nested',
          difficultyTier: DifficultyTier.beginner,
          label: 'Standard',
          fileName: 'nested.musicxml',
          storedRelativePath: relPath,
          importedAtMs: 1,
        );
        final piece = Piece(
          id: 'p_nested',
          title: 'Two Note Study',
          artist: '',
          scale: twoNoteScore.scale,
          variants: <ScoreVariant>[variant],
        );
        await catalogRepo.createPiece(piece);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              midiRepositoryProvider.overrideWithValue(midiRepo),
              catalogRepositoryProvider.overrideWithValue(catalogRepo),
              scoreFileStoreProvider.overrideWithValue(fileStore),
              scoreParserProvider.overrideWithValue(
                const MusicXmlScoreParser(),
              ),
              scoreSerializerProvider.overrideWithValue(
                const MusicXmlScoreSerializer(),
              ),
              practiceChordWindowProvider.overrideWithValue(
                const Duration(milliseconds: 10),
              ),
              scoreEditorChordWindowProvider.overrideWithValue(
                const Duration(milliseconds: 10),
              ),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => PieceScoreScreen(
                  piece: piece,
                  initialVariant: variant,
                  onEditVariant: (p, v) => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ScoreEditorScreen(
                        sessionId: ScoreEditorSessionId('edit_${v.id}'),
                        initialPiece: p,
                        initialVariant: v,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open ScoreEditorScreen from PieceScoreScreen (#1), then Practice preview (#2).
        await _tapByKey(tester, 'piece-score-edit-button');
        await tester.pumpAndSettle();
        await _tapByKey(tester, 'editor-practice-button');
        await tester.pumpAndSettle();

        // Preview (#2) evaluates C4 + D4 -> completes; parent (#1) ignores those notes.
        midiRepo.emitNoteOn(60);
        await tester.pump(const Duration(milliseconds: 20));
        midiRepo.emitNoteOff(60);
        await tester.pump();
        midiRepo.emitNoteOn(62);
        await tester.pump(const Duration(milliseconds: 20));
        midiRepo.emitNoteOff(62);
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('practice_completed_banner')),
          findsOneWidget,
        );

        // Pop preview and editor back to parent PieceScoreScreen (#1).
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('practice_completed_banner')),
          findsNothing,
        );

        // Parent (#1) resumes cleanly upon return.
        midiRepo.emitNoteOn(60);
        await tester.pump(const Duration(milliseconds: 20));
        midiRepo.emitNoteOff(60);
        await tester.pump();
        midiRepo.emitNoteOn(62);
        await tester.pump(const Duration(milliseconds: 20));
        midiRepo.emitNoteOff(62);
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('practice_completed_banner')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'disables Save and Practice buttons and ignores MIDI when loadError is active',
      (tester) async {
        final missingVariant = ScoreVariant(
          id: 'v_broken',
          pieceId: 'p_broken',
          difficultyTier: DifficultyTier.beginner,
          label: 'Broken',
          fileName: 'broken.musicxml',
          storedRelativePath: 'scores/v_broken.musicxml',
          importedAtMs: 1,
        );
        final piece = Piece(
          id: 'p_broken',
          title: 'Broken Piece',
          artist: '',
          scale: Scale.fromKeySignature(KeySignature.cMajor),
          variants: <ScoreVariant>[missingVariant],
        );
        const session = ScoreEditorSessionId('edit_v_broken');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              midiRepositoryProvider.overrideWithValue(midiRepo),
              catalogRepositoryProvider.overrideWithValue(catalogRepo),
              scoreFileStoreProvider.overrideWithValue(fileStore),
              scoreParserProvider.overrideWithValue(
                const MusicXmlScoreParser(),
              ),
              scoreSerializerProvider.overrideWithValue(
                const MusicXmlScoreSerializer(),
              ),
              scoreEditorChordWindowProvider.overrideWithValue(
                const Duration(milliseconds: 10),
              ),
            ],
            child: MaterialApp(
              home: ScoreEditorScreen(
                sessionId: session,
                initialPiece: piece,
                initialVariant: missingVariant,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final practiceBtn = tester.widget<IconButton>(
          find.byKey(const ValueKey<String>('editor-practice-button')),
        );
        final saveBtn = tester.widget<IconButton>(
          find.byKey(const ValueKey<String>('editor-open-save-button')),
        );
        expect(practiceBtn.onPressed, isNull);
        expect(saveBtn.onPressed, isNull);

        midiRepo.emitNoteOn(60);
        await tester.pump(const Duration(milliseconds: 20));
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ScoreEditorScreen)),
        );
        final state = container.read(scoreEditorControllerProvider(session));
        expect(state.loadError, isNotNull);
        expect(state.isDirty, isFalse);
      },
    );

    testWidgets(
      'ScoreSaveSheet shows Attach to piece with unfiltered catalog pieces despite active search filter',
      (tester) async {
        final piece = Piece(
          id: 'p_existing',
          title: 'Sonata in C',
          artist: 'W. A. Mozart',
          scale: Scale.fromKeySignature(KeySignature.cMajor),
          variants: <ScoreVariant>[
            ScoreVariant(
              id: 'v_1',
              pieceId: 'p_existing',
              difficultyTier: DifficultyTier.beginner,
              label: 'Beginner',
              fileName: 'sonata.musicxml',
              storedRelativePath: 'scores/v_1.musicxml',
              importedAtMs: 1,
            ),
          ],
        );
        await catalogRepo.createPiece(piece);

        await _pumpEditor(
          tester,
          midiRepo: midiRepo,
          catalogRepo: catalogRepo,
          fileStore: fileStore,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ScoreEditorScreen)),
        );
        final catalogSub = container.listen(
          catalogControllerProvider,
          (_, _) {},
        );
        addTearDown(catalogSub.close);
        container
            .read(catalogQueryProvider.notifier)
            .setSearchText('no_such_piece_filter');
        await tester.pumpAndSettle();
        expect(
          container.read(catalogControllerProvider).value?.pieces,
          isEmpty,
        );

        await _tapByKey(tester, 'editor-open-save-button');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('save-mode-attach-piece')),
          findsOneWidget,
        );
        await _tapByKey(tester, 'save-mode-attach-piece');
        await tester.pumpAndSettle();
        expect(find.text('Sonata in C — W. A. Mozart'), findsOneWidget);
        await _tapByKey(tester, 'save-submit-button');
        await tester.pumpAndSettle();
        final updated = await catalogRepo.getPieceById('p_existing');
        expect(updated?.variants, hasLength(2));
      },
    );
  });
}
