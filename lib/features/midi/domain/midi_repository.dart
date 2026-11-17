import 'package:piano_exercises/features/midi/domain/midi_device_info.dart';
import 'package:piano_exercises/features/midi/domain/midi_note_event.dart';

/// Host Bluetooth adapter availability state relevant to BLE-MIDI discovery.
enum MidiBluetoothStatus {
  unknown,
  poweredOn,
  poweredOff,
  unauthorized,
  unsupported,
}

/// Domain-level failure raised by MIDI discovery or connection operations.
final class MidiOperationException implements Exception {
  const MidiOperationException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Boundary interface for MIDI device discovery, connection lifecycle, and note input.
abstract interface class MidiRepository {
  Stream<List<MidiDeviceInfo>> get devicesStream;
  Stream<MidiNoteEvent> get noteEventsStream;
  Stream<MidiBluetoothStatus> get bluetoothStateStream;
  MidiBluetoothStatus get currentBluetoothStatus;

  Future<List<MidiDeviceInfo>> currentDevices();
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(MidiDeviceInfo device);
  Future<void> disconnect(MidiDeviceInfo device);
  Future<void> dispose();
}
