import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/score_playback/score_playback.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('PianoPcmSynthesizer', () {
    const synth = PianoPcmSynthesizer(sampleRate: 24000);

    test('returns silent zeroed PCM when no notes overlap the window', () {
      final empty = synth.synthesizeWindow(
        notes: const <PlaybackNoteSpan>[],
        startSample: 0,
        sampleCount: 480,
      );
      expect(empty.length, 960);
      expect(empty.every((b) => b == 0), isTrue);
    });

    test('renders phase-continuous chunk boundaries identical to single-pass render', () {
      final notes = <PlaybackNoteSpan>[
        const PlaybackNoteSpan(
          midiNote: MidiNote(60),
          velocity: 96,
          startMs: 0,
          endMs: 400,
        ),
        const PlaybackNoteSpan(
          midiNote: MidiNote(64),
          velocity: 92,
          startMs: 50,
          endMs: 400,
        ),
        const PlaybackNoteSpan(
          midiNote: MidiNote(108), // C8 Nyquist band-limit check
          velocity: 110,
          startMs: 100,
          endMs: 300,
        ),
      ];

      final full = synth.synthesizeWindow(
        notes: notes,
        startSample: 0,
        sampleCount: 4800,
      );
      final partA = synth.synthesizeWindow(
        notes: notes,
        startSample: 0,
        sampleCount: 2400,
      );
      final partB = synth.synthesizeWindow(
        notes: notes,
        startSample: 2400,
        sampleCount: 2400,
      );

      final combined = Uint8List(4800 * 2)
        ..setRange(0, partA.length, partA)
        ..setRange(partA.length, full.length, partB);

      expect(combined, equals(full));

      // Verify non-silent audio energy without clipping.
      final bd = ByteData.sublistView(full);
      var maxAbs = 0;
      for (var i = 0; i < 4800; i += 1) {
        final s = bd.getInt16(i * 2, Endian.little).abs();
        if (s > maxAbs) {
          maxAbs = s;
        }
      }
      expect(maxAbs, greaterThan(2000));
      expect(maxAbs, lessThanOrEqualTo(32767));
    });
  });
}
