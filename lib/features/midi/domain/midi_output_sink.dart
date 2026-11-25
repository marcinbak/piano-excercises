import 'package:piano_exercises/shared/music/music.dart';

/// Boundary interface for sending real-time MIDI Note On/Off messages to connected hardware.
abstract interface class MidiOutputSink {
  /// Sends a MIDI Note On message for [note] on [channel] (`0..15`).
  Future<void> sendNoteOn(
    MidiNote note, {
    int velocity = 96,
    int channel = 0,
    String? deviceId,
  });

  /// Sends a MIDI Note Off message for [note] on [channel] (`0..15`).
  Future<void> sendNoteOff(MidiNote note, {int channel = 0, String? deviceId});

  /// Silences all active notes on [channel] (explicit Note Offs + CC 123).
  Future<void> sendAllNotesOff({int channel = 0, String? deviceId});
}

/// Safe default [MidiOutputSink] that discards outgoing MIDI messages.
final class NoopMidiOutputSink implements MidiOutputSink {
  const NoopMidiOutputSink();

  @override
  Future<void> sendNoteOn(
    MidiNote note, {
    int velocity = 96,
    int channel = 0,
    String? deviceId,
  }) async {}

  @override
  Future<void> sendNoteOff(
    MidiNote note, {
    int channel = 0,
    String? deviceId,
  }) async {}

  @override
  Future<void> sendAllNotesOff({int channel = 0, String? deviceId}) async {}
}
