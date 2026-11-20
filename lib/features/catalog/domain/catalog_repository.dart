import 'package:piano_exercises/features/catalog/domain/catalog_query.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
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

/// Atomic update payload modifying a piece's metadata and one [ScoreVariant] row.
final class CatalogVariantUpdate {
  const CatalogVariantUpdate({
    required this.pieceId,
    required this.variantId,
    required this.title,
    required this.artist,
    required this.scale,
    required this.difficultyTier,
    required this.label,
    required this.fileName,
    required this.storedRelativePath,
    required this.importedAtMs,
  });

  final String pieceId;
  final String variantId;
  final String title;
  final String artist;
  final Scale scale;
  final DifficultyTier difficultyTier;
  final String label;
  final String fileName;
  final String storedRelativePath;
  final int importedAtMs;
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

  Future<Piece> updateVariant(CatalogVariantUpdate update);

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
