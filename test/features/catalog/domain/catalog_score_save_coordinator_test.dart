import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/shared/music/music.dart';

final class _FailUpdateCatalogRepository implements CatalogRepository {
  _FailUpdateCatalogRepository(this._delegate);

  final InMemoryCatalogRepository _delegate;
  bool failCreate = false;
  bool failAttach = false;
  bool failUpdate = false;

  @override
  Future<Piece> createPiece(Piece piece) {
    if (failCreate) {
      throw const CatalogStorageException('Simulated create failure');
    }
    return _delegate.createPiece(piece);
  }

  @override
  Future<Piece> attachVariant({
    required String pieceId,
    required ScoreVariant variant,
  }) {
    if (failAttach) {
      throw const CatalogStorageException('Simulated attach failure');
    }
    return _delegate.attachVariant(pieceId: pieceId, variant: variant);
  }

  @override
  Future<Piece> updateVariant(CatalogVariantUpdate update) {
    if (failUpdate) {
      throw const CatalogStorageException('Simulated update failure');
    }
    return _delegate.updateVariant(update);
  }

  @override
  Future<void> applyBatch(CatalogBatchMutation batch) =>
      _delegate.applyBatch(batch);

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<int> countPieces() => _delegate.countPieces();

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

Score _sampleScore({String title = 'Draft', String artist = ''}) {
  return ScoreTimelineReducer.reduce(
    title: title,
    artist: artist,
    initialScale: Scale.fromKeySignature(const KeySignature(1)),
    initialTimeSignature: TimeSignature.common,
    measures: <MeasureTimelineInput>[
      MeasureTimelineInput(
        measureNumber: 1,
        notes: <NoteTimelineInput>[
          NoteTimelineInput(
            clef: Clef.treble,
            diatonicNote: DiatonicNote.g,
            octave: 4,
            explicitAlter: 0,
            beatOffset: const RationalBeats.zero(),
            duration: DurationValue(base: NoteBaseDuration.whole),
          ),
        ],
      ),
    ],
  );
}

void main() {
  const parser = MusicXmlScoreParser();
  const serializer = MusicXmlScoreSerializer();

  group('CatalogScoreSaveCoordinator', () {
    late InMemoryCatalogRepository baseRepo;
    late _FailUpdateCatalogRepository repo;
    late InMemoryScoreFileStore store;
    late int nextId;
    late int nowMs;
    late CatalogScoreSaveCoordinator coordinator;

    setUp(() {
      baseRepo = InMemoryCatalogRepository();
      repo = _FailUpdateCatalogRepository(baseRepo);
      store = InMemoryScoreFileStore();
      nextId = 0;
      nowMs = 1000;
      coordinator = CatalogScoreSaveCoordinator(
        catalogRepository: repo,
        scoreFileStore: store,
        scoreSerializer: serializer,
        clockMs: () => ++nowMs,
        generateId: () => 'id_${++nextId}',
      );
    });

    test(
      'saveAsNewPiece rewrites XML metadata and rolls back file on DB failure',
      () async {
        final piece = await coordinator.saveAsNewPiece(
          score: _sampleScore(title: 'Old Draft', artist: 'Old Artist'),
          details: const CatalogScoreSaveDetails(
            title: 'Morning Etude',
            artist: 'A. Composer',
            difficultyTier: DifficultyTier.elementary,
            variantLabel: 'Practice Cut',
          ),
        );

        expect(piece.title, 'Morning Etude');
        expect(piece.artist, 'A. Composer');
        final variant = piece.variants.single;
        expect(variant.label, 'Practice Cut');
        expect(variant.fileName, 'Morning_Etude.musicxml');
        expect(variant.storedRelativePath, endsWith('.musicxml'));

        final bytes = await store.readScoreBytes(variant.storedRelativePath);
        final parsed = parser.parseBytes(bytes, fileName: variant.fileName);
        expect(parsed.score.title, 'Morning Etude');
        expect(parsed.score.artist, 'A. Composer');

        repo.failCreate = true;
        await expectLater(
          () => coordinator.saveAsNewPiece(
            score: _sampleScore(),
            details: const CatalogScoreSaveDetails(
              title: 'Should Rollback',
              difficultyTier: DifficultyTier.beginner,
            ),
          ),
          throwsA(isA<CatalogStorageException>()),
        );
        expect(
          await store.purgeOrphans(await repo.listStoredRelativePaths()),
          0,
        );
      },
    );

    test('saveAsAttachedVariant uses existing piece metadata and rolls back on failure', () async {
      final created = await coordinator.saveAsNewPiece(
        score: _sampleScore(),
        details: const CatalogScoreSaveDetails(
          title: 'Sonatina',
          artist: 'Clementi',
          difficultyTier: DifficultyTier.beginner,
        ),
      );

      final updated = await coordinator.saveAsAttachedVariant(
        pieceId: created.id,
        score: _sampleScore(title: 'Ignored', artist: 'Ignored'),
        difficultyTier: DifficultyTier.intermediate,
        variantLabel: 'Full',
      );
      expect(updated.variants, hasLength(2));
      final attached = updated.variants.last;
      final parsed = parser.parseBytes(
        await store.readScoreBytes(attached.storedRelativePath),
      );
      expect(parsed.score.title, 'Sonatina');
      expect(parsed.score.artist, 'Clementi');

      repo.failAttach = true;
      await expectLater(
        () => coordinator.saveAsAttachedVariant(
          pieceId: created.id,
          score: _sampleScore(),
          difficultyTier: DifficultyTier.advanced,
        ),
        throwsA(isA<CatalogStorageException>()),
      );
      expect(await store.purgeOrphans(await repo.listStoredRelativePaths()), 0);
    });

    test(
      'updateVariantInPlace restores prior .musicxml bytes on DB failure',
      () async {
        final piece = await coordinator.saveAsNewPiece(
          score: _sampleScore(),
          details: const CatalogScoreSaveDetails(
            title: 'Original Title',
            artist: 'Original Artist',
            difficultyTier: DifficultyTier.beginner,
          ),
        );
        final variant = piece.variants.single;
        final priorBytes = await store.readScoreBytes(
          variant.storedRelativePath,
        );

        repo.failUpdate = true;
        await expectLater(
          () => coordinator.updateVariantInPlace(
            existingVariant: variant,
            score: _sampleScore(title: 'Corrupted New'),
            details: const CatalogScoreSaveDetails(
              title: 'Changed Title',
              artist: 'Changed Artist',
              difficultyTier: DifficultyTier.intermediate,
            ),
          ),
          throwsA(isA<CatalogStorageException>()),
        );

        expect(
          await store.readScoreBytes(variant.storedRelativePath),
          priorBytes,
        );
        expect((await repo.getPieceById(piece.id))?.title, 'Original Title');
      },
    );

    test('updateVariantInPlace upgrades .mxl -> .musicxml and rolls back on DB failure', () async {
      final mxlBytes = Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04, 1, 2]);
      final oldPath = await store.saveScoreBytes(
        variantId: 'v_mxl',
        format: ScoreFormat.mxl,
        bytes: mxlBytes,
      );
      final mxlVariant = ScoreVariant(
        id: 'v_mxl',
        pieceId: 'p_mxl',
        difficultyTier: DifficultyTier.beginner,
        label: 'Beginner',
        fileName: 'Minuet.mxl',
        storedRelativePath: oldPath,
        importedAtMs: 500,
      );
      await repo.createPiece(
        Piece(
          id: 'p_mxl',
          title: 'Minuet',
          artist: 'Bach',
          scale: Scale.fromKeySignature(const KeySignature(1)),
          variants: <ScoreVariant>[mxlVariant],
        ),
      );

      // Failure case: keeps old .mxl and removes staged .musicxml.
      repo.failUpdate = true;
      await expectLater(
        () => coordinator.updateVariantInPlace(
          existingVariant: mxlVariant,
          score: _sampleScore(),
          details: const CatalogScoreSaveDetails(
            title: 'Minuet Revised',
            artist: 'J. S. Bach',
            difficultyTier: DifficultyTier.intermediate,
          ),
        ),
        throwsA(isA<CatalogStorageException>()),
      );
      expect(await store.readScoreBytes('scores/v_mxl.mxl'), mxlBytes);
      await expectLater(
        store.readScoreBytes('scores/v_mxl.musicxml'),
        throwsA(isA<CatalogStorageException>()),
      );

      // Success case: commits .musicxml and deletes old .mxl.
      repo.failUpdate = false;
      final updated = await coordinator.updateVariantInPlace(
        existingVariant: mxlVariant,
        score: _sampleScore(),
        details: const CatalogScoreSaveDetails(
          title: 'Minuet Revised',
          artist: 'J. S. Bach',
          difficultyTier: DifficultyTier.intermediate,
          variantLabel: 'Edited',
        ),
      );
      final updatedVariant = updated.variants.single;
      expect(updated.title, 'Minuet Revised');
      expect(updated.artist, 'J. S. Bach');
      expect(updatedVariant.fileName, 'Minuet.musicxml');
      expect(updatedVariant.storedRelativePath, 'scores/v_mxl.musicxml');
      expect(updatedVariant.difficultyTier, DifficultyTier.intermediate);
      expect(updatedVariant.label, 'Edited');
      await expectLater(
        store.readScoreBytes('scores/v_mxl.mxl'),
        throwsA(isA<CatalogStorageException>()),
      );
      final reparsed = parser.parseBytes(
        await store.readScoreBytes('scores/v_mxl.musicxml'),
      );
      expect(reparsed.score.title, 'Minuet Revised');
      expect(reparsed.score.artist, 'J. S. Bach');
    });
  });
}
