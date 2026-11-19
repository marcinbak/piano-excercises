import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';

/// Cursor indicator and navigation callbacks displayed in [PieceScoreHeaderBar].
final class PieceScoreCursorBarData {
  const PieceScoreCursorBarData({
    required this.measureNumber,
    required this.measureCount,
    required this.canStepPrev,
    required this.canStepNext,
    this.onPrevSlice,
    this.onNextSlice,
    this.onResetSlice,
  });

  final int measureNumber;
  final int measureCount;
  final bool canStepPrev;
  final bool canStepNext;
  final VoidCallback? onPrevSlice;
  final VoidCallback? onNextSlice;
  final VoidCallback? onResetSlice;
}

/// Responsive controls strip for variants, hand dimming, and cursor stepping.
class PieceScoreHeaderBar extends StatelessWidget {
  const PieceScoreHeaderBar({
    super.key,
    required this.piece,
    required this.selectedVariant,
    required this.onSelectVariant,
    required this.handMode,
    required this.onSelectHandMode,
    this.cursor,
  });

  final Piece piece;
  final ScoreVariant selectedVariant;
  final ValueChanged<ScoreVariant> onSelectVariant;
  final HandMode handMode;
  final ValueChanged<HandMode> onSelectHandMode;
  final PieceScoreCursorBarData? cursor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final showVariants = piece.variants.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (piece.artist.isNotEmpty) ...<Widget>[
          Text(
            piece.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (showVariants) ...<Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              for (final variant in piece.variants)
                ChoiceChip(
                  key: ValueKey<String>('variant_chip_${variant.id}'),
                  showCheckmark: false,
                  label: Text(
                    'Tier ${variant.difficultyTier.tier}: ${variant.label}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: variant.id == selectedVariant.id,
                  onSelected: (_) => onSelectVariant(variant),
                ),
            ],
          ),
          if (cursor != null) const SizedBox(height: 6),
        ],
        if (cursor != null)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final mode in HandMode.values)
                ChoiceChip(
                  key: ValueKey<String>('hand_mode_${mode.name}'),
                  showCheckmark: false,
                  avatar: Icon(_iconForHand(mode), size: 16),
                  label: Text(mode.label),
                  selected: handMode == mode,
                  onSelected: (_) => onSelectHandMode(mode),
                ),
              _MeasureBadge(
                measureNumber: cursor!.measureNumber,
                measureCount: cursor!.measureCount,
              ),
              _CursorStepRow(cursor: cursor!),
            ],
          ),
      ],
    );
  }

  static IconData _iconForHand(HandMode mode) => switch (mode) {
    HandMode.both => Icons.piano,
    HandMode.right => Icons.front_hand_outlined,
    HandMode.left => Icons.back_hand_outlined,
  };
}

class _MeasureBadge extends StatelessWidget {
  const _MeasureBadge({
    required this.measureNumber,
    required this.measureCount,
  });

  final int measureNumber;
  final int measureCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      key: const ValueKey<String>('score_measure_indicator'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Measure $measureNumber / $measureCount',
        style: theme.textTheme.labelLarge?.copyWith(
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _CursorStepRow extends StatelessWidget {
  const _CursorStepRow({required this.cursor});

  final PieceScoreCursorBarData cursor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          key: const ValueKey<String>('score_prev_slice'),
          tooltip: 'Previous beat',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left),
          onPressed: cursor.canStepPrev ? cursor.onPrevSlice : null,
        ),
        IconButton(
          key: const ValueKey<String>('score_next_slice'),
          tooltip: 'Next beat',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right),
          onPressed: cursor.canStepNext ? cursor.onNextSlice : null,
        ),
        IconButton(
          key: const ValueKey<String>('score_reset_slice'),
          tooltip: 'Reset cursor',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.first_page),
          onPressed: cursor.canStepPrev ? cursor.onResetSlice : null,
        ),
      ],
    );
  }
}
