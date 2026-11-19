import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:piano_exercises/features/catalog/data/musicxml_score_parser.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Picks and validates `.mxl`/`.musicxml` files through the native file picker.
final class FilePickerScoreImporter implements ScoreImportSource {
  FilePickerScoreImporter({
    ScoreParser? parser,
    Future<PlatformFile?> Function()? pickFile,
    this.maxBytes = defaultMaxBytes,
  }) : _parser = parser ?? const MusicXmlScoreParser(),
       _pickFile = pickFile ?? _defaultPickFile;

  static const int defaultMaxBytes = 10 * 1024 * 1024;

  final ScoreParser _parser;
  final Future<PlatformFile?> Function() _pickFile;
  final int maxBytes;

  static Future<PlatformFile?> _defaultPickFile() {
    return FilePicker.pickFile(
      type: FileType.any,
      dialogTitle: 'Select .mxl or .musicxml score',
    );
  }

  @override
  Future<ImportedScoreCandidate?> pickAndParseScore() async {
    final picked = await _pickFile();
    if (picked == null) {
      return null;
    }
    final fileName = picked.name;
    final lowerName = fileName.trim().toLowerCase();
    if (!lowerName.endsWith('.mxl') && !lowerName.endsWith('.musicxml')) {
      throw const ScoreParseException(
        'Unsupported file type. Select a .mxl or .musicxml score.',
      );
    }

    final knownLength = picked.lengthSync();
    if (knownLength != null && knownLength > maxBytes) {
      throw ScoreParseException(
        'Score file exceeds the $maxBytes byte size limit.',
      );
    }
    if (knownLength != null && knownLength == 0) {
      throw const ScoreParseException('Score file is empty.');
    }

    final builder = BytesBuilder(copy: false);
    var totalBytes = 0;
    await for (final chunk in picked.readAsByteStream()) {
      totalBytes += chunk.length;
      if (totalBytes > maxBytes) {
        throw ScoreParseException(
          'Score file exceeds the $maxBytes byte size limit.',
        );
      }
      builder.add(chunk);
    }

    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      throw const ScoreParseException('Score file is empty.');
    }

    final parsedScore = _parser.parseBytes(bytes, fileName: fileName);
    return ImportedScoreCandidate(
      fileName: fileName,
      bytes: bytes,
      parsedScore: parsedScore,
    );
  }
}
