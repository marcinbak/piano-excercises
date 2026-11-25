import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_controller.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_state.dart';
import 'package:piano_exercises/features/score_editor/ui/score_editor_header_strip.dart';
import 'package:piano_exercises/features/score_editor/ui/score_editor_toolbar.dart';
import 'package:piano_exercises/features/score_editor/ui/score_editor_viewport.dart';
import 'package:piano_exercises/features/score_playback/score_playback.dart';

export 'package:piano_exercises/features/score_editor/ui/score_editor_viewport.dart'
    show buildEditorPreviewPiece;

/// Synchronizes step-time MIDI pause state and halts playback on edits or tab/modal pauses.
void listenScoreEditorPlaybackSync(
  WidgetRef ref, {
  required ScoreEditorSessionId sessionId,
  required ScorePlaybackSessionId playbackId,
}) {
  if (sessionId == ScoreEditorSessionId.composeTab) {
    ref.listen<bool>(scoreEditorPausedProvider, (_, paused) {
      if (paused) {
        ref.read(scorePlaybackControllerProvider(playbackId).notifier).stop();
      }
    });
  }
  ref.listen<bool>(scoreEditorSessionPausedProvider(sessionId), (_, paused) {
    if (paused) {
      ref.read(scorePlaybackControllerProvider(playbackId).notifier).stop();
    }
  });
  ref.listen<bool>(scoreEditorPlaybackPausedProvider(sessionId), (_, _) {});
  ref.listen<ScorePlaybackState>(scorePlaybackControllerProvider(playbackId), (
    prev,
    next,
  ) {
    if (prev?.isPlaying != next.isPlaying) {
      ref
          .read(scoreEditorPlaybackPausedProvider(sessionId).notifier)
          .setPaused(next.isPlaying);
    }
  });
  ref.listen<ScoreEditorState>(scoreEditorControllerProvider(sessionId), (
    prev,
    next,
  ) {
    if (prev != null && prev.draft != next.draft) {
      ref.read(scorePlaybackControllerProvider(playbackId).notifier).stop();
    }
  });
}

/// Renders loading, load-error, or active grand-staff editor body with playback sync.
class ScoreEditorBody extends StatelessWidget {
  const ScoreEditorBody({
    super.key,
    required this.state,
    required this.controller,
    required this.playbackState,
    required this.playbackController,
    required this.onOpenSetup,
    required this.isCompactHeight,
  });

  final ScoreEditorState state;
  final ScoreEditorController controller;
  final ScorePlaybackState playbackState;
  final ScorePlaybackController playbackController;
  final VoidCallback onOpenSetup;
  final bool isCompactHeight;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingVariant) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.loadError != null) {
      return ScoreEditorLoadErrorView(
        message: state.loadError!,
        onRetry: state.binding == null
            ? null
            : () => unawaited(
                controller.loadVariantForEditing(
                  state.binding!.piece,
                  state.binding!.variant,
                ),
              ),
      );
    }

    final displayedSliceIndex = playbackState.isPlaying
        ? (playbackState.activeSliceIndex ?? state.activeSliceIndex)
        : state.activeSliceIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ScoreEditorHeaderStrip(
          state: state,
          controller: controller,
          onOpenSetup: onOpenSetup,
          onResetScore: () {
            playbackController.stop();
            controller.clearScore();
          },
          isPlaying: playbackState.isPlaying,
          onPlay: () => playbackController.playScore(
            state.score,
            options: const ScorePlaybackOptions(
              trimTrailingEmptyMeasures: true,
            ),
          ),
          onStop: playbackController.stop,
          isCompact: isCompactHeight,
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(isCompactHeight ? 4 : 10),
            child: ScoreEditorViewport(
              score: state.score,
              activeSliceIndex: displayedSliceIndex,
              onSliceTapped: (sliceIdx) {
                playbackController.stop();
                controller.selectSlice(sliceIdx);
              },
            ),
          ),
        ),
        const Divider(height: 1),
        ScoreEditorToolbar(
          state: state,
          controller: controller,
          isCompact: isCompactHeight,
        ),
      ],
    );
  }
}
