import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/app/app.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/progression/progression.dart';
import 'package:piano_exercises/shared/music/music.dart';

class _StubMidiRepository implements MidiRepository {
  final StreamController<List<MidiDeviceInfo>> _devicesController =
      StreamController<List<MidiDeviceInfo>>.broadcast();
  final StreamController<MidiNoteEvent> _noteEventsController =
      StreamController<MidiNoteEvent>.broadcast();
  final StreamController<MidiBluetoothStatus> _bluetoothController =
      StreamController<MidiBluetoothStatus>.broadcast();

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
    'PianoExercisesApp renders DrillScreen and navigates to BLE-MIDI Connection',
    (tester) async {
      final repository = _StubMidiRepository();
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [midiRepositoryProvider.overrideWithValue(repository)],
          child: const PianoExercisesApp(),
        ),
      );
      await tester.pump();

      expect(find.text('Sight-Reading Drill'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('grand-staff-card')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('midi-status-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('BLE-MIDI Connection'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
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
