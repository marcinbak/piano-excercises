import 'package:piano_exercises/features/catalog/domain/catalog_batch_import_planner.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/features/catalog/domain/score_file_store.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';

/// Summary counts returned after a committed batch import.
final class CatalogBatchImportResult {
  const CatalogBatchImportResult({
    required this.createdPieceCount,
    required this.attachedVariantCount,
    required this.skippedDuplicateCount,
  });

  final int createdPieceCount;
  final int attachedVariantCount;
  final int skippedDuplicateCount;
}

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

  /// Writes all planned score payloads first, commits one repository batch, and unlinks all written files on failure.
  Future<CatalogBatchImportResult> executeBatchImport(
    CatalogBatchImportPlan plan,
  ) async {
    if (!plan.hasImports) {
      return CatalogBatchImportResult(
        createdPieceCount: 0,
        attachedVariantCount: 0,
        skippedDuplicateCount: plan.skippedDuplicates.length,
      );
    }

    final writtenPaths = <String>[];
    try {
      final mutation = await _stageBatchMutation(plan, writtenPaths);
      await catalogRepository.applyBatch(mutation);
      var attachedVariantCount = 0;
      for (final attachment in mutation.attachments) {
        attachedVariantCount += attachment.variants.length;
      }
      return CatalogBatchImportResult(
        createdPieceCount: mutation.newPieces.length,
        attachedVariantCount: attachedVariantCount,
        skippedDuplicateCount: plan.skippedDuplicates.length,
      );
    } catch (_) {
      for (final path in writtenPaths) {
        await _rollbackFile(path);
      }
      rethrow;
    }
  }

  Future<CatalogBatchMutation> _stageBatchMutation(
    CatalogBatchImportPlan plan,
    List<String> writtenPaths,
  ) async {
    final importedAtMs = clockMs();
    final newPieces = <Piece>[];
    for (final plannedPiece in plan.newPieces) {
      final pieceId = _nextSafeId('piece');
      final variants = await _savePlannedVariants(
        pieceId: pieceId,
        plannedVariants: plannedPiece.variants,
        importedAtMs: importedAtMs,
        writtenPaths: writtenPaths,
      );
      newPieces.add(
        Piece(
          id: pieceId,
          title: plannedPiece.title,
          artist: plannedPiece.artist,
          scale: plannedPiece.scale,
          variants: variants,
        ),
      );
    }
    final attachments = <CatalogBatchPieceAttachment>[];
    for (final plannedAttachment in plan.attachments) {
      final variants = await _savePlannedVariants(
        pieceId: plannedAttachment.targetPiece.id,
        plannedVariants: plannedAttachment.variants,
        importedAtMs: importedAtMs,
        writtenPaths: writtenPaths,
      );
      attachments.add(
        CatalogBatchPieceAttachment(
          pieceId: plannedAttachment.targetPiece.id,
          variants: variants,
        ),
      );
    }
    return CatalogBatchMutation(newPieces: newPieces, attachments: attachments);
  }

  Future<List<ScoreVariant>> _savePlannedVariants({
    required String pieceId,
    required List<PlannedBatchVariant> plannedVariants,
    required int importedAtMs,
    required List<String> writtenPaths,
  }) async {
    final variants = <ScoreVariant>[];
    for (final planned in plannedVariants) {
      final variantId = _nextSafeId('variant');
      final metadata = planned.candidate.parsedScore.metadata;
      final storedRelativePath = await scoreFileStore.saveScoreBytes(
        variantId: variantId,
        format: metadata.sourceFormat,
        bytes: planned.candidate.bytes,
      );
      writtenPaths.add(storedRelativePath);
      variants.add(
        ScoreVariant(
          id: variantId,
          pieceId: pieceId,
          difficultyTier: planned.difficultyTier,
          label: _resolveVariantLabel(
            planned.labelOverride,
            planned.difficultyTier,
          ),
          fileName: planned.effectiveFileName,
          storedRelativePath: storedRelativePath,
          importedAtMs: importedAtMs,
        ),
      );
    }
    return variants;
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
