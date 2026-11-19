import 'dart:typed_data';

import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Validated score file bytes paired with the parsed [ParsedScore].
final class ImportedScoreCandidate {
  const ImportedScoreCandidate({
    required this.fileName,
    required this.bytes,
    required this.parsedScore,
  });

  final String fileName;
  final Uint8List bytes;
  final ParsedScore parsedScore;
}

/// Boundary contract for picking and parsing a user-selected score file.
abstract interface class ScoreImportSource {
  Future<ImportedScoreCandidate?> pickAndParseScore();
}
