import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/catalog/data/file_picker_score_importer.dart';
import 'package:piano_exercises/features/catalog/data/musicxml_score_parser.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_import_coordinator.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_query.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/in_memory_catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/features/catalog/domain/score_file_store.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:piano_exercises/features/catalog/state/catalog_query_state.dart';
import 'package:piano_exercises/shared/music/music.dart';

export 'package:piano_exercises/features/catalog/state/catalog_query_state.dart'
    show
        CatalogErrorNotifier,
        CatalogQueryNotifier,
        CatalogSnapshot,
        catalogErrorProvider,
        catalogQueryProvider;

/// Parses imported `.mxl` and `.musicxml` score bytes.
final scoreParserProvider = Provider<ScoreParser>((ref) {
  return const MusicXmlScoreParser();
});

/// Catalog metadata persistence boundary; overridden in `app/` and tests.
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final repository = InMemoryCatalogRepository();
  ref.onDispose(() {
    unawaited(repository.close());
  });
  return repository;
});

/// Score file storage boundary; overridden in `app/` and tests.
final scoreFileStoreProvider = Provider<ScoreFileStore>((ref) {
  return InMemoryScoreFileStore();
});

/// Interactive score file picker and parser boundary.
final scoreImportSourceProvider = Provider<ScoreImportSource>((ref) {
  return FilePickerScoreImporter(parser: ref.watch(scoreParserProvider));
});

/// Wall-clock timestamp source (ms since epoch); overridable in tests.
final catalogClockMsProvider = Provider<int Function()>((ref) {
  return () => DateTime.now().millisecondsSinceEpoch;
});

/// Generates safe alphanumeric IDs for imported pieces and variants.
final catalogIdGeneratorProvider = Provider<String Function()>((ref) {
  var counter = 0;
  final random = math.Random.secure();
  return () {
    counter += 1;
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = random.nextInt(0x7fffffff).toRadixString(36);
    return 'c_${micros}_${counter}_$salt';
  };
});

/// Coordinates atomic file writes with catalog repository transactions.
final catalogImportCoordinatorProvider = Provider<CatalogImportCoordinator>((
  ref,
) {
  return CatalogImportCoordinator(
    catalogRepository: ref.watch(catalogRepositoryProvider),
    scoreFileStore: ref.watch(scoreFileStoreProvider),
    clockMs: ref.watch(catalogClockMsProvider),
    generateId: ref.watch(catalogIdGeneratorProvider),
  );
});

/// Manages catalog query results and runtime `.mxl`/`.musicxml` import mutations.
class CatalogController extends AsyncNotifier<CatalogSnapshot> {
  @override
  Future<CatalogSnapshot> build() async {
    final repository = ref.watch(catalogRepositoryProvider);
    final query = ref.watch(catalogQueryProvider);
    return _loadSnapshot(repository, query);
  }

  Future<ImportedScoreCandidate?> pickCandidate() async {
    ref.read(catalogErrorProvider.notifier).clear();
    try {
      final candidate = await ref
          .read(scoreImportSourceProvider)
          .pickAndParseScore();
      return ref.mounted ? candidate : null;
    } catch (error) {
      if (ref.mounted) {
        ref.read(catalogErrorProvider.notifier).setError(_formatError(error));
      }
      return null;
    }
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
  }) async {
    await _runMutation(
      () => ref
          .read(catalogImportCoordinatorProvider)
          .deleteVariant(pieceId: pieceId, variantId: variantId),
    );
  }

  Future<void> deletePiece(String pieceId) async {
    await _runMutation(
      () => ref.read(catalogImportCoordinatorProvider).deletePiece(pieceId),
    );
  }

  Future<void> refresh() => _reloadSnapshot();

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

  Future<void> _reloadSnapshot() async {
    final snapshot = await _loadSnapshot(
      ref.read(catalogRepositoryProvider),
      ref.read(catalogQueryProvider),
    );
    if (!ref.mounted) {
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
        ? (await repository.queryPieces()).length
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
