import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/midi/midi.dart';

class _FakeMidiRepository implements MidiRepository {
  final StreamController<List<MidiDeviceInfo>> devicesController =
      StreamController<List<MidiDeviceInfo>>.broadcast();
  final StreamController<MidiNoteEvent> noteEventsController =
      StreamController<MidiNoteEvent>.broadcast();
  final StreamController<MidiBluetoothStatus> bluetoothController =
      StreamController<MidiBluetoothStatus>.broadcast();

  List<MidiDeviceInfo> initialDevices = const <MidiDeviceInfo>[];

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
  Future<List<MidiDeviceInfo>> currentDevices() async => initialDevices;

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

void main() {
  late _FakeMidiRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = _FakeMidiRepository();
    container = ProviderContainer(
      overrides: [midiRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() async {
    container.dispose();
    await repository.dispose();
  });

  test('midiNoteEventsProvider forwards live note events', () async {
    final received = <MidiNoteEvent>[];
    final sub = container.listen(midiNoteEventsProvider, (_, next) {
      final value = next.value;
      if (value != null) {
        received.add(value);
      }
    });

    final noteOn = MidiNoteEvent.fromChannelMessage(
      noteNumber: 60,
      velocity: 96,
      isNoteOn: true,
      channel: 0,
      deviceId: 'ble-1',
      timestampMs: 12,
    );
    repository.noteEventsController.add(noteOn);
    await Future<void>.delayed(Duration.zero);

    expect(received, <MidiNoteEvent>[noteOn]);
    sub.close();
  });

  test('connectedMidiDevicesProvider filters to connected devices', () async {
    const connected = MidiDeviceInfo(
      id: 'ble-1',
      name: 'FP-30X',
      typeLabel: 'BLE',
      isConnected: true,
    );
    const disconnected = MidiDeviceInfo(
      id: 'ble-2',
      name: 'P-225',
      typeLabel: 'BLE',
      isConnected: false,
    );
    repository.initialDevices = const <MidiDeviceInfo>[connected, disconnected];

    final devicesSub = container.listen(midiDevicesProvider, (_, _) {});
    final connectedSub = container.listen(
      connectedMidiDevicesProvider,
      (_, _) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(connectedSub.read(), const <MidiDeviceInfo>[connected]);

    repository.devicesController.add(const <MidiDeviceInfo>[disconnected]);
    await Future<void>.delayed(Duration.zero);
    expect(connectedSub.read(), isEmpty);

    connectedSub.close();
    devicesSub.close();
  });
}
