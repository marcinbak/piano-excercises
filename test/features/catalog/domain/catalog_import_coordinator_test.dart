import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/shared/music/music.dart';

class _FailingCatalogRepository implements CatalogRepository {
  _FailingCatalogRepository(this._delegate);

  final InMemoryCatalogRepository _delegate;
  bool failCreate = false;
  bool failAttach = false;

  @override
  Future<Piece> createPiece(Piece piece) {
    if (failCreate) {
      throw const CatalogStorageException('Simulated DB create failure');
    }
    return _delegate.createPiece(piece);
  }

  @override
  Future<Piece> attachVariant({
    required String pieceId,
    required ScoreVariant variant,
  }) {
    if (failAttach) {
      throw const CatalogStorageException('Simulated DB attach failure');
    }
    return _delegate.attachVariant(pieceId: pieceId, variant: variant);
  }

  @override
  Future<void> close() => _delegate.close();

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

  @override
  Future<List<Piece>> queryPieces([
    CatalogQuery query = const CatalogQuery(),
  ]) => _delegate.queryPieces(query);
}

ImportedScoreCandidate _makeCandidate({
  String fileName = 'prelude.mxl',
  ScoreFormat format = ScoreFormat.mxl,
}) {
  final scale = Scale.fromKeySignature(KeySignature.cMajor);
  final score = Score(
    title: 'Prelude',
    artist: 'Bach',
    scale: scale,
    timeSignature: TimeSignature.common,
    measures: const <ScoreMeasure>[],
  );
  return ImportedScoreCandidate(
    fileName: fileName,
    bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    parsedScore: ParsedScore(
      score: score,
      metadata: ScoreMetadata(
        title: 'Prelude',
        artist: 'Bach',
        scale: scale,
        timeSignature: TimeSignature.common,
        measureCount: 1,
        sourceFormat: format,
      ),
    ),
  );
}

void main() {
  late InMemoryCatalogRepository innerRepo;
  late _FailingCatalogRepository repo;
  late InMemoryScoreFileStore store;
  late CatalogImportCoordinator coordinator;
  var nextId = 0;

  setUp(() {
    nextId = 0;
    innerRepo = InMemoryCatalogRepository();
    repo = _FailingCatalogRepository(innerRepo);
    store = InMemoryScoreFileStore();
    coordinator = CatalogImportCoordinator(
      catalogRepository: repo,
      scoreFileStore: store,
      clockMs: () => 1700000000000,
      generateId: () => 'id_${++nextId}',
    );
  });

  tearDown(() => repo.close());

  test('createPieceFromCandidate trims metadata, stores bytes, and rejects empty title', () async {
    final candidate = _makeCandidate();
    await expectLater(
      () => coordinator.createPieceFromCandidate(
        candidate: candidate,
        title: '   ',
        artist: 'Bach',
        difficultyTier: DifficultyTier.beginner,
      ),
      throwsArgumentError,
    );
    expect(await store.purgeOrphans(<String>{}), 0);

    final created = await coordinator.createPieceFromCandidate(
      candidate: candidate,
      title: '  Prelude in C  ',
      artist: '  J.S. Bach  ',
      difficultyTier: DifficultyTier.elementary,
    );
    expect(created.title, 'Prelude in C');
    expect(created.artist, 'J.S. Bach');
    expect(created.variants.single.label, 'Elementary');
    expect(
      await store.readScoreBytes(created.variants.single.storedRelativePath),
      candidate.bytes,
    );
  });

  test(
    'rolls back saved score file when createPiece or attachVariant throws',
    () async {
      final candidate = _makeCandidate();
      repo.failCreate = true;
      await expectLater(
        () => coordinator.createPieceFromCandidate(
          candidate: candidate,
          title: 'Prelude',
          artist: 'Bach',
          difficultyTier: DifficultyTier.beginner,
        ),
        throwsA(isA<CatalogStorageException>()),
      );
      expect(await store.purgeOrphans(<String>{}), 0);

      repo.failCreate = false;
      final created = await coordinator.createPieceFromCandidate(
        candidate: candidate,
        title: 'Prelude',
        artist: 'Bach',
        difficultyTier: DifficultyTier.beginner,
      );

      repo.failAttach = true;
      await expectLater(
        () => coordinator.attachVariantFromCandidate(
          pieceId: created.id,
          candidate: _makeCandidate(
            fileName: 'prelude_orig.musicxml',
            format: ScoreFormat.musicXml,
          ),
          difficultyTier: DifficultyTier.original,
          variantLabel: 'Urtext',
        ),
        throwsA(isA<CatalogStorageException>()),
      );
      expect(await store.purgeOrphans(await repo.listStoredRelativePaths()), 0);
    },
  );

  test('deleteVariant removes file & keeps piece or cascades last variant; deletePiece removes all files', () async {
    final piece = await coordinator.createPieceFromCandidate(
      candidate: _makeCandidate(fileName: 'easy.mxl'),
      title: 'Prelude',
      artist: 'Bach',
      difficultyTier: DifficultyTier.beginner,
    );
    final updated = await coordinator.attachVariantFromCandidate(
      pieceId: piece.id,
      candidate: _makeCandidate(fileName: 'hard.mxl'),
      difficultyTier: DifficultyTier.advanced,
    );
    expect(updated.variants, hasLength(2));

    final firstPath = updated.variants.first.storedRelativePath;
    final secondPath = updated.variants.last.storedRelativePath;
    final afterFirstDelete = await coordinator.deleteVariant(
      pieceId: piece.id,
      variantId: updated.variants.first.id,
    );
    expect(afterFirstDelete?.variants, hasLength(1));
    await expectLater(
      () => store.readScoreBytes(firstPath),
      throwsA(isA<CatalogStorageException>()),
    );
    expect(await store.readScoreBytes(secondPath), isNotEmpty);

    final afterLastDelete = await coordinator.deleteVariant(
      pieceId: piece.id,
      variantId: updated.variants.last.id,
    );
    expect(afterLastDelete, isNull);
    expect(await repo.getPieceById(piece.id), isNull);
    expect(await store.purgeOrphans(<String>{}), 0);

    final multi = await coordinator.createPieceFromCandidate(
      candidate: _makeCandidate(fileName: 'a.mxl'),
      title: 'Invention',
      artist: 'Bach',
      difficultyTier: DifficultyTier.elementary,
    );
    await coordinator.attachVariantFromCandidate(
      pieceId: multi.id,
      candidate: _makeCandidate(fileName: 'b.mxl'),
      difficultyTier: DifficultyTier.original,
    );
    await coordinator.deletePiece(multi.id);
    expect(await repo.queryPieces(), isEmpty);
    expect(await store.purgeOrphans(<String>{}), 0);
  });
}
