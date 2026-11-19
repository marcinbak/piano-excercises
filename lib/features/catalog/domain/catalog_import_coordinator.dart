import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/features/catalog/domain/score_file_store.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';

/// Coordinates atomic score-file storage and catalog repository mutations.
final class CatalogImportCoordinator {
  const CatalogImportCoordinator({
    required this.catalogRepository,
    required this.scoreFileStore,
    required this.clockMs,
    required this.generateId,
  });

  final CatalogRepository catalogRepository;
  final ScoreFileStore scoreFileStore;
  final int Function() clockMs;
  final String Function() generateId;

  Future<Piece> createPieceFromCandidate({
    required ImportedScoreCandidate candidate,
    required String title,
    required String artist,
    required DifficultyTier difficultyTier,
    String? variantLabel,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Title must not be empty.');
    }
    final trimmedArtist = artist.trim();
    final effectiveLabel = _resolveVariantLabel(variantLabel, difficultyTier);
    final pieceId = _nextSafeId('piece');
    final variantId = _nextSafeId('variant');
    final importedAtMs = clockMs();
    final metadata = candidate.parsedScore.metadata;

    // Persist file first so a DB row never references missing bytes; roll back on DB failure.
    final storedRelativePath = await scoreFileStore.saveScoreBytes(
      variantId: variantId,
      format: metadata.sourceFormat,
      bytes: candidate.bytes,
    );
    try {
      final variant = ScoreVariant(
        id: variantId,
        pieceId: pieceId,
        difficultyTier: difficultyTier,
        label: effectiveLabel,
        fileName: candidate.fileName,
        storedRelativePath: storedRelativePath,
        importedAtMs: importedAtMs,
      );
      final piece = Piece(
        id: pieceId,
        title: trimmedTitle,
        artist: trimmedArtist,
        scale: metadata.scale,
        variants: <ScoreVariant>[variant],
      );
      return await catalogRepository.createPiece(piece);
    } catch (_) {
      await _rollbackFile(storedRelativePath);
      rethrow;
    }
  }

  Future<Piece> attachVariantFromCandidate({
    required String pieceId,
    required ImportedScoreCandidate candidate,
    required DifficultyTier difficultyTier,
    String? variantLabel,
  }) async {
    final existing = await catalogRepository.getPieceById(pieceId);
    if (existing == null) {
      throw CatalogStorageException('Piece $pieceId not found.');
    }
    final effectiveLabel = _resolveVariantLabel(variantLabel, difficultyTier);
    final variantId = _nextSafeId('variant');
    final importedAtMs = clockMs();
    final metadata = candidate.parsedScore.metadata;

    final storedRelativePath = await scoreFileStore.saveScoreBytes(
      variantId: variantId,
      format: metadata.sourceFormat,
      bytes: candidate.bytes,
    );
    try {
      final variant = ScoreVariant(
        id: variantId,
        pieceId: pieceId,
        difficultyTier: difficultyTier,
        label: effectiveLabel,
        fileName: candidate.fileName,
        storedRelativePath: storedRelativePath,
        importedAtMs: importedAtMs,
      );
      return await catalogRepository.attachVariant(
        pieceId: pieceId,
        variant: variant,
      );
    } catch (_) {
      await _rollbackFile(storedRelativePath);
      rethrow;
    }
  }

  Future<Piece?> deleteVariant({
    required String pieceId,
    required String variantId,
  }) async {
    final existing = await catalogRepository.getPieceById(pieceId);
    String? pathToDelete;
    if (existing != null) {
      for (final variant in existing.variants) {
        if (variant.id == variantId) {
          pathToDelete = variant.storedRelativePath;
          break;
        }
      }
    }
    final updated = await catalogRepository.deleteVariant(
      pieceId: pieceId,
      variantId: variantId,
    );
    if (pathToDelete != null) {
      await scoreFileStore.deleteScoreFile(pathToDelete);
    }
    return updated;
  }

  Future<void> deletePiece(String pieceId) async {
    final existing = await catalogRepository.getPieceById(pieceId);
    final paths =
        existing?.variants
            .map((v) => v.storedRelativePath)
            .toList(growable: false) ??
        const <String>[];
    await catalogRepository.deletePiece(pieceId);
    Object? firstError;
    for (final path in paths) {
      try {
        await scoreFileStore.deleteScoreFile(path);
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, StackTrace.current);
    }
  }

  String _nextSafeId(String kind) {
    final id = generateId();
    if (!ScoreFileStore.isValidVariantId(id)) {
      throw CatalogStorageException('Generated invalid $kind id: $id');
    }
    return id;
  }

  static String _resolveVariantLabel(
    String? variantLabel,
    DifficultyTier difficultyTier,
  ) {
    final trimmed = variantLabel?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return difficultyTier.label;
    }
    return trimmed;
  }

  Future<void> _rollbackFile(String storedRelativePath) async {
    try {
      await scoreFileStore.deleteScoreFile(storedRelativePath);
    } catch (_) {
      // Never mask the primary repository error with a secondary cleanup error.
    }
  }
}
