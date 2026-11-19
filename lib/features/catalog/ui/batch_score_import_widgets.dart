import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_batch_import_planner.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';

/// Summary badge wrap displaying planned import, duplicate, ignored, and failure counts.
class BatchImportSummaryChips extends StatelessWidget {
  const BatchImportSummaryChips({
    super.key,
    required this.plan,
    required this.selection,
  });

  final CatalogBatchImportPlan plan;
  final ScoreImportSelection selection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final attachedCount = plan.attachments.fold<int>(
      0,
      (sum, item) => sum + item.variants.length,
    );
    final newCount = plan.newPieces.length;
    final dupCount = plan.skippedDuplicates.length;
    final ignoredCount = selection.ignoredNonScoreCount;
    final failureCount = selection.failures.length;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: <Widget>[
        _SummaryTag(
          label: '$newCount new ${newCount == 1 ? 'piece' : 'pieces'}',
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
        ),
        if (attachedCount > 0)
          _SummaryTag(
            label: '$attachedCount attached',
            backgroundColor: colorScheme.secondaryContainer,
            foregroundColor: colorScheme.onSecondaryContainer,
          ),
        if (dupCount > 0)
          _SummaryTag(
            label:
                '$dupCount ${dupCount == 1 ? 'duplicate' : 'duplicates'} skipped',
            backgroundColor: colorScheme.surfaceContainerHighest,
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
        if (ignoredCount > 0)
          _SummaryTag(
            label:
                '$ignoredCount ignored non-score ${ignoredCount == 1 ? 'file' : 'files'}',
            backgroundColor: colorScheme.surfaceContainerHighest,
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
        if (failureCount > 0)
          _SummaryTag(
            label: '$failureCount failed',
            backgroundColor: colorScheme.errorContainer,
            foregroundColor: colorScheme.onErrorContainer,
          ),
      ],
    );
  }
}

/// Controls auto-detect vs single-tier override and the default/override [DifficultyTier].
class BatchTierModeControls extends StatelessWidget {
  const BatchTierModeControls({
    super.key,
    required this.overrideInferredTiers,
    required this.selectedTier,
    required this.enabled,
    required this.onModeChanged,
    required this.onTierChanged,
  });

  final bool overrideInferredTiers;
  final DifficultyTier selectedTier;
  final bool enabled;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<DifficultyTier> onTierChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Difficulty Tiers', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            ChoiceChip(
              key: const ValueKey<String>('batch-tier-mode-auto'),
              showCheckmark: false,
              label: const Text('Auto-detect'),
              selected: !overrideInferredTiers,
              onSelected: enabled ? (_) => onModeChanged(false) : null,
            ),
            ChoiceChip(
              key: const ValueKey<String>('batch-tier-mode-override'),
              showCheckmark: false,
              label: const Text('One tier for all'),
              selected: overrideInferredTiers,
              onSelected: enabled ? (_) => onModeChanged(true) : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          overrideInferredTiers
              ? 'Tier for all imported scores'
              : 'Default tier (when filename/title has no hint)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            for (final tier in DifficultyTier.values)
              ChoiceChip(
                key: ValueKey<String>('batch-tier-chip-${tier.tier}'),
                showCheckmark: false,
                label: Text(tier.label),
                selected: selectedTier == tier,
                onSelected: enabled ? (_) => onTierChanged(tier) : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _SummaryTag extends StatelessWidget {
  const _SummaryTag({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foregroundColor),
      ),
    );
  }
}
