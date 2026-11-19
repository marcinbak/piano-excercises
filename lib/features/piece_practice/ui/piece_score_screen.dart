import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/state/piece_score_providers.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_header_bar.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_viewport.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:smufl_notation/smufl_notation.dart';

/// Displays an interactive SMuFL grand-staff viewport for a catalog [Piece].
class PieceScoreScreen extends ConsumerStatefulWidget {
  const PieceScoreScreen({
    super.key,
    required this.piece,
    this.initialVariant,
    this.initialScore,
    this.wrongNoteOverlays = const <WrongNoteOverlay>[],
    this.wrongNoteOverlaysBuilder,
    this.appBarActionsBuilder,
  });

  final Piece piece;
  final ScoreVariant? initialVariant;
  final Score? initialScore;
  final List<WrongNoteOverlay> wrongNoteOverlays;
  final List<WrongNoteOverlay> Function(Score score, int activeSliceIndex)?
  wrongNoteOverlaysBuilder;
  final List<Widget> Function(
    Score score,
    int activeSliceIndex,
    ValueChanged<int> selectSlice,
  )?
  appBarActionsBuilder;

  @override
  ConsumerState<PieceScoreScreen> createState() => _PieceScoreScreenState();
}

class _PieceScoreScreenState extends ConsumerState<PieceScoreScreen> {
  late ScoreVariant _selectedVariant;
  HandMode _handMode = HandMode.both;
  int _activeSliceIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedVariant = _resolveInitialVariant();
  }

  @override
  void didUpdateWidget(covariant PieceScoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.piece.id != widget.piece.id) {
      _selectedVariant = _resolveInitialVariant();
      _activeSliceIndex = 0;
    }
  }

  ScoreVariant _resolveInitialVariant() {
    final candidate = widget.initialVariant;
    if (candidate != null &&
        widget.piece.variants.any((v) => v.id == candidate.id)) {
      return candidate;
    }
    return widget.piece.variants.first;
  }

  @override
  Widget build(BuildContext context) {
    final useInitialScore =
        widget.initialScore != null &&
        _selectedVariant.id == _resolveInitialVariant().id;
    final asyncScore = useInitialScore
        ? AsyncData<Score>(widget.initialScore!)
        : ref
              .watch(variantScoreProvider(_selectedVariant))
              .whenData((parsed) => parsed.score);
    final loadedScore = asyncScore.value;
    final safeSliceIndex = loadedScore == null || loadedScore.slices.isEmpty
        ? 0
        : _activeSliceIndex.clamp(0, loadedScore.slices.length - 1);
    final isCompactHeight = MediaQuery.sizeOf(context).height < 480;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isCompactHeight ? 48 : null,
        title: Text(
          widget.piece.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: loadedScore != null && widget.appBarActionsBuilder != null
            ? widget.appBarActionsBuilder!(
                loadedScore,
                safeSliceIndex,
                (index) => _selectSlice(loadedScore, index),
              )
            : null,
      ),
      body: SafeArea(
        child: asyncScore.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
              key: ValueKey<String>('score_loading_indicator'),
            ),
          ),
          error: (error, _) => _ScoreErrorView(
            error: error,
            onRetry: () =>
                ref.invalidate(variantScoreProvider(_selectedVariant)),
          ),
          data: (score) => _buildLoadedBody(
            context,
            score: score,
            safeSliceIndex: safeSliceIndex,
            isCompactHeight: isCompactHeight,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadedBody(
    BuildContext context, {
    required Score score,
    required int safeSliceIndex,
    required bool isCompactHeight,
  }) {
    final sliceCount = score.slices.length;
    final currentMeasure = sliceCount == 0
        ? 0
        : score.slices[safeSliceIndex].measureNumber;
    final resolvedWrongNotes = <WrongNoteOverlay>[
      ...widget.wrongNoteOverlays,
      if (widget.wrongNoteOverlaysBuilder != null && sliceCount > 0)
        ...widget.wrongNoteOverlaysBuilder!(score, safeSliceIndex),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeaderHeight = isCompactHeight
            ? math.max(96.0, constraints.maxHeight * 0.42)
            : math.max(120.0, constraints.maxHeight * 0.36);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeaderHeight),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  12,
                  isCompactHeight ? 4 : 8,
                  12,
                  isCompactHeight ? 4 : 8,
                ),
                child: PieceScoreHeaderBar(
                  piece: widget.piece,
                  selectedVariant: _selectedVariant,
                  onSelectVariant: _selectVariant,
                  handMode: _handMode,
                  onSelectHandMode: (mode) => setState(() => _handMode = mode),
                  cursor: PieceScoreCursorBarData(
                    measureNumber: currentMeasure,
                    measureCount: score.measures.length,
                    canStepPrev: sliceCount > 0 && safeSliceIndex > 0,
                    canStepNext:
                        sliceCount > 0 && safeSliceIndex < sliceCount - 1,
                    onPrevSlice: () => _selectSlice(score, safeSliceIndex - 1),
                    onNextSlice: () => _selectSlice(score, safeSliceIndex + 1),
                    onResetSlice: () => _selectSlice(score, 0),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isCompactHeight ? 6 : 12),
                child: PieceScoreViewport(
                  score: score,
                  activeSliceIndex: sliceCount == 0 ? null : safeSliceIndex,
                  handMode: _handMode,
                  wrongNoteOverlays: resolvedWrongNotes,
                  onSliceTapped: (index) => _selectSlice(score, index),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _selectVariant(ScoreVariant variant) {
    if (variant.id == _selectedVariant.id) {
      return;
    }
    setState(() {
      _selectedVariant = variant;
      _activeSliceIndex = 0;
    });
  }

  void _selectSlice(Score score, int nextIndex) {
    if (score.slices.isEmpty) {
      return;
    }
    final clamped = nextIndex.clamp(0, score.slices.length - 1);
    setState(() => _activeSliceIndex = clamped);
  }
}

class _ScoreErrorView extends StatelessWidget {
  const _ScoreErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey<String>('score_error_view'),
      child: Padding(
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
