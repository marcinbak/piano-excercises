import 'package:piano_exercises/features/catalog/domain/catalog_batch_import_matching.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_batch_import_models.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier_inference.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';

export 'package:piano_exercises/features/catalog/domain/catalog_batch_import_models.dart';
export 'package:piano_exercises/features/catalog/domain/difficulty_tier_inference.dart'
    show inferDifficultyTier;

/// Groups imported candidates into new pieces, attachments, and skipped duplicates.
abstract final class CatalogBatchImportPlanner {
  static CatalogBatchImportPlan plan({
    required List<ImportedScoreCandidate> candidates,
    required List<Piece> existingPieces,
    DifficultyTier defaultTier = DifficultyTier.intermediate,
    bool overrideInferredTiers = false,
  }) {
    final existingByKey = _indexExistingPieces(existingPieces);
    final groups = _groupCandidatesByPiece(candidates);
    final newPieces = <PlannedNewPiece>[];
    final attachments = <PlannedPieceAttachment>[];
    final skipped = <SkippedBatchCandidate>[];

    for (final entry in groups.entries) {
      final existingPiece = existingByKey[entry.key];
      final plannedVariants = _planGroupVariants(
        candidates: entry.value,
        existingPiece: existingPiece,
        defaultTier: defaultTier,
        overrideInferredTiers: overrideInferredTiers,
        skipped: skipped,
      );
      if (plannedVariants.isEmpty) {
        continue;
      }
      if (existingPiece != null) {
        attachments.add(
          PlannedPieceAttachment(
            targetPiece: existingPiece,
            variants: plannedVariants,
          ),
        );
      } else {
        newPieces.add(_buildPlannedNewPiece(plannedVariants));
      }
    }

    return CatalogBatchImportPlan(
      newPieces: newPieces,
      attachments: attachments,
      skippedDuplicates: skipped,
    );
  }
}

Map<(String, String), Piece> _indexExistingPieces(List<Piece> existingPieces) {
  final indexed = <(String, String), Piece>{};
  for (final piece in existingPieces) {
    indexed.putIfAbsent(pieceGroupKey(piece.title, piece.artist), () => piece);
  }
  return indexed;
}

Map<(String, String), List<ImportedScoreCandidate>> _groupCandidatesByPiece(
  List<ImportedScoreCandidate> candidates,
) {
  final groups = <(String, String), List<ImportedScoreCandidate>>{};
  for (final candidate in candidates) {
    final meta = candidate.parsedScore.metadata;
    final key = pieceGroupKey(meta.title, meta.artist);
    groups.putIfAbsent(key, () => <ImportedScoreCandidate>[]).add(candidate);
  }
  return groups;
}

List<PlannedBatchVariant> _planGroupVariants({
  required List<ImportedScoreCandidate> candidates,
  required Piece? existingPiece,
  required DifficultyTier defaultTier,
  required bool overrideInferredTiers,
  required List<SkippedBatchCandidate> skipped,
}) {
  final uniqueByContent = _filterContentDuplicates(
    candidates: candidates,
    existingPiece: existingPiece,
    skipped: skipped,
  );
  if (uniqueByContent.isEmpty) {
    return const <PlannedBatchVariant>[];
  }
  return _buildPlannedVariants(
    candidates: uniqueByContent,
    existingPiece: existingPiece,
    defaultTier: defaultTier,
    overrideInferredTiers: overrideInferredTiers,
    skipped: skipped,
  );
}

List<ImportedScoreCandidate> _filterContentDuplicates({
  required List<ImportedScoreCandidate> candidates,
  required Piece? existingPiece,
  required List<SkippedBatchCandidate> skipped,
}) {
  final uniqueByContent = <ImportedScoreCandidate>[];
  final bucketsByHash = <int, List<ImportedScoreCandidate>>{};
  for (final candidate in candidates) {
    if (matchesExistingVariant(candidate, existingPiece)) {
      skipped.add(
        SkippedBatchCandidate(
          candidate: candidate,
          reason: 'Already exists on "${existingPiece!.title}".',
        ),
      );
      continue;
    }
    final hash = fnv1a32BytesHash(candidate.bytes);
    final bucket = bucketsByHash[hash];
    if (bucket != null &&
        bucket.any((prev) => bytesEqual(prev.bytes, candidate.bytes))) {
      skipped.add(
        SkippedBatchCandidate(
          candidate: candidate,
          reason: 'Duplicate score bytes in batch.',
        ),
      );
      continue;
    }
    uniqueByContent.add(candidate);
    (bucketsByHash[hash] ??= <ImportedScoreCandidate>[]).add(candidate);
  }
  return uniqueByContent;
}

List<PlannedBatchVariant> _buildPlannedVariants({
  required List<ImportedScoreCandidate> candidates,
  required Piece? existingPiece,
  required DifficultyTier defaultTier,
  required bool overrideInferredTiers,
  required List<SkippedBatchCandidate> skipped,
}) {
  final baseNameCounts = _countBaseNames(candidates);
  final existingNames = existingPiece == null
      ? const <String>{}
      : <String>{
          for (final v in existingPiece.variants)
            v.fileName.trim().toLowerCase(),
        };
  final seenEffectiveNames = <String>{};
  final planned = <PlannedBatchVariant>[];
  for (final candidate in candidates) {
    final baseName = baseImportFileName(candidate.fileName);
    final baseLower = baseName.toLowerCase();
    final normArchive = normalizeArchiveEntryPath(candidate.archiveEntryPath);
    final hasCollision =
        (baseNameCounts[baseLower] ?? 0) > 1 ||
        existingNames.contains(baseLower);
    final effectiveName = (hasCollision && normArchive != null)
        ? normArchive
        : baseName;
    if (!seenEffectiveNames.add(effectiveName.toLowerCase())) {
      skipped.add(
        SkippedBatchCandidate(
          candidate: candidate,
          reason: 'Duplicate file name "$effectiveName" in batch.',
        ),
      );
      continue;
    }
    planned.add(
      _toPlannedVariant(
        candidate: candidate,
        effectiveName: effectiveName,
        defaultTier: defaultTier,
        overrideInferredTiers: overrideInferredTiers,
      ),
    );
  }
  return planned;
}

Map<String, int> _countBaseNames(List<ImportedScoreCandidate> candidates) {
  final counts = <String, int>{};
  for (final candidate in candidates) {
    final key = baseImportFileName(candidate.fileName).toLowerCase();
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

PlannedBatchVariant _toPlannedVariant({
  required ImportedScoreCandidate candidate,
  required String effectiveName,
  required DifficultyTier defaultTier,
  required bool overrideInferredTiers,
}) {
  final meta = candidate.parsedScore.metadata;
  final tier = overrideInferredTiers
      ? defaultTier
      : (inferDifficultyTier(
              archiveEntryPath: candidate.archiveEntryPath,
              fileName: candidate.fileName,
              title: meta.title,
            ) ??
            defaultTier);
  return PlannedBatchVariant(
    candidate: candidate,
    difficultyTier: tier,
    effectiveFileName: effectiveName,
  );
}

PlannedNewPiece _buildPlannedNewPiece(List<PlannedBatchVariant> variants) {
  var representative = variants.first;
  for (final variant in variants.skip(1)) {
    if (variant.difficultyTier.tier < representative.difficultyTier.tier) {
      representative = variant;
    }
  }
  final firstMeta = variants.first.candidate.parsedScore.metadata;
  final trimmedTitle = firstMeta.title.trim();
  return PlannedNewPiece(
    title: trimmedTitle.isEmpty ? 'Untitled' : trimmedTitle,
    artist: firstMeta.artist.trim(),
    scale: representative.candidate.parsedScore.metadata.scale,
    variants: variants,
  );
}
