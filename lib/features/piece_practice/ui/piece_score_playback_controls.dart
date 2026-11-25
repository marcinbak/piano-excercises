import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/domain/score_practice_navigator.dart';
import 'package:piano_exercises/features/piece_practice/state/piece_practice_controller.dart';
import 'package:piano_exercises/features/piece_practice/state/practice_session_state.dart';
import 'package:piano_exercises/features/piece_practice/ui/measure_loop_sheet.dart';
import 'package:piano_exercises/features/score_playback/score_playback.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Resolved playback callbacks and highlight slice for `PieceScoreScreen`.
final class PieceScorePlaybackBinding {
  const PieceScorePlaybackBinding({
    required this.isPlaying,
    required this.hasPlayableNotes,
    required this.onPlay,
    required this.onStop,
    this.playbackSliceIndex,
  });

  final bool isPlaying;
  final bool hasPlayableNotes;
  final void Function() onPlay;
  final void Function() onStop;
  final int? playbackSliceIndex;

  void Function()? fullscreenToggle({required bool canStartPlayback}) {
    if (isPlaying) {
      return onStop;
    }
    return (hasPlayableNotes && canStartPlayback) ? onPlay : null;
  }
}

/// Watches active [HandMode] and mounted [PiecePracticeController] for [loadedScore].
({
  HandMode handMode,
  PracticeSessionState? state,
  PiecePracticeController? controller,
})
watchPiecePracticeSession(
  WidgetRef ref, {
  required ScoreVariant activeVariant,
  required Score? loadedScore,
  required int routeId,
}) {
  final handMode = ref.watch(practiceHandModeProvider);
  if (loadedScore == null) {
    return (handMode: handMode, state: null, controller: null);
  }
  final key = PracticeSessionKey(
    variantId: activeVariant.id,
    score: loadedScore,
    routeId: routeId,
  );
  return (
    handMode: handMode,
    state: ref.watch(piecePracticeControllerProvider(key)),
    controller: ref.read(piecePracticeControllerProvider(key).notifier),
  );
}

/// Synchronizes Wait-Mode route pause state and stops playback when externally paused.
void listenPieceScorePlaybackSync(
  WidgetRef ref, {
  required int routeId,
  required ScorePlaybackSessionId playbackId,
}) {
  ref.listen<bool>(practicePausedProvider, (_, paused) {
    if (paused) {
      ref.read(scorePlaybackControllerProvider(playbackId).notifier).stop();
    }
  });
  ref.listen<bool>(practiceRoutePausedProvider(routeId), (_, paused) {
    if (paused) {
      ref.read(scorePlaybackControllerProvider(playbackId).notifier).stop();
    }
  });
  ref.listen<bool>(practicePlaybackPausedProvider(routeId), (_, _) {});
  ref.listen<ScorePlaybackState>(scorePlaybackControllerProvider(playbackId), (
    prev,
    next,
  ) {
    if (prev?.isPlaying != next.isPlaying) {
      ref
          .read(practicePlaybackPausedProvider(routeId).notifier)
          .setPaused(next.isPlaying);
    }
  });
}

/// Resolves [preferredId] inside [piece.variants], falling back to the first variant.
ScoreVariant matchPieceScoreVariant(
  Piece piece,
  String? preferredId, {
  ScoreVariant? fallback,
}) {
  if (preferredId != null) {
    for (final variant in piece.variants) {
      if (variant.id == preferredId) {
        return variant;
      }
    }
  }
  return piece.variants.isNotEmpty ? piece.variants.first : fallback!;
}

/// Builds [PieceScorePlaybackBinding] scoped to [handMode] and any active loop.
PieceScorePlaybackBinding? buildPieceScorePlaybackBinding({
  required Score? loadedScore,
  required HandMode handMode,
  required PracticeSessionState? sessionState,
  required ScorePlaybackState playbackState,
  required ScorePlaybackController playbackController,
}) {
  if (loadedScore == null || sessionState == null) {
    return null;
  }
  final includeTreble = handMode != HandMode.left;
  final includeBass = handMode != HandMode.right;
  final loopRange = sessionState.loopRange;

  final hasNotes = _scoreHasPlayableNotes(
    loadedScore,
    includeTreble: includeTreble,
    includeBass: includeBass,
    startMeasureIndex: loopRange?.startMeasureIndex,
    endMeasureIndex: loopRange?.endMeasureIndex,
  );

  void startPlayback() {
    var startOrdinal = 0;
    if (loopRange == null &&
        sessionState.status == PracticeSessionStatus.active &&
        sessionState.activeSliceOrdinal != null) {
      startOrdinal = sessionState.activeSliceOrdinal!;
    }
    final started = playbackController.playScore(
      loadedScore,
      options: ScorePlaybackOptions(
        includeTreble: includeTreble,
        includeBass: includeBass,
        startMeasureIndex: loopRange?.startMeasureIndex,
        endMeasureIndex: loopRange?.endMeasureIndex,
        startSliceOrdinal: startOrdinal,
      ),
      loop: loopRange != null,
    );
    if (!started && startOrdinal > 0) {
      playbackController.playScore(
        loadedScore,
        options: ScorePlaybackOptions(
          includeTreble: includeTreble,
          includeBass: includeBass,
        ),
      );
    }
  }

  return PieceScorePlaybackBinding(
    isPlaying: playbackState.isPlaying,
    hasPlayableNotes: hasNotes,
    onPlay: startPlayback,
    onStop: playbackController.stop,
    playbackSliceIndex: playbackState.isPlaying
        ? playbackState.activeSliceIndex
        : null,
  );
}

bool _scoreHasPlayableNotes(
  Score score, {
  required bool includeTreble,
  required bool includeBass,
  int? startMeasureIndex,
  int? endMeasureIndex,
}) {
  if (score.measures.isEmpty) {
    return false;
  }
  final start = (startMeasureIndex ?? 0).clamp(0, score.measures.length - 1);
  final end = (endMeasureIndex ?? (score.measures.length - 1)).clamp(
    start,
    score.measures.length - 1,
  );
  for (var m = start; m <= end; m += 1) {
    for (final slice in score.measures[m].slices) {
      if ((includeTreble &&
              slice.trebleNotes.any((note) => note.requiresAttack)) ||
          (includeBass && slice.bassNotes.any((note) => note.requiresAttack))) {
        return true;
      }
    }
  }
  return false;
}

/// Presents [MeasureLoopSheet] and applies or clears the selected range on [controller].
Future<void> presentPieceMeasureLoopSheet({
  required BuildContext context,
  required Score score,
  required PracticeSessionState sessionState,
  required PiecePracticeController controller,
  required void Function() onBeforeModal,
  required void Function() onAfterModal,
}) async {
  final initialMeasure = sessionState.activeSliceOrdinal == null
      ? 0
      : ScorePracticeNavigator.measureIndexOfSliceOrdinal(
          score,
          sessionState.activeSliceOrdinal!,
        );
  onBeforeModal();
  final MeasureLoopSheetResult? result;
  try {
    result = await MeasureLoopSheet.show(
      context,
      measures: score.measures,
      initialMeasureIndex: initialMeasure,
      currentLoop: sessionState.loopRange,
    );
  } finally {
    onAfterModal();
  }
  if (!context.mounted || result == null) {
    return;
  }
  switch (result) {
    case MeasureLoopApply(:final range):
      controller.setLoopRange(range);
    case MeasureLoopClear():
      controller.setLoopRange(null);
  }
}
