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
          remainingByteBudget: maxBundleBytes,
          remainingCandidateBudget: defaultMaxFiles,
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
    final state = _MultiSelectionAccumulator(
      remainingByteBudget: maxBundleBytes,
      remainingCandidateBudget: defaultMaxFiles,
    );
    for (var i = 0; i < pickedFiles.length; i += 1) {
      await _processMultiEntry(pickedFiles[i], state);
      if ((i + 1) % _yieldInterval == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (state.candidates.isEmpty) {
      throw state.firstParseError ??
          ScoreParseException(
            state.failures.isNotEmpty
                ? state.failures.first.message
                : 'No valid scores selected.',
          );
    }
    return ScoreImportSelection(
      candidates: state.candidates,
      failures: state.failures,
      ignoredNonScoreCount: state.ignoredNonScoreCount,
      isBundle: state.hasBundle,
    );
  }

  Future<void> _processMultiEntry(
    PlatformFile picked,
    _MultiSelectionAccumulator state,
  ) async {
    try {
      final parsed = await _readAndParsePickedEntry(
        picked,
        remainingByteBudget: state.remainingByteBudget,
        remainingCandidateBudget: state.remainingCandidateBudget,
      );
      state.recordSuccess(
        parsed,
        maxBundleBytes: maxBundleBytes,
        maxCandidates: defaultMaxFiles,
      );
    } on _SelectionLimitExceededException catch (error) {
      throw ScoreParseException(error.message);
    } on ScoreParseException catch (error) {
      state.firstParseError ??= error;
      state.failures.add(
        ScoreImportFailure(sourceName: picked.name, message: error.message),
      );
    }
  }

  Future<_ParsedPickedEntry> _readAndParsePickedEntry(
    PlatformFile picked, {
    required int remainingByteBudget,
    required int remainingCandidateBudget,
  }) async {
    final lowerName = picked.name.trim().toLowerCase();
    if (lowerName.endsWith('.zip')) {
      final bytes = await _readBoundedBytes(
        picked,
        perFileLimit: maxBundleBytes,
        remainingSelectionBudget: maxBundleBytes,
      );
      final selection = await _bundleExtractor.extractBundle(
        bytes,
        maxUncompressedBytes: remainingByteBudget,
        maxScoreCandidates: remainingCandidateBudget,
        onBudgetExceeded: (msg) => throw _SelectionLimitExceededException(msg),
      );
      var extractedBytes = 0;
      for (final candidate in selection.candidates) {
        extractedBytes += candidate.bytes.length;
      }
      return _ParsedPickedEntry(
        selection: selection,
        consumedBytes: extractedBytes,
        consumedCandidates: selection.candidates.length,
      );
    }
    _ensureScoreExtension(lowerName);
    if (remainingCandidateBudget <= 0) {
      throw const _SelectionLimitExceededException(
        'Cannot import more than $defaultMaxFiles scores at once.',
      );
    }
    final bytes = await _readBoundedBytes(
      picked,
      perFileLimit: maxBytes,
      remainingSelectionBudget: remainingByteBudget,
    );
    final parsed = _parser.parseBytes(bytes, fileName: picked.name);
    return _ParsedPickedEntry(
      selection: ScoreImportSelection.single(
        ImportedScoreCandidate(
          fileName: picked.name,
          bytes: bytes,
          parsedScore: parsed,
        ),
      ),
      consumedBytes: bytes.length,
      consumedCandidates: 1,
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

final class _ParsedPickedEntry {
  const _ParsedPickedEntry({
    required this.selection,
    required this.consumedBytes,
    required this.consumedCandidates,
  });

  final ScoreImportSelection selection;
  final int consumedBytes;
  final int consumedCandidates;
}

final class _MultiSelectionAccumulator {
  _MultiSelectionAccumulator({
    required this.remainingByteBudget,
    required this.remainingCandidateBudget,
  });

  final List<ImportedScoreCandidate> candidates = <ImportedScoreCandidate>[];
  final List<ScoreImportFailure> failures = <ScoreImportFailure>[];
  int ignoredNonScoreCount = 0;
  int remainingByteBudget;
  int remainingCandidateBudget;
  int totalRetainedCandidateBytes = 0;
  bool hasBundle = false;
  ScoreParseException? firstParseError;

  void recordSuccess(
    _ParsedPickedEntry parsed, {
    required int maxBundleBytes,
    required int maxCandidates,
  }) {
    remainingByteBudget -= parsed.consumedBytes;
    remainingCandidateBudget -= parsed.consumedCandidates;
    totalRetainedCandidateBytes += parsed.consumedBytes;
    candidates.addAll(parsed.selection.candidates);
    failures.addAll(parsed.selection.failures);
    ignoredNonScoreCount += parsed.selection.ignoredNonScoreCount;
    hasBundle = hasBundle || parsed.selection.isBundle;
    if (totalRetainedCandidateBytes > maxBundleBytes) {
      throw _SelectionLimitExceededException(
        'Selected scores exceed the $maxBundleBytes byte total size limit.',
      );
    }
    if (candidates.length > maxCandidates) {
      throw _SelectionLimitExceededException(
        'Cannot import more than $maxCandidates scores at once.',
      );
    }
  }
}

final class _SelectionLimitExceededException implements Exception {
  const _SelectionLimitExceededException(this.message);

  final String message;
}
