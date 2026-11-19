import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';

/// Variant selection binding for [PieceScoreHeaderBar].
final class PieceScoreVariantControl {
  const PieceScoreVariantControl({
    required this.selectedVariant,
    required this.onSelectVariant,
  });

  final ScoreVariant selectedVariant;
  final ValueChanged<ScoreVariant> onSelectVariant;
}

/// Hand-mode selection binding for [PieceScoreHeaderBar].
final class PieceScoreHandControl {
  const PieceScoreHandControl({
    required this.handMode,
    required this.onSelectHandMode,
  });

  final HandMode handMode;
  final ValueChanged<HandMode> onSelectHandMode;
}

/// Cursor stepping callbacks (`null` disables the corresponding button).
final class PieceScoreStepControls {
  const PieceScoreStepControls({
    this.onPrevSlice,
    this.onNextSlice,
    this.onResetSlice,
  });

  final VoidCallback? onPrevSlice;
  final VoidCallback? onNextSlice;
  final VoidCallback? onResetSlice;
}

/// Measure-loop status and modal triggers displayed in [PieceScoreHeaderBar].
final class PieceScoreLoopControls {
  const PieceScoreLoopControls({
    this.loopLabel,
    this.onOpenLoopSheet,
    this.onClearLoop,
  });

  final String? loopLabel;
  final VoidCallback? onOpenLoopSheet;
  final VoidCallback? onClearLoop;
}

/// Cursor indicator and navigation bindings displayed in [PieceScoreHeaderBar].
final class PieceScoreCursorBarData {
  const PieceScoreCursorBarData({
    required this.measureNumber,
    required this.measureCount,
    this.stepControls = const PieceScoreStepControls(),
    this.loopControls = const PieceScoreLoopControls(),
  });

  final int measureNumber;
  final int measureCount;
  final PieceScoreStepControls stepControls;
  final PieceScoreLoopControls loopControls;

  bool get canStepPrev => stepControls.onPrevSlice != null;
  bool get canStepNext => stepControls.onNextSlice != null;
  bool get canReset => stepControls.onResetSlice != null;
  VoidCallback? get onPrevSlice => stepControls.onPrevSlice;
  VoidCallback? get onNextSlice => stepControls.onNextSlice;
  VoidCallback? get onResetSlice => stepControls.onResetSlice;
  String? get loopLabel => loopControls.loopLabel;
  VoidCallback? get onOpenLoopSheet => loopControls.onOpenLoopSheet;
  VoidCallback? get onClearLoop => loopControls.onClearLoop;
}

/// Responsive controls strip for variants, hand dimming, measure loops, and cursor stepping.
class PieceScoreHeaderBar extends StatelessWidget {
  const PieceScoreHeaderBar({
    super.key,
    required this.piece,
    required this.variantControl,
    required this.handControl,
    this.cursor,
  });

  final Piece piece;
  final PieceScoreVariantControl variantControl;
  final PieceScoreHandControl handControl;
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
                  selected: variant.id == variantControl.selectedVariant.id,
                  onSelected: (_) => variantControl.onSelectVariant(variant),
                ),
            ],
          ),
          if (cursor != null) const SizedBox(height: 6),
        ],
        if (cursor != null) _buildPracticeControls(colorScheme, cursor!),
      ],
    );
  }

  Widget _buildPracticeControls(
    ColorScheme colorScheme,
    PieceScoreCursorBarData activeCursor,
  ) {
    return Wrap(
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
            selected: handControl.handMode == mode,
            onSelected: (_) => handControl.onSelectHandMode(mode),
          ),
        _MeasureBadge(
          measureNumber: activeCursor.measureNumber,
          measureCount: activeCursor.measureCount,
        ),
        _CursorStepRow(cursor: activeCursor),
        if (activeCursor.onOpenLoopSheet != null)
          _LoopChipRow(cursor: activeCursor, colorScheme: colorScheme),
      ],
    );
  }

  static IconData _iconForHand(HandMode mode) => switch (mode) {
    HandMode.both => Icons.piano,
    HandMode.right => Icons.front_hand_outlined,
    HandMode.left => Icons.back_hand_outlined,
  };
}

class _LoopChipRow extends StatelessWidget {
  const _LoopChipRow({required this.cursor, required this.colorScheme});

  final PieceScoreCursorBarData cursor;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final isLoopActive = cursor.loopLabel != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ActionChip(
          key: const ValueKey<String>('score_loop_button'),
          avatar: Icon(
            Icons.repeat,
            size: 16,
            color: isLoopActive ? colorScheme.onSecondaryContainer : null,
          ),
          label: Text(cursor.loopLabel ?? 'Loop'),
          backgroundColor: isLoopActive ? colorScheme.secondaryContainer : null,
          onPressed: cursor.onOpenLoopSheet,
        ),
        if (isLoopActive && cursor.onClearLoop != null)
          IconButton(
            key: const ValueKey<String>('score_clear_loop_button'),
            tooltip: 'Clear loop',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: cursor.onClearLoop,
          ),
      ],
    );
  }
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
          tooltip: 'Restart',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.first_page),
          onPressed: cursor.canReset ? cursor.onResetSlice : null,
        ),
      ],
    );
  }
}
