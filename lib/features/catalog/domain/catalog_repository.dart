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

  /// Deletes [variantId] from [pieceId]; removes parent [Piece] and returns `null` if last variant.
  Future<Piece?> deleteVariant({
    required String pieceId,
    required String variantId,
  });

  Future<void> deletePiece(String pieceId);

  Future<Set<String>> listStoredRelativePaths();

  Future<void> close();
}
