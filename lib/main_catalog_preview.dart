import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:piano_exercises/app/app.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/piece_practice/piece_practice.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:smufl_notation/smufl_notation.dart';

const String _definedImportFile = String.fromEnvironment('CATALOG_IMPORT_FILE');

/// Standalone entry point previewing [CatalogScreen] -> [PieceScoreScreen].
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final importSource = _definedImportFile.isEmpty
      ? null
      : const _DefinedFileScoreImportSource(_definedImportFile);
  final root = await bootstrapPianoExercisesRoot(
    scoreImportSource: importSource,
    home: const _CatalogPreviewHome(),
  );
  runApp(root);
}

class _CatalogPreviewHome extends StatelessWidget {
  const _CatalogPreviewHome();

  @override
  Widget build(BuildContext context) {
    return CatalogScreen(
      onSelectVariant: (piece, variant) {
        unawaited(
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  _PreviewScorePage(piece: piece, initialVariant: variant),
            ),
          ),
        );
      },
    );
  }
}

class _PreviewScorePage extends StatefulWidget {
  const _PreviewScorePage({required this.piece, required this.initialVariant});

  final Piece piece;
  final ScoreVariant initialVariant;

  @override
  State<_PreviewScorePage> createState() => _PreviewScorePageState();
}

class _PreviewScorePageState extends State<_PreviewScorePage> {
  bool _showWrongNotes = false;

  @override
  Widget build(BuildContext context) {
    return PieceScoreScreen(
      piece: widget.piece,
      initialVariant: widget.initialVariant,
      wrongNoteOverlaysBuilder: (score, activeSliceIndex) {
        if (!_showWrongNotes) {
          return const <WrongNoteOverlay>[];
        }
        return <WrongNoteOverlay>[
          ScoreNotationMapper.mapWrongNotes(
            sliceIndex: activeSliceIndex,
            clef: SmuflClef.treble,
            wrongNotes: const <StaffNote>[
              StaffNote(note: DiatonicNote.f, octave: 5, clef: Clef.treble),
              StaffNote(note: DiatonicNote.b, octave: 5, clef: Clef.treble),
              StaffNote(
                note: DiatonicNote.c,
                octave: 6,
                clef: Clef.treble,
                accidental: Accidental.sharp,
              ),
            ],
            activeKeySignature: ScoreNotationMapper.activeKeySignatureAtSlice(
              score,
              activeSliceIndex,
            ),
          ),
        ];
      },
      appBarActionsBuilder: (score, activeSliceIndex, selectSlice) => <Widget>[
        IconButton(
          key: const ValueKey<String>('preview_jump_last_slice'),
          tooltip: 'Jump to end',
          icon: const Icon(Icons.last_page),
          onPressed: score.slices.isEmpty
              ? null
              : () => selectSlice(score.slices.length - 1),
        ),
        IconButton(
          key: const ValueKey<String>('preview_toggle_wrong_notes'),
          tooltip: 'Toggle wrong-note overlay',
          icon: Icon(_showWrongNotes ? Icons.error : Icons.error_outline),
          onPressed: () => setState(() => _showWrongNotes = !_showWrongNotes),
        ),
      ],
    );
  }
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
