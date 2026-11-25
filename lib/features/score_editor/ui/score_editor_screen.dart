import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/piece_practice/piece_practice.dart'
    show PieceScoreScreen;
import 'package:piano_exercises/features/score_editor/state/score_editor_controller.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_state.dart';
import 'package:piano_exercises/features/score_editor/ui/score_editor_playback_sync.dart';
import 'package:piano_exercises/features/score_editor/ui/score_save_sheet.dart';
import 'package:piano_exercises/features/score_editor/ui/score_setup_sheet.dart';
import 'package:piano_exercises/features/score_playback/score_playback.dart';

/// Step-time MIDI and touch grand-staff score composer and arranger screen.
class ScoreEditorScreen extends ConsumerStatefulWidget {
  const ScoreEditorScreen({
    super.key,
    this.sessionId = ScoreEditorSessionId.composeTab,
    this.initialPiece,
    this.initialVariant,
    this.appBarActions = const <Widget>[],
  });

  final ScoreEditorSessionId sessionId;
  final Piece? initialPiece;
  final ScoreVariant? initialVariant;
  final List<Widget> appBarActions;

  @override
  ConsumerState<ScoreEditorScreen> createState() => _ScoreEditorScreenState();
}

class _ScoreEditorScreenState extends ConsumerState<ScoreEditorScreen> {
  int _modalPauseDepth = 0;
  bool _wasSessionPausedBeforeModal = false;
  bool _isOpeningModal = false;

  ScorePlaybackSessionId get _playbackId =>
      ScorePlaybackSessionId('editor_${widget.sessionId.value}');

  @override
  void initState() {
    super.initState();
    final piece = widget.initialPiece;
    final variant = widget.initialVariant;
    if (piece != null && variant != null) {
      Future<void>.microtask(() {
        if (mounted) {
          unawaited(
            ref
                .read(scoreEditorControllerProvider(widget.sessionId).notifier)
                .loadVariantForEditing(piece, variant),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    listenScoreEditorPlaybackSync(
      ref,
      sessionId: widget.sessionId,
      playbackId: _playbackId,
    );
    final state = ref.watch(scoreEditorControllerProvider(widget.sessionId));
    final controller = ref.read(
      scoreEditorControllerProvider(widget.sessionId).notifier,
    );
    final playbackState = ref.watch(
      scorePlaybackControllerProvider(_playbackId),
    );
    final playbackController = ref.read(
      scorePlaybackControllerProvider(_playbackId).notifier,
    );
    final isCompactHeight = MediaQuery.sizeOf(context).height < 480;
    final actionsDisabled = state.isLoadingVariant || state.loadError != null;
    final baseTitle =
        state.binding?.piece.title ??
        (state.draft.title == 'Untitled' ? 'Compose Score' : state.draft.title);
    final titleText = state.isDirty ? '$baseTitle *' : baseTitle;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isCompactHeight ? 48 : null,
        title: Text(titleText, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('editor-practice-button'),
            tooltip: 'Practice preview',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.school_outlined),
            onPressed: actionsDisabled
                ? null
                : () => unawaited(_openPreviewPractice(state)),
          ),
          IconButton(
            key: const ValueKey<String>('editor-open-save-button'),
            tooltip: 'Save score',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.save_outlined),
            onPressed: actionsDisabled
                ? null
                : () => unawaited(_openSaveSheet(state, controller)),
          ),
          if (widget.appBarActions.isNotEmpty)
            ...widget.appBarActions
          else
            MidiStatusActionButton(
              onBeforeOpen: _pauseSessionBeforeModal,
              onAfterClose: _restoreSessionAfterModal,
            ),
        ],
      ),
      body: SafeArea(
        child: ScoreEditorBody(
          state: state,
          controller: controller,
          playbackState: playbackState,
          playbackController: playbackController,
          onOpenSetup: () => unawaited(_openSetupSheet(state, controller)),
          isCompactHeight: isCompactHeight,
        ),
      ),
    );
  }

  void _pauseSessionBeforeModal() {
    ref.read(scorePlaybackControllerProvider(_playbackId).notifier).stop();
    if (_modalPauseDepth == 0) {
      _wasSessionPausedBeforeModal = ref.read(
        scoreEditorSessionPausedProvider(widget.sessionId),
      );
      ref
          .read(scoreEditorSessionPausedProvider(widget.sessionId).notifier)
          .setPaused(true);
    }
    _modalPauseDepth += 1;
  }

  void _restoreSessionAfterModal() {
    if (_modalPauseDepth > 0) {
      _modalPauseDepth -= 1;
    }
    if (!mounted || _modalPauseDepth > 0 || _wasSessionPausedBeforeModal) {
      return;
    }
    ref
        .read(scoreEditorSessionPausedProvider(widget.sessionId).notifier)
        .setPaused(false);
  }

  Future<void> _openSetupSheet(
    ScoreEditorState state,
    ScoreEditorController controller,
  ) async {
    if (_isOpeningModal) {
      return;
    }
    _isOpeningModal = true;
    _pauseSessionBeforeModal();
    final ScoreSetupResult? result;
    try {
      result = await ScoreSetupSheet.show(context, draft: state.draft);
    } finally {
      _isOpeningModal = false;
      _restoreSessionAfterModal();
    }
    if (!mounted || result == null) {
      return;
    }
    switch (result) {
      case ScoreSetupClear():
        controller.clearScore();
      case ScoreSetupApply():
        controller.updateSetup(
          scale: result.scale,
          timeSignature: result.timeSignature,
          splitPointMidi: result.splitPointMidi,
          clefMode: result.clefMode,
        );
    }
  }

  Future<void> _openSaveSheet(
    ScoreEditorState state,
    ScoreEditorController controller,
  ) async {
    if (_isOpeningModal) {
      return;
    }
    _isOpeningModal = true;
    _pauseSessionBeforeModal();
    try {
      await ScoreSaveSheet.show(
        context,
        editorState: state,
        editorController: controller,
      );
    } finally {
      _isOpeningModal = false;
      _restoreSessionAfterModal();
    }
  }

  Future<void> _openPreviewPractice(ScoreEditorState state) async {
    if (_isOpeningModal) {
      return;
    }
    _isOpeningModal = true;
    _pauseSessionBeforeModal();
    final previewPiece = buildEditorPreviewPiece(
      state.draft,
      state.binding?.variant,
    );
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PieceScoreScreen(
            piece: previewPiece,
            initialVariant: previewPiece.variants.single,
            initialScore: state.score,
          ),
        ),
      );
    } finally {
      _isOpeningModal = false;
      _restoreSessionAfterModal();
    }
  }
}
