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
  Future<ScoreImportSelection> extractBundle(
    Uint8List bytes, {
    int? maxUncompressedBytes,
    int? maxScoreCandidates,
    void Function(String message)? onBudgetExceeded,
  }) async {
    final limits = _resolveEffectiveLimits(
      maxUncompressedBytes: maxUncompressedBytes,
      maxScoreCandidates: maxScoreCandidates,
      onBudgetExceeded: onBudgetExceeded,
    );
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
      limits.maxBytes,
      errorMessage: 'Decompressed .zip bundle content exceeds maximum uncompressed byte limit.',
    );
    final candidates = <ImportedScoreCandidate>[];
    final failures = <ScoreImportFailure>[];
    final outcome = await _extractEntries(
      headers: directory.fileHeaders,
      budget: budget,
      maxCandidates: limits.maxCandidates,
      candidates: candidates,
      failures: failures,
    );
    if (outcome.budgetExceeded) {
      onBudgetExceeded?.call(budget.errorMessage);
      throw ScoreParseException(budget.errorMessage);
    }
    if (outcome.candidateLimitExceeded) {
      final msg =
          'Cannot import more than ${limits.maxCandidates} scores at once.';
      onBudgetExceeded?.call(msg);
      throw ScoreParseException(msg);
    }
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
      ignoredNonScoreCount: outcome.ignoredNonScoreCount,
      isBundle: true,
    );
  }

  ({int maxBytes, int maxCandidates}) _resolveEffectiveLimits({
    required int? maxUncompressedBytes,
    required int? maxScoreCandidates,
    required void Function(String message)? onBudgetExceeded,
  }) {
    final effectiveMaxBytes = maxUncompressedBytes == null
        ? maxTotalUncompressedBytes
        : math.min(maxUncompressedBytes, maxTotalUncompressedBytes);
    final effectiveMaxCandidates = maxScoreCandidates == null
        ? maxEntries
        : math.min(maxScoreCandidates, maxEntries);
    if (effectiveMaxBytes <= 0) {
      const msg =
          'Decompressed .zip bundle content exceeds maximum uncompressed byte limit.';
      onBudgetExceeded?.call(msg);
      throw const ScoreParseException(msg);
    }
    if (effectiveMaxCandidates <= 0) {
      final msg = 'Cannot import more than $maxEntries scores at once.';
      onBudgetExceeded?.call(msg);
      throw ScoreParseException(msg);
    }
    return (maxBytes: effectiveMaxBytes, maxCandidates: effectiveMaxCandidates);
  }

  Future<
    ({
      int ignoredNonScoreCount,
      bool budgetExceeded,
      bool candidateLimitExceeded,
    })
  >
  _extractEntries({
    required List<ZipFileHeader> headers,
    required DecodeBudget budget,
    required int maxCandidates,
    required List<ImportedScoreCandidate> candidates,
    required List<ScoreImportFailure> failures,
  }) async {
    var ignoredNonScoreCount = 0;
    var parsedAttempts = 0;
    for (final header in headers) {
      final kind = _classifyEntry(header.filename);
      if (kind == _BundleEntryKind.skip) {
        continue;
      }
      if (kind == _BundleEntryKind.nestedZip) {
        failures.add(
          ScoreImportFailure(
            sourceName: header.filename,
            message: 'Nested .zip archives are not supported.',
          ),
        );
        continue;
      }
      if (kind == _BundleEntryKind.nonScore) {
        ignoredNonScoreCount += 1;
        continue;
      }
      if (candidates.length >= maxCandidates) {
        return (
          ignoredNonScoreCount: ignoredNonScoreCount,
          budgetExceeded: false,
          candidateLimitExceeded: true,
        );
      }
      final result = _tryExtractScoreCandidate(
        header: header,
        path: header.filename,
        baseName: header.filename.split('/').last,
        budget: budget,
      );
      if (budget.exceeded) {
        return (
          ignoredNonScoreCount: ignoredNonScoreCount,
          budgetExceeded: true,
          candidateLimitExceeded: false,
        );
      }
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
    return (
      ignoredNonScoreCount: ignoredNonScoreCount,
      budgetExceeded: false,
      candidateLimitExceeded: false,
    );
  }

  static _BundleEntryKind _classifyEntry(String path) {
    if (path.endsWith('/') || _isIgnoredMetadataEntry(path)) {
      return _BundleEntryKind.skip;
    }
    final lowerBase = path.split('/').last.toLowerCase();
    if (lowerBase.endsWith('.zip')) {
      return _BundleEntryKind.nestedZip;
    }
    if (!lowerBase.endsWith('.mxl') && !lowerBase.endsWith('.musicxml')) {
      return _BundleEntryKind.nonScore;
    }
    return _BundleEntryKind.score;
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

enum _BundleEntryKind { skip, nestedZip, nonScore, score }
