import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/app/app.dart';
import 'package:piano_exercises/app/app_navigation_shell.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/drill/drill.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/piece_practice/piece_practice.dart';
import 'package:piano_exercises/features/progression/progression.dart';
import 'package:piano_exercises/shared/music/music.dart';

class _StubMidiRepository implements MidiRepository {
  final StreamController<List<MidiDeviceInfo>> _devicesController =
      StreamController<List<MidiDeviceInfo>>.broadcast();
  final StreamController<MidiNoteEvent> _noteEventsController =
      StreamController<MidiNoteEvent>.broadcast();
  final StreamController<MidiBluetoothStatus> _bluetoothController =
      StreamController<MidiBluetoothStatus>.broadcast();

  void emitNoteOn(int noteNumber) {
    _noteEventsController.add(
      MidiNoteEvent.fromChannelMessage(
        noteNumber: noteNumber,
        velocity: 96,
        isNoteOn: true,
        channel: 0,
        deviceId: 'ble-1',
        timestampMs: 0,
      ),
    );
  }

  void emitNoteOff(int noteNumber) {
    _noteEventsController.add(
      MidiNoteEvent.fromChannelMessage(
        noteNumber: noteNumber,
        velocity: 0,
        isNoteOn: false,
        channel: 0,
        deviceId: 'ble-1',
        timestampMs: 0,
      ),
    );
  }

  @override
  Stream<List<MidiDeviceInfo>> get devicesStream => _devicesController.stream;

  @override
  Stream<MidiNoteEvent> get noteEventsStream => _noteEventsController.stream;

  @override
  Stream<MidiBluetoothStatus> get bluetoothStateStream =>
      _bluetoothController.stream;

  @override
  MidiBluetoothStatus get currentBluetoothStatus => MidiBluetoothStatus.unknown;

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
    await _devicesController.close();
    await _noteEventsController.close();
    await _bluetoothController.close();
  }
}

void main() {
  testWidgets(
    'AppNavigationShell switches Drill <-> Catalog, shares midi-status-button, and enforces DrillController pause matrix',
    (tester) async {
      final midiRepo = _StubMidiRepository();
      final catalogRepo = InMemoryCatalogRepository();
      final fileStore = InMemoryScoreFileStore();
      addTearDown(() async {
        await midiRepo.dispose();
        await catalogRepo.close();
      });

      final sampleBytes = Uint8List.fromList(
        File('test/fixtures/simplified_melody_bass.musicxml').readAsBytesSync(),
      );
      await fileStore.saveScoreBytes(
        variantId: 'v1',
        format: ScoreFormat.musicXml,
        bytes: sampleBytes,
      );
      await catalogRepo.createPiece(
        Piece(
          id: 'p1',
          title: 'Simple Waltz',
          artist: 'Bach',
          scale: Scale.fromKeySignature(const KeySignature(1)),
          variants: <ScoreVariant>[
            ScoreVariant(
              id: 'v1',
              pieceId: 'p1',
              difficultyTier: DifficultyTier.beginner,
              label: 'Easy',
              fileName: 'simplified_melody_bass.musicxml',
              storedRelativePath: 'scores/v1.musicxml',
              importedAtMs: 1,
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            midiRepositoryProvider.overrideWithValue(midiRepo),
            catalogRepositoryProvider.overrideWithValue(catalogRepo),
            scoreFileStoreProvider.overrideWithValue(fileStore),
            scoreParserProvider.overrideWithValue(const MusicXmlScoreParser()),
            drillRandomIntProvider.overrideWithValue((_) => 0),
          ],
          child: const PianoExercisesApp(),
        ),
      );
      await tester.pumpAndSettle();

      final shellContext = tester.element(find.byType(AppNavigationShell));
      final container = ProviderScope.containerOf(shellContext);

      // Default tab is Drill; DrillController starts unpaused.
      expect(find.text('Sight-Reading Drill'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('grand-staff-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('midi-status-button')),
        findsOneWidget,
      );
      expect(
        container.read(drillControllerProvider.notifier).isPaused,
        isFalse,
      );

      // Switch Drill -> Catalog: DrillController pauses and ignores MIDI notes.
      await tester.tap(find.byKey(const ValueKey<String>('shell_nav_catalog')));
      await tester.pumpAndSettle();
      expect(find.text('Piece Catalog'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('midi-status-button')),
        findsOneWidget,
      );
      expect(container.read(drillControllerProvider.notifier).isPaused, isTrue);

      midiRepo.emitNoteOn(61);
      await tester.pump(const Duration(milliseconds: 40));
      midiRepo.emitNoteOff(61);
      await tester.pump();
      expect(container.read(drillControllerProvider).lastResult, isNull);

      // Open MidiConnectionScreen from Catalog and pop back -> Drill stays paused!
      await tester.tap(
        find.byKey(const ValueKey<String>('midi-status-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('BLE-MIDI Connection'), findsOneWidget);
      expect(container.read(drillControllerProvider.notifier).isPaused, isTrue);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Piece Catalog'), findsOneWidget);
      expect(container.read(drillControllerProvider.notifier).isPaused, isTrue);

      // Open PieceScoreScreen from Catalog -> Drill stays paused during & after pop.
      await tester.tap(find.byKey(const ValueKey<String>('open_variant_v1')));
      await tester.pumpAndSettle();
      expect(find.byType(PieceScoreScreen), findsOneWidget);
      expect(container.read(drillControllerProvider.notifier).isPaused, isTrue);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Piece Catalog'), findsOneWidget);
      expect(container.read(drillControllerProvider.notifier).isPaused, isTrue);

      // Switch Catalog -> Drill: DrillController resumes and grades MIDI notes.
      await tester.tap(find.byKey(const ValueKey<String>('shell_nav_drill')));
      await tester.pumpAndSettle();
      expect(
        container.read(drillControllerProvider.notifier).isPaused,
        isFalse,
      );

      midiRepo.emitNoteOn(60);
      await tester.pump(const Duration(milliseconds: 40));
      midiRepo.emitNoteOff(60);
      await tester.pump();
      expect(
        container.read(drillControllerProvider).lastResult?.status,
        DrillFeedbackStatus.correct,
      );
    },
  );

  testWidgets(
    'AppNavigationShell renders NavigationRail cleanly at 800x360 @ 1.6x with zero overflow across tabs',
    (tester) async {
      final midiRepo = _StubMidiRepository();
      addTearDown(midiRepo.dispose);
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [midiRepositoryProvider.overrideWithValue(midiRepo)],
          child: const PianoExercisesApp(
            home: AppNavigationShell(initialTab: AppShellTab.catalog),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppNavigationShell)),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Piece Catalog'), findsOneWidget);
      expect(container.read(drillControllerProvider.notifier).isPaused, isTrue);

      await tester.tap(find.byKey(const ValueKey<String>('shell_nav_drill')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Sight-Reading Drill'), findsOneWidget);
      expect(
        container.read(drillControllerProvider.notifier).isPaused,
        isFalse,
      );
    },
  );

  test('bootstrapPianoExercisesRoot passes created repository and falls back to in-memory on init failure', () async {
    final provided = InMemoryProgressionRepository();
    final normalRoot = await bootstrapPianoExercisesRoot(
      createProgressionRepository: () async => provided,
    );
    expect(normalRoot.progressionRepository, same(provided));

    final fallbackRoot = await bootstrapPianoExercisesRoot(
      createProgressionRepository: () async {
        throw StateError('Simulated storage plugin failure');
      },
    );
    expect(
      fallbackRoot.progressionRepository,
      isA<InMemoryProgressionRepository>(),
    );
  });

  test('bootstrapPianoExercisesRoot skips purgeOrphans when catalog repository falls back', () async {
    final spyStore = _SpyScoreFileStore();
    final rootOnFailure = await bootstrapPianoExercisesRoot(
      createProgressionRepository: () async => InMemoryProgressionRepository(),
      createCatalogRepository: () async {
        throw StateError('Simulated SQLite failure');
      },
      createScoreFileStore: () async => spyStore,
    );
    expect(rootOnFailure.catalogRepository, isA<InMemoryCatalogRepository>());
    expect(spyStore.purgeOrphansCalls, 0);

    final repo = InMemoryCatalogRepository();
    addTearDown(repo.close);
    await repo.createPiece(
      Piece(
        id: 'p1',
        title: 'Sonata',
        artist: 'Mozart',
        scale: Scale.fromKeySignature(KeySignature.cMajor),
        variants: <ScoreVariant>[
          ScoreVariant(
            id: 'v1',
            pieceId: 'p1',
            difficultyTier: DifficultyTier.beginner,
            label: 'Beginner',
            fileName: 'sonata.mxl',
            storedRelativePath: 'scores/v1.mxl',
            importedAtMs: 1,
          ),
        ],
      ),
    );
    await bootstrapPianoExercisesRoot(
      createProgressionRepository: () async => InMemoryProgressionRepository(),
      createCatalogRepository: () async => repo,
      createScoreFileStore: () async => spyStore,
    );
    expect(spyStore.purgeOrphansCalls, 1);
    expect(spyStore.lastActivePaths, {'scores/v1.mxl'});
  });
}

class _SpyScoreFileStore implements ScoreFileStore {
  final InMemoryScoreFileStore _delegate = InMemoryScoreFileStore();
  int purgeOrphansCalls = 0;
  Set<String>? lastActivePaths;

  @override
  Future<void> deleteScoreFile(String storedRelativePath) =>
      _delegate.deleteScoreFile(storedRelativePath);

  @override
  Future<int> purgeOrphans(Set<String> activeRelativePaths) async {
    purgeOrphansCalls += 1;
    lastActivePaths = Set<String>.of(activeRelativePaths);
    return _delegate.purgeOrphans(activeRelativePaths);
  }

  @override
  Future<Uint8List> readScoreBytes(String storedRelativePath) =>
      _delegate.readScoreBytes(storedRelativePath);

  @override
  Future<String> saveScoreBytes({
    required String variantId,
    required ScoreFormat format,
    required Uint8List bytes,
  }) => _delegate.saveScoreBytes(
    variantId: variantId,
    format: format,
    bytes: bytes,
  );
}
