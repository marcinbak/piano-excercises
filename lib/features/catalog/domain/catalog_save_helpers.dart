import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';

/// Validates and trims a required score title before persistence.
String requireCatalogSaveTitle(String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(title, 'title', 'Title must not be empty.');
  }
  return trimmed;
}

/// Resolves an explicit variant label or defaults to [difficultyTier.label].
String resolveCatalogVariantLabel(
  String? variantLabel,
  DifficultyTier difficultyTier,
) {
  final trimmed = variantLabel?.trim();
  return (trimmed == null || trimmed.isEmpty) ? difficultyTier.label : trimmed;
}

/// Rewrites an existing `.mxl`/`.xml` filename to `.musicxml` when updating in place.
String toMusicXmlVariantFileName(
  String existingFileName, {
  required String fallbackTitle,
  required String fallbackId,
}) {
  final trimmed = existingFileName.trim();
  if (trimmed.isEmpty) {
    return buildMusicXmlFileName(fallbackTitle, fallbackId: fallbackId);
  }
  final lower = trimmed.toLowerCase();
  if (lower.endsWith('.musicxml')) {
    return trimmed;
  }
  if (lower.endsWith('.mxl') || lower.endsWith('.xml')) {
    return '${trimmed.substring(0, trimmed.length - 4)}.musicxml';
  }
  return '$trimmed.musicxml';
}

/// Sanitizes [title] into a bounded `.musicxml` filename.
String buildMusicXmlFileName(String title, {required String fallbackId}) {
  final cleaned = title
      .trim()
      .replaceAll(RegExp(r'[/\\:*?"<>|]+'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final stem = cleaned.isEmpty ? fallbackId : cleaned;
  final truncated = stem.length > 80 ? stem.substring(0, 80) : stem;
  return '$truncated.musicxml';
}
