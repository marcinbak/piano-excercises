import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Planned variant assignment ready to be persisted in a batch import.
final class PlannedBatchVariant {
  const PlannedBatchVariant({
    required this.candidate,
    required this.difficultyTier,
    required this.effectiveFileName,
    this.labelOverride,
  });

  final ImportedScoreCandidate candidate;
  final DifficultyTier difficultyTier;
  final String effectiveFileName;
  final String? labelOverride;
}

/// Planned creation of a new catalog [Piece] with `1..N` variants.
final class PlannedNewPiece {
  PlannedNewPiece({
    required this.title,
    required this.artist,
    required this.scale,
    required List<PlannedBatchVariant> variants,
  }) : variants = List<PlannedBatchVariant>.unmodifiable(variants);

  final String title;
  final String artist;
  final Scale scale;
  final List<PlannedBatchVariant> variants;
}

/// Planned attachment of `1..N` variants to an existing [Piece].
final class PlannedPieceAttachment {
  PlannedPieceAttachment({
    required this.targetPiece,
    required List<PlannedBatchVariant> variants,
  }) : variants = List<PlannedBatchVariant>.unmodifiable(variants);

  final Piece targetPiece;
  final List<PlannedBatchVariant> variants;
}

/// Candidate excluded from a batch import due to an existing or intra-batch duplicate.
final class SkippedBatchCandidate {
  const SkippedBatchCandidate({required this.candidate, required this.reason});

  final ImportedScoreCandidate candidate;
  final String reason;
}

/// Dry-run plan produced by `CatalogBatchImportPlanner` for review and execution.
final class CatalogBatchImportPlan {
  CatalogBatchImportPlan({
    required List<PlannedNewPiece> newPieces,
    required List<PlannedPieceAttachment> attachments,
    required List<SkippedBatchCandidate> skippedDuplicates,
  }) : newPieces = List<PlannedNewPiece>.unmodifiable(newPieces),
       attachments = List<PlannedPieceAttachment>.unmodifiable(attachments),
       skippedDuplicates = List<SkippedBatchCandidate>.unmodifiable(
         skippedDuplicates,
       );

  final List<PlannedNewPiece> newPieces;
  final List<PlannedPieceAttachment> attachments;
  final List<SkippedBatchCandidate> skippedDuplicates;

  int get totalVariantsToImport {
    var count = 0;
    for (final piece in newPieces) {
      count += piece.variants.length;
    }
    for (final attachment in attachments) {
      count += attachment.variants.length;
    }
    return count;
  }

  bool get hasImports => totalVariantsToImport > 0;
}
