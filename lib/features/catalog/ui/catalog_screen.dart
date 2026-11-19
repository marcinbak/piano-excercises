import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/features/catalog/state/catalog_providers.dart';
import 'package:piano_exercises/features/catalog/ui/catalog_feedback_views.dart';
import 'package:piano_exercises/features/catalog/ui/catalog_filter_bar.dart';
import 'package:piano_exercises/features/catalog/ui/piece_catalog_card.dart';
import 'package:piano_exercises/features/catalog/ui/score_import_sheet.dart';

/// Displays the searchable piece catalog and runtime `.mxl`/`.musicxml` importer.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({
    super.key,
    this.onSelectVariant,
    this.appBarActions = const <Widget>[],
  });

  final void Function(Piece piece, ScoreVariant variant)? onSelectVariant;
  final List<Widget> appBarActions;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  bool _isPickingFile = false;

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(catalogQueryProvider);
    final queryNotifier = ref.read(catalogQueryProvider.notifier);
    final catalogAsync = ref.watch(catalogControllerProvider);
    final errorMessage = ref.watch(catalogErrorProvider);
    final availableScales = catalogAsync.value?.availableScales ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Piece Catalog'),
        actions: <Widget>[
          ...widget.appBarActions,
          IconButton(
            key: const ValueKey<String>('catalog-import-button'),
            tooltip: 'Import score',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _isPickingFile ? null : () => unawaited(_startImport()),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (errorMessage != null) ...<Widget>[
                CatalogErrorBanner(
                  message: errorMessage,
                  onDismiss: ref.read(catalogErrorProvider.notifier).clear,
                ),
                const SizedBox(height: 12),
              ],
              CatalogFilterBar(
                searchText: query.searchText,
                selectedTier: query.difficultyFilter,
                selectedScale: query.scaleFilter,
                availableScales: availableScales,
                onSearchChanged: queryNotifier.setSearchText,
                onTierChanged: queryNotifier.setDifficultyFilter,
                onScaleChanged: queryNotifier.setScaleFilter,
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(catalogAsync, queryNotifier)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<CatalogSnapshot> catalogAsync,
    CatalogQueryNotifier queryNotifier,
  ) {
    return catalogAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Could not load piece catalog: $error'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => unawaited(
                  ref.read(catalogControllerProvider.notifier).refresh(),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (snapshot) {
        if (snapshot.totalPieceCount == 0) {
          return CatalogEmptyState(
            onImport: _isPickingFile ? null : () => unawaited(_startImport()),
          );
        }
        if (snapshot.pieces.isEmpty) {
          return CatalogNoMatchesState(
            onClearFilters: queryNotifier.clearFilters,
          );
        }
        return ListView.builder(
          key: const ValueKey<String>('catalog-piece-list'),
          itemCount: snapshot.pieces.length,
          itemBuilder: (context, index) {
            final piece = snapshot.pieces[index];
            return PieceCatalogCard(
              piece: piece,
              onSelectVariant: widget.onSelectVariant,
              onAttachVariant: () =>
                  unawaited(_startImport(initialTargetPiece: piece)),
              onDeletePiece: () => unawaited(_confirmDeletePiece(piece)),
              onDeleteVariant: (variant) =>
                  unawaited(_confirmDeleteVariant(piece, variant)),
            );
          },
        );
      },
    );
  }

  Future<void> _startImport({Piece? initialTargetPiece}) async {
    if (_isPickingFile) {
      return;
    }
    setState(() => _isPickingFile = true);
    try {
      final candidate = await ref
          .read(catalogControllerProvider.notifier)
          .pickCandidate();
      if (!mounted || candidate == null) {
        return;
      }
      final List<Piece> existingPieces;
      try {
        existingPieces = await ref
            .read(catalogRepositoryProvider)
            .queryPieces();
      } catch (error) {
        if (mounted) {
          final message = error is CatalogStorageException
              ? error.message
              : error.toString();
          ref.read(catalogErrorProvider.notifier).setError(message);
        }
        return;
      }
      if (!mounted) {
        return;
      }
      await ScoreImportSheet.show(
        context,
        candidate: candidate,
        existingPieces: existingPieces,
        initialTargetPiece: initialTargetPiece,
      );
    } finally {
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }
  }

  Future<void> _confirmDeletePiece(Piece piece) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: 'Delete Piece?',
      message:
          'Remove "${piece.title}" and its ${piece.variants.length} '
          'imported score file(s)?',
    );
    if (confirmed == true && mounted) {
      await ref.read(catalogControllerProvider.notifier).deletePiece(piece.id);
    }
  }

  Future<void> _confirmDeleteVariant(Piece piece, ScoreVariant variant) async {
    final isLast = piece.variants.length == 1;
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: 'Remove Arrangement?',
      message: isLast
          ? 'Removing the last arrangement (${variant.label}) will also delete "${piece.title}".'
          : 'Remove "${variant.label}" (${variant.fileName}) from "${piece.title}"?',
    );
    if (confirmed == true && mounted) {
      await ref
          .read(catalogControllerProvider.notifier)
          .deleteVariant(pieceId: piece.id, variantId: variant.id);
    }
  }
}
