import 'dart:typed_data';

import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Validated score file bytes paired with the parsed [ParsedScore].
final class ImportedScoreCandidate {
  const ImportedScoreCandidate({
    required this.fileName,
    required this.bytes,
    required this.parsedScore,
    this.archiveEntryPath,
  });

  final String fileName;
  final Uint8List bytes;
  final ParsedScore parsedScore;
  final String? archiveEntryPath;
}

/// Non-fatal per-entry or per-file parse failure within a multi-score selection.
final class ScoreImportFailure {
  const ScoreImportFailure({required this.sourceName, required this.message});

  final String sourceName;
  final String message;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScoreImportFailure &&
            other.sourceName == sourceName &&
            other.message == message);
  }

  @override
  int get hashCode => Object.hash(sourceName, message);
}

/// Result of picking and parsing one or more `.mxl`, `.musicxml`, or `.zip` inputs.
final class ScoreImportSelection {
  ScoreImportSelection({
    required List<ImportedScoreCandidate> candidates,
    List<ScoreImportFailure> failures = const <ScoreImportFailure>[],
    this.ignoredNonScoreCount = 0,
    this.isBundle = false,
  }) : candidates = List<ImportedScoreCandidate>.unmodifiable(candidates),
       failures = List<ScoreImportFailure>.unmodifiable(failures) {
    if (ignoredNonScoreCount < 0) {
      throw ArgumentError.value(
        ignoredNonScoreCount,
        'ignoredNonScoreCount',
        'Must be >= 0.',
      );
    }
  }

  factory ScoreImportSelection.single(ImportedScoreCandidate candidate) {
    return ScoreImportSelection(
      candidates: <ImportedScoreCandidate>[candidate],
    );
  }

  final List<ImportedScoreCandidate> candidates;
  final List<ScoreImportFailure> failures;
  final int ignoredNonScoreCount;
  final bool isBundle;

  /// Routes single clean scores (or single-candidate card attaches) to the single-score sheet.
  bool shouldUseSingleScoreSheet({required bool hasInitialTargetPiece}) {
    return (!isBundle && candidates.length == 1 && failures.isEmpty) ||
        (hasInitialTargetPiece && candidates.length == 1 && failures.isEmpty);
  }
}

/// Boundary contract for picking and parsing user-selected score files or bundles.
abstract interface class ScoreImportSource {
  Future<ScoreImportSelection?> pickAndParseScores();
}
