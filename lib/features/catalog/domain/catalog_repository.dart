import 'package:piano_exercises/features/catalog/domain/catalog_query.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Persistence or I/O exception raised by catalog storage operations.
final class CatalogStorageException implements Exception {
  const CatalogStorageException(this.message);

  final String message;

  @override
  String toString() => 'CatalogStorageException: $message';
}

/// Variant additions targeting an existing catalog [Piece].
final class CatalogBatchPieceAttachment {
  CatalogBatchPieceAttachment({
    required this.pieceId,
    required List<ScoreVariant> variants,
  }) : variants = List<ScoreVariant>.unmodifiable(variants);

  final String pieceId;
  final List<ScoreVariant> variants;
}

/// Atomic batch of new [Piece]s and existing-piece attachments.
final class CatalogBatchMutation {
  CatalogBatchMutation({
    List<Piece> newPieces = const <Piece>[],
    List<CatalogBatchPieceAttachment> attachments =
        const <CatalogBatchPieceAttachment>[],
  }) : newPieces = List<Piece>.unmodifiable(newPieces),
       attachments = List<CatalogBatchPieceAttachment>.unmodifiable(
         attachments,
       );

  final List<Piece> newPieces;
  final List<CatalogBatchPieceAttachment> attachments;

  bool get isEmpty => newPieces.isEmpty && attachments.isEmpty;
}

/// Boundary contract for querying and mutating persisted catalog pieces.
abstract interface class CatalogRepository {
  Future<List<Piece>> queryPieces([CatalogQuery query = const CatalogQuery()]);

  Future<int> countPieces();

  Future<List<Scale>> listAvailableScales();

  Future<Piece?> getPieceById(String pieceId);

  Future<Piece> createPiece(Piece piece);

  Future<Piece> attachVariant({
    required String pieceId,
    required ScoreVariant variant,
  });

  Future<void> applyBatch(CatalogBatchMutation batch);

  /// Deletes [variantId] from [pieceId]; removes parent [Piece] and returns `null` if last variant.
  Future<Piece?> deleteVariant({
    required String pieceId,
    required String variantId,
  });

  Future<void> deletePiece(String pieceId);

  Future<Set<String>> listStoredRelativePaths();

  Future<void> close();
}
