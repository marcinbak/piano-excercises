import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/shared/music/music.dart';

class _RecordingBleTransport extends MidiBleTransport {
  final MidiDevice testDevice = MidiDevice(
    'ble-1',
    'Test BLE Piano',
    MidiDeviceType.ble,
    false,
  );
  final List<({Uint8List data, String? deviceId})> sentPackets =
      <({Uint8List data, String? deviceId})>[];
  bool throwOnSend = false;
  Completer<void>? writeBarrier;

  @override
  Future<void> startBluetooth() async {}

  @override
  Future<String> bluetoothState() async => 'poweredOn';

  @override
  Stream<String> get onBluetoothStateChanged => const Stream<String>.empty();

  @override
  Future<void> startScanningForBluetoothDevices() async {}

  @override
  void stopScanningForBluetoothDevices() {}

  @override
  Future<List<MidiDevice>> get devices async => <MidiDevice>[testDevice];

  @override
  Future<void> connectToDevice(
    MidiDevice device, {
    List<MidiPort>? ports,
    Duration? timeout,
  }) async {
    device.connected = true;
  }

  @override
  void disconnectDevice(MidiDevice device) {
    device.connected = false;
  }

  @override
  void sendData(Uint8List data, {int? timestamp, String? deviceId}) {
    if (throwOnSend) {
      throw StateError('Simulated BLE disconnect');
    }
    sentPackets.add((data: Uint8List.fromList(data), deviceId: deviceId));
  }

  @override
  Future<void> sendDataAwaitingDelivery(
    Uint8List data, {
    int? timestamp,
    String? deviceId,
  }) async {
    final barrier = writeBarrier;
    if (barrier != null) {
      await barrier.future;
    }
    sendData(data, timestamp: timestamp, deviceId: deviceId);
  }

  @override
  Stream<MidiPacket> get onMidiDataReceived => const Stream<MidiPacket>.empty();

  @override
  Stream<MidiSetupChange> get onMidiSetupChanged =>
      const Stream<MidiSetupChange>.empty();

  @override
  void teardown() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterMidiOutputSink & NoopMidiOutputSink', () {
    late _RecordingBleTransport bleTransport;
    late MidiCommand command;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MidiCommand.resetForTest();
      bleTransport = _RecordingBleTransport();
      command = MidiCommand(bleTransport: bleTransport);
      await command.connectToDevice(bleTransport.testDevice);
    });

    tearDown(() {
      MidiCommand.resetForTest();
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'NoopMidiOutputSink completes Note On/Off/AllNotesOff safely',
      () async {
        const noop = NoopMidiOutputSink();
        await noop.sendNoteOn(const MidiNote(60), velocity: 100);
        await noop.sendNoteOff(const MidiNote(60));
        await noop.sendAllNotesOff();
      },
    );

    test(
      'encodes MIDI Note On, Note Off, and explicit AllNotesOff bytes',
      () async {
        final sink = FlutterMidiOutputSink(midiCommand: command);

        await sink.sendNoteOn(
          const MidiNote(60),
          velocity: 100,
          channel: 0,
          deviceId: 'ble-1',
        );
        await sink.sendNoteOn(
          const MidiNote(64),
          velocity: 90,
          channel: 0,
          deviceId: 'ble-1',
        );
        expect(bleTransport.sentPackets, hasLength(2));
        expect(bleTransport.sentPackets[0].data, <int>[0x90, 60, 100]);
        expect(bleTransport.sentPackets[1].data, <int>[0x90, 64, 90]);

        await sink.sendNoteOff(
          const MidiNote(60),
          channel: 0,
          deviceId: 'ble-1',
        );
        expect(bleTransport.sentPackets[2].data, <int>[0x80, 60, 0]);

        bleTransport.sentPackets.clear();
        await sink.sendAllNotesOff(channel: 0, deviceId: 'ble-1');
        expect(
          bleTransport.sentPackets.map((p) => p.data.toList()).toList(),
          <List<int>>[
            <int>[0x80, 64, 0],
            <int>[0xB0, 123, 0],
            <int>[0xB0, 64, 0],
          ],
        );
      },
    );

    test('swallows transport write errors without crashing', () async {
      final sink = FlutterMidiOutputSink(midiCommand: command);
      bleTransport.throwOnSend = true;

      await sink.sendNoteOn(const MidiNote(60), deviceId: 'ble-1');
      await sink.sendNoteOff(const MidiNote(60), deviceId: 'ble-1');
      await sink.sendAllNotesOff(deviceId: 'ble-1');
    });

    test('serializes unawaited sendAllNotesOff strictly ahead of subsequent sendNoteOn', () async {
      final sink = FlutterMidiOutputSink(midiCommand: command);
      await sink.sendNoteOn(const MidiNote(60), deviceId: 'ble-1');
      bleTransport.sentPackets.clear();

      final barrier = Completer<void>();
      bleTransport.writeBarrier = barrier;

      final allOffFuture = sink.sendAllNotesOff(deviceId: 'ble-1');
      final nextNoteFuture = sink.sendNoteOn(
        const MidiNote(67),
        velocity: 88,
        deviceId: 'ble-1',
      );

      barrier.complete();
      await Future.wait(<Future<void>>[allOffFuture, nextNoteFuture]);

      // AllNotesOff (0x80 60, 0xB0 123, 0xB0 64) must precede the new Note On (0x90 67).
      expect(
        bleTransport.sentPackets.map((p) => p.data.toList()).toList(),
        <List<int>>[
          <int>[0x80, 60, 0],
          <int>[0xB0, 123, 0],
          <int>[0xB0, 64, 0],
          <int>[0x90, 67, 88],
        ],
      );
    });
  });
}
