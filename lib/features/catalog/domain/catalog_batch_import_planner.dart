import 'dart:typed_data';

import 'package:piano_exercises/features/catalog/domain/catalog_batch_import_models.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_search_normalizer.dart';
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
    indexed.putIfAbsent(_pieceGroupKey(piece.title, piece.artist), () => piece);
  }
  return indexed;
}

Map<(String, String), List<ImportedScoreCandidate>> _groupCandidatesByPiece(
  List<ImportedScoreCandidate> candidates,
) {
  final groups = <(String, String), List<ImportedScoreCandidate>>{};
  for (final candidate in candidates) {
    final meta = candidate.parsedScore.metadata;
    final key = _pieceGroupKey(meta.title, meta.artist);
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
  final baseNameCounts = <String, int>{};
  for (final candidate in uniqueByContent) {
    final key = _baseFileName(candidate.fileName).toLowerCase();
    baseNameCounts[key] = (baseNameCounts[key] ?? 0) + 1;
  }
  return _buildPlannedVariants(
    candidates: uniqueByContent,
    baseNameCounts: baseNameCounts,
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
  final existingNames = existingPiece == null
      ? const <String>{}
      : <String>{
          for (final v in existingPiece.variants)
            v.fileName.trim().toLowerCase(),
        };
  final uniqueByContent = <ImportedScoreCandidate>[];
  for (final candidate in candidates) {
    if (_matchesExistingVariant(candidate, existingNames)) {
      skipped.add(
        SkippedBatchCandidate(
          candidate: candidate,
          reason: 'Already exists on "${existingPiece!.title}".',
        ),
      );
      continue;
    }
    if (uniqueByContent.any(
      (prev) => _bytesEqual(prev.bytes, candidate.bytes),
    )) {
      skipped.add(
        SkippedBatchCandidate(
          candidate: candidate,
          reason: 'Duplicate score bytes in batch.',
        ),
      );
      continue;
    }
    uniqueByContent.add(candidate);
  }
  return uniqueByContent;
}

List<PlannedBatchVariant> _buildPlannedVariants({
  required List<ImportedScoreCandidate> candidates,
  required Map<String, int> baseNameCounts,
  required DifficultyTier defaultTier,
  required bool overrideInferredTiers,
  required List<SkippedBatchCandidate> skipped,
}) {
  final seenEffectiveNames = <String>{};
  final planned = <PlannedBatchVariant>[];
  for (final candidate in candidates) {
    final baseName = _baseFileName(candidate.fileName);
    final normArchive = _normalizeArchivePath(candidate.archiveEntryPath);
    final hasCollision = (baseNameCounts[baseName.toLowerCase()] ?? 0) > 1;
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
    final meta = candidate.parsedScore.metadata;
    final tier = overrideInferredTiers
        ? defaultTier
        : (inferDifficultyTier(
                archiveEntryPath: candidate.archiveEntryPath,
                fileName: candidate.fileName,
                title: meta.title,
              ) ??
              defaultTier);
    planned.add(
      PlannedBatchVariant(
        candidate: candidate,
        difficultyTier: tier,
        effectiveFileName: effectiveName,
      ),
    );
  }
  return planned;
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

bool _matchesExistingVariant(
  ImportedScoreCandidate candidate,
  Set<String> existingNamesLower,
) {
  if (existingNamesLower.isEmpty) {
    return false;
  }
  final baseLower = _baseFileName(candidate.fileName).toLowerCase();
  if (existingNamesLower.contains(baseLower)) {
    return true;
  }
  final normArchive = _normalizeArchivePath(candidate.archiveEntryPath);
  return normArchive != null &&
      existingNamesLower.contains(normArchive.toLowerCase());
}

(String, String) _pieceGroupKey(String title, String artist) {
  final normTitle = CatalogSearchNormalizer.normalizeText(title);
  final normArtist = CatalogSearchNormalizer.normalizeText(artist);
  return (
    normTitle.isEmpty ? title.trim().toLowerCase() : normTitle,
    normArtist.isEmpty ? artist.trim().toLowerCase() : normArtist,
  );
}

String _baseFileName(String fileName) {
  final trimmed = fileName.trim();
  return trimmed.isEmpty ? 'score.musicxml' : trimmed;
}

String? _normalizeArchivePath(String? archiveEntryPath) {
  if (archiveEntryPath == null) {
    return null;
  }
  var normalized = archiveEntryPath.trim().replaceAll(r'\', '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  while (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? null : segments.join('/');
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
