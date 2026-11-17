import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/midi/data/flutter_midi_mapper.dart';
import 'package:piano_exercises/features/midi/domain/midi_repository.dart';

void main() {
  group('mapMidiDevice', () {
    test('maps device fields and trims empty names', () {
      final ble = MidiDevice('id-1', '  FP-30X  ', MidiDeviceType.ble, true);
      final unnamed = MidiDevice('id-2', '   ', MidiDeviceType.serial, false)
        ..setConnectionState(MidiConnectionState.connecting);

      final mappedBle = mapMidiDevice(ble);
      expect(mappedBle.id, 'id-1');
      expect(mappedBle.name, 'FP-30X');
      expect(mappedBle.typeLabel, 'BLE');
      expect(mappedBle.isConnected, isTrue);
      expect(mappedBle.isConnecting, isFalse);

      final mappedUnnamed = mapMidiDevice(unnamed);
      expect(mappedUnnamed.name, 'Unknown MIDI Device');
      expect(mappedUnnamed.typeLabel, 'USB / Native');
      expect(mappedUnnamed.isConnected, isFalse);
      expect(mappedUnnamed.isConnecting, isTrue);
    });
  });

  group('mapBluetoothState', () {
    test('maps all plugin BluetoothState values', () {
      expect(
        mapBluetoothState(BluetoothState.poweredOn),
        MidiBluetoothStatus.poweredOn,
      );
      expect(
        mapBluetoothState(BluetoothState.poweredOff),
        MidiBluetoothStatus.poweredOff,
      );
      expect(
        mapBluetoothState(BluetoothState.unauthorized),
        MidiBluetoothStatus.unauthorized,
      );
      expect(
        mapBluetoothState(BluetoothState.unsupported),
        MidiBluetoothStatus.unsupported,
      );
      expect(
        mapBluetoothState(BluetoothState.resetting),
        MidiBluetoothStatus.unknown,
      );
      expect(
        mapBluetoothState(BluetoothState.unknown),
        MidiBluetoothStatus.unknown,
      );
    });
  });

  group('mapMidiDataEvent', () {
    final device = MidiDevice('ble-1', 'Piano', MidiDeviceType.ble, true);

    test('maps NoteOn, velocity-0 NoteOn, and NoteOff safely', () {
      final noteOn = mapMidiDataEvent(
        MidiDataReceivedEvent(
          message: NoteOnMessage(channel: 0, note: 60, velocity: 90),
          device: device,
          transport: MidiTransport.ble,
          timestamp: 100,
        ),
      );
      expect(noteOn?.isNoteOn, isTrue);
      expect(noteOn?.noteNumber, 60);
      expect(noteOn?.velocity, 90);

      final velocityZero = mapMidiDataEvent(
        MidiDataReceivedEvent(
          message: NoteOnMessage(channel: 0, note: 60, velocity: 0),
          device: device,
          transport: MidiTransport.ble,
          timestamp: 110,
        ),
      );
      expect(velocityZero?.isNoteOn, isFalse);

      final noteOff = mapMidiDataEvent(
        MidiDataReceivedEvent(
          message: NoteOffMessage(channel: 1, note: 64, velocity: 50),
          device: device,
          transport: MidiTransport.ble,
          timestamp: 120,
        ),
      );
      expect(noteOff?.isNoteOn, isFalse);
      expect(noteOff?.channel, 1);
    });

    test('ignores out-of-range bytes and non-note messages', () {
      expect(
        mapMidiDataEvent(
          MidiDataReceivedEvent(
            message: NoteOnMessage(channel: 0, note: 200, velocity: 64),
            device: device,
            transport: MidiTransport.ble,
            timestamp: 130,
          ),
        ),
        isNull,
      );
      expect(
        mapMidiDataEvent(
          MidiDataReceivedEvent(
            message: NoteOnMessage(channel: 0, note: 60, velocity: -1),
            device: device,
            transport: MidiTransport.ble,
            timestamp: 140,
          ),
        ),
        isNull,
      );
      expect(
        mapMidiDataEvent(
          MidiDataReceivedEvent(
            message: CCMessage(channel: 0, controller: 64, value: 127),
            device: device,
            transport: MidiTransport.ble,
            timestamp: 150,
          ),
        ),
        isNull,
      );
    });
  });
}
