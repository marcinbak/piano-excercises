import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/piece_practice/state/piece_practice_controller.dart';
import 'package:piano_exercises/features/piece_practice/state/piece_score_providers.dart';
import 'package:piano_exercises/features/piece_practice/state/practice_session_state.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_practice_body.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_fullscreen_view.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_header_bar.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_header_strip.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_playback_controls.dart';
import 'package:piano_exercises/features/score_playback/score_playback.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:smufl_notation/smufl_notation.dart';

/// Interactive SMuFL grand-staff Wait-Mode practice screen for a catalog [Piece].
class PieceScoreScreen extends ConsumerStatefulWidget {
  const PieceScoreScreen({
    super.key,
    required this.piece,
    this.initialVariant,
    this.initialScore,
    this.wrongNoteOverlays = const <WrongNoteOverlay>[],
    this.onEditVariant,
  });

  final Piece piece;
  final ScoreVariant? initialVariant;
  final Score? initialScore;
  final List<WrongNoteOverlay> wrongNoteOverlays;
  final Future<void> Function(Piece piece, ScoreVariant variant)? onEditVariant;

  @override
  ConsumerState<PieceScoreScreen> createState() => _PieceScoreScreenState();
}

class _PieceScoreScreenState extends ConsumerState<PieceScoreScreen> {
  static int _nextRouteId = 1;

  late final int _routeId = _nextRouteId++;
  late final ScorePlaybackSessionId _playbackId = ScorePlaybackSessionId(
    'practice_route_$_routeId',
  );
  late ScoreVariant _selectedVariant;
  int _modalPauseDepth = 0;
  bool _wasExternallyPausedBeforeModal = false;
  bool _isOpeningLoopSheet = false;
  bool _isOpeningEditor = false;
  PieceScoreFullscreenState _fullscreen = const PieceScoreFullscreenState();

  @override
  void initState() {
    super.initState();
    _selectedVariant = matchPieceScoreVariant(
      widget.piece,
      widget.initialVariant?.id,
    );
  }

  @override
  void didUpdateWidget(covariant PieceScoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.piece.id != widget.piece.id) {
      _selectedVariant = matchPieceScoreVariant(
        widget.piece,
        widget.initialVariant?.id,
        fallback: _selectedVariant,
      );
    }
  }

  @override
  void dispose() {
    if (_fullscreen.isFullscreen) {
      unawaited(setFullscreenSystemUiMode(fullscreen: false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    listenPieceScorePlaybackSync(
      ref,
      routeId: _routeId,
      playbackId: _playbackId,
    );
    final effectivePiece =
        ref.watch(livePieceProvider(widget.piece.id)).value ?? widget.piece;
    final activeVariant = matchPieceScoreVariant(
      effectivePiece,
      _selectedVariant.id,
      fallback: _selectedVariant,
    );
    final initialId = matchPieceScoreVariant(
      effectivePiece,
      widget.initialVariant?.id,
      fallback: _selectedVariant,
    ).id;
    final asyncScore =
        (widget.initialScore != null && activeVariant.id == initialId)
        ? AsyncData<Score>(widget.initialScore!)
        : ref
              .watch(variantScoreProvider(activeVariant))
              .whenData((parsed) => parsed.score);
    final loadedScore = asyncScore.value;
    final screenSize = MediaQuery.sizeOf(context);
    final isCompactHeight = screenSize.height < 480;
    final session = watchPiecePracticeSession(
      ref,
      activeVariant: activeVariant,
      loadedScore: loadedScore,
      routeId: _routeId,
    );
    final playbackState = ref.watch(
      scorePlaybackControllerProvider(_playbackId),
    );
    final playbackController = ref.read(
      scorePlaybackControllerProvider(_playbackId).notifier,
    );
    final canStartPlayback = ref.watch(canStartScorePlaybackProvider);
    final playback = buildPieceScorePlaybackBinding(
      loadedScore: loadedScore,
      handMode: session.handMode,
      sessionState: session.state,
      playbackState: playbackState,
      playbackController: playbackController,
    );
    final practiceBody = PiecePracticeBody(
      asyncScore: asyncScore,
      handMode: session.handMode,
      sessionState: session.state,
      config: PiecePracticeBodyConfig(
        isCompactHeight: _fullscreen.isFullscreen || isCompactHeight,
        onRetry: () => ref.invalidate(variantScoreProvider(activeVariant)),
        controller: session.controller,
        playbackSliceIndex: playback?.playbackSliceIndex,
        onStopPlayback: playbackController.stop,
        staticWrongOverlays: widget.wrongNoteOverlays,
      ),
    );

    return PopScope(
      canPop: !_fullscreen.isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen.isFullscreen) {
          setState(() => _fullscreen = _fullscreen.exit());
        }
      },
      child: Scaffold(
        appBar: _fullscreen.isFullscreen
            ? null
            : PieceScoreAppBar(
                title: effectivePiece.title,
                isCompactHeight: isCompactHeight,
                onEditArrangement:
                    (widget.onEditVariant != null &&
                        widget.initialScore == null)
                    ? () =>
                          unawaited(_openEditor(effectivePiece, activeVariant))
                    : null,
                onEnterFullscreen: asyncScore.hasValue
                    ? () => setState(
                        () => _fullscreen = _fullscreen.enter(screenSize),
                      )
                    : null,
                onBeforeModal: _pauseBeforeModal,
                onAfterModal: _restoreAfterModal,
              ),
        body: SafeArea(
          child: _fullscreen.isFullscreen
              ? PieceScoreFullscreenView(
                  quarterTurns: _fullscreen.effectiveQuarterTurns(screenSize),
                  isPlaying: playback?.isPlaying ?? false,
                  onTogglePlayback: playback?.fullscreenToggle(
                    canStartPlayback: canStartPlayback,
                  ),
                  onRotateQuarterTurn: () => setState(
                    () =>
                        _fullscreen = _fullscreen.rotateQuarterTurn(screenSize),
                  ),
                  onExitFullscreen: () =>
                      setState(() => _fullscreen = _fullscreen.exit()),
                  child: practiceBody,
                )
              : LayoutBuilder(
                  builder: (_, constraints) => PieceScoreNormalBody(
                    data: PiecePracticeScreenData(
                      effectivePiece: effectivePiece,
                      activeVariant: activeVariant,
                      asyncScore: asyncScore,
                      isCompactHeight: isCompactHeight,
                      maxHeight: constraints.maxHeight,
                    ),
                    variantControl: PieceScoreVariantControl(
                      selectedVariant: activeVariant,
                      onSelectVariant: _selectVariant,
                    ),
                    handControl: PieceScoreHandControl(
                      handMode: session.handMode,
                      onSelectHandMode: (mode) {
                        playbackController.stop();
                        ref
                            .read(practiceHandModeProvider.notifier)
                            .setMode(mode);
                      },
                    ),
                    cursor: buildPieceScoreCursorOrNull(
                      loadedScore: loadedScore,
                      handMode: session.handMode,
                      sessionState: session.state,
                      controller: session.controller,
                      onStopPlayback: playbackController.stop,
                      onOpenLoopSheet:
                          (loadedScore == null ||
                              loadedScore.measures.isEmpty ||
                              session.state == null ||
                              session.controller == null)
                          ? null
                          : () => unawaited(
                              _openLoopSheet(
                                loadedScore,
                                session.state!,
                                session.controller!,
                              ),
                            ),
                    ),
                    playbackControls: playback == null
                        ? null
                        : ScorePlaybackControls(
                            keyPrefix: 'score',
                            isPlaying: playback.isPlaying,
                            hasPlayableNotes: playback.hasPlayableNotes,
                            onPlay: playback.onPlay,
                            onStop: playback.onStop,
                          ),
                    practiceBody: practiceBody,
                  ),
                ),
        ),
      ),
    );
  }

  void _pauseBeforeModal() {
    ref.read(scorePlaybackControllerProvider(_playbackId).notifier).stop();
    if (_modalPauseDepth == 0) {
      _wasExternallyPausedBeforeModal = ref.read(
        practiceRoutePausedProvider(_routeId),
      );
      ref.read(practiceRoutePausedProvider(_routeId).notifier).setPaused(true);
    }
    _modalPauseDepth += 1;
  }

  void _restoreAfterModal() {
    if (_modalPauseDepth > 0) {
      _modalPauseDepth -= 1;
    }
    if (!mounted || _modalPauseDepth > 0 || _wasExternallyPausedBeforeModal) {
      return;
    }
    ref.read(practiceRoutePausedProvider(_routeId).notifier).setPaused(false);
  }

  Future<void> _openLoopSheet(
    Score score,
    PracticeSessionState sessionState,
    PiecePracticeController controller,
  ) async {
    if (_isOpeningLoopSheet) {
      return;
    }
    _isOpeningLoopSheet = true;
    try {
      await presentPieceMeasureLoopSheet(
        context: context,
        score: score,
        sessionState: sessionState,
        controller: controller,
        onBeforeModal: _pauseBeforeModal,
        onAfterModal: _restoreAfterModal,
      );
    } finally {
      _isOpeningLoopSheet = false;
    }
  }

  void _selectVariant(ScoreVariant variant) {
    if (variant.id != _selectedVariant.id) {
      ref.read(scorePlaybackControllerProvider(_playbackId).notifier).stop();
      setState(() => _selectedVariant = variant);
    }
  }

  Future<void> _openEditor(Piece piece, ScoreVariant variant) async {
    if (_isOpeningEditor || widget.onEditVariant == null) {
      return;
    }
    _isOpeningEditor = true;
    _pauseBeforeModal();
    try {
      await widget.onEditVariant!(piece, variant);
    } finally {
      _isOpeningEditor = false;
      _restoreAfterModal();
    }
  }
}
