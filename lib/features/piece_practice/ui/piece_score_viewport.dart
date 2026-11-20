import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/ui/score_notation_mapper.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:smufl_notation/smufl_notation.dart';

/// Material-3 themed grand-staff viewport memoizing [ScoreNotationMapper.mapScore].
class PieceScoreViewport extends StatefulWidget {
  const PieceScoreViewport({
    super.key,
    required this.score,
    this.activeSliceIndex,
    this.matchedSliceIndex,
    this.handMode = HandMode.both,
    this.wrongNoteOverlays = const <WrongNoteOverlay>[],
    this.onSliceTapped,
    this.controller,
  });

  final Score score;
  final int? activeSliceIndex;
  final int? matchedSliceIndex;
  final HandMode handMode;
  final List<WrongNoteOverlay> wrongNoteOverlays;
  final ValueChanged<int>? onSliceTapped;
  final ScrollController? controller;

  @override
  State<PieceScoreViewport> createState() => _PieceScoreViewportState();
}

class _PieceScoreViewportState extends State<PieceScoreViewport> {
  late NotationScore _notationScore;

  @override
  void initState() {
    super.initState();
    _notationScore = ScoreNotationMapper.mapScore(widget.score);
  }

  @override
  void didUpdateWidget(covariant PieceScoreViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.score, widget.score)) {
      _notationScore = ScoreNotationMapper.mapScore(widget.score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = ScoreStyle(
      inkColor: colorScheme.onSurface,
      staffLineColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      cursorColor: colorScheme.primary.withValues(alpha: 0.16),
      errorColor: colorScheme.error,
      successColor: theme.brightness == Brightness.dark
          ? const Color(0xFF66BB6A)
          : const Color(0xFF2E7D32),
      dimmedOpacity: 0.32,
    );

    return Card(
      key: const ValueKey<String>('piece_score_viewport'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: GrandStaffScoreView(
        score: _notationScore,
        style: style,
        activeSliceIndex: widget.activeSliceIndex,
        matchedSliceIndex: widget.matchedSliceIndex,
        activeHand: ScoreNotationMapper.mapHandMode(widget.handMode),
        wrongNoteOverlays: widget.wrongNoteOverlays,
        onSliceTapped: widget.onSliceTapped,
        controller: widget.controller,
      ),
    );
  }
}
