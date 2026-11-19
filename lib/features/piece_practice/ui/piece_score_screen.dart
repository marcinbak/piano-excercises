import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/domain/score_practice_navigator.dart';
import 'package:piano_exercises/features/piece_practice/state/piece_practice_controller.dart';
import 'package:piano_exercises/features/piece_practice/state/piece_score_providers.dart';
import 'package:piano_exercises/features/piece_practice/state/practice_session_state.dart';
import 'package:piano_exercises/features/piece_practice/ui/measure_loop_sheet.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_practice_body.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_header_bar.dart';
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
  });

  final Piece piece;
  final ScoreVariant? initialVariant;
  final Score? initialScore;
  final List<WrongNoteOverlay> wrongNoteOverlays;

  @override
  ConsumerState<PieceScoreScreen> createState() => _PieceScoreScreenState();
}

class _PieceScoreScreenState extends ConsumerState<PieceScoreScreen> {
  late ScoreVariant _selectedVariant;
  int _modalPauseDepth = 0;
  bool _wasExternallyPausedBeforeModal = false;
  bool _isOpeningLoopSheet = false;

  @override
  void initState() {
    super.initState();
    _selectedVariant = _resolveInitialVariant(widget.piece);
  }

  @override
  void didUpdateWidget(covariant PieceScoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.piece.id != widget.piece.id) {
      _selectedVariant = _resolveInitialVariant(widget.piece);
    }
  }

  ScoreVariant _resolveInitialVariant(Piece piece) {
    final candidate = widget.initialVariant;
    if (candidate != null && piece.variants.any((v) => v.id == candidate.id)) {
      return candidate;
    }
    return piece.variants.first;
  }

  ScoreVariant _resolveActiveVariant(Piece effectivePiece) {
    for (final variant in effectivePiece.variants) {
      if (variant.id == _selectedVariant.id) {
        return variant;
      }
    }
    return effectivePiece.variants.isNotEmpty
        ? effectivePiece.variants.first
        : _selectedVariant;
  }

  @override
  Widget build(BuildContext context) {
    // Retain autoDispose paused state across AsyncLoading before controller mounts.
    ref.listen<bool>(practicePausedProvider, (_, _) {});
    final effectivePiece =
        ref.watch(livePieceProvider(widget.piece.id)).value ?? widget.piece;
    final activeVariant = _resolveActiveVariant(effectivePiece);
    final useInitialScore =
        widget.initialScore != null &&
        activeVariant.id == _resolveInitialVariant(effectivePiece).id;
    final asyncScore = useInitialScore
        ? AsyncData<Score>(widget.initialScore!)
        : ref
              .watch(variantScoreProvider(activeVariant))
              .whenData((parsed) => parsed.score);
    final isCompactHeight = MediaQuery.sizeOf(context).height < 480;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isCompactHeight ? 48 : null,
        title: Text(
          effectivePiece.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          MidiStatusActionButton(
            onBeforeOpen: _pauseBeforeModal,
            onAfterClose: _restoreAfterModal,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => _buildScaffoldBody(
            PiecePracticeScreenData(
              effectivePiece: effectivePiece,
              activeVariant: activeVariant,
              asyncScore: asyncScore,
              isCompactHeight: isCompactHeight,
              maxHeight: constraints.maxHeight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScaffoldBody(PiecePracticeScreenData data) {
    final loadedScore = data.asyncScore.value;
    final showHeader =
        loadedScore != null || data.effectivePiece.variants.length > 1;
    final maxHeaderHeight = data.isCompactHeight
        ? math.max(96.0, data.maxHeight * 0.42)
        : math.max(120.0, data.maxHeight * 0.36);

    final handMode = ref.watch(practiceHandModeProvider);
    final sessionKey = loadedScore == null
        ? null
        : PracticeSessionKey(
            variantId: data.activeVariant.id,
            score: loadedScore,
          );
    final sessionState = sessionKey == null
        ? null
        : ref.watch(piecePracticeControllerProvider(sessionKey));
    final controller = sessionKey == null
        ? null
        : ref.read(piecePracticeControllerProvider(sessionKey).notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showHeader) ...<Widget>[
          _buildHeaderStrip(
            data: data,
            handMode: handMode,
            cursor: _buildCursorOrNull(
              loadedScore,
              handMode,
              sessionState,
              controller,
            ),
            maxHeaderHeight: maxHeaderHeight,
          ),
          const Divider(height: 1),
        ],
        Expanded(
          child: PiecePracticeBody(
            asyncScore: data.asyncScore,
            handMode: handMode,
            sessionState: sessionState,
            config: PiecePracticeBodyConfig(
              isCompactHeight: data.isCompactHeight,
              onRetry: () =>
                  ref.invalidate(variantScoreProvider(data.activeVariant)),
              controller: controller,
              staticWrongOverlays: widget.wrongNoteOverlays,
            ),
          ),
        ),
      ],
    );
  }

  PieceScoreCursorBarData? _buildCursorOrNull(
    Score? loadedScore,
    HandMode handMode,
    PracticeSessionState? sessionState,
    PiecePracticeController? controller,
  ) {
    if (loadedScore == null || sessionState == null || controller == null) {
      return null;
    }
    return buildPieceScoreCursorBarData(
      score: loadedScore,
      handMode: handMode,
      sessionState: sessionState,
      controller: controller,
      onOpenLoopSheet: loadedScore.measures.isEmpty
          ? null
          : () => unawaited(
              _openLoopSheet(loadedScore, sessionState, controller),
            ),
    );
  }

  Widget _buildHeaderStrip({
    required PiecePracticeScreenData data,
    required HandMode handMode,
    required PieceScoreCursorBarData? cursor,
    required double maxHeaderHeight,
  }) {
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
            onSelectVariant: _selectVariant,
          ),
          handControl: PieceScoreHandControl(
            handMode: handMode,
            onSelectHandMode: (mode) =>
                ref.read(practiceHandModeProvider.notifier).setMode(mode),
          ),
          cursor: cursor,
        ),
      ),
    );
  }

  void _pauseBeforeModal() {
    if (_modalPauseDepth == 0) {
      _wasExternallyPausedBeforeModal = ref.read(practicePausedProvider);
      ref.read(practicePausedProvider.notifier).setPaused(true);
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
    ref.read(practicePausedProvider.notifier).setPaused(false);
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
    final initialMeasure = sessionState.activeSliceOrdinal == null
        ? 0
        : ScorePracticeNavigator.measureIndexOfSliceOrdinal(
            score,
            sessionState.activeSliceOrdinal!,
          );
    _pauseBeforeModal();
    final MeasureLoopSheetResult? result;
    try {
      result = await MeasureLoopSheet.show(
        context,
        measures: score.measures,
        initialMeasureIndex: initialMeasure,
        currentLoop: sessionState.loopRange,
      );
    } finally {
      _isOpeningLoopSheet = false;
      _restoreAfterModal();
    }
    if (!mounted || result == null) {
      return;
    }
    _applyLoopSheetResult(result, controller);
  }

  void _applyLoopSheetResult(
    MeasureLoopSheetResult result,
    PiecePracticeController controller,
  ) {
    switch (result) {
      case MeasureLoopApply(:final range):
        controller.setLoopRange(range);
      case MeasureLoopClear():
        controller.setLoopRange(null);
    }
  }

  void _selectVariant(ScoreVariant variant) {
    if (variant.id == _selectedVariant.id) {
      return;
    }
    setState(() => _selectedVariant = variant);
  }
}
