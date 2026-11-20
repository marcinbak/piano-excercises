import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_models.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_controller.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_state.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Compact two-row step-time rhythm and touch pitch editing toolbar.
class ScoreEditorToolbar extends StatelessWidget {
  const ScoreEditorToolbar({
    super.key,
    required this.state,
    required this.controller,
    required this.isCompact,
  });

  final ScoreEditorState state;
  final ScoreEditorController controller;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final verticalPad = isCompact ? 2.0 : 4.0;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: verticalPad),
            child: _RhythmToolbarRow(state: state, controller: controller),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: verticalPad),
            child: _PitchToolbarRow(state: state, controller: controller),
          ),
        ],
      ),
    );
  }
}

class _RhythmToolbarRow extends StatelessWidget {
  const _RhythmToolbarRow({required this.state, required this.controller});

  static const List<(NoteBaseDuration, String)> _durations =
      <(NoteBaseDuration, String)>[
        (NoteBaseDuration.whole, '1'),
        (NoteBaseDuration.half, '1/2'),
        (NoteBaseDuration.quarter, '1/4'),
        (NoteBaseDuration.eighth, '1/8'),
        (NoteBaseDuration.sixteenth, '1/16'),
      ];

  final ScoreEditorState state;
  final ScoreEditorController controller;

  @override
  Widget build(BuildContext context) {
    final selectedDur = state.draft.selectedDuration;
    final hasNotes = state.notesAtCursor.isNotEmpty;
    final isTied = state.notesAtCursor.any(
      (n) => n.tie == TieType.start || n.tie == TieType.continueTie,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          IconButton(
            key: const ValueKey<String>('editor-prev-slice'),
            tooltip: 'Previous beat',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left),
            onPressed: controller.moveCursorPrev,
          ),
          IconButton(
            key: const ValueKey<String>('editor-next-slice'),
            tooltip: 'Next beat',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right),
            onPressed: controller.moveCursorNext,
          ),
          for (final (base, label) in _durations) ...<Widget>[
            const SizedBox(width: 4),
            ChoiceChip(
              key: ValueKey<String>('editor-duration-${base.name}'),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              label: Text(label),
              selected: selectedDur.base == base,
              onSelected: (_) => controller.setBaseDuration(base),
            ),
          ],
          const SizedBox(width: 4),
          ChoiceChip(
            key: const ValueKey<String>('editor-dot-toggle'),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: const Text('.'),
            selected: selectedDur.dots > 0,
            onSelected: (_) => controller.toggleDot(),
          ),
          const SizedBox(width: 6),
          ActionChip(
            key: const ValueKey<String>('editor-insert-rest'),
            visualDensity: VisualDensity.compact,
            label: const Text('Rest'),
            onPressed: controller.insertRest,
          ),
          const SizedBox(width: 4),
          ChoiceChip(
            key: const ValueKey<String>('editor-tie-toggle'),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: const Text('Tie'),
            selected: isTied,
            onSelected: hasNotes ? (_) => controller.toggleTieAtCursor() : null,
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey<String>('editor-insert-slice'),
            tooltip: 'Insert gap',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_box_outlined, size: 20),
            onPressed: controller.insertEmptySlice,
          ),
          IconButton(
            key: const ValueKey<String>('editor-delete-slice'),
            tooltip: 'Delete at cursor',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.backspace_outlined, size: 20),
            onPressed: hasNotes ? controller.deleteAtCursor : null,
          ),
        ],
      ),
    );
  }
}

class _PitchToolbarRow extends StatelessWidget {
  const _PitchToolbarRow({required this.state, required this.controller});

  final ScoreEditorState state;
  final ScoreEditorController controller;

  @override
  Widget build(BuildContext context) {
    final notes = state.notesAtCursor;
    final hasNotes = notes.isNotEmpty;
    final idx = hasNotes
        ? (state.selectedNoteIndex ?? 0).clamp(0, notes.length - 1)
        : null;
    final DraftNoteEvent? selectedNote = idx == null ? null : notes[idx];
    final cycleLabel = selectedNote == null
        ? 'Note'
        : '${idx! + 1}/${notes.length} ${selectedNote.staffNote.pitchName}';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          ActionChip(
            key: const ValueKey<String>('editor-cycle-note'),
            visualDensity: VisualDensity.compact,
            label: Text(cycleLabel),
            onPressed: hasNotes ? controller.cycleSelectedNote : null,
          ),
          const SizedBox(width: 4),
          ActionChip(
            key: const ValueKey<String>('editor-add-note'),
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.add, size: 16),
            label: const Text('Note'),
            onPressed: controller.addTouchNote,
          ),
          IconButton(
            key: const ValueKey<String>('editor-pitch-down'),
            tooltip: 'Step pitch down',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_downward, size: 20),
            onPressed: hasNotes
                ? () => controller.stepSelectedNotePitch(-1)
                : null,
          ),
          IconButton(
            key: const ValueKey<String>('editor-pitch-up'),
            tooltip: 'Step pitch up',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_upward, size: 20),
            onPressed: hasNotes
                ? () => controller.stepSelectedNotePitch(1)
                : null,
          ),
          ChoiceChip(
            key: const ValueKey<String>('editor-accidental-flat'),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: const Text('b'),
            selected: selectedNote?.explicitAccidental == Accidental.flat,
            onSelected: hasNotes
                ? (_) => controller.setSelectedNoteAccidental(Accidental.flat)
                : null,
          ),
          const SizedBox(width: 4),
          ChoiceChip(
            key: const ValueKey<String>('editor-accidental-natural'),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: const Text('♮'),
            selected: selectedNote?.explicitAccidental == Accidental.natural,
            onSelected: hasNotes
                ? (_) =>
                      controller.setSelectedNoteAccidental(Accidental.natural)
                : null,
          ),
          const SizedBox(width: 4),
          ChoiceChip(
            key: const ValueKey<String>('editor-accidental-sharp'),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: const Text('#'),
            selected: selectedNote?.explicitAccidental == Accidental.sharp,
            onSelected: hasNotes
                ? (_) => controller.setSelectedNoteAccidental(Accidental.sharp)
                : null,
          ),
          const SizedBox(width: 4),
          ChoiceChip(
            key: const ValueKey<String>('editor-accidental-key'),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: const Text('Key'),
            selected: hasNotes && selectedNote?.explicitAccidental == null,
            onSelected: hasNotes
                ? (_) => controller.setSelectedNoteAccidental(null)
                : null,
          ),
          const SizedBox(width: 4),
          ActionChip(
            key: const ValueKey<String>('editor-flip-clef'),
            visualDensity: VisualDensity.compact,
            label: Text(
              selectedNote == null
                  ? 'Clef'
                  : (selectedNote.staffNote.clef == Clef.treble
                        ? 'To Bass'
                        : 'To Treble'),
            ),
            onPressed: hasNotes ? controller.flipSelectedNoteClef : null,
          ),
        ],
      ),
    );
  }
}
