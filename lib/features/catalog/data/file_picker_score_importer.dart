import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:piano_exercises/features/catalog/data/musicxml_score_parser.dart';
import 'package:piano_exercises/features/catalog/data/zip_bundle_score_extractor.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Picks and validates `.mxl`, `.musicxml`, and `.zip` score files through the native picker.
final class FilePickerScoreImporter implements ScoreImportSource {
  FilePickerScoreImporter({
    ScoreParser? parser,
    ZipBundleScoreExtractor? bundleExtractor,
    Future<List<PlatformFile>> Function()? pickFiles,
    this.maxBytes = defaultMaxBytes,
    this.maxBundleBytes = defaultMaxBundleBytes,
  }) : _parser = parser ?? const MusicXmlScoreParser(),
       _bundleExtractor =
           bundleExtractor ??
           ZipBundleScoreExtractor(
             parser: parser ?? const MusicXmlScoreParser(),
             maxTotalUncompressedBytes: maxBundleBytes,
             maxSingleScoreBytes: maxBytes,
           ),
       _pickFiles = pickFiles ?? _defaultPickFiles;

  static const int defaultMaxBytes = 10 * 1024 * 1024;
  static const int defaultMaxBundleBytes = 50 * 1024 * 1024;
  static const int defaultMaxFiles = 500;
  static const int _yieldInterval = 8;

  final ScoreParser _parser;
  final ZipBundleScoreExtractor _bundleExtractor;
  final Future<List<PlatformFile>> Function() _pickFiles;
  final int maxBytes;
  final int maxBundleBytes;

  static Future<List<PlatformFile>> _defaultPickFiles() {
    return FilePicker.pickFiles(
      type: FileType.any,
      dialogTitle: 'Select .mxl, .musicxml, or .zip scores',
    );
  }

  @override
  Future<ScoreImportSelection?> pickAndParseScores() async {
    final pickedFiles = await _pickFiles();
    if (pickedFiles.isEmpty) {
      return null;
    }
    if (pickedFiles.length > defaultMaxFiles) {
      throw const ScoreParseException(
        'Cannot import more than $defaultMaxFiles files at once.',
      );
    }
    if (pickedFiles.length == 1) {
      try {
        final parsed = await _readAndParsePickedEntry(
          pickedFiles.single,
          maxBundleBytes,
        );
        return parsed.selection;
      } on _SelectionLimitExceededException catch (error) {
        throw ScoreParseException(error.message);
      }
    }
    return _importMultiplePickedFiles(pickedFiles);
  }

  Future<ScoreImportSelection> _importMultiplePickedFiles(
    List<PlatformFile> pickedFiles,
  ) async {
    final candidates = <ImportedScoreCandidate>[];
    final failures = <ScoreImportFailure>[];
    var ignoredNonScoreCount = 0;
    var remainingBudget = maxBundleBytes;
    var hasBundle = false;
    ScoreParseException? firstParseError;

    for (var i = 0; i < pickedFiles.length; i += 1) {
      final picked = pickedFiles[i];
      try {
        final parsed = await _readAndParsePickedEntry(picked, remainingBudget);
        remainingBudget -= parsed.consumedBytes;
        candidates.addAll(parsed.selection.candidates);
        failures.addAll(parsed.selection.failures);
        ignoredNonScoreCount += parsed.selection.ignoredNonScoreCount;
        hasBundle = hasBundle || parsed.selection.isBundle;
      } on _SelectionLimitExceededException catch (error) {
        throw ScoreParseException(error.message);
      } on ScoreParseException catch (error) {
        firstParseError ??= error;
        failures.add(
          ScoreImportFailure(sourceName: picked.name, message: error.message),
        );
      }
      if ((i + 1) % _yieldInterval == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (candidates.isEmpty) {
      throw firstParseError ??
          ScoreParseException(
            failures.isNotEmpty
                ? failures.first.message
                : 'No valid scores selected.',
          );
    }
    return ScoreImportSelection(
      candidates: candidates,
      failures: failures,
      ignoredNonScoreCount: ignoredNonScoreCount,
      isBundle: hasBundle,
    );
  }

  Future<({ScoreImportSelection selection, int consumedBytes})>
  _readAndParsePickedEntry(PlatformFile picked, int remainingBudget) async {
    final lowerName = picked.name.trim().toLowerCase();
    if (lowerName.endsWith('.zip')) {
      final bytes = await _readBoundedBytes(
        picked,
        perFileLimit: maxBundleBytes,
        remainingSelectionBudget: remainingBudget,
      );
      return (
        selection: await _bundleExtractor.extractBundle(bytes),
        consumedBytes: bytes.length,
      );
    }
    _ensureScoreExtension(lowerName);
    final bytes = await _readBoundedBytes(
      picked,
      perFileLimit: maxBytes,
      remainingSelectionBudget: remainingBudget,
    );
    final parsed = _parser.parseBytes(bytes, fileName: picked.name);
    return (
      selection: ScoreImportSelection.single(
        ImportedScoreCandidate(
          fileName: picked.name,
          bytes: bytes,
          parsedScore: parsed,
        ),
      ),
      consumedBytes: bytes.length,
    );
  }

  static void _ensureScoreExtension(String lowerName) {
    if (!lowerName.endsWith('.mxl') && !lowerName.endsWith('.musicxml')) {
      throw const ScoreParseException(
        'Unsupported file type. Select a .mxl, .musicxml, or .zip score.',
      );
    }
  }

  Future<Uint8List> _readBoundedBytes(
    PlatformFile picked, {
    required int perFileLimit,
    required int remainingSelectionBudget,
  }) async {
    final knownLength = picked.lengthSync();
    if (knownLength != null && knownLength == 0) {
      throw const ScoreParseException('Score file is empty.');
    }
    if (knownLength != null && knownLength > perFileLimit) {
      throw ScoreParseException(
        'Score file exceeds the $perFileLimit byte size limit.',
      );
    }
    if (knownLength != null && knownLength > remainingSelectionBudget) {
      throw _SelectionLimitExceededException(
        'Selected files exceed the $maxBundleBytes byte total size limit.',
      );
    }

    final builder = BytesBuilder(copy: false);
    var totalBytes = 0;
    await for (final chunk in picked.readAsByteStream()) {
      totalBytes += chunk.length;
      if (totalBytes > perFileLimit) {
        throw ScoreParseException(
          'Score file exceeds the $perFileLimit byte size limit.',
        );
      }
      if (totalBytes > remainingSelectionBudget) {
        throw _SelectionLimitExceededException(
          'Selected files exceed the $maxBundleBytes byte total size limit.',
        );
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      throw const ScoreParseException('Score file is empty.');
    }
    return bytes;
  }
}

final class _SelectionLimitExceededException implements Exception {
  const _SelectionLimitExceededException(this.message);

  final String message;
}
