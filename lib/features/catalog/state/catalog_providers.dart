import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_batch_import_planner.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_import_coordinator.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_query.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:piano_exercises/features/catalog/state/catalog_dependencies.dart';
import 'package:piano_exercises/features/catalog/state/catalog_query_state.dart';
import 'package:piano_exercises/shared/music/music.dart';

export 'package:piano_exercises/features/catalog/state/catalog_dependencies.dart'
    show
        catalogClockMsProvider,
        catalogIdGeneratorProvider,
        catalogImportCoordinatorProvider,
        catalogRepositoryProvider,
        scoreFileStoreProvider,
        scoreImportSourceProvider,
        scoreParserProvider;
export 'package:piano_exercises/features/catalog/state/catalog_query_state.dart'
    show
        CatalogErrorNotifier,
        CatalogQueryNotifier,
        CatalogSnapshot,
        catalogErrorProvider,
        catalogQueryProvider;

/// Manages catalog query results and runtime `.mxl`/`.musicxml` import mutations.
class CatalogController extends AsyncNotifier<CatalogSnapshot> {
  @override
  Future<CatalogSnapshot> build() async {
    final repository = ref.watch(catalogRepositoryProvider);
    final query = ref.watch(catalogQueryProvider);
    return _loadSnapshot(repository, query);
  }

  Future<ScoreImportSelection?> pickSelection() async {
    ref.read(catalogErrorProvider.notifier).clear();
    try {
      final selection = await ref
          .read(scoreImportSourceProvider)
          .pickAndParseScores();
      return ref.mounted ? selection : null;
    } catch (error) {
      if (ref.mounted) {
        ref.read(catalogErrorProvider.notifier).setError(_formatError(error));
      }
      return null;
    }
  }

  Future<CatalogBatchImportResult?> importBatch(CatalogBatchImportPlan plan) {
    return _runMutation(
      () => ref.read(catalogImportCoordinatorProvider).executeBatchImport(plan),
    );
  }

  Future<Piece?> importAsNewPiece({
    required ImportedScoreCandidate candidate,
    required String title,
    required String artist,
    required DifficultyTier difficultyTier,
    String? variantLabel,
  }) {
    return _runMutation(
      () => ref
          .read(catalogImportCoordinatorProvider)
          .createPieceFromCandidate(
            candidate: candidate,
            title: title,
            artist: artist,
            difficultyTier: difficultyTier,
            variantLabel: variantLabel,
          ),
    );
  }

  Future<Piece?> importAsVariant({
    required String pieceId,
    required ImportedScoreCandidate candidate,
    required DifficultyTier difficultyTier,
    String? variantLabel,
  }) {
    return _runMutation(
      () => ref
          .read(catalogImportCoordinatorProvider)
          .attachVariantFromCandidate(
            pieceId: pieceId,
            candidate: candidate,
            difficultyTier: difficultyTier,
            variantLabel: variantLabel,
          ),
    );
  }

  Future<void> deleteVariant({
    required String pieceId,
    required String variantId,
  }) {
    return _runDeletion(
      () => ref
          .read(catalogImportCoordinatorProvider)
          .deleteVariant(pieceId: pieceId, variantId: variantId),
    );
  }

  Future<void> deletePiece(String pieceId) {
    return _runDeletion(
      () => ref.read(catalogImportCoordinatorProvider).deletePiece(pieceId),
    );
  }

  Future<void> refresh() async {
    final query = ref.read(catalogQueryProvider);
    final repository = ref.read(catalogRepositoryProvider);
    state = const AsyncLoading<CatalogSnapshot>();
    try {
      final snapshot = await _loadSnapshot(repository, query);
      if (!ref.mounted || ref.read(catalogQueryProvider) != query) {
        return;
      }
      state = AsyncData<CatalogSnapshot>(snapshot);
    } catch (error, stackTrace) {
      if (!ref.mounted || ref.read(catalogQueryProvider) != query) {
        return;
      }
      state = AsyncError<CatalogSnapshot>(error, stackTrace);
    }
  }

  Future<T?> _runMutation<T>(Future<T> Function() action) async {
    ref.read(catalogErrorProvider.notifier).clear();
    try {
      final result = await action();
      if (!ref.mounted) {
        return result;
      }
      await _reloadSnapshot();
      return result;
    } catch (error) {
      if (ref.mounted) {
        ref.read(catalogErrorProvider.notifier).setError(_formatError(error));
      }
      return null;
    }
  }

  Future<void> _runDeletion(Future<Object?> Function() action) async {
    ref.read(catalogErrorProvider.notifier).clear();
    Object? deletionError;
    try {
      await action();
    } catch (error) {
      deletionError = error;
    }
    if (!ref.mounted) {
      return;
    }
    // Reload even when post-DB file cleanup fails so UI matches committed DB state.
    try {
      await _reloadSnapshot();
    } catch (reloadError) {
      deletionError ??= reloadError;
    }
    if (deletionError != null && ref.mounted) {
      ref
          .read(catalogErrorProvider.notifier)
          .setError(_formatError(deletionError));
    }
  }

  Future<void> _reloadSnapshot() async {
    final query = ref.read(catalogQueryProvider);
    final snapshot = await _loadSnapshot(
      ref.read(catalogRepositoryProvider),
      query,
    );
    if (!ref.mounted || ref.read(catalogQueryProvider) != query) {
      return;
    }
    state = AsyncData<CatalogSnapshot>(snapshot);
  }

  static Future<CatalogSnapshot> _loadSnapshot(
    CatalogRepository repository,
    CatalogQuery query,
  ) async {
    final pieces = await repository.queryPieces(query);
    final availableScales = await repository.listAvailableScales();
    final totalPieceCount = query.hasActiveFilters
        ? await repository.countPieces()
        : pieces.length;
    return CatalogSnapshot(
      pieces: List<Piece>.unmodifiable(pieces),
      availableScales: List<Scale>.unmodifiable(availableScales),
      totalPieceCount: totalPieceCount,
    );
  }

  static String _formatError(Object error) {
    if (error is ScoreParseException) {
      return error.message;
    }
    if (error is CatalogStorageException) {
      return error.message;
    }
    if (error is ArgumentError) {
      return error.message?.toString() ?? error.toString();
    }
    return error.toString();
  }
}

final catalogControllerProvider =
    AsyncNotifierProvider<CatalogController, CatalogSnapshot>(
      CatalogController.new,
    );
