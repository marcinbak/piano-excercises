import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:piano_exercises/app/app.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';

const String _definedImportFile = String.fromEnvironment('CATALOG_IMPORT_FILE');

/// Standalone entry point previewing [CatalogScreen] before `[M9]` shell wiring.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final importSource = _definedImportFile.isEmpty
      ? null
      : const _DefinedFileScoreImportSource(_definedImportFile);
  final root = await bootstrapPianoExercisesRoot(
    scoreImportSource: importSource,
    home: const CatalogScreen(),
  );
  runApp(root);
}

final class _DefinedFileScoreImportSource implements ScoreImportSource {
  const _DefinedFileScoreImportSource(this._filePath);

  final String _filePath;

  @override
  Future<ImportedScoreCandidate?> pickAndParseScore() async {
    try {
      final bytes = await File(_filePath).readAsBytes();
      final fileName = p.basename(_filePath);
      final parsedScore = const MusicXmlScoreParser().parseBytes(
        bytes,
        fileName: fileName,
      );
      return ImportedScoreCandidate(
        fileName: fileName,
        bytes: bytes,
        parsedScore: parsedScore,
      );
    } on FileSystemException catch (error) {
      throw ScoreParseException('Failed to read $_filePath: ${error.message}');
    }
  }
}
