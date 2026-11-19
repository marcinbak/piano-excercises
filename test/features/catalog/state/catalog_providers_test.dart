import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/shared/music/music.dart';

class _ControllableCatalogRepository implements CatalogRepository {
  final InMemoryCatalogRepository _delegate = InMemoryCatalogRepository();
  int queryPiecesCalls = 0;
  int countPiecesCalls = 0;
  bool failQuery = false;
  Completer<void>? nextQueryGate;

  @override
  Future<List<Piece>> queryPieces([
    CatalogQuery query = const CatalogQuery(),
  ]) async {
    queryPiecesCalls += 1;
    final gate = nextQueryGate;
    if (gate != null) {
      nextQueryGate = null;
      await gate.future;
    }
    if (failQuery) {
      throw const CatalogStorageException('Simulated read failure');
    }
    return _delegate.queryPieces(query);
  }

  @override
  Future<int> countPieces() {
    countPiecesCalls += 1;
    return _delegate.countPieces();
  }

  @override
  Future<Piece> attachVariant({
    required String pieceId,
    required ScoreVariant variant,
  }) => _delegate.attachVariant(pieceId: pieceId, variant: variant);

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<Piece> createPiece(Piece piece) => _delegate.createPiece(piece);

  @override
  Future<void> deletePiece(String pieceId) => _delegate.deletePiece(pieceId);

  @override
  Future<Piece?> deleteVariant({
    required String pieceId,
    required String variantId,
  }) => _delegate.deleteVariant(pieceId: pieceId, variantId: variantId);

  @override
  Future<Piece?> getPieceById(String pieceId) =>
      _delegate.getPieceById(pieceId);

  @override
  Future<List<Scale>> listAvailableScales() => _delegate.listAvailableScales();

  @override
  Future<Set<String>> listStoredRelativePaths() =>
      _delegate.listStoredRelativePaths();
}

class _FailingDeleteScoreStore implements ScoreFileStore {
  final InMemoryScoreFileStore _delegate = InMemoryScoreFileStore();
  bool failDelete = false;

  @override
  Future<void> deleteScoreFile(String storedRelativePath) async {
    if (failDelete) {
      throw const CatalogStorageException('Simulated disk unlink failure');
    }
    return _delegate.deleteScoreFile(storedRelativePath);
  }

  @override
  Future<int> purgeOrphans(Set<String> activeRelativePaths) =>
      _delegate.purgeOrphans(activeRelativePaths);

  @override
  Future<Uint8List> readScoreBytes(String storedRelativePath) =>
      _delegate.readScoreBytes(storedRelativePath);

  @override
  Future<String> saveScoreBytes({
    required String variantId,
    required ScoreFormat format,
    required Uint8List bytes,
  }) => _delegate.saveScoreBytes(
    variantId: variantId,
    format: format,
    bytes: bytes,
  );
}

Piece _makePiece(String id, String title, String variantId) {
  return Piece(
    id: id,
    title: title,
    artist: 'Composer',
    scale: Scale.fromKeySignature(KeySignature.cMajor),
    variants: <ScoreVariant>[
      ScoreVariant(
        id: variantId,
        pieceId: id,
        difficultyTier: DifficultyTier.beginner,
        label: 'Beginner',
        fileName: '$id.mxl',
        storedRelativePath: 'scores/$variantId.mxl',
        importedAtMs: 1,
      ),
    ],
  );
}

void main() {
  test(
    'scoreParserProvider and scoreImportSourceProvider require overrides',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(scoreParserProvider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'exception',
            isA<UnimplementedError>(),
          ),
        ),
      );
      expect(
        () => container.read(scoreImportSourceProvider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'exception',
            isA<UnimplementedError>(),
          ),
        ),
      );
    },
  );

  test('refresh sets AsyncError on failure without throwing and guards stale queries', () async {
    final repo = _ControllableCatalogRepository();
    await repo.createPiece(_makePiece('p1', 'Alpha', 'v1'));
    await repo.createPiece(_makePiece('p2', 'Beta', 'v2'));

    final container = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWith((ref) {
          ref.onDispose(repo.close);
          return repo;
        }),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(catalogControllerProvider.future);
    expect(initial.pieces, hasLength(2));

    // Filtered query uses countPieces() instead of a second queryPieces() call.
    repo.queryPiecesCalls = 0;
    repo.countPiecesCalls = 0;
    container.read(catalogQueryProvider.notifier).setSearchText('Alpha');
    final filtered = await container.read(catalogControllerProvider.future);
    expect(filtered.pieces.map((p) => p.id), ['p1']);
    expect(filtered.totalPieceCount, 2);
    expect(repo.queryPiecesCalls, 1);
    expect(repo.countPiecesCalls, 1);

    // refresh() surfaces error as AsyncError rather than leaking an unhandled Future error.
    repo.failQuery = true;
    await container.read(catalogControllerProvider.notifier).refresh();
    expect(
      container.read(catalogControllerProvider),
      isA<AsyncError<CatalogSnapshot>>(),
    );

    // Recover on retry.
    repo.failQuery = false;
    await container.read(catalogControllerProvider.notifier).refresh();
    expect(
      container.read(catalogControllerProvider).value?.pieces.map((p) => p.id),
      ['p1'],
    );

    // Stale refresh for 'Alpha' must not overwrite newer query 'Beta'.
    final staleGate = Completer<void>();
    repo.nextQueryGate = staleGate;
    final staleRefresh = container
        .read(catalogControllerProvider.notifier)
        .refresh();
    container.read(catalogQueryProvider.notifier).setSearchText('Beta');
    final newerSnapshot = await container.read(
      catalogControllerProvider.future,
    );
    expect(newerSnapshot.pieces.map((p) => p.id), ['p2']);

    staleGate.complete();
    await staleRefresh;
    expect(
      container.read(catalogControllerProvider).value?.pieces.map((p) => p.id),
      ['p2'],
    );
  });

  test(
    'deletePiece reloads snapshot even when post-DB file unlink fails',
    () async {
      final repo = _ControllableCatalogRepository();
      final store = _FailingDeleteScoreStore();
      await store.saveScoreBytes(
        variantId: 'v1',
        format: ScoreFormat.mxl,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      await repo.createPiece(_makePiece('p1', 'Alpha', 'v1'));

      final container = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWith((ref) {
            ref.onDispose(repo.close);
            return repo;
          }),
          scoreFileStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      await container.read(catalogControllerProvider.future);
      store.failDelete = true;

      await container
          .read(catalogControllerProvider.notifier)
          .deletePiece('p1');

      expect(container.read(catalogControllerProvider).value?.pieces, isEmpty);
      expect(
        container.read(catalogErrorProvider),
        'Simulated disk unlink failure',
      );
    },
  );
}
