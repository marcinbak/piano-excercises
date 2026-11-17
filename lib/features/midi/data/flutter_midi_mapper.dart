import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';
import 'package:piano_exercises/features/midi/domain/midi_device_info.dart';
import 'package:piano_exercises/features/midi/domain/midi_note_event.dart';
import 'package:piano_exercises/features/midi/domain/midi_repository.dart';

/// Maps a plugin [MidiDevice] to a domain [MidiDeviceInfo].
MidiDeviceInfo mapMidiDevice(MidiDevice device) {
  final trimmedName = device.name.trim();
  return MidiDeviceInfo(
    id: device.id,
    name: trimmedName.isEmpty ? 'Unknown MIDI Device' : trimmedName,
    typeLabel: _formatDeviceType(device.type),
    isConnected: device.connected,
    isConnecting: device.connectionState == MidiConnectionState.connecting,
  );
}

String _formatDeviceType(MidiDeviceType type) {
  switch (type) {
    case MidiDeviceType.ble:
      return 'BLE';
    case MidiDeviceType.serial:
      return 'USB / Native';
    case MidiDeviceType.network:
      return 'Network';
    case MidiDeviceType.virtual:
    case MidiDeviceType.ownVirtual:
      return 'Virtual';
    case MidiDeviceType.unknown:
      return 'MIDI';
  }
}

/// Maps plugin [BluetoothState] to domain [MidiBluetoothStatus].
MidiBluetoothStatus mapBluetoothState(BluetoothState state) {
  switch (state) {
    case BluetoothState.poweredOn:
      return MidiBluetoothStatus.poweredOn;
    case BluetoothState.poweredOff:
      return MidiBluetoothStatus.poweredOff;
    case BluetoothState.unauthorized:
      return MidiBluetoothStatus.unauthorized;
    case BluetoothState.unsupported:
      return MidiBluetoothStatus.unsupported;
    case BluetoothState.resetting:
    case BluetoothState.unknown:
    case BluetoothState.other:
      return MidiBluetoothStatus.unknown;
  }
}

/// Maps a [MidiDataReceivedEvent] to a normalized [MidiNoteEvent], or `null` if
/// the message is not Note On/Off or has out-of-range MIDI bytes.
MidiNoteEvent? mapMidiDataEvent(MidiDataReceivedEvent event) {
  final message = event.message;
  if (message is NoteOnMessage) {
    return MidiNoteEvent.tryFromChannelMessage(
      noteNumber: message.note,
      velocity: message.velocity,
      isNoteOn: true,
      channel: message.channel,
      deviceId: event.device.id,
      timestampMs: event.timestamp,
    );
  }
  if (message is NoteOffMessage) {
    return MidiNoteEvent.tryFromChannelMessage(
      noteNumber: message.note,
      velocity: message.velocity,
      isNoteOn: false,
      channel: message.channel,
      deviceId: event.device.id,
      timestampMs: event.timestamp,
    );
  }
  return null;
}
