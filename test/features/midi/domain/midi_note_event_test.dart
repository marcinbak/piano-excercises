import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/midi/domain/midi_note_event.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('formatMidiNoteName', () {
    test('formats piano and MIDI boundary notes accurately', () {
      expect(formatMidiNoteName(0), 'C-1');
      expect(formatMidiNoteName(21), 'A0');
      expect(formatMidiNoteName(60), 'C4');
      expect(formatMidiNoteName(61), 'C#4');
      expect(formatMidiNoteName(69), 'A4');
      expect(formatMidiNoteName(108), 'C8');
      expect(formatMidiNoteName(127), 'G9');
    });

    test('throws RangeError for out-of-range note numbers', () {
      expect(() => formatMidiNoteName(-1), throwsRangeError);
      expect(() => formatMidiNoteName(128), throwsRangeError);
    });
  });

  group('MidiNoteEvent.fromChannelMessage', () {
    test('preserves Note On when velocity is positive', () {
      final event = MidiNoteEvent.fromChannelMessage(
        noteNumber: 60,
        velocity: 96,
        isNoteOn: true,
        channel: 0,
        deviceId: 'piano-1',
        timestampMs: 1234,
      );

      expect(event.noteNumber, 60);
      expect(event.note, MidiNote.middleC);
      expect(event.noteName, 'C4');
      expect(event.velocity, 96);
      expect(event.isNoteOn, isTrue);
      expect(event.channel, 0);
      expect(event.deviceId, 'piano-1');
      expect(event.timestampMs, 1234);
    });

    test('treats Note On with velocity 0 as Note Off', () {
      final event = MidiNoteEvent.fromChannelMessage(
        noteNumber: 64,
        velocity: 0,
        isNoteOn: true,
        channel: 1,
        deviceId: 'piano-1',
        timestampMs: 2000,
      );

      expect(event.isNoteOn, isFalse);
      expect(event.velocity, 0);
      expect(event.noteName, 'E4');
    });

    test('preserves Note Off even with non-zero release velocity', () {
      final event = MidiNoteEvent.fromChannelMessage(
        noteNumber: 67,
        velocity: 40,
        isNoteOn: false,
        channel: 2,
        deviceId: 'piano-1',
        timestampMs: 3000,
      );

      expect(event.isNoteOn, isFalse);
      expect(event.velocity, 40);
    });

    test('rejects out-of-range note, velocity, and channel bytes', () {
      expect(
        () => MidiNoteEvent.fromChannelMessage(
          noteNumber: -1,
          velocity: 64,
          isNoteOn: true,
          channel: 0,
          deviceId: 'd',
          timestampMs: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => MidiNoteEvent.fromChannelMessage(
          noteNumber: 128,
          velocity: 64,
          isNoteOn: true,
          channel: 0,
          deviceId: 'd',
          timestampMs: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => MidiNoteEvent.fromChannelMessage(
          noteNumber: 60,
          velocity: -1,
          isNoteOn: true,
          channel: 0,
          deviceId: 'd',
          timestampMs: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => MidiNoteEvent.fromChannelMessage(
          noteNumber: 60,
          velocity: 128,
          isNoteOn: true,
          channel: 0,
          deviceId: 'd',
          timestampMs: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => MidiNoteEvent.fromChannelMessage(
          noteNumber: 60,
          velocity: 64,
          isNoteOn: true,
          channel: -1,
          deviceId: 'd',
          timestampMs: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => MidiNoteEvent.fromChannelMessage(
          noteNumber: 60,
          velocity: 64,
          isNoteOn: true,
          channel: 16,
          deviceId: 'd',
          timestampMs: 0,
        ),
        throwsRangeError,
      );
    });
  });

  group('MidiNoteEvent.tryFromChannelMessage', () {
    test(
      'returns null on out-of-range inputs and normalizes valid messages',
      () {
        expect(
          MidiNoteEvent.tryFromChannelMessage(
            noteNumber: 130,
            velocity: 64,
            isNoteOn: true,
            channel: 0,
            deviceId: 'd',
            timestampMs: 0,
          ),
          isNull,
        );
        expect(
          MidiNoteEvent.tryFromChannelMessage(
            noteNumber: 60,
            velocity: 200,
            isNoteOn: true,
            channel: 0,
            deviceId: 'd',
            timestampMs: 0,
          ),
          isNull,
        );
        expect(
          MidiNoteEvent.tryFromChannelMessage(
            noteNumber: 60,
            velocity: 0,
            isNoteOn: true,
            channel: 15,
            deviceId: 'd',
            timestampMs: 10,
          )?.isNoteOn,
          isFalse,
        );
      },
    );
  });
}
