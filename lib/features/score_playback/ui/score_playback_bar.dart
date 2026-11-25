import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/score_playback/domain/playback_models.dart';
import 'package:piano_exercises/features/score_playback/state/score_playback_state.dart';

/// Compact Play/Stop, Output target (`Auto`/`Speaker`/`Piano`), and Tempo controls.
class ScorePlaybackControls extends ConsumerWidget {
  const ScorePlaybackControls({
    super.key,
    required this.isPlaying,
    required this.hasPlayableNotes,
    required this.onPlay,
    required this.onStop,
    this.keyPrefix = 'playback',
    this.showSpeedChip = true,
  });

  final bool isPlaying;
  final bool hasPlayableNotes;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final String keyPrefix;
  final bool showSpeedChip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outputMode = ref.watch(playbackOutputModeProvider);
    final hasMidi = ref.watch(connectedMidiDevicesProvider).isNotEmpty;
    final speed = ref.watch(playbackSpeedProvider);
    final resolvedTarget = outputMode.resolveTarget(hasConnectedMidi: hasMidi);
    final pianoBlocked = outputMode == PlaybackOutputMode.piano && !hasMidi;
    final canTriggerPlay = hasPlayableNotes && !pianoBlocked;

    final outputIcon = switch (resolvedTarget) {
      PlaybackTarget.midiPiano => Icons.piano,
      PlaybackTarget.deviceAudio => Icons.volume_up_outlined,
    };
    final outputTooltip = switch (outputMode) {
      PlaybackOutputMode.auto =>
        hasMidi
            ? 'Output: Auto (Connected Piano)'
            : 'Output: Auto (Device Speaker)',
      PlaybackOutputMode.piano =>
        hasMidi
            ? 'Output: Connected Piano (MIDI)'
            : 'Output: Piano (Disconnected)',
      PlaybackOutputMode.device => 'Output: Device Speaker',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          key: ValueKey<String>('$keyPrefix-play-stop-button'),
          tooltip: isPlaying
              ? 'Stop playback'
              : (pianoBlocked
                    ? 'Connect MIDI piano or switch output'
                    : 'Play score'),
          visualDensity: VisualDensity.compact,
          icon: Icon(
            isPlaying ? Icons.stop_circle_outlined : Icons.play_circle_outline,
            color: isPlaying ? Theme.of(context).colorScheme.primary : null,
          ),
          onPressed: isPlaying ? onStop : (canTriggerPlay ? onPlay : null),
        ),
        ActionChip(
          key: ValueKey<String>('$keyPrefix-output-mode-chip'),
          tooltip: outputTooltip,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          avatar: Icon(outputIcon, size: 16),
          label: Text(outputMode.label),
          onPressed: () =>
              ref.read(playbackOutputModeProvider.notifier).cycleMode(),
        ),
        if (showSpeedChip) ...<Widget>[
          const SizedBox(width: 4),
          ActionChip(
            key: ValueKey<String>('$keyPrefix-speed-chip'),
            tooltip: 'Playback speed',
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            label: Text(_formatSpeed(speed)),
            onPressed: () =>
                ref.read(playbackSpeedProvider.notifier).cycleSpeed(),
          ),
        ],
      ],
    );
  }

  static String _formatSpeed(double speed) {
    if (speed == 1.0) {
      return '1x';
    }
    return '${speed}x';
  }
}
