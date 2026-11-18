import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/app/app.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/progression/progression.dart';

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
}
