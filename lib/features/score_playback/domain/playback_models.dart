import 'package:piano_exercises/shared/music/music.dart';

/// User-selected routing mode for score playback audio.
enum PlaybackOutputMode {
  auto,
  piano,
  device;

  String get label => switch (this) {
    PlaybackOutputMode.auto => 'Auto',
    PlaybackOutputMode.piano => 'Piano',
    PlaybackOutputMode.device => 'Speaker',
  };

  /// Resolves the active hardware destination given [hasConnectedMidi].
  PlaybackTarget resolveTarget({required bool hasConnectedMidi}) =>
      switch (this) {
        PlaybackOutputMode.auto =>
          hasConnectedMidi
              ? PlaybackTarget.midiPiano
              : PlaybackTarget.deviceAudio,
        PlaybackOutputMode.piano => PlaybackTarget.midiPiano,
        PlaybackOutputMode.device => PlaybackTarget.deviceAudio,
      };

  /// Cycles through `Auto -> Speaker -> Piano -> Auto`.
  PlaybackOutputMode nextMode() => switch (this) {
    PlaybackOutputMode.auto => PlaybackOutputMode.device,
    PlaybackOutputMode.device => PlaybackOutputMode.piano,
    PlaybackOutputMode.piano => PlaybackOutputMode.auto,
  };
}

/// Concrete hardware sink resolved for a playback run.
enum PlaybackTarget { midiPiano, deviceAudio }

/// Scoped identifier isolating playback sessions across tabs and pushed routes.
final class ScorePlaybackSessionId {
  const ScorePlaybackSessionId(this.value);

  final String value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScorePlaybackSessionId && other.value == value);
  }

  @override
  int get hashCode => value.hashCode;
}

/// Chronological slice time window `[startMs, endMs)` for playback cursor sync.
final class PlaybackSliceWindow {
  const PlaybackSliceWindow({
    required this.sliceOrdinal,
    required this.sliceIndex,
    required this.measureNumber,
    required this.startMs,
    required this.endMs,
  });

  final int sliceOrdinal;
  final int sliceIndex;
  final int measureNumber;
  final int startMs;
  final int endMs;
}

/// Coalesced sounding note event `[startMs, endMs)` ready for MIDI or PCM synthesis.
final class PlaybackNoteSpan {
  const PlaybackNoteSpan({
    required this.midiNote,
    required this.velocity,
    required this.startMs,
    required this.endMs,
  });

  final MidiNote midiNote;
  final int velocity;
  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;
}
