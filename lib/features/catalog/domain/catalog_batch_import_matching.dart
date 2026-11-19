import 'dart:typed_data';

import 'package:piano_exercises/features/catalog/domain/catalog_search_normalizer.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier_inference.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';

/// Checks whether [candidate] duplicates an already persisted variant on [existingPiece].
bool matchesExistingVariant(
  ImportedScoreCandidate candidate,
  Piece? existingPiece,
) {
  if (existingPiece == null || existingPiece.variants.isEmpty) {
    return false;
  }
  final baseLower = baseImportFileName(candidate.fileName).toLowerCase();
  final normArchive = normalizeArchiveEntryPath(candidate.archiveEntryPath);
  final normArchiveLower = normArchive?.toLowerCase();
  final inferredTier = inferDifficultyTier(
    archiveEntryPath: candidate.archiveEntryPath,
    fileName: candidate.fileName,
    title: candidate.parsedScore.metadata.title,
  );
  var hasBareBaseMatch = false;
  for (final variant in existingPiece.variants) {
    final existingNameLower = variant.fileName.trim().toLowerCase();
    if (normArchiveLower != null && existingNameLower == normArchiveLower) {
      return true;
    }
    if (existingNameLower == baseLower) {
      hasBareBaseMatch = true;
      if (inferredTier != null && variant.difficultyTier == inferredTier) {
        return true;
      }
    }
  }
  if (!hasBareBaseMatch) {
    return false;
  }
  return !(normArchive != null &&
      normArchive.contains('/') &&
      inferredTier != null);
}

(String, String) pieceGroupKey(String title, String artist) {
  final normTitle = CatalogSearchNormalizer.normalizeText(title);
  final normArtist = CatalogSearchNormalizer.normalizeText(artist);
  return (
    normTitle.isEmpty ? title.trim().toLowerCase() : normTitle,
    normArtist.isEmpty ? artist.trim().toLowerCase() : normArtist,
  );
}

String baseImportFileName(String fileName) {
  final trimmed = fileName.trim();
  return trimmed.isEmpty ? 'score.musicxml' : trimmed;
}

String? normalizeArchiveEntryPath(String? archiveEntryPath) {
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

int fnv1a32BytesHash(Uint8List bytes) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < bytes.length; i += 1) {
    hash ^= bytes[i];
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

bool bytesEqual(Uint8List a, Uint8List b) {
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
