import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_import_coordinator.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_score_save_coordinator.dart';
import 'package:piano_exercises/features/catalog/domain/in_memory_catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/score_file_store.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:piano_exercises/features/catalog/domain/score_serializer.dart';

/// Parses imported `.mxl` and `.musicxml` score bytes; overridden in `app/` and tests.
final scoreParserProvider = Provider<ScoreParser>((ref) {
  throw UnimplementedError(
    'scoreParserProvider must be overridden in ProviderScope.',
  );
});

/// Serializes edited/composed [Score]s into `.musicxml` bytes; overridden in `app/` and tests.
final scoreSerializerProvider = Provider<ScoreSerializer>((ref) {
  throw UnimplementedError(
    'scoreSerializerProvider must be overridden in ProviderScope.',
  );
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

/// Interactive score file picker and parser boundary; overridden in `app/` and tests.
final scoreImportSourceProvider = Provider<ScoreImportSource>((ref) {
  throw UnimplementedError(
    'scoreImportSourceProvider must be overridden in ProviderScope.',
  );
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

/// Coordinates score serialization, atomic file writes, and catalog save mutations.
final catalogScoreSaveCoordinatorProvider =
    Provider<CatalogScoreSaveCoordinator>((ref) {
      return CatalogScoreSaveCoordinator(
        catalogRepository: ref.watch(catalogRepositoryProvider),
        scoreFileStore: ref.watch(scoreFileStoreProvider),
        scoreSerializer: ref.watch(scoreSerializerProvider),
        clockMs: ref.watch(catalogClockMsProvider),
        generateId: ref.watch(catalogIdGeneratorProvider),
      );
    });

/// Monotonic version bumped on every catalog write/delete to invalidate cached variant scores.
class CatalogMutationVersionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state += 1;
}

final catalogMutationVersionProvider =
    NotifierProvider<CatalogMutationVersionNotifier, int>(
      CatalogMutationVersionNotifier.new,
    );
