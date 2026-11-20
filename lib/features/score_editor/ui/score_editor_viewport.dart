import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:piano_exercises/shared/notation/notation.dart';
import 'package:smufl_notation/smufl_notation.dart';

/// Builds a transient catalog [Piece] wrapper for practicing an unsaved editor draft.
Piece buildEditorPreviewPiece(ScoreDraft draft, ScoreVariant? boundVariant) {
  final title = draft.title.trim().isEmpty ? 'Preview' : draft.title.trim();
  return Piece(
    id: 'editor_preview_piece',
    title: title,
    artist: draft.artist,
    scale: draft.scale,
    variants: <ScoreVariant>[
      ScoreVariant(
        id: 'editor_preview_variant',
        pieceId: 'editor_preview_piece',
        difficultyTier: boundVariant?.difficultyTier ?? DifficultyTier.beginner,
        label: boundVariant?.label ?? 'Preview',
        fileName: 'preview.musicxml',
        storedRelativePath: 'scores/editor_preview_variant.musicxml',
        importedAtMs: 0,
      ),
    ],
  );
}

/// Centered error/retry view shown when loading a bound arrangement fails.
class ScoreEditorLoadErrorView extends StatelessWidget {
  const ScoreEditorLoadErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(
              'Could not open arrangement: $message',
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Material-3 themed grand-staff viewport memoizing [ScoreNotationMapper.mapScore].
class ScoreEditorViewport extends StatefulWidget {
  const ScoreEditorViewport({
    super.key,
    required this.score,
    this.activeSliceIndex,
    this.onSliceTapped,
  });

  final Score score;
  final int? activeSliceIndex;
  final ValueChanged<int>? onSliceTapped;

  @override
  State<ScoreEditorViewport> createState() => _ScoreEditorViewportState();
}

class _ScoreEditorViewportState extends State<ScoreEditorViewport> {
  late NotationScore _notationScore;

  @override
  void initState() {
    super.initState();
    _notationScore = ScoreNotationMapper.mapScore(widget.score);
  }

  @override
  void didUpdateWidget(covariant ScoreEditorViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.score, widget.score)) {
      _notationScore = ScoreNotationMapper.mapScore(widget.score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = ScoreStyle(
      inkColor: colorScheme.onSurface,
      staffLineColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      cursorColor: colorScheme.primary.withValues(alpha: 0.16),
      errorColor: colorScheme.error,
      dimmedOpacity: 0.32,
    );

    return Card(
      key: const ValueKey<String>('editor-score-viewport'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: GrandStaffScoreView(
        score: _notationScore,
        style: style,
        activeSliceIndex: widget.activeSliceIndex,
        onSliceTapped: widget.onSliceTapped,
      ),
    );
  }
}
