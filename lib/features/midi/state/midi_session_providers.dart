import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/midi/domain/midi_device_info.dart';
import 'package:piano_exercises/features/midi/domain/midi_note_event.dart';
import 'package:piano_exercises/features/midi/state/midi_providers.dart';

/// Live stream of normalized Note On/Off events from the active MIDI repository.
final midiNoteEventsProvider = StreamProvider<MidiNoteEvent>((ref) {
  return ref.watch(midiRepositoryProvider).noteEventsStream;
});

/// Unmodifiable snapshot of currently connected MIDI devices.
final connectedMidiDevicesProvider = Provider<List<MidiDeviceInfo>>((ref) {
  final devices =
      ref.watch(midiDevicesProvider).value ?? const <MidiDeviceInfo>[];
  return List<MidiDeviceInfo>.unmodifiable(
    devices.where((device) => device.isConnected),
  );
});
