import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/score_file_store.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Persists imported `.mxl`/`.musicxml` bytes under `<appDocs>/scores/`.
final class AppDocsScoreStore implements ScoreFileStore {
  AppDocsScoreStore({required this.rootDirectory});

  static const int maxBytes = 10 * 1024 * 1024;
  static final RegExp _relativePathPattern = RegExp(
    r'^scores/([a-zA-Z0-9_-]{1,64})\.(mxl|musicxml)$',
  );

  final Directory rootDirectory;
  int _writeNonce = 0;

  Directory get _scoresDirectory =>
      Directory(p.join(rootDirectory.path, 'scores'));

  /// Creates an [AppDocsScoreStore] rooted in the platform documents folder.
  static Future<AppDocsScoreStore> create() async {
    final directory = await getApplicationDocumentsDirectory();
    return AppDocsScoreStore(rootDirectory: directory);
  }

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
    final scoresDir = _scoresDirectory;
    _ensureScoresDirectory(scoresDir);

    final targetPath = _resolveValidatedPath(relativePath, scoresDir);
    final tempName =
        '.tmp_${variantId}_${DateTime.now().microsecondsSinceEpoch}_${++_writeNonce}';
    final tempPath = p.join(scoresDir.path, tempName);
    if (!p.isWithin(scoresDir.path, tempPath)) {
      throw const CatalogStorageException('Invalid temporary score file path.');
    }

    final tempFile = File(tempPath);
    RandomAccessFile? raf;
    try {
      raf = await tempFile.open(mode: FileMode.writeOnly);
      await raf.writeFrom(bytes);
      await raf.flush();
      await raf.close();
      raf = null;
      if (FileSystemEntity.isLinkSync(targetPath)) {
        throw const CatalogStorageException(
          'Refusing to overwrite symlink score target.',
        );
      }
      await tempFile.rename(targetPath);
      return relativePath;
    } catch (error) {
      if (raf != null) {
        try {
          await raf.close();
        } catch (_) {}
      }
      try {
        tempFile.deleteSync();
      } on PathNotFoundException {
        // Temp file already renamed or not yet created.
      } on FileSystemException {
        // Best-effort temp cleanup.
      }
      if (error is CatalogStorageException) {
        rethrow;
      }
      throw CatalogStorageException('Failed to save score file: $error');
    }
  }

  @override
  Future<Uint8List> readScoreBytes(String storedRelativePath) async {
    final targetPath = _resolveValidatedPath(
      storedRelativePath,
      _scoresDirectory,
    );
    try {
      final bytes = await File(targetPath).readAsBytes();
      if (bytes.isEmpty || bytes.length > maxBytes) {
        throw CatalogStorageException(
          'Stored score size out of bounds (${bytes.length} bytes).',
        );
      }
      return bytes;
    } on PathNotFoundException {
      throw CatalogStorageException(
        'Stored score file not found: $storedRelativePath',
      );
    } on FileSystemException catch (error) {
      throw CatalogStorageException(
        'Failed to read stored score file $storedRelativePath: $error',
      );
    }
  }

  @override
  Future<void> deleteScoreFile(String storedRelativePath) async {
    final targetPath = _resolveValidatedPath(
      storedRelativePath,
      _scoresDirectory,
    );
    try {
      await File(targetPath).delete();
    } on PathNotFoundException {
      return;
    } on FileSystemException catch (error) {
      throw CatalogStorageException(
        'Failed to delete stored score file $storedRelativePath: $error',
      );
    }
  }

  @override
  Future<int> purgeOrphans(Set<String> activeRelativePaths) async {
    final scoresDir = _scoresDirectory;
    if (!scoresDir.existsSync() ||
        FileSystemEntity.isLinkSync(scoresDir.path)) {
      return 0;
    }
    var deletedCount = 0;
    await for (final entity in scoresDir.list(followLinks: false)) {
      final baseName = p.basename(entity.path);
      if (entity is Link) {
        if (await _deleteEntitySafely(entity)) {
          deletedCount += 1;
        }
        continue;
      }
      if (entity is File) {
        final relativePath = 'scores/$baseName';
        if (baseName.startsWith('.tmp_') ||
            !activeRelativePaths.contains(relativePath)) {
          if (await _deleteEntitySafely(entity)) {
            deletedCount += 1;
          }
        }
      }
    }
    return deletedCount;
  }

  static void _ensureScoresDirectory(Directory scoresDir) {
    if (FileSystemEntity.isLinkSync(scoresDir.path)) {
      throw const CatalogStorageException(
        'Scores directory cannot be a symbolic link.',
      );
    }
    if (!scoresDir.existsSync()) {
      scoresDir.createSync(recursive: true);
    }
  }

  static String _resolveValidatedPath(
    String storedRelativePath,
    Directory scoresDir,
  ) {
    final match = _relativePathPattern.firstMatch(storedRelativePath);
    if (match == null) {
      throw CatalogStorageException(
        'Invalid score relative path: $storedRelativePath',
      );
    }
    final fileName = '${match.group(1)}.${match.group(2)}';
    final targetPath = p.join(scoresDir.path, fileName);
    if (!p.isWithin(scoresDir.path, targetPath) ||
        FileSystemEntity.isLinkSync(targetPath)) {
      throw CatalogStorageException(
        'Unsafe score storage path: $storedRelativePath',
      );
    }
    return targetPath;
  }

  static Future<bool> _deleteEntitySafely(FileSystemEntity entity) async {
    try {
      await entity.delete();
      return true;
    } on PathNotFoundException {
      return false;
    } on FileSystemException {
      return false;
    }
  }
}
