import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';
import 'package:piano_exercises/features/midi/domain/midi_output_sink.dart';
import 'package:piano_exercises/shared/music/music.dart';

typedef _ActiveMidiNote = ({String? deviceId, int channel, int noteNumber});

/// [MidiOutputSink] backed by `flutter_midi_command` over BLE-MIDI and CoreMIDI/Android MIDI.
class FlutterMidiOutputSink implements MidiOutputSink {
  FlutterMidiOutputSink({MidiCommand? midiCommand})
    : _midiCommand =
          midiCommand ?? MidiCommand(bleTransport: UniversalBleMidiTransport());

  final MidiCommand _midiCommand;
  final Set<_ActiveMidiNote> _activeNotes = <_ActiveMidiNote>{};
  Future<void> _writeChain = Future<void>.value();

  @override
  Future<void> sendNoteOn(
    MidiNote note, {
    int velocity = 96,
    int channel = 0,
    String? deviceId,
  }) {
    final ch = channel.clamp(0, 15);
    final vel = velocity.clamp(1, 127);
    _activeNotes.add((
      deviceId: deviceId,
      channel: ch,
      noteNumber: note.number,
    ));
    return _enqueueWrite(
      Uint8List.fromList(<int>[0x90 | ch, note.number & 0x7F, vel]),
      deviceId: deviceId,
    );
  }

  @override
  Future<void> sendNoteOff(MidiNote note, {int channel = 0, String? deviceId}) {
    final ch = channel.clamp(0, 15);
    _activeNotes.removeWhere(
      (entry) =>
          entry.channel == ch &&
          entry.noteNumber == note.number &&
          (deviceId == null || entry.deviceId == deviceId),
    );
    return _enqueueWrite(
      Uint8List.fromList(<int>[0x80 | ch, note.number & 0x7F, 0]),
      deviceId: deviceId,
    );
  }

  @override
  Future<void> sendAllNotesOff({int channel = 0, String? deviceId}) {
    final ch = channel.clamp(0, 15);
    final matching = _activeNotes
        .where(
          (entry) =>
              entry.channel == ch &&
              (deviceId == null ||
                  entry.deviceId == null ||
                  entry.deviceId == deviceId),
        )
        .toList(growable: false);
    _activeNotes.removeAll(matching);

    // Serialize all Note Offs + CC 123/64 ahead of any subsequent sendNoteOn.
    return _writeChain = _writeChain.then((_) async {
      for (final entry in matching) {
        await _sendBytesNow(
          Uint8List.fromList(<int>[
            0x80 | entry.channel,
            entry.noteNumber & 0x7F,
            0,
          ]),
          deviceId: deviceId ?? entry.deviceId,
        );
      }
      await _sendBytesNow(
        Uint8List.fromList(<int>[0xB0 | ch, 123, 0]),
        deviceId: deviceId,
      );
      await _sendBytesNow(
        Uint8List.fromList(<int>[0xB0 | ch, 64, 0]),
        deviceId: deviceId,
      );
    });
  }

  Future<void> _enqueueWrite(Uint8List bytes, {String? deviceId}) {
    return _writeChain = _writeChain.then(
      (_) => _sendBytesNow(bytes, deviceId: deviceId),
    );
  }

  Future<void> _sendBytesNow(Uint8List bytes, {String? deviceId}) async {
    try {
      await _midiCommand.sendDataAwaitingDelivery(bytes, deviceId: deviceId);
    } catch (_) {
      // Disconnected or stalled BLE links must not surface unhandled exceptions.
    }
  }
}
