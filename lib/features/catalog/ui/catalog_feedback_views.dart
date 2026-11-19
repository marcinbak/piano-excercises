import 'package:material_ui/material_ui.dart';

/// Dismissible error banner displayed at the top of the catalog screen.
class CatalogErrorBanner extends StatelessWidget {
  const CatalogErrorBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey<String>('catalog-error-banner'),
      color: colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
            IconButton(
              key: const ValueKey<String>('catalog-error-dismiss-button'),
              tooltip: 'Dismiss error',
              icon: Icon(Icons.close, color: colorScheme.onErrorContainer),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty catalog placeholder with a primary import CTA.
class CatalogEmptyState extends StatelessWidget {
  const CatalogEmptyState({super.key, required this.onImport});

  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey<String>('catalog-empty-state'),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'No pieces in your catalog yet.\nImport a .mxl or .musicxml score.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey<String>('catalog-empty-import-button'),
              onPressed: onImport,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import Score'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filtered empty state with a button to reset active search and chips.
class CatalogNoMatchesState extends StatelessWidget {
  const CatalogNoMatchesState({super.key, required this.onClearFilters});

  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey<String>('catalog-no-matches-state'),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('No pieces match your current search or filters.'),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey<String>('catalog-clear-filters-button'),
              onPressed: onClearFilters,
              child: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prompts the user to confirm deleting a piece or arrangement variant.
Future<bool?> showConfirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey<String>('confirm-delete-dialog'),
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('cancel-delete-button'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('confirm-delete-button'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
