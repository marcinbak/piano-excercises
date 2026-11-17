import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/midi/midi.dart';

class _FakeMidiRepository implements MidiRepository {
  final StreamController<List<MidiDeviceInfo>> devicesController =
      StreamController<List<MidiDeviceInfo>>.broadcast();
  final StreamController<MidiNoteEvent> noteEventsController =
      StreamController<MidiNoteEvent>.broadcast();
  final StreamController<MidiBluetoothStatus> bluetoothController =
      StreamController<MidiBluetoothStatus>.broadcast();

  List<MidiDeviceInfo> devices = const <MidiDeviceInfo>[];
  MidiBluetoothStatus bluetoothStatus = MidiBluetoothStatus.poweredOn;

  Object? startScanError;
  Future<void> Function(MidiDeviceInfo device)? onConnect;
  int startScanCalls = 0;
  int stopScanCalls = 0;
  int disconnectCalls = 0;

  @override
  Stream<List<MidiDeviceInfo>> get devicesStream => devicesController.stream;

  @override
  Stream<MidiNoteEvent> get noteEventsStream => noteEventsController.stream;

  @override
  Stream<MidiBluetoothStatus> get bluetoothStateStream =>
      bluetoothController.stream;

  @override
  MidiBluetoothStatus get currentBluetoothStatus => bluetoothStatus;

  @override
  Future<List<MidiDeviceInfo>> currentDevices() async => devices;

  @override
  Future<void> startScan() async {
    startScanCalls += 1;
    if (startScanError != null) {
      throw startScanError!;
    }
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls += 1;
  }

  @override
  Future<void> connect(MidiDeviceInfo device) async {
    if (onConnect != null) {
      await onConnect!(device);
    }
  }

  @override
  Future<void> disconnect(MidiDeviceInfo device) async {
    disconnectCalls += 1;
  }

  @override
  Future<void> dispose() async {
    await devicesController.close();
    await noteEventsController.close();
    await bluetoothController.close();
  }
}

void main() {
  late _FakeMidiRepository repository;

  setUp(() {
    repository = _FakeMidiRepository();
  });

  tearDown(() async {
    await repository.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [midiRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: MidiSpikeScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders Bluetooth status, scan toggle, and dismissible error', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('BLE-MIDI Spike'), findsOneWidget);
    expect(find.text('Bluetooth On'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);

    await tester.tap(find.text('Scan'));
    await tester.pump();
    expect(repository.startScanCalls, 1);
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(repository.stopScanCalls, 1);
    expect(find.text('Scan'), findsOneWidget);

    repository.startScanError = const MidiOperationException(
      'Bluetooth permission denied',
    );
    await tester.tap(find.text('Scan'));
    await tester.pump();
    expect(find.text('Bluetooth permission denied'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss error'));
    await tester.pump();
    expect(find.text('Bluetooth permission denied'), findsNothing);
  });

  testWidgets('displays discovered devices and live note feed', (tester) async {
    const availableDevice = MidiDeviceInfo(
      id: 'ble-1',
      name: 'Yamaha P-225',
      typeLabel: 'BLE',
      isConnected: false,
    );
    const connectedDevice = MidiDeviceInfo(
      id: 'ble-1',
      name: 'Yamaha P-225',
      typeLabel: 'BLE',
      isConnected: true,
    );
    final connectCompleter = Completer<void>();
    repository.onConnect = (_) => connectCompleter.future;

    await pumpScreen(tester);

    repository.devices = const <MidiDeviceInfo>[availableDevice];
    repository.devicesController.add(repository.devices);
    await tester.pump();

    expect(find.text('Yamaha P-225'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('BLE · Connecting...'), findsOneWidget);

    repository.devices = const <MidiDeviceInfo>[connectedDevice];
    repository.devicesController.add(repository.devices);
    connectCompleter.complete();
    await tester.pump();

    expect(find.text('BLE · Connected'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);

    repository.noteEventsController.add(
      MidiNoteEvent.fromChannelMessage(
        noteNumber: 60,
        velocity: 100,
        isNoteOn: true,
        channel: 0,
        deviceId: 'ble-1',
        timestampMs: 42,
      ),
    );
    repository.noteEventsController.add(
      MidiNoteEvent.fromChannelMessage(
        noteNumber: 60,
        velocity: 0,
        isNoteOn: true,
        channel: 0,
        deviceId: 'ble-1',
        timestampMs: 84,
      ),
    );
    await tester.pump();

    expect(find.text('Live Note Events (2)'), findsOneWidget);
    expect(find.text('C4'), findsNWidgets(2));
    expect(find.text('ON'), findsOneWidget);
    expect(find.text('OFF'), findsOneWidget);
    expect(find.text('MIDI 60 · vel 100 · ch 1'), findsOneWidget);
    expect(find.text('MIDI 60 · vel 0 · ch 1'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('Live Note Events (0)'), findsOneWidget);

    await tester.tap(find.text('Disconnect'));
    await tester.pump();
    expect(repository.disconnectCalls, 1);
  });
}
