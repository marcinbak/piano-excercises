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
  Future<Piece> updateVariant(CatalogVariantUpdate update) =>
      _delegate.updateVariant(update);

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<Piece> createPiece(Piece piece) => _delegate.createPiece(piece);

  @override
  Future<void> applyBatch(CatalogBatchMutation batch) =>
      _delegate.applyBatch(batch);

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
      expect(
        () => container.read(scoreSerializerProvider),
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

  test(
    'importBatch reloads CatalogSnapshot once after committing a batch',
    () async {
      final repo = _ControllableCatalogRepository();
      final store = InMemoryScoreFileStore();
      var nextId = 0;

      final container = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWith((ref) {
            ref.onDispose(repo.close);
            return repo;
          }),
          scoreFileStoreProvider.overrideWithValue(store),
          catalogClockMsProvider.overrideWithValue(() => 1700000000000),
          catalogIdGeneratorProvider.overrideWithValue(() => 'id_${++nextId}'),
        ],
      );
      addTearDown(container.dispose);

      await container.read(catalogControllerProvider.future);
      repo.queryPiecesCalls = 0;

      final cMajor = Scale.fromKeySignature(KeySignature.cMajor);
      ImportedScoreCandidate candidate(String name, String title) {
        final score = Score(
          title: title,
          artist: 'Bartók',
          scale: cMajor,
          timeSignature: TimeSignature.common,
          measures: const <ScoreMeasure>[],
        );
        return ImportedScoreCandidate(
          fileName: name,
          bytes: Uint8List.fromList(name.codeUnits),
          parsedScore: ParsedScore(
            score: score,
            metadata: ScoreMetadata(
              title: title,
              artist: 'Bartók',
              scale: cMajor,
              timeSignature: TimeSignature.common,
              measureCount: 1,
              sourceFormat: ScoreFormat.mxl,
            ),
          ),
        );
      }

      final plan = CatalogBatchImportPlanner.plan(
        existingPieces: const <Piece>[],
        candidates: <ImportedScoreCandidate>[
          candidate('a.mxl', 'Piece A'),
          candidate('b.mxl', 'Piece B'),
          candidate('c.mxl', 'Piece C'),
        ],
      );
      final result = await container
          .read(catalogControllerProvider.notifier)
          .importBatch(plan);

      expect(result?.createdPieceCount, 3);
      expect(repo.queryPiecesCalls, 1);
      expect(
        container.read(catalogControllerProvider).value?.pieces,
        hasLength(3),
      );
    },
  );

  test('CatalogController saveScoreAsNewPiece, saveScoreAsVariant, updateVariantScore bump mutation version', () async {
    final repo = _ControllableCatalogRepository();
    final store = InMemoryScoreFileStore();
    var nextId = 0;
    var nowMs = 100;
    final container = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWith((ref) {
          ref.onDispose(repo.close);
          return repo;
        }),
        scoreFileStoreProvider.overrideWithValue(store),
        scoreSerializerProvider.overrideWithValue(
          const MusicXmlScoreSerializer(),
        ),
        catalogIdGeneratorProvider.overrideWithValue(() => 'm_${++nextId}'),
        catalogClockMsProvider.overrideWithValue(() => ++nowMs),
      ],
    );
    addTearDown(container.dispose);

    await container.read(catalogControllerProvider.future);
    expect(container.read(catalogMutationVersionProvider), 0);

    final score = ScoreTimelineReducer.reduce(
      title: 'Draft',
      initialScale: Scale.fromKeySignature(KeySignature.cMajor),
      initialTimeSignature: TimeSignature.common,
      measures: <MeasureTimelineInput>[
        MeasureTimelineInput(
          measureNumber: 1,
          notes: <NoteTimelineInput>[
            NoteTimelineInput(
              clef: Clef.treble,
              diatonicNote: DiatonicNote.c,
              octave: 4,
              beatOffset: const RationalBeats.zero(),
              duration: DurationValue(base: NoteBaseDuration.quarter),
            ),
          ],
        ),
      ],
    );
    final controller = container.read(catalogControllerProvider.notifier);

    final created = await controller.saveScoreAsNewPiece(
      score: score,
      details: const CatalogScoreSaveDetails(
        title: 'Composed One',
        artist: 'Editor',
        difficultyTier: DifficultyTier.beginner,
      ),
    );
    expect(created, isNotNull);
    expect(container.read(catalogMutationVersionProvider), 1);

    final attached = await controller.saveScoreAsVariant(
      pieceId: created!.id,
      score: score,
      difficultyTier: DifficultyTier.intermediate,
      variantLabel: 'Harder',
    );
    expect(attached?.variants, hasLength(2));
    expect(container.read(catalogMutationVersionProvider), 2);

    final updated = await controller.updateVariantScore(
      existingVariant: created.variants.single,
      score: score,
      details: const CatalogScoreSaveDetails(
        title: 'Composed Updated',
        artist: 'Editor 2',
        difficultyTier: DifficultyTier.elementary,
      ),
    );
    expect(updated?.title, 'Composed Updated');
    expect(container.read(catalogMutationVersionProvider), 3);
  });
}
