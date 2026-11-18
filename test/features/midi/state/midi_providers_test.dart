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
  MidiBluetoothStatus bluetoothStatus = MidiBluetoothStatus.unknown;

  Object? startScanError;
  Object? stopScanError;
  Future<void> Function()? onStartScan;
  Future<void> Function(MidiDeviceInfo device)? onConnect;
  Future<void> Function(MidiDeviceInfo device)? onDisconnect;

  int startScanCalls = 0;
  int stopScanCalls = 0;
  final List<String> callOrder = <String>[];

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
  Future<List<MidiDeviceInfo>> currentDevices() async => initialDevices;

  @override
  Future<void> startScan() async {
    startScanCalls += 1;
    callOrder.add('startScan');
    if (onStartScan != null) {
      await onStartScan!();
    }
    if (startScanError != null) {
      throw startScanError!;
    }
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls += 1;
    callOrder.add('stopScan');
    if (stopScanError != null) {
      throw stopScanError!;
    }
  }

  @override
  Future<void> connect(MidiDeviceInfo device) async {
    callOrder.add('connect:${device.id}');
    if (onConnect != null) {
      await onConnect!(device);
    }
  }

  @override
  Future<void> disconnect(MidiDeviceInfo device) async {
    if (onDisconnect != null) {
      await onDisconnect!(device);
    }
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

  test('midiDevicesProvider emits initial snapshot and updates', () async {
    const piano = MidiDeviceInfo(
      id: 'ble-1',
      name: 'FP-30X',
      typeLabel: 'BLE',
      isConnected: false,
    );
    repository.initialDevices = const <MidiDeviceInfo>[];

    final sub = container.listen(midiDevicesProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value, isEmpty);

    repository.devicesController.add(const <MidiDeviceInfo>[piano]);
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value, const <MidiDeviceInfo>[piano]);
    sub.close();
  });

  test('midiScanControllerProvider toggles scan and surfaces errors', () async {
    final controller = container.read(midiScanControllerProvider.notifier);

    await controller.startScan();
    expect(repository.startScanCalls, 1);
    expect(container.read(midiScanControllerProvider).isScanning, isTrue);

    await controller.stopScan();
    expect(repository.stopScanCalls, 1);
    expect(container.read(midiScanControllerProvider).isScanning, isFalse);

    repository.startScanError = const MidiOperationException(
      'Bluetooth is off',
    );
    await controller.startScan();
    final afterError = container.read(midiScanControllerProvider);
    expect(afterError.isScanning, isFalse);
    expect(afterError.errorMessage, 'Bluetooth is off');

    controller.dismissError();
    expect(container.read(midiScanControllerProvider).errorMessage, isNull);
  });

  test(
    'connect tracks in-flight device and surfaces connection errors',
    () async {
      const device = MidiDeviceInfo(
        id: 'ble-1',
        name: 'Kawai ES120',
        typeLabel: 'BLE',
        isConnected: false,
      );
      final pendingConnect = Completer<void>();
      repository.onConnect = (_) => pendingConnect.future;

      final controller = container.read(midiScanControllerProvider.notifier);
      final connectFuture = controller.connect(device);
      expect(
        container.read(midiScanControllerProvider).connectingDeviceId,
        'ble-1',
      );

      pendingConnect.completeError(
        const MidiOperationException('Pairing was rejected'),
      );
      await connectFuture;

      final state = container.read(midiScanControllerProvider);
      expect(state.connectingDeviceId, isNull);
      expect(state.errorMessage, 'Pairing was rejected');
    },
  );

  test(
    'midiNoteLogProvider keeps newest 30 events and supports clear',
    () async {
      final sub = container.listen(midiNoteLogProvider, (_, _) {});
      for (var i = 0; i < 35; i += 1) {
        repository.noteEventsController.add(
          MidiNoteEvent.fromChannelMessage(
            noteNumber: 40 + i,
            velocity: 100,
            isNoteOn: true,
            channel: 0,
            deviceId: 'ble-1',
            timestampMs: i,
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);

      final log = sub.read();
      expect(log.length, 30);
      expect(log.first.sequence, 35);
      expect(log.first.event.noteNumber, 74);
      expect(log.last.sequence, 6);
      expect(log.last.event.noteNumber, 45);

      container.read(midiNoteLogProvider.notifier).clear();
      expect(sub.read(), isEmpty);

      repository.noteEventsController.add(
        MidiNoteEvent.fromChannelMessage(
          noteNumber: 60,
          velocity: 80,
          isNoteOn: true,
          channel: 0,
          deviceId: 'ble-1',
          timestampMs: 500,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sub.read().single.sequence, 1);
      sub.close();
    },
  );

  test('scanning stops automatically if Bluetooth turns off', () async {
    final sub = container.listen(midiScanControllerProvider, (_, _) {});
    final controller = container.read(midiScanControllerProvider.notifier);

    await controller.startScan();
    expect(sub.read().isScanning, isTrue);

    repository.bluetoothStatus = MidiBluetoothStatus.poweredOff;
    repository.bluetoothController.add(MidiBluetoothStatus.poweredOff);
    await Future<void>.delayed(Duration.zero);

    expect(sub.read().isScanning, isFalse);
    expect(repository.stopScanCalls, 1);
    sub.close();
  });

  test(
    'stopScan cancels an in-flight startScan once startScan resolves',
    () async {
      final pendingStart = Completer<void>();
      repository.onStartScan = () => pendingStart.future;

      final sub = container.listen(midiScanControllerProvider, (_, _) {});
      final controller = container.read(midiScanControllerProvider.notifier);

      final startFuture = controller.startScan();
      expect(sub.read().isScanning, isTrue);
      expect(repository.startScanCalls, 1);

      await controller.stopScan();
      expect(sub.read().isScanning, isFalse);
      expect(repository.stopScanCalls, 1);

      pendingStart.complete();
      await startFuture;

      expect(sub.read().isScanning, isFalse);
      expect(sub.read().errorMessage, isNull);
      expect(repository.stopScanCalls, 2);
      sub.close();
    },
  );

  test(
    'disposing while startScan is pending stops scan without throwing',
    () async {
      final pendingStart = Completer<void>();
      repository.onStartScan = () => pendingStart.future;

      final sub = container.listen(midiScanControllerProvider, (_, _) {});
      final controller = container.read(midiScanControllerProvider.notifier);

      final startFuture = controller.startScan();
      expect(sub.read().isScanning, isTrue);

      container.dispose();
      expect(repository.stopScanCalls, 1);

      pendingStart.complete();
      await expectLater(startFuture, completes);
      expect(repository.stopScanCalls, 2);
    },
  );

  test(
    'startScan surfaces error when Bluetooth becomes poweredOff mid-flight',
    () async {
      repository.bluetoothStatus = MidiBluetoothStatus.unknown;
      repository.onStartScan = () async {
        repository.bluetoothStatus = MidiBluetoothStatus.poweredOff;
        repository.bluetoothController.add(MidiBluetoothStatus.poweredOff);
        // Yield a turn so ref.listen processes poweredOff before startScan throws.
        await Future<void>.delayed(Duration.zero);
        throw const MidiOperationException('Bluetooth is turned off.');
      };

      final sub = container.listen(midiScanControllerProvider, (_, _) {});
      final controller = container.read(midiScanControllerProvider.notifier);

      await controller.startScan();

      expect(sub.read().isScanning, isFalse);
      expect(sub.read().errorMessage, 'Bluetooth is turned off.');
      sub.close();
    },
  );

  test('connect stops an active scan before connecting', () async {
    const device = MidiDeviceInfo(
      id: 'ble-1',
      name: 'FP-30X',
      typeLabel: 'BLE',
      isConnected: false,
    );
    final sub = container.listen(midiScanControllerProvider, (_, _) {});
    final controller = container.read(midiScanControllerProvider.notifier);

    await controller.startScan();
    expect(sub.read().isScanning, isTrue);

    await controller.connect(device);
    expect(sub.read().isScanning, isFalse);
    expect(sub.read().connectingDeviceId, isNull);
    expect(repository.callOrder, const <String>[
      'startScan',
      'stopScan',
      'connect:ble-1',
    ]);
    sub.close();
  });
}
