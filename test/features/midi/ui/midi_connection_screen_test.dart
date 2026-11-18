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
  Future<List<MidiDeviceInfo>> currentDevices() async => devices;

  @override
  Future<void> startScan() async {
    startScanCalls += 1;
    callOrder.add('startScan');
    if (startScanError != null) {
      throw startScanError!;
    }
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls += 1;
    callOrder.add('stopScan');
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
        child: const MaterialApp(home: MidiConnectionScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders Bluetooth status, scan toggle, and dismissible error', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('BLE-MIDI Connection'), findsOneWidget);
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

  testWidgets(
    'manages device connect/disconnect, stops scan on connect, and updates MidiInputCheckCard',
    (tester) async {
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

      expect(
        find.byKey(const ValueKey<String>('midi-input-check-card')),
        findsOneWidget,
      );
      expect(
        find.text('Play any key on your connected piano to verify input.'),
        findsOneWidget,
      );

      repository.devices = const <MidiDeviceInfo>[availableDevice];
      repository.devicesController.add(repository.devices);
      await tester.pump();

      expect(find.text('Yamaha P-225'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);

      await tester.tap(find.text('Scan'));
      await tester.pump();
      expect(find.text('Stop'), findsOneWidget);

      await tester.tap(find.text('Connect'));
      await tester.pump();
      expect(find.text('BLE · Connecting...'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
      expect(repository.callOrder, const <String>[
        'startScan',
        'stopScan',
        'connect:ble-1',
      ]);

      repository.devices = const <MidiDeviceInfo>[connectedDevice];
      repository.devicesController.add(repository.devices);
      connectCompleter.complete();
      await tester.pump();

      expect(find.text('BLE · Connected'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);

      repository.noteEventsController.add(
        MidiNoteEvent.fromChannelMessage(
          noteNumber: 60,
          velocity: 96,
          isNoteOn: true,
          channel: 0,
          deviceId: 'ble-1',
          timestampMs: 42,
        ),
      );
      await tester.pump();

      expect(find.text('C4'), findsOneWidget);
      expect(find.text('Note On'), findsOneWidget);
      expect(find.text('Ch 1'), findsOneWidget);
      expect(find.text('Vel 96'), findsOneWidget);
      expect(find.textContaining('42 ms'), findsNothing);
      expect(find.textContaining('#1'), findsNothing);

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

      expect(find.text('C4'), findsOneWidget);
      expect(find.text('Note Off'), findsOneWidget);
      expect(find.text('Vel 0'), findsOneWidget);
      expect(find.textContaining('84 ms'), findsNothing);
      expect(find.textContaining('#2'), findsNothing);

      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(
        find.text('Play any key on your connected piano to verify input.'),
        findsOneWidget,
      );

      repository.noteEventsController.add(
        MidiNoteEvent.fromChannelMessage(
          noteNumber: 64,
          velocity: 90,
          isNoteOn: true,
          channel: 2,
          deviceId: 'ble-1',
          timestampMs: 300,
        ),
      );
      await tester.pump();
      expect(find.text('E4'), findsOneWidget);
      expect(find.text('Note On'), findsOneWidget);
      expect(find.text('Ch 3'), findsOneWidget);
      expect(find.text('Vel 90'), findsOneWidget);

      await tester.tap(find.text('Disconnect'));
      await tester.pump();
      expect(repository.disconnectCalls, 1);
    },
  );

  testWidgets('route disposal stops active scan cleanly', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [midiRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  unawaited(
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const MidiConnectionScreen(),
                      ),
                    ),
                  );
                },
                child: const Text('Open MIDI'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open MIDI'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan'));
    await tester.pump();
    expect(repository.startScanCalls, 1);
    expect(repository.stopScanCalls, 0);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repository.stopScanCalls, 1);

    // Re-opening displays Scan (not stuck on Stop).
    await tester.tap(find.text('Open MIDI'));
    await tester.pumpAndSettle();
    expect(find.text('Scan'), findsOneWidget);
  });

  testWidgets(
    'lays out without overflow on compact viewports at 1.6x text scale',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const populatedDevices = <MidiDeviceInfo>[
        MidiDeviceInfo(
          id: 'ble-1',
          name: 'Yamaha P-225',
          typeLabel: 'BLE',
          isConnected: true,
        ),
        MidiDeviceInfo(
          id: 'ble-2',
          name: 'Roland FP-30X',
          typeLabel: 'BLE',
          isConnected: false,
          isConnecting: true,
        ),
        MidiDeviceInfo(
          id: 'ble-3',
          name: 'Kawai ES120',
          typeLabel: 'BLE',
          isConnected: false,
        ),
      ];

      for (final surfaceSize in const <Size>[Size(360, 420), Size(780, 340)]) {
        await tester.binding.setSurfaceSize(surfaceSize);

        // 1) Loading state + Permission Denied pill + error banner
        final loadingRepo = _FakeMidiRepository()
          ..bluetoothStatus = MidiBluetoothStatus.unauthorized
          ..startScanError = const MidiOperationException(
            'Bluetooth permission denied for BLE-MIDI scanning.',
          );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [midiRepositoryProvider.overrideWithValue(loadingRepo)],
            child: const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: MaterialApp(home: MidiConnectionScreen()),
            ),
          ),
        );
        await tester.tap(find.text('Scan'));
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Overflow in loading state at $surfaceSize',
        );
        await loadingRepo.dispose();

        // 2) Empty state
        final emptyRepo = _FakeMidiRepository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [midiRepositoryProvider.overrideWithValue(emptyRepo)],
            child: const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: MaterialApp(home: MidiConnectionScreen()),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Overflow in empty state at $surfaceSize',
        );
        await emptyRepo.dispose();

        // 3) Populated (3 devices) + error banner + active InputCheckCard
        final populatedRepo = _FakeMidiRepository()
          ..devices = populatedDevices
          ..startScanError = const MidiOperationException(
            'Connection timed out while pairing with device.',
          );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              midiRepositoryProvider.overrideWithValue(populatedRepo),
            ],
            child: const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: MaterialApp(home: MidiConnectionScreen()),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Scan'));
        populatedRepo.noteEventsController.add(
          MidiNoteEvent.fromChannelMessage(
            noteNumber: 61,
            velocity: 112,
            isNoteOn: true,
            channel: 15,
            deviceId: 'ble-1',
            timestampMs: 99,
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Overflow in populated state at $surfaceSize',
        );
        await populatedRepo.dispose();
      }
    },
  );
}
