import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_mutations.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_providers.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_state.dart';
import 'package:piano_exercises/shared/music/music.dart';

export 'package:piano_exercises/features/score_editor/state/score_editor_providers.dart'
    show
        ScoreEditorPausedNotifier,
        ScoreEditorPlaybackPausedNotifier,
        ScoreEditorSessionPausedNotifier,
        scoreEditorChordWindowProvider,
        scoreEditorClockMsProvider,
        scoreEditorPausedProvider,
        scoreEditorPlaybackPausedProvider,
        scoreEditorSessionPausedProvider;

/// Orchestrates MIDI chord entry, touch edits, undo/redo, and variant loading.
class ScoreEditorController extends Notifier<ScoreEditorState> {
  ScoreEditorController(this.arg);

  final ScoreEditorSessionId arg;

  late MidiChordCoalescer _coalescer;
  int _loadSequence = 0;

  bool get isPaused => _coalescer.isPaused;

  @override
  ScoreEditorState build() {
    _coalescer = MidiChordCoalescer(
      chordWindow: ref.watch(scoreEditorChordWindowProvider),
      clockMs: ref.watch(scoreEditorClockMsProvider),
      onFlush: _onChordFlush,
    );
    _coalescer.setPaused(_computeEffectivePaused());
    _bindListeners();
    return ScoreEditorState.initial();
  }

  /// Pauses or resumes live MIDI capture while preserving held-key carryover.
  void setPaused(bool paused) {
    if (!ref.mounted) {
      return;
    }
    _coalescer.setPaused(paused);
  }

  /// Loads [variant] of [piece] from storage into the editor draft.
  Future<void> loadVariantForEditing(Piece piece, ScoreVariant variant) async {
    final loadId = ++_loadSequence;
    _coalescer.resetActivePrompt();
    state = state.copyWith(
      binding: ScoreEditorBinding(piece: piece, variant: variant),
      isLoadingVariant: true,
      clearLoadError: true,
    );
    try {
      final bytes = await ref
          .read(scoreFileStoreProvider)
          .readScoreBytes(variant.storedRelativePath);
      final parsed = ref
          .read(scoreParserProvider)
          .parseBytes(bytes, fileName: variant.fileName);
      if (!ref.mounted || loadId != _loadSequence) {
        return;
      }
      final loadedDraft = ScoreDraft.fromScore(parsed.score)
          .copyWith(title: piece.title, artist: piece.artist);
      state = ScoreEditorState.fromDraft(
        loadedDraft,
        binding: ScoreEditorBinding(piece: piece, variant: variant),
        isDirty: false,
      );
    } catch (error) {
      if (!ref.mounted || loadId != _loadSequence) {
        return;
      }
      state = state.copyWith(
        isLoadingVariant: false,
        loadError: formatEditorLoadError(error),
      );
    }
  }

  /// Binds a committed catalog save result and clears the dirty flag.
  void applySaveResult({required Piece piece, required ScoreVariant variant}) {
    if (!ref.mounted) {
      return;
    }
    final nextDraft = state.draft.copyWith(
      title: piece.title,
      artist: piece.artist,
    );
    final nextScore = nextDraft.toScore();
    state = state.copyWith(
      draft: nextDraft,
      score: nextScore,
      binding: ScoreEditorBinding(piece: piece, variant: variant),
      isDirty: false,
      activeSliceIndex: nextDraft.activeSliceIndexIn(nextScore),
    );
  }

  void undo() {
    final nextState = state.steppedUndo();
    if (!ref.mounted || _isUnavailable || nextState == null) {
      return;
    }
    _coalescer.resetActivePrompt();
    state = nextState;
  }

  void redo() {
    final nextState = state.steppedRedo();
    if (!ref.mounted || _isUnavailable || nextState == null) {
      return;
    }
    _coalescer.resetActivePrompt();
    state = nextState;
  }

  void selectSlice(int sliceIndex) =>
      _applyCursorMove(state.draft.selectSlice(state.score, sliceIndex));

  void moveCursorPrev() => _applyCursorMove(state.draft.moveCursorPrev());

  void moveCursorNext() => _applyCursorMove(state.draft.moveCursorNext());

  void setBaseDuration(NoteBaseDuration base) =>
      _applyEdit(state.draft.setBaseDuration(base));

  void toggleDot() => _applyEdit(state.draft.toggleDot());

  void insertRest() => _applyEdit(state.draft.insertRest());

  void insertEmptySlice() => _applyEdit(state.draft.insertEmptySlice());

  void deleteAtCursor() => _applyEdit(state.draft.deleteAtCursor());

  void addMeasure() => _applyEdit(state.draft.addMeasure());

  void deleteCurrentMeasure() => _applyEdit(state.draft.deleteCurrentMeasure());

  void toggleTieAtCursor() => _applyEdit(
    state.draft.toggleTieAtCursor(noteIndex: state.selectedNoteIndex),
  );

  void cycleSelectedNote() {
    if (!ref.mounted || _isUnavailable) {
      return;
    }
    final count = state.draft.notesAtCursor.length;
    if (count == 0) {
      state = state.copyWith(clearSelectedNote: true);
      return;
    }
    final next = state.selectedNoteIndex == null
        ? 0
        : (state.selectedNoteIndex! + 1) % count;
    state = state.copyWith(selectedNoteIndex: next);
  }

  void addTouchNote() {
    final prevNotes = state.draft.notesAtCursor;
    final nextDraft = state.draft.addTouchNote();
    if (nextDraft == state.draft) {
      return;
    }
    _applyEdit(
      nextDraft,
      selectedNoteIndex: findAddedEditorNoteIndex(
        prevNotes,
        nextDraft.notesAtCursor,
      ),
    );
  }

  void stepSelectedNotePitch(int deltaSteps) =>
      _mutateSelectedNote((idx) => state.draft.stepNotePitch(idx, deltaSteps));

  void setSelectedNoteAccidental(Accidental? accidental) => _mutateSelectedNote(
    (idx) => state.draft.setNoteAccidental(idx, accidental),
  );

  void flipSelectedNoteClef() =>
      _mutateSelectedNote((idx) => state.draft.flipNoteClef(idx));

  void updateSetup({
    Scale? scale,
    TimeSignature? timeSignature,
    int? splitPointMidi,
    ClefAssignmentMode? clefMode,
  }) {
    _applyEdit(
      state.draft.updateSetup(
        scale: scale,
        timeSignature: timeSignature,
        splitPointMidi: splitPointMidi,
        clefMode: clefMode,
      ),
    );
  }

  void clearScore() => _applyEdit(state.draft.clearScore());

  void _mutateSelectedNote(ScoreDraft Function(int noteIndex) transform) {
    final idx = _effectiveSelectedIndex();
    if (idx == null) {
      return;
    }
    final prevNotes = state.draft.notesAtCursor;
    final nextDraft = transform(idx);
    if (nextDraft == state.draft) {
      return;
    }
    _applyEdit(
      nextDraft,
      selectedNoteIndex: findChangedEditorNoteIndex(
        prevNotes,
        nextDraft.notesAtCursor,
        idx,
      ),
    );
  }

  void _bindListeners() {
    final repository = ref.watch(midiRepositoryProvider);
    final noteSub = repository.noteEventsStream.listen(_coalescer.onNoteEvent);
    final deviceSub = repository.devicesStream.listen(
      _coalescer.syncConnectedDevices,
    );
    ref.onDispose(() {
      unawaited(noteSub.cancel());
      unawaited(deviceSub.cancel());
      _coalescer.dispose();
    });

    if (arg == ScoreEditorSessionId.composeTab) {
      ref.listen<bool>(scoreEditorPausedProvider, (_, _) {
        setPaused(_computeEffectivePaused());
      });
    }
    ref.listen<bool>(scoreEditorSessionPausedProvider(arg), (_, _) {
      setPaused(_computeEffectivePaused());
    });
    ref.listen<bool>(scoreEditorPlaybackPausedProvider(arg), (_, _) {
      setPaused(_computeEffectivePaused());
    });
    ref.listen<AsyncValue<List<MidiDeviceInfo>>>(midiDevicesProvider, (
      _,
      next,
    ) {
      final devices = next.value;
      if (devices != null) {
        _coalescer.syncConnectedDevices(devices);
      }
    }, fireImmediately: true);
  }

  bool get _isUnavailable => state.isLoadingVariant || state.loadError != null;

  void _onChordFlush(MidiChordFlush flush) {
    if (!ref.mounted || _coalescer.isPaused || _isUnavailable) {
      return;
    }
    final nextDraft = state.draft.enterMidiChord(flush.combinedNotes);
    if (nextDraft != state.draft) {
      _coalescer.resetActivePrompt();
      _applyEdit(nextDraft, resetSelectionToFirst: true);
    }
  }

  void _applyEdit(
    ScoreDraft nextDraft, {
    int? selectedNoteIndex,
    bool resetSelectionToFirst = false,
  }) {
    if (!ref.mounted || _isUnavailable || nextDraft == state.draft) {
      return;
    }
    final nextSelection = resetSelectionToFirst
        ? (nextDraft.notesAtCursor.isEmpty ? null : 0)
        : selectedNoteIndex;
    state = state.withDraftEdit(
      nextDraft,
      selectedNoteIndex: nextSelection,
      clearSelectedNote: nextDraft.notesAtCursor.isEmpty,
    );
  }

  void _applyCursorMove(ScoreDraft nextDraft) {
    if (!ref.mounted || _isUnavailable || nextDraft == state.draft) {
      return;
    }
    _coalescer.resetActivePrompt();
    state = state.withCursorMove(nextDraft);
  }

  bool _computeEffectivePaused() {
    final tabPaused =
        arg == ScoreEditorSessionId.composeTab &&
        ref.read(scoreEditorPausedProvider);
    final sessionPaused = ref.read(scoreEditorSessionPausedProvider(arg));
    final playbackPaused = ref.read(scoreEditorPlaybackPausedProvider(arg));
    return tabPaused || sessionPaused || playbackPaused;
  }

  int? _effectiveSelectedIndex() {
    final notes = state.draft.notesAtCursor;
    if (notes.isEmpty) {
      return null;
    }
    return (state.selectedNoteIndex ?? 0).clamp(0, notes.length - 1);
  }
}

final scoreEditorControllerProvider = NotifierProvider.autoDispose
    .family<ScoreEditorController, ScoreEditorState, ScoreEditorSessionId>(
      ScoreEditorController.new,
    );
