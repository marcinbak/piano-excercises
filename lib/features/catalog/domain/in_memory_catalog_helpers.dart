import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_search_normalizer.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';

/// Validates atomicity invariants for [CatalogBatchMutation] against [pieces].
void validateInMemoryCatalogBatchMutation(
  Map<String, Piece> pieces,
  CatalogBatchMutation batch,
) {
  final seenPieceIds = Set<String>.of(pieces.keys);
  final seenVariantIds = <String>{
    for (final piece in pieces.values)
      for (final variant in piece.variants) variant.id,
  };
  for (final piece in batch.newPieces) {
    if (piece.variants.isEmpty) {
      throw CatalogStorageException('Piece ${piece.id} has zero variants.');
    }
    if (!seenPieceIds.add(piece.id)) {
      throw CatalogStorageException('Piece ${piece.id} already exists.');
    }
    _validateBatchVariants(piece.id, piece.variants, seenVariantIds);
  }
  for (final attachment in batch.attachments) {
    if (!pieces.containsKey(attachment.pieceId)) {
      throw CatalogStorageException('Piece ${attachment.pieceId} not found.');
    }
    if (attachment.variants.isEmpty) {
      throw CatalogStorageException(
        'Attachment for ${attachment.pieceId} has zero variants.',
      );
    }
    _validateBatchVariants(
      attachment.pieceId,
      attachment.variants,
      seenVariantIds,
    );
  }
}

void _validateBatchVariants(
  String pieceId,
  List<ScoreVariant> variants,
  Set<String> seenVariantIds,
) {
  for (final variant in variants) {
    if (variant.pieceId != pieceId) {
      throw CatalogStorageException(
        'Variant pieceId ${variant.pieceId} does not match $pieceId.',
      );
    }
    if (!seenVariantIds.add(variant.id)) {
      throw CatalogStorageException(
        'ScoreVariant ${variant.id} already exists.',
      );
    }
  }
}

/// Evaluates normalized token-prefix matching equivalent to SQLite FTS5/FTS4.
bool matchesInMemoryCatalogSearch(Piece piece, List<String> queryTokens) {
  final docIndex = CatalogSearchNormalizer.buildDocumentIndex(
    title: piece.title,
    artist: piece.artist,
    scale: piece.scale,
    fileNames: piece.variants.map((v) => v.fileName),
  );
  if (docIndex.isEmpty) {
    return false;
  }
  final docTokens = docIndex.split(' ');
  return queryTokens.every(
    (queryToken) =>
        docTokens.any((docToken) => docToken.startsWith(queryToken)),
  );
}
