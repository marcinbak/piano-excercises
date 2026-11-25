import 'dart:math' as math;
import 'dart:typed_data';

import 'package:piano_exercises/features/score_playback/domain/playback_models.dart';

class _PianoBandTables {
  const _PianoBandTables({required this.warm, required this.bright});

  final Float64List warm;
  final Float64List bright;
}

/// Pure-Dart band-limited polyphonic piano PCM synthesizer (`16-bit LE mono`).
final class PianoPcmSynthesizer {
  const PianoPcmSynthesizer({this.sampleRate = defaultSampleRate});

  static const int defaultSampleRate = 24000;
  static const int releaseTailMs = 70;
  static const int _tableSize = 4096;
  static const int _tableMask = _tableSize - 1;

  static final Map<int, _PianoBandTables> _tablesByMaxHarmonic =
      <int, _PianoBandTables>{};

  final int sampleRate;

  /// Synthesizes `[startSample, startSample + sampleCount)` into `16-bit LE` PCM bytes.
  Uint8List synthesizeWindow({
    required List<PlaybackNoteSpan> notes,
    required int startSample,
    required int sampleCount,
  }) {
    if (sampleCount <= 0) {
      return Uint8List(0);
    }
    final pcmBytes = Uint8List(sampleCount * 2);
    if (notes.isEmpty) {
      return pcmBytes;
    }

    final windowStartMs = (startSample * 1000) ~/ sampleRate;
    final windowEndMs = ((startSample + sampleCount) * 1000) ~/ sampleRate + 2;
    final activeNotes = notes
        .where(
          (n) =>
              n.startMs < windowEndMs &&
              (n.endMs + releaseTailMs) > windowStartMs,
        )
        .toList(growable: false);
    if (activeNotes.isEmpty) {
      return pcmBytes;
    }

    final mixBuffer = Float64List(sampleCount);
    final attackSamples = math.max(1, (sampleRate * 0.004).round());
    final releaseSamples = math.max(1, (sampleRate * releaseTailMs) ~/ 1000);
    final nyquistSafeHz = sampleRate * 0.45;

    for (final span in activeNotes) {
      _mixNoteIntoWindow(
        span: span,
        mixBuffer: mixBuffer,
        windowStartSample: startSample,
        sampleCount: sampleCount,
        attackSamples: attackSamples,
        releaseSamples: releaseSamples,
        nyquistSafeHz: nyquistSafeHz,
      );
    }

    final byteData = ByteData.sublistView(pcmBytes);
    for (var i = 0; i < sampleCount; i += 1) {
      final raw = mixBuffer[i] * 0.28;
      // Soft rational limiter prevents polyphonic chord clipping.
      final limited = raw / (1.0 + 0.42 * raw.abs());
      final pcm16 = (limited * 32000.0).round().clamp(-32767, 32767);
      byteData.setInt16(i * 2, pcm16, Endian.little);
    }
    return pcmBytes;
  }

  void _mixNoteIntoWindow({
    required PlaybackNoteSpan span,
    required Float64List mixBuffer,
    required int windowStartSample,
    required int sampleCount,
    required int attackSamples,
    required int releaseSamples,
    required double nyquistSafeHz,
  }) {
    final midi = span.midiNote.number;
    final freq = 440.0 * math.pow(2.0, (midi - 69) / 12.0);
    final maxHarmonic = (nyquistSafeHz / freq).floor().clamp(1, 6);
    final tables = _getBandTables(maxHarmonic);

    final noteStartSample = (span.startMs * sampleRate) ~/ 1000;
    final noteEndSample = math.max(
      noteStartSample + 1,
      (span.endMs * sampleRate) ~/ 1000,
    );
    final noteFinalSample = noteEndSample + releaseSamples;

    final fromIdx = math.max(0, noteStartSample - windowStartSample);
    final toIdx = math.min(sampleCount, noteFinalSample - windowStartSample);
    if (fromIdx >= toIdx) {
      return;
    }

    final velNorm = (span.velocity.clamp(1, 127)) / 127.0;
    final amp = math.pow(velNorm, 1.25).toDouble();
    // Bass strings ring longer; high treble decays crisply like felt hammers.
    final tauSlowSec = (2.2 * math.pow(0.5, (midi - 36) / 28.0)).clamp(
      0.38,
      2.6,
    );
    final tauFastSec = tauSlowSec * 0.28;
    final invSampleRate = 1.0 / sampleRate;
    final phaseIncrement = (freq * _tableSize) / sampleRate;
    // Subtle unison-string detune above bass muddiness range.
    final detuneIncrement = midi >= 48 ? phaseIncrement * 1.00046 : 0.0;

    for (var i = fromIdx; i < toIdx; i += 1) {
      final localSample = (windowStartSample + i) - noteStartSample;
      final tSec = localSample * invSampleRate;

      var attackGain = 1.0;
      if (localSample < attackSamples) {
        attackGain =
            0.5 * (1.0 - math.cos(math.pi * localSample / attackSamples));
      }

      var damperGain = 1.0;
      final globalSample = windowStartSample + i;
      if (globalSample > noteEndSample) {
        final relProgress = (globalSample - noteEndSample) / releaseSamples;
        damperGain = math.exp(-5.0 * relProgress);
      }

      final warmEnv =
          0.42 * math.exp(-tSec / tauFastSec) +
          0.58 * math.exp(-tSec / tauSlowSec);
      final brightEnv = math.exp(-tSec / tauFastSec);

      final idx1 = (localSample * phaseIncrement).toInt() & _tableMask;
      var voice =
          warmEnv * tables.warm[idx1] +
          brightEnv * velNorm * tables.bright[idx1];
      if (detuneIncrement > 0) {
        final idx2 = (localSample * detuneIncrement).toInt() & _tableMask;
        voice = 0.65 * voice + 0.35 * warmEnv * tables.warm[idx2];
      }

      mixBuffer[i] += amp * attackGain * damperGain * voice;
    }
  }

  static _PianoBandTables _getBandTables(int maxHarmonic) {
    return _tablesByMaxHarmonic.putIfAbsent(maxHarmonic, () {
      final warm = Float64List(_tableSize);
      final bright = Float64List(_tableSize);
      const harmonicWeights = <double>[0.0, 1.0, 0.46, 0.30, 0.17, 0.09, 0.05];
      for (var i = 0; i < _tableSize; i += 1) {
        final theta = (2.0 * math.pi * i) / _tableSize;
        var w = math.sin(theta);
        if (maxHarmonic >= 2) {
          w += harmonicWeights[2] * math.sin(2.0 * theta);
        }
        warm[i] = w / 1.46;

        var b = 0.0;
        for (var h = 3; h <= maxHarmonic; h += 1) {
          b += harmonicWeights[h] * math.sin(h * theta);
        }
        bright[i] = b;
      }
      return _PianoBandTables(warm: warm, bright: bright);
    });
  }
}
