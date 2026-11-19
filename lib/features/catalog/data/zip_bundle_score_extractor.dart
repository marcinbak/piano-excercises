import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:piano_exercises/features/catalog/data/bounded_zip_stream.dart';
import 'package:piano_exercises/features/catalog/data/mxl_entry_validator.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Extracts and parses `.mxl` and `.musicxml` scores from bounded `.zip` bundles.
final class ZipBundleScoreExtractor {
  const ZipBundleScoreExtractor({
    required this.parser,
    this.maxEntries = defaultMaxEntries,
    this.maxTotalUncompressedBytes = defaultMaxTotalUncompressedBytes,
    this.maxSingleScoreBytes = defaultMaxSingleScoreBytes,
  });

  static const int defaultMaxEntries = 500;
  static const int defaultMaxTotalUncompressedBytes = 50 * 1024 * 1024;
  static const int defaultMaxSingleScoreBytes = 10 * 1024 * 1024;
  static const int _yieldInterval = 8;

  final ScoreParser parser;
  final int maxEntries;
  final int maxTotalUncompressedBytes;
  final int maxSingleScoreBytes;

  /// Validates the outer ZIP structure and parses every `.mxl`/`.musicxml` score entry.
  Future<ScoreImportSelection> extractBundle(Uint8List bytes) async {
    final directory = readBoundedZipDirectory(
      bytes,
      maxArchiveBytes: maxTotalUncompressedBytes,
      maxEntries: maxEntries,
    );
    MxlEntryValidator.validateAllHeaders(
      bytes,
      directory.fileHeaders,
      maxUncompressedBytes: maxTotalUncompressedBytes,
    );

    final budget = DecodeBudget(
      maxTotalUncompressedBytes,
      errorMessage: 'Decompressed .zip bundle content exceeds maximum uncompressed byte limit.',
    );
    final candidates = <ImportedScoreCandidate>[];
    final failures = <ScoreImportFailure>[];
    final ignoredNonScoreCount = await _extractEntries(
      headers: directory.fileHeaders,
      budget: budget,
      candidates: candidates,
      failures: failures,
    );

    if (candidates.isEmpty) {
      throw ScoreParseException(
        failures.isNotEmpty
            ? failures.first.message
            : 'No .mxl or .musicxml scores found in archive.',
      );
    }

    return ScoreImportSelection(
      candidates: candidates,
      failures: failures,
      ignoredNonScoreCount: ignoredNonScoreCount,
      isBundle: true,
    );
  }

  Future<int> _extractEntries({
    required List<ZipFileHeader> headers,
    required DecodeBudget budget,
    required List<ImportedScoreCandidate> candidates,
    required List<ScoreImportFailure> failures,
  }) async {
    var ignoredNonScoreCount = 0;
    var parsedAttempts = 0;
    for (final header in headers) {
      final path = header.filename;
      if (path.endsWith('/') || _isIgnoredMetadataEntry(path)) {
        continue;
      }
      final baseName = path.split('/').last;
      final lowerBase = baseName.toLowerCase();
      if (lowerBase.endsWith('.zip')) {
        failures.add(
          ScoreImportFailure(
            sourceName: path,
            message: 'Nested .zip archives are not supported.',
          ),
        );
        continue;
      }
      if (!lowerBase.endsWith('.mxl') && !lowerBase.endsWith('.musicxml')) {
        ignoredNonScoreCount += 1;
        continue;
      }
      final result = _tryExtractScoreCandidate(
        header: header,
        path: path,
        baseName: baseName,
        budget: budget,
      );
      if (result.candidate != null) {
        candidates.add(result.candidate!);
      } else if (result.failure != null) {
        failures.add(result.failure!);
      }
      parsedAttempts += 1;
      if (parsedAttempts % _yieldInterval == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return ignoredNonScoreCount;
  }

  ({ImportedScoreCandidate? candidate, ScoreImportFailure? failure})
  _tryExtractScoreCandidate({
    required ZipFileHeader header,
    required String path,
    required String baseName,
    required DecodeBudget budget,
  }) {
    try {
      return (
        candidate: _extractScoreCandidate(
          header: header,
          path: path,
          baseName: baseName,
          budget: budget,
        ),
        failure: null,
      );
    } on ScoreParseException catch (error) {
      return (
        candidate: null,
        failure: ScoreImportFailure(sourceName: path, message: error.message),
      );
    }
  }

  ImportedScoreCandidate _extractScoreCandidate({
    required ZipFileHeader header,
    required String path,
    required String baseName,
    required DecodeBudget budget,
  }) {
    final file = header.file;
    if (file == null) {
      throw const ScoreParseException('Missing local file header in .zip.');
    }
    final declaredSize = math.max(
      header.uncompressedSize ?? 0,
      file.uncompressedSize ?? 0,
    );
    if (declaredSize <= 0 || declaredSize > maxSingleScoreBytes) {
      throw ScoreParseException(
        'Score entry size must be between 1 and $maxSingleScoreBytes bytes.',
      );
    }
    final entryBytes = decompressBoundedZipEntry(
      header,
      budget,
      maxEntryBytes: maxSingleScoreBytes,
    );
    final parsed = parser.parseBytes(entryBytes, fileName: baseName);
    return ImportedScoreCandidate(
      fileName: baseName,
      archiveEntryPath: path,
      bytes: entryBytes,
      parsedScore: parsed,
    );
  }

  static bool _isIgnoredMetadataEntry(String path) {
    final segments = path.split('/');
    for (final segment in segments) {
      if (segment.toUpperCase() == '__MACOSX') {
        return true;
      }
    }
    final baseName = segments.last;
    if (baseName.isEmpty ||
        baseName.startsWith('.') ||
        baseName.startsWith('._')) {
      return true;
    }
    final lowerBase = baseName.toLowerCase();
    return lowerBase == 'thumbs.db' || lowerBase == 'desktop.ini';
  }
}
