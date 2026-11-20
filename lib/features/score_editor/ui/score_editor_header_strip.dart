import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_controller.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_state.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Compact horizontally scrollable strip displaying undo/redo, setup, bar actions, and position.
class ScoreEditorHeaderStrip extends StatelessWidget {
  const ScoreEditorHeaderStrip({
    super.key,
    required this.state,
    required this.controller,
    required this.onOpenSetup,
    required this.isCompact,
  });

  final ScoreEditorState state;
  final ScoreEditorController controller;
  final VoidCallback onOpenSetup;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final draft = state.draft;
    final notes = draft.notesAtCursor;
    final selectedIdx = state.selectedNoteIndex;
    final activeNote =
        (notes.isNotEmpty &&
            selectedIdx != null &&
            selectedIdx >= 0 &&
            selectedIdx < notes.length)
        ? notes[selectedIdx]
        : (notes.isNotEmpty ? notes.first : null);
    final noteSummary = activeNote == null
        ? 'Rest'
        : '${activeNote.staffNote.pitchName} '
              '(${activeNote.staffNote.clef == Clef.treble ? 'RH' : 'LH'})';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: isCompact ? 2 : 6,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            key: const ValueKey<String>('editor-undo-button'),
            tooltip: 'Undo',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.undo, size: 20),
            onPressed: state.canUndo ? controller.undo : null,
          ),
          IconButton(
            key: const ValueKey<String>('editor-redo-button'),
            tooltip: 'Redo',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.redo, size: 20),
            onPressed: state.canRedo ? controller.redo : null,
          ),
          const SizedBox(width: 4),
          ActionChip(
            key: const ValueKey<String>('editor-open-setup-button'),
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.tune, size: 16),
            label: Text('${draft.scale.label} · ${draft.timeSignature.label}'),
            onPressed: onOpenSetup,
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey<String>('editor-add-measure-button'),
            tooltip: 'Add measure',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.playlist_add, size: 20),
            onPressed: controller.addMeasure,
          ),
          IconButton(
            key: const ValueKey<String>('editor-delete-measure-button'),
            tooltip: 'Delete measure',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            onPressed: controller.deleteCurrentMeasure,
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Bar ${draft.cursor.measureIndex + 1}/${draft.measures.length} • '
              'Beat ${draft.cursor.beatOffset}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(noteSummary, style: theme.textTheme.labelMedium),
          ),
        ],
      ),
    );
  }
}
