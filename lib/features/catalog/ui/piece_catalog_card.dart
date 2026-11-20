import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';

/// Displays a [Piece] card with metadata, actions, and attached [ScoreVariant]s.
class PieceCatalogCard extends StatelessWidget {
  const PieceCatalogCard({
    super.key,
    required this.piece,
    required this.onAttachVariant,
    required this.onDeletePiece,
    required this.onDeleteVariant,
    this.onSelectVariant,
    this.onEditVariant,
  });

  final Piece piece;
  final VoidCallback onAttachVariant;
  final VoidCallback onDeletePiece;
  final ValueChanged<ScoreVariant> onDeleteVariant;
  final void Function(Piece piece, ScoreVariant variant)? onSelectVariant;
  final void Function(Piece piece, ScoreVariant variant)? onEditVariant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      key: ValueKey<String>('piece-card-${piece.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelectVariant == null
            ? null
            : () => onSelectVariant!(piece, piece.variants.first),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(piece.title, style: theme.textTheme.titleMedium),
                        if (piece.artist.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            piece.artist,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey<String>(
                      'piece-attach-variant-button-${piece.id}',
                    ),
                    tooltip: 'Attach arrangement',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: onAttachVariant,
                  ),
                  IconButton(
                    key: ValueKey<String>('piece-delete-button-${piece.id}'),
                    tooltip: 'Delete piece',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDeletePiece,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  _MetaTag(label: piece.scale.label),
                  _MetaTag(label: piece.difficultySummary),
                  _MetaTag(
                    label: piece.variants.length == 1
                        ? '1 arrangement'
                        : '${piece.variants.length} arrangements',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final variant in piece.variants)
                _VariantRow(
                  pieceId: piece.id,
                  variant: variant,
                  onOpen: onSelectVariant == null
                      ? null
                      : () => onSelectVariant!(piece, variant),
                  onEdit: onEditVariant == null
                      ? null
                      : () => onEditVariant!(piece, variant),
                  onDelete: () => onDeleteVariant(variant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: colorScheme.onSecondaryContainer),
      ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.pieceId,
    required this.variant,
    required this.onOpen,
    required this.onDelete,
    this.onEdit,
  });

  final String pieceId;
  final ScoreVariant variant;
  final VoidCallback? onOpen;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      key: ValueKey<String>('piece-variant-badge-$pieceId-${variant.id}'),
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              key: ValueKey<String>('open_variant_${variant.id}'),
              borderRadius: BorderRadius.circular(10),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Tier ${variant.difficultyTier.tier}: ${variant.label}',
                            style: theme.textTheme.labelLarge,
                          ),
                          Text(
                            variant.fileName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onOpen != null)
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (onEdit != null)
            IconButton(
              key: ValueKey<String>('variant-edit-button-${variant.id}'),
              tooltip: 'Edit arrangement',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
            ),
          IconButton(
            key: ValueKey<String>('variant-delete-button-${variant.id}'),
            tooltip: 'Remove arrangement',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
