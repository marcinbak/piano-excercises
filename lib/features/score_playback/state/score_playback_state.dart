import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/score_playback/domain/pcm_audio_output.dart';
import 'package:piano_exercises/features/score_playback/domain/piano_pcm_synthesizer.dart';
import 'package:piano_exercises/features/score_playback/domain/playback_models.dart';

/// DI boundary for on-device PCM speaker output; overridden in `app/` and tests.
final pcmAudioOutputProvider = Provider<PcmAudioOutput>((ref) {
  return const NoopPcmAudioOutput();
});

/// Shared pure-Dart piano PCM synthesizer instance.
final pianoPcmSynthesizerProvider = Provider<PianoPcmSynthesizer>((ref) {
  return const PianoPcmSynthesizer();
});

/// Monotonic millisecond clock used by `ScorePlaybackController`; overridable in tests.
final scorePlaybackClockMsProvider = Provider<int Function()>((ref) {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsedMilliseconds;
});

/// Timer tick cadence driving score playback cursor and MIDI/PCM scheduling.
final scorePlaybackTickIntervalProvider = Provider<Duration>((ref) {
  return const Duration(milliseconds: 25);
});

/// Session-wide playback output preference (`Auto`, `Speaker`, or `Piano`).
class PlaybackOutputModeNotifier extends Notifier<PlaybackOutputMode> {
  @override
  PlaybackOutputMode build() => PlaybackOutputMode.auto;

  void setMode(PlaybackOutputMode mode) => state = mode;

  void cycleMode() => state = state.nextMode();
}

final playbackOutputModeProvider =
    NotifierProvider<PlaybackOutputModeNotifier, PlaybackOutputMode>(
      PlaybackOutputModeNotifier.new,
    );

/// Session-wide playback speed multiplier (`0.75x`, `1.0x`, `1.25x`).
class PlaybackSpeedNotifier extends Notifier<double> {
  static const List<double> presets = <double>[0.75, 1.0, 1.25];

  @override
  double build() => 1.0;

  void setSpeed(double speed) => state = speed;

  void cycleSpeed() {
    final idx = presets.indexOf(state);
    state = presets[(idx + 1) % presets.length];
  }
}

final playbackSpeedProvider = NotifierProvider<PlaybackSpeedNotifier, double>(
  PlaybackSpeedNotifier.new,
);

/// Immutable UI snapshot for a scoped `ScorePlaybackController`.
final class ScorePlaybackState {
  const ScorePlaybackState({
    this.isPlaying = false,
    this.activeTarget,
    this.activeSliceOrdinal,
    this.activeSliceIndex,
    this.activeMeasureNumber,
    this.bpm,
    this.isLooping = false,
  });

  final bool isPlaying;
  final PlaybackTarget? activeTarget;
  final int? activeSliceOrdinal;
  final int? activeSliceIndex;
  final int? activeMeasureNumber;
  final int? bpm;
  final bool isLooping;

  ScorePlaybackState copyWith({
    bool? isPlaying,
    PlaybackTarget? activeTarget,
    int? activeSliceOrdinal,
    int? activeSliceIndex,
    int? activeMeasureNumber,
    int? bpm,
    bool? isLooping,
  }) {
    return ScorePlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      activeTarget: activeTarget ?? this.activeTarget,
      activeSliceOrdinal: activeSliceOrdinal ?? this.activeSliceOrdinal,
      activeSliceIndex: activeSliceIndex ?? this.activeSliceIndex,
      activeMeasureNumber: activeMeasureNumber ?? this.activeMeasureNumber,
      bpm: bpm ?? this.bpm,
      isLooping: isLooping ?? this.isLooping,
    );
  }
}

/// Resolves whether playback can currently run under the chosen output mode.
final canStartScorePlaybackProvider = Provider<bool>((ref) {
  final mode = ref.watch(playbackOutputModeProvider);
  final hasMidi = ref.watch(connectedMidiDevicesProvider).isNotEmpty;
  return mode != PlaybackOutputMode.piano || hasMidi;
});
