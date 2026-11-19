import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_batch_import_planner.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';

/// Capped inline list of per-entry import failures (`<= 5` shown + remainder note).
class BatchFailuresPreview extends StatelessWidget {
  const BatchFailuresPreview({super.key, required this.failures});

  static const int maxVisible = 5;

  final List<ScoreImportFailure> failures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visible = failures.take(maxVisible);
    final remaining = failures.length - maxVisible;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Skipped due to errors (${failures.length})',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 6),
          for (final failure in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${failure.sourceName}: ${failure.message}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
          if (remaining > 0)
            Text(
              '...and $remaining more',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
        ],
      ),
    );
  }
}

/// Capped inline preview of planned new pieces and attachments (`<= 20` shown + remainder note).
class BatchPlanPreviewList extends StatelessWidget {
  const BatchPlanPreviewList({super.key, required this.plan});

  static const int maxVisible = 20;

  final CatalogBatchImportPlan plan;

  @override
  Widget build(BuildContext context) {
    final items = _buildPreviewItems();
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final visible = items.take(maxVisible);
    final remaining = items.length - maxVisible;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Planned Catalog Changes', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final item in visible) _PreviewRow(item: item),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '...and $remaining more',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  List<_BatchPreviewItem> _buildPreviewItems() {
    return <_BatchPreviewItem>[
      for (final piece in plan.newPieces)
        _BatchPreviewItem(
          title: piece.artist.isEmpty
              ? piece.title
              : '${piece.title} — ${piece.artist}',
          subtitle: 'New • ${_formatVariantsSummary(piece.variants)}',
        ),
      for (final attachment in plan.attachments)
        _BatchPreviewItem(
          title: attachment.targetPiece.artist.isEmpty
              ? attachment.targetPiece.title
              : '${attachment.targetPiece.title} — ${attachment.targetPiece.artist}',
          subtitle: 'Attach • ${_formatVariantsSummary(attachment.variants)}',
        ),
    ];
  }

  static String _formatVariantsSummary(List<PlannedBatchVariant> variants) {
    if (variants.length == 1) {
      final v = variants.first;
      return 'Tier ${v.difficultyTier.tier}: ${v.difficultyTier.label} (${v.effectiveFileName})';
    }
    final tiers = variants
        .map((v) => 'T${v.difficultyTier.tier}')
        .toSet()
        .join(', ');
    return '${variants.length} arrangements ($tiers)';
  }
}

final class _BatchPreviewItem {
  const _BatchPreviewItem({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.item});

  final _BatchPreviewItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
