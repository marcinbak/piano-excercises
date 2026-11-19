import 'dart:typed_data';

import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Boundary contract for persisting imported `.mxl`/`.musicxml` byte payloads.
abstract interface class ScoreFileStore {
  static final RegExp _variantIdPattern = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');

  static bool isValidVariantId(String variantId) =>
      _variantIdPattern.hasMatch(variantId);

  Future<String> saveScoreBytes({
    required String variantId,
    required ScoreFormat format,
    required Uint8List bytes,
  });

  Future<Uint8List> readScoreBytes(String storedRelativePath);

  Future<void> deleteScoreFile(String storedRelativePath);

  Future<int> purgeOrphans(Set<String> activeRelativePaths);
}

/// Pure-Dart in-memory [ScoreFileStore] for tests and non-persistent fallback.
final class InMemoryScoreFileStore implements ScoreFileStore {
  static const int maxBytes = 10 * 1024 * 1024;
  static final RegExp _relativePathPattern = RegExp(
    r'^scores/[a-zA-Z0-9_-]{1,64}\.(mxl|musicxml)$',
  );

  final Map<String, Uint8List> _files = <String, Uint8List>{};

  @override
  Future<String> saveScoreBytes({
    required String variantId,
    required ScoreFormat format,
    required Uint8List bytes,
  }) async {
    if (!ScoreFileStore.isValidVariantId(variantId)) {
      throw CatalogStorageException('Invalid variant id: $variantId');
    }
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw CatalogStorageException(
        'Score byte size must be in 1..$maxBytes (got ${bytes.length}).',
      );
    }
    final ext = format == ScoreFormat.mxl ? 'mxl' : 'musicxml';
    final relativePath = 'scores/$variantId.$ext';
    _files[relativePath] = Uint8List.fromList(bytes);
    return relativePath;
  }

  @override
  Future<Uint8List> readScoreBytes(String storedRelativePath) async {
    _validateRelativePath(storedRelativePath);
    final bytes = _files[storedRelativePath];
    if (bytes == null) {
      throw CatalogStorageException(
        'Stored score file not found: $storedRelativePath',
      );
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteScoreFile(String storedRelativePath) async {
    _validateRelativePath(storedRelativePath);
    _files.remove(storedRelativePath);
  }

  @override
  Future<int> purgeOrphans(Set<String> activeRelativePaths) async {
    final toRemove = _files.keys
        .where((path) => !activeRelativePaths.contains(path))
        .toList(growable: false);
    for (final path in toRemove) {
      _files.remove(path);
    }
    return toRemove.length;
  }

  static void _validateRelativePath(String path) {
    if (!_relativePathPattern.hasMatch(path)) {
      throw CatalogStorageException('Invalid score relative path: $path');
    }
  }
}
