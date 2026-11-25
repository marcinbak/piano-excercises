import 'package:flutter/services.dart';
import 'package:piano_exercises/features/score_playback/domain/pcm_audio_output.dart';
import 'package:piano_exercises/features/score_playback/domain/piano_pcm_synthesizer.dart';

/// [PcmAudioOutput] bridging to iOS `AVAudioEngine` and Android `AudioTrack` via `MethodChannel`.
class MethodChannelPcmAudioOutput implements PcmAudioOutput {
  MethodChannelPcmAudioOutput({
    this.sampleRate = PianoPcmSynthesizer.defaultSampleRate,
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'piano_exercises/pcm_audio';

  @override
  final int sampleRate;

  final MethodChannel _channel;
  bool _isDisposed = false;

  @override
  Future<void> enqueuePcm16Mono(Uint8List pcmBytes) async {
    if (_isDisposed || pcmBytes.isEmpty) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('enqueue', <String, Object>{
        'pcm': pcmBytes,
        'sampleRate': sampleRate,
      });
    } on MissingPluginException {
      // Headless tests and unsupported desktop hosts omit the native handler.
    } on PlatformException {
      // Transient audio-session interruptions must not crash playback state.
    }
  }

  @override
  Future<void> stop() async {
    if (_isDisposed) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Safe no-op outside mobile targets.
    } on PlatformException {
      // Ignore stop failures when audio session is already inactive.
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
