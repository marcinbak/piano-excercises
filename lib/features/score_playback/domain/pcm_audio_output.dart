import 'dart:typed_data';

import 'package:piano_exercises/features/score_playback/domain/piano_pcm_synthesizer.dart';

/// Boundary interface for streaming `16-bit LE` mono PCM buffers to device speakers.
abstract interface class PcmAudioOutput {
  int get sampleRate;

  /// Appends [pcmBytes] (`16-bit LE` mono at [sampleRate]) to the hardware playback queue.
  Future<void> enqueuePcm16Mono(Uint8List pcmBytes);

  /// Immediately halts and flushes all queued PCM buffers.
  Future<void> stop();

  /// Releases underlying native audio resources.
  Future<void> dispose();
}

/// Safe default [PcmAudioOutput] used in tests or headless environments.
final class NoopPcmAudioOutput implements PcmAudioOutput {
  const NoopPcmAudioOutput({
    this.sampleRate = PianoPcmSynthesizer.defaultSampleRate,
  });

  @override
  final int sampleRate;

  @override
  Future<void> enqueuePcm16Mono(Uint8List pcmBytes) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
