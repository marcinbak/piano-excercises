import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Imported arrangement score belonging to a parent [Piece].
final class ScoreVariant {
  ScoreVariant({
    required this.id,
    required this.pieceId,
    required this.difficultyTier,
    required this.label,
    required this.fileName,
    required this.storedRelativePath,
    required this.importedAtMs,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(pieceId, 'pieceId');
    _requireNonEmpty(label, 'label');
    _requireNonEmpty(fileName, 'fileName');
    _requireNonEmpty(storedRelativePath, 'storedRelativePath');
    if (importedAtMs < 0) {
      throw ArgumentError.value(importedAtMs, 'importedAtMs', 'Must be >= 0.');
    }
  }

  final String id;
  final String pieceId;
  final DifficultyTier difficultyTier;
  final String label;
  final String fileName;
  final String storedRelativePath;
  final int importedAtMs;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScoreVariant &&
            other.id == id &&
            other.pieceId == pieceId &&
            other.difficultyTier == difficultyTier &&
            other.label == label &&
            other.fileName == fileName &&
            other.storedRelativePath == storedRelativePath &&
            other.importedAtMs == importedAtMs);
  }

  @override
  int get hashCode => Object.hash(
    id,
    pieceId,
    difficultyTier,
    label,
    fileName,
    storedRelativePath,
    importedAtMs,
  );
}

/// Musical work grouping `1..N` [ScoreVariant] arrangements sorted by difficulty.
final class Piece {
  Piece({
    required this.id,
    required this.title,
    required this.artist,
    required this.scale,
    required List<ScoreVariant> variants,
  }) : variants = _validateAndSortVariants(id, title, variants);

  final String id;
  final String title;
  final String artist;
  final Scale scale;
  final List<ScoreVariant> variants;

  DifficultyTier get minDifficulty => variants.first.difficultyTier;

  DifficultyTier get maxDifficulty => variants.last.difficultyTier;

  String get difficultySummary => minDifficulty == maxDifficulty
      ? minDifficulty.label
      : '${minDifficulty.label} – ${maxDifficulty.label}';

  int get latestImportedAtMs {
    var latest = variants.first.importedAtMs;
    for (final variant in variants.skip(1)) {
      if (variant.importedAtMs > latest) {
        latest = variant.importedAtMs;
      }
    }
    return latest;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Piece &&
            other.id == id &&
            other.title == title &&
            other.artist == artist &&
            other.scale == scale &&
            _variantsEqual(other.variants, variants));
  }

  @override
  int get hashCode =>
      Object.hash(id, title, artist, scale, Object.hashAll(variants));

  static List<ScoreVariant> _validateAndSortVariants(
    String id,
    String title,
    List<ScoreVariant> variants,
  ) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(title, 'title');
    if (variants.isEmpty) {
      throw ArgumentError.value(
        variants,
        'variants',
        'Piece must have at least one ScoreVariant.',
      );
    }
    for (final variant in variants) {
      if (variant.pieceId != id) {
        throw ArgumentError.value(
          variant.pieceId,
          'variants',
          'Variant ${variant.id} pieceId must match piece $id.',
        );
      }
    }
    final sorted = List<ScoreVariant>.of(variants)
      ..sort((a, b) {
        final tierCmp = a.difficultyTier.tier.compareTo(b.difficultyTier.tier);
        if (tierCmp != 0) {
          return tierCmp;
        }
        final timeCmp = a.importedAtMs.compareTo(b.importedAtMs);
        if (timeCmp != 0) {
          return timeCmp;
        }
        return a.id.compareTo(b.id);
      });
    return List<ScoreVariant>.unmodifiable(sorted);
  }

  static bool _variantsEqual(List<ScoreVariant> a, List<ScoreVariant> b) {
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
}

void _requireNonEmpty(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'Must not be empty.');
  }
}
