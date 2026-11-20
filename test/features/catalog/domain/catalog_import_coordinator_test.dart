import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/shared/music/music.dart';

class _FailingCatalogRepository implements CatalogRepository {
  _FailingCatalogRepository(this._delegate);

  final InMemoryCatalogRepository _delegate;
  bool failCreate = false;
  bool failAttach = false;
  bool failBatch = false;

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
  Future<Piece> updateVariant(CatalogVariantUpdate update) =>
      _delegate.updateVariant(update);

  @override
  Future<void> applyBatch(CatalogBatchMutation batch) {
    if (failBatch) {
      throw const CatalogStorageException('Simulated DB batch failure');
    }
    return _delegate.applyBatch(batch);
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

  @override
  Future<int> countPieces() => _delegate.countPieces();
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

  test('executeBatchImport commits new + attached scores and rolls back all written files on DB or mid-write failure', () async {
    final existing = await coordinator.createPieceFromCandidate(
      candidate: _makeCandidate(fileName: 'prelude_easy.mxl'),
      title: 'Prelude',
      artist: 'Bach',
      difficultyTier: DifficultyTier.beginner,
    );

    ImportedScoreCandidate buildCandidate({
      required String fileName,
      required String title,
      required String artist,
      required List<int> bytes,
    }) {
      final scale = Scale.fromKeySignature(KeySignature.cMajor);
      final score = Score(
        title: title,
        artist: artist,
        scale: scale,
        timeSignature: TimeSignature.common,
        measures: const <ScoreMeasure>[],
      );
      return ImportedScoreCandidate(
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        parsedScore: ParsedScore(
          score: score,
          metadata: ScoreMetadata(
            title: title,
            artist: artist,
            scale: scale,
            timeSignature: TimeSignature.common,
            measureCount: 1,
            sourceFormat: ScoreFormat.mxl,
          ),
        ),
      );
    }

    final plan = CatalogBatchImportPlanner.plan(
      existingPieces: <Piece>[existing],
      candidates: <ImportedScoreCandidate>[
        buildCandidate(
          fileName: 'prelude_easy.mxl',
          title: 'Prelude',
          artist: 'Bach',
          bytes: const <int>[1, 2, 3, 4],
        ),
        buildCandidate(
          fileName: 'prelude_advanced.mxl',
          title: 'Prelude',
          artist: 'Bach',
          bytes: const <int>[5, 6, 7],
        ),
        buildCandidate(
          fileName: 'fugue_tier2.mxl',
          title: 'Fugue',
          artist: 'Bach',
          bytes: const <int>[8, 9, 10],
        ),
      ],
    );

    // 1. Repository batch failure rolls back all newly written files while preserving existing piece file.
    repo.failBatch = true;
    await expectLater(
      () => coordinator.executeBatchImport(plan),
      throwsA(isA<CatalogStorageException>()),
    );
    expect(await store.purgeOrphans(await repo.listStoredRelativePaths()), 0);
    expect(await repo.countPieces(), 1);

    // 2. Mid-batch ScoreFileStore failure (e.g. second candidate has empty bytes) rolls back first file.
    repo.failBatch = false;
    final midFailPlan = CatalogBatchImportPlanner.plan(
      existingPieces: const <Piece>[],
      candidates: <ImportedScoreCandidate>[
        buildCandidate(
          fileName: 'good.mxl',
          title: 'Good',
          artist: 'Bach',
          bytes: const <int>[1, 2, 3],
        ),
        buildCandidate(
          fileName: 'empty.mxl',
          title: 'Bad',
          artist: 'Bach',
          bytes: const <int>[],
        ),
      ],
    );
    await expectLater(
      () => coordinator.executeBatchImport(midFailPlan),
      throwsA(isA<CatalogStorageException>()),
    );
    expect(await store.purgeOrphans(await repo.listStoredRelativePaths()), 0);

    // 3. Clean batch commit persists new piece + attachment + skips duplicate.
    final result = await coordinator.executeBatchImport(plan);
    expect(result.createdPieceCount, 1);
    expect(result.attachedVariantCount, 1);
    expect(result.skippedDuplicateCount, 1);
    expect(await repo.countPieces(), 2);
    expect((await repo.getPieceById(existing.id))?.variants, hasLength(2));
    expect(await store.purgeOrphans(await repo.listStoredRelativePaths()), 0);
  });
}
