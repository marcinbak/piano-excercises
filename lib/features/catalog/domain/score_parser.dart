import 'dart:typed_data';

import 'package:piano_exercises/shared/music/music.dart';

/// Supported input file encodings for score import.
enum ScoreFormat { musicXml, mxl }

/// Summary metadata extracted alongside a parsed [Score].
final class ScoreMetadata {
  const ScoreMetadata({
    required this.title,
    required this.artist,
    required this.scale,
    required this.timeSignature,
    this.initialTempo,
    required this.measureCount,
    required this.sourceFormat,
  });

  final String title;
  final String artist;
  final Scale scale;
  final TimeSignature timeSignature;
  final TempoMark? initialTempo;
  final int measureCount;
  final ScoreFormat sourceFormat;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScoreMetadata &&
            other.title == title &&
            other.artist == artist &&
            other.scale == scale &&
            other.timeSignature == timeSignature &&
            other.initialTempo == initialTempo &&
            other.measureCount == measureCount &&
            other.sourceFormat == sourceFormat);
  }

  @override
  int get hashCode => Object.hash(
    title,
    artist,
    scale,
    timeSignature,
    initialTempo,
    measureCount,
    sourceFormat,
  );
}

/// Complete parsed score payload paired with [ScoreMetadata].
final class ParsedScore {
  const ParsedScore({required this.score, required this.metadata});

  final Score score;
  final ScoreMetadata metadata;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ParsedScore &&
            other.score == score &&
            other.metadata == metadata);
  }

  @override
  int get hashCode => Object.hash(score, metadata);
}

/// Domain exception raised when score bytes are malformed, unsafe, or invalid.
final class ScoreParseException implements Exception {
  const ScoreParseException(this.message);

  final String message;

  @override
  String toString() => 'ScoreParseException: $message';
}

/// Boundary contract for decoding untrusted score bytes into a [ParsedScore].
abstract interface class ScoreParser {
  ParsedScore parseBytes(Uint8List bytes, {String? fileName});
}
