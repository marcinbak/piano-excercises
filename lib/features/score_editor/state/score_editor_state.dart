import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Family key scoping a [ScoreEditorController] instance to a host tab or route.
final class ScoreEditorSessionId {
  const ScoreEditorSessionId(this.value);

  /// Standing Compose tab session retained in the main navigation shell.
  static const ScoreEditorSessionId composeTab = ScoreEditorSessionId(
    'shell_compose',
  );

  final String value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScoreEditorSessionId && other.value == value);
  }

  @override
  int get hashCode => value.hashCode;
}

/// Catalog piece and variant currently bound to an editor session.
final class ScoreEditorBinding {
  const ScoreEditorBinding({required this.piece, required this.variant});

  final Piece piece;
  final ScoreVariant variant;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScoreEditorBinding &&
            other.piece == piece &&
            other.variant == variant);
  }

  @override
  int get hashCode => Object.hash(piece, variant);
}

/// Immutable Riverpod state snapshot for a score-editor session.
final class ScoreEditorState {
  ScoreEditorState({
    required this.draft,
    required this.score,
    this.binding,
    List<ScoreDraft> undoStack = const <ScoreDraft>[],
    List<ScoreDraft> redoStack = const <ScoreDraft>[],
    this.isDirty = false,
    this.selectedNoteIndex,
    this.activeSliceIndex,
    this.isLoadingVariant = false,
    this.loadError,
  }) : undoStack = List<ScoreDraft>.unmodifiable(undoStack),
       redoStack = List<ScoreDraft>.unmodifiable(redoStack);

  /// Creates the default blank four-measure `4/4` `C Major` editor state.
  factory ScoreEditorState.initial() =>
      ScoreEditorState.fromDraft(ScoreDraft());

  /// Lowers [draft] to [Score] and resolves active slice and selected note index.
  factory ScoreEditorState.fromDraft(
    ScoreDraft draft, {
    ScoreEditorBinding? binding,
    bool isDirty = false,
  }) {
    final score = draft.toScore();
    final notesAtCursor = draft.notesAtCursor;
    return ScoreEditorState(
      draft: draft,
      score: score,
      binding: binding,
      isDirty: isDirty,
      selectedNoteIndex: notesAtCursor.isEmpty ? null : 0,
      activeSliceIndex: draft.activeSliceIndexIn(score),
    );
  }

  static const int maxUndoSteps = 100;

  final ScoreDraft draft;
  final Score score;
  final ScoreEditorBinding? binding;
  final List<ScoreDraft> undoStack;
  final List<ScoreDraft> redoStack;
  final bool isDirty;
  final int? selectedNoteIndex;
  final int? activeSliceIndex;
  final bool isLoadingVariant;
  final String? loadError;

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;
  List<DraftNoteEvent> get notesAtCursor => draft.notesAtCursor;

  ScoreEditorState withDraftEdit(
    ScoreDraft nextDraft, {
    int? selectedNoteIndex,
    bool clearSelectedNote = false,
  }) {
    final boundedUndo = <ScoreDraft>[...undoStack, draft];
    if (boundedUndo.length > maxUndoSteps) {
      boundedUndo.removeAt(0);
    }
    final nextScore = nextDraft.toScore();
    final cursorNotes = nextDraft.notesAtCursor;
    final resolvedSelection = clearSelectedNote || cursorNotes.isEmpty
        ? null
        : (selectedNoteIndex ?? this.selectedNoteIndex ?? 0).clamp(
            0,
            cursorNotes.length - 1,
          );
    return ScoreEditorState(
      draft: nextDraft,
      score: nextScore,
      binding: binding,
      undoStack: boundedUndo,
      redoStack: const <ScoreDraft>[],
      isDirty: true,
      selectedNoteIndex: resolvedSelection,
      activeSliceIndex: nextDraft.activeSliceIndexIn(nextScore),
    );
  }

  ScoreEditorState withCursorMove(ScoreDraft nextDraft) {
    final cursorNotes = nextDraft.notesAtCursor;
    return ScoreEditorState(
      draft: nextDraft,
      score: score,
      binding: binding,
      undoStack: undoStack,
      redoStack: redoStack,
      isDirty: isDirty,
      selectedNoteIndex: cursorNotes.isEmpty ? null : 0,
      activeSliceIndex: nextDraft.activeSliceIndexIn(score),
    );
  }

  /// Steps one entry backward on [undoStack], pushing current draft onto [redoStack].
  ScoreEditorState? steppedUndo() {
    if (!canUndo) {
      return null;
    }
    final previous = undoStack.last;
    final nextRedo = <ScoreDraft>[...redoStack, draft];
    if (nextRedo.length > maxUndoSteps) {
      nextRedo.removeAt(0);
    }
    final nextScore = previous.toScore();
    final cursorNotes = previous.notesAtCursor;
    return copyWith(
      draft: previous,
      score: nextScore,
      undoStack: undoStack.sublist(0, undoStack.length - 1),
      redoStack: nextRedo,
      isDirty: true,
      selectedNoteIndex: cursorNotes.isEmpty ? null : 0,
      clearSelectedNote: cursorNotes.isEmpty,
      activeSliceIndex: previous.activeSliceIndexIn(nextScore),
    );
  }

  /// Steps one entry forward on [redoStack], pushing current draft onto [undoStack].
  ScoreEditorState? steppedRedo() {
    if (!canRedo) {
      return null;
    }
    final next = redoStack.last;
    final nextUndo = <ScoreDraft>[...undoStack, draft];
    if (nextUndo.length > maxUndoSteps) {
      nextUndo.removeAt(0);
    }
    final nextScore = next.toScore();
    final cursorNotes = next.notesAtCursor;
    return copyWith(
      draft: next,
      score: nextScore,
      undoStack: nextUndo,
      redoStack: redoStack.sublist(0, redoStack.length - 1),
      isDirty: true,
      selectedNoteIndex: cursorNotes.isEmpty ? null : 0,
      clearSelectedNote: cursorNotes.isEmpty,
      activeSliceIndex: next.activeSliceIndexIn(nextScore),
    );
  }

  ScoreEditorState copyWith({
    ScoreDraft? draft,
    Score? score,
    ScoreEditorBinding? binding,
    bool clearBinding = false,
    List<ScoreDraft>? undoStack,
    List<ScoreDraft>? redoStack,
    bool? isDirty,
    int? selectedNoteIndex,
    bool clearSelectedNote = false,
    int? activeSliceIndex,
    bool? isLoadingVariant,
    String? loadError,
    bool clearLoadError = false,
  }) {
    return ScoreEditorState(
      draft: draft ?? this.draft,
      score: score ?? this.score,
      binding: clearBinding ? null : (binding ?? this.binding),
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      isDirty: isDirty ?? this.isDirty,
      selectedNoteIndex: clearSelectedNote
          ? null
          : (selectedNoteIndex ?? this.selectedNoteIndex),
      activeSliceIndex: activeSliceIndex ?? this.activeSliceIndex,
      isLoadingVariant: isLoadingVariant ?? this.isLoadingVariant,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
    );
  }
}
