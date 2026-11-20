import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/domain/score_practice_navigator.dart';
import 'package:piano_exercises/features/piece_practice/state/piece_practice_controller.dart';
import 'package:piano_exercises/features/piece_practice/state/practice_session_state.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_practice_status_banner.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_header_bar.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_viewport.dart';
import 'package:piano_exercises/features/piece_practice/ui/score_notation_mapper.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:smufl_notation/smufl_notation.dart';

/// Snapshot passed from [PieceScoreScreen] to body and header helpers.
final class PiecePracticeScreenData {
  const PiecePracticeScreenData({
    required this.effectivePiece,
    required this.activeVariant,
    required this.asyncScore,
    required this.isCompactHeight,
    required this.maxHeight,
  });

  final Piece effectivePiece;
  final ScoreVariant activeVariant;
  final AsyncValue<Score> asyncScore;
  final bool isCompactHeight;
  final double maxHeight;
}

/// Callbacks and static overlays for [PiecePracticeBody].
final class PiecePracticeBodyConfig {
  const PiecePracticeBodyConfig({
    required this.isCompactHeight,
    required this.onRetry,
    this.controller,
    this.staticWrongOverlays = const <WrongNoteOverlay>[],
  });

  final bool isCompactHeight;
  final VoidCallback onRetry;
  final PiecePracticeController? controller;
  final List<WrongNoteOverlay> staticWrongOverlays;
}

/// Scroll-bounded header strip hosting [PieceScoreHeaderBar] above the score.
class PieceScoreHeaderStrip extends StatelessWidget {
  const PieceScoreHeaderStrip({
    super.key,
    required this.data,
    required this.handMode,
    required this.onSelectVariant,
    required this.onSelectHandMode,
    required this.cursor,
    required this.maxHeaderHeight,
  });

  final PiecePracticeScreenData data;
  final HandMode handMode;
  final ValueChanged<ScoreVariant> onSelectVariant;
  final ValueChanged<HandMode> onSelectHandMode;
  final PieceScoreCursorBarData? cursor;
  final double maxHeaderHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeaderHeight),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          12,
          data.isCompactHeight ? 4 : 8,
          12,
          data.isCompactHeight ? 4 : 8,
        ),
        child: PieceScoreHeaderBar(
          piece: data.effectivePiece,
          variantControl: PieceScoreVariantControl(
            selectedVariant: data.activeVariant,
            onSelectVariant: onSelectVariant,
          ),
          handControl: PieceScoreHandControl(
            handMode: handMode,
            onSelectHandMode: onSelectHandMode,
          ),
          cursor: cursor,
        ),
      ),
    );
  }
}

/// Renders loading, retry error, status banner, and interactive score viewport.
class PiecePracticeBody extends StatelessWidget {
  const PiecePracticeBody({
    super.key,
    required this.asyncScore,
    required this.handMode,
    required this.sessionState,
    required this.config,
  });

  final AsyncValue<Score> asyncScore;
  final HandMode handMode;
  final PracticeSessionState? sessionState;
  final PiecePracticeBodyConfig config;

  @override
  Widget build(BuildContext context) {
    return asyncScore.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          key: ValueKey<String>('score_loading_indicator'),
        ),
      ),
      error: (error, _) =>
          _ScoreErrorView(error: error, onRetry: config.onRetry),
      data: (score) => _buildLoaded(score, sessionState!, config.controller!),
    );
  }

  Widget _buildLoaded(
    Score score,
    PracticeSessionState activeSession,
    PiecePracticeController controller,
  ) {
    final activeOrdinal = activeSession.activeSliceOrdinal;
    final activeSliceIndex =
        (activeOrdinal != null &&
            activeOrdinal >= 0 &&
            activeOrdinal < score.slices.length)
        ? score.slices[activeOrdinal].sliceIndex
        : null;
    final wrongOverlays = <WrongNoteOverlay>[
      ...config.staticWrongOverlays,
      if (activeSliceIndex != null && activeSession.wrongPlayedNotes.isNotEmpty)
        ...ScoreNotationMapper.mapWrongNoteOverlays(
          sliceIndex: activeSliceIndex,
          wrongNotes: activeSession.wrongPlayedNotes,
          activeKeySignature: ScorePracticeNavigator.activeKeySignatureAtSlice(
            score,
            activeSliceIndex,
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PiecePracticeStatusBanner(
          status: activeSession.status,
          onRestart: controller.restart,
          isCompact: config.isCompactHeight,
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(config.isCompactHeight ? 6 : 12),
            child: PieceScoreViewport(
              score: score,
              activeSliceIndex: activeSliceIndex,
              matchedSliceIndex: activeSession.isShowingCorrect
                  ? activeSliceIndex
                  : null,
              handMode: handMode,
              wrongNoteOverlays: wrongOverlays,
              onSliceTapped: (tappedSliceIndex) =>
                  _onSliceTapped(score, controller, tappedSliceIndex),
            ),
          ),
        ),
      ],
    );
  }

  static void _onSliceTapped(
    Score score,
    PiecePracticeController controller,
    int tappedSliceIndex,
  ) {
    final slices = score.slices;
    if (slices.isEmpty) {
      return;
    }
    final ordinal =
        (tappedSliceIndex >= 0 &&
            tappedSliceIndex < slices.length &&
            slices[tappedSliceIndex].sliceIndex == tappedSliceIndex)
        ? tappedSliceIndex
        : slices.indexWhere((slice) => slice.sliceIndex == tappedSliceIndex);
    if (ordinal >= 0) {
      controller.seekToSlice(ordinal);
    }
  }
}

/// Builds [PieceScoreCursorBarData] when [score], [sessionState], and [controller] are loaded.
PieceScoreCursorBarData? buildPieceScoreCursorBarData({
  required Score? score,
  required HandMode handMode,
  required PracticeSessionState? sessionState,
  required PiecePracticeController? controller,
  required VoidCallback? onOpenLoopSheet,
}) {
  if (score == null || sessionState == null || controller == null) {
    return null;
  }
  final activeOrdinal = sessionState.activeSliceOrdinal;
  final loopRange = sessionState.loopRange;
  final currentMeasure = (activeOrdinal == null || score.slices.isEmpty)
      ? 0
      : score.slices[activeOrdinal].measureNumber;
  final firstPlayable = ScorePracticeNavigator.firstPlayableOrdinal(
    score,
    handMode,
    loopRange: loopRange,
  );
  final canPrev =
      activeOrdinal != null &&
      ScorePracticeNavigator.previousPlayableOrdinal(
            score,
            activeOrdinal,
            handMode,
            loopRange: loopRange,
          ) !=
          null;
  final canNext =
      activeOrdinal != null &&
      ScorePracticeNavigator.nextPlayableOrdinal(
            score,
            activeOrdinal,
            handMode,
            loopRange: loopRange,
          ) !=
          null;
  final canReset =
      firstPlayable != null &&
      (activeOrdinal != firstPlayable ||
          sessionState.status != PracticeSessionStatus.active ||
          sessionState.wrongPlayedNotes.isNotEmpty ||
          sessionState.completedSlicesCount > 0);

  return PieceScoreCursorBarData(
    measureNumber: currentMeasure,
    measureCount: score.measures.length,
    stepControls: PieceScoreStepControls(
      onPrevSlice: canPrev ? controller.stepPrevious : null,
      onNextSlice: canNext ? controller.stepNext : null,
      onResetSlice: canReset ? controller.restart : null,
    ),
    loopControls: PieceScoreLoopControls(
      loopLabel: loopRange?.formatLabel(score.measures),
      onOpenLoopSheet: onOpenLoopSheet,
      onClearLoop: loopRange != null
          ? () => controller.setLoopRange(null)
          : null,
    ),
  );
}

class _ScoreErrorView extends StatelessWidget {
  const _ScoreErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey<String>('score_error_view'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text('Could not load score: $error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey<String>('score_retry_button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
