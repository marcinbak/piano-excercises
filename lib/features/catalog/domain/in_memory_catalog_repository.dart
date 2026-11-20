import 'package:piano_exercises/features/catalog/domain/catalog_query.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_search_normalizer.dart';
import 'package:piano_exercises/features/catalog/domain/in_memory_catalog_helpers.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Pure-Dart in-memory [CatalogRepository] with FTS-equivalent search semantics.
final class InMemoryCatalogRepository implements CatalogRepository {
  final Map<String, Piece> _pieces = <String, Piece>{};
  bool _closed = false;

  @override
  Future<List<Piece>> queryPieces([
    CatalogQuery query = const CatalogQuery(),
  ]) async {
    _ensureOpen();
    final searchTokens = CatalogSearchNormalizer.tokenize(query.searchText);
    final matches = <Piece>[];
    for (final piece in _pieces.values) {
      if (query.scaleFilter != null && piece.scale != query.scaleFilter) {
        continue;
      }
      if (query.difficultyFilter != null &&
          !piece.variants.any(
            (v) => v.difficultyTier == query.difficultyFilter,
          )) {
        continue;
      }
      if (searchTokens.isNotEmpty &&
          !matchesInMemoryCatalogSearch(piece, searchTokens)) {
        continue;
      }
      matches.add(piece);
    }
    matches.sort((a, b) {
      final titleCmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (titleCmp != 0) {
        return titleCmp;
      }
      return a.id.compareTo(b.id);
    });
    return List<Piece>.unmodifiable(matches);
  }

  @override
  Future<int> countPieces() async {
    _ensureOpen();
    return _pieces.length;
  }

  @override
  Future<List<Scale>> listAvailableScales() async {
    _ensureOpen();
    final seen = <Scale>{};
    for (final piece in _pieces.values) {
      seen.add(piece.scale);
    }
    final scales = seen.toList()
      ..sort((a, b) {
        final fifthsCmp = a.keySignature.fifths.compareTo(
          b.keySignature.fifths,
        );
        if (fifthsCmp != 0) {
          return fifthsCmp;
        }
        return a.mode.name.compareTo(b.mode.name);
      });
    return List<Scale>.unmodifiable(scales);
  }

  @override
  Future<Piece?> getPieceById(String pieceId) async {
    _ensureOpen();
    return _pieces[pieceId];
  }

  @override
  Future<Piece> createPiece(Piece piece) async {
    _ensureOpen();
    if (_pieces.containsKey(piece.id)) {
      throw CatalogStorageException('Piece ${piece.id} already exists.');
    }
    for (final variant in piece.variants) {
      if (_containsVariantId(variant.id)) {
        throw CatalogStorageException(
          'ScoreVariant ${variant.id} already exists.',
        );
      }
    }
    _pieces[piece.id] = piece;
    return piece;
  }

  @override
  Future<Piece> attachVariant({
    required String pieceId,
    required ScoreVariant variant,
  }) async {
    _ensureOpen();
    if (variant.pieceId != pieceId) {
      throw CatalogStorageException(
        'Variant pieceId ${variant.pieceId} does not match $pieceId.',
      );
    }
    final existing = _pieces[pieceId];
    if (existing == null) {
      throw CatalogStorageException('Piece $pieceId not found.');
    }
    if (_containsVariantId(variant.id)) {
      throw CatalogStorageException(
        'ScoreVariant ${variant.id} already exists.',
      );
    }
    final updated = Piece(
      id: existing.id,
      title: existing.title,
      artist: existing.artist,
      scale: existing.scale,
      variants: <ScoreVariant>[...existing.variants, variant],
    );
    _pieces[pieceId] = updated;
    return updated;
  }

  @override
  Future<void> applyBatch(CatalogBatchMutation batch) async {
    _ensureOpen();
    if (batch.isEmpty) {
      return;
    }
    validateInMemoryCatalogBatchMutation(_pieces, batch);
    for (final piece in batch.newPieces) {
      _pieces[piece.id] = piece;
    }
    for (final attachment in batch.attachments) {
      if (attachment.variants.isEmpty) {
        continue;
      }
      final existing = _pieces[attachment.pieceId]!;
      _pieces[attachment.pieceId] = Piece(
        id: existing.id,
        title: existing.title,
        artist: existing.artist,
        scale: existing.scale,
        variants: <ScoreVariant>[...existing.variants, ...attachment.variants],
      );
    }
  }

  @override
  Future<Piece?> deleteVariant({
    required String pieceId,
    required String variantId,
  }) async {
    _ensureOpen();
    final existing = _pieces[pieceId];
    if (existing == null) {
      return null;
    }
    final remaining = existing.variants
        .where((v) => v.id != variantId)
        .toList(growable: false);
    if (remaining.isEmpty) {
      _pieces.remove(pieceId);
      return null;
    }
    final updated = Piece(
      id: existing.id,
      title: existing.title,
      artist: existing.artist,
      scale: existing.scale,
      variants: remaining,
    );
    _pieces[pieceId] = updated;
    return updated;
  }

  @override
  Future<void> deletePiece(String pieceId) async {
    _ensureOpen();
    _pieces.remove(pieceId);
  }

  @override
  Future<Set<String>> listStoredRelativePaths() async {
    _ensureOpen();
    final paths = <String>{};
    for (final piece in _pieces.values) {
      for (final variant in piece.variants) {
        paths.add(variant.storedRelativePath);
      }
    }
    return Set<String>.unmodifiable(paths);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw const CatalogStorageException('Catalog repository is closed.');
    }
  }

  bool _containsVariantId(String variantId) {
    for (final piece in _pieces.values) {
      if (piece.variants.any((v) => v.id == variantId)) {
        return true;
      }
    }
    return false;
  }
}
