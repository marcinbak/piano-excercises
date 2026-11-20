import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_controller.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_state.dart';
import 'package:piano_exercises/features/score_editor/ui/score_save_submitter.dart';

/// Modal bottom sheet saving a composed or edited score to the piece catalog.
class ScoreSaveSheet extends ConsumerStatefulWidget {
  const ScoreSaveSheet({
    super.key,
    required this.editorState,
    required this.editorController,
  });

  final ScoreEditorState editorState;
  final ScoreEditorController editorController;

  static Future<void> show(
    BuildContext context, {
    required ScoreEditorState editorState,
    required ScoreEditorController editorController,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ScoreSaveSheet(
        editorState: editorState,
        editorController: editorController,
      ),
    );
  }

  @override
  ConsumerState<ScoreSaveSheet> createState() => _ScoreSaveSheetState();
}

class _ScoreSaveSheetState extends ConsumerState<ScoreSaveSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _variantLabelController;
  late ScoreSaveMode _mode;
  late DifficultyTier _selectedTier;
  String? _selectedPieceId;
  String? _titleError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final binding = widget.editorState.binding;
    final draft = widget.editorState.draft;
    _mode = binding != null ? ScoreSaveMode.update : ScoreSaveMode.newPiece;
    _titleController = TextEditingController(
      text: binding?.piece.title ?? draft.title,
    );
    _artistController = TextEditingController(
      text: binding?.piece.artist ?? draft.artist,
    );
    _selectedTier = binding?.variant.difficultyTier ?? DifficultyTier.beginner;
    _variantLabelController = TextEditingController(
      text: binding?.variant.label ?? '',
    );
    _selectedPieceId = binding?.piece.id;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _variantLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalogSnapshot = ref.watch(catalogControllerProvider).value;
    final existingPieces = catalogSnapshot?.pieces ?? const <Piece>[];
    final catalogError = ref.watch(catalogErrorProvider);
    final binding = widget.editorState.binding;
    final effectivePieceId =
        (_selectedPieceId != null &&
            existingPieces.any((p) => p.id == _selectedPieceId))
        ? _selectedPieceId
        : (existingPieces.isNotEmpty ? existingPieces.first.id : null);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Save Score', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '${widget.editorState.draft.scale.label} • '
              '${widget.editorState.draft.timeSignature.label} • '
              '${widget.editorState.draft.measures.length} measures',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (catalogError != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                catalogError,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                if (binding != null)
                  ChoiceChip(
                    key: const ValueKey<String>('save-mode-update'),
                    showCheckmark: false,
                    label: const Text('Update arrangement'),
                    selected: _mode == ScoreSaveMode.update,
                    onSelected: (_) =>
                        setState(() => _mode = ScoreSaveMode.update),
                  ),
                ChoiceChip(
                  key: const ValueKey<String>('save-mode-new-piece'),
                  showCheckmark: false,
                  label: const Text('New piece'),
                  selected: _mode == ScoreSaveMode.newPiece,
                  onSelected: (_) =>
                      setState(() => _mode = ScoreSaveMode.newPiece),
                ),
                if (existingPieces.isNotEmpty)
                  ChoiceChip(
                    key: const ValueKey<String>('save-mode-attach-piece'),
                    showCheckmark: false,
                    label: const Text('Attach to piece'),
                    selected: _mode == ScoreSaveMode.attach,
                    onSelected: (_) => setState(() {
                      _mode = ScoreSaveMode.attach;
                      _selectedPieceId = effectivePieceId;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_mode != ScoreSaveMode.attach) ...<Widget>[
              TextField(
                key: const ValueKey<String>('save-title-field'),
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  errorText: _titleError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_titleError != null) {
                    setState(() => _titleError = null);
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey<String>('save-artist-field'),
                controller: _artistController,
                decoration: const InputDecoration(
                  labelText: 'Composer / Artist',
                  border: OutlineInputBorder(),
                ),
              ),
            ] else
              TargetPieceDropdown(
                pieces: existingPieces,
                selectedPieceId: effectivePieceId,
                onChanged: (value) => setState(() => _selectedPieceId = value),
              ),
            const SizedBox(height: 12),
            Text('Difficulty Tier', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            DifficultyTierSelector(
              selectedTier: _selectedTier,
              onChanged: (tier) => setState(() => _selectedTier = tier),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('save-variant-label-field'),
              controller: _variantLabelController,
              decoration: InputDecoration(
                labelText: 'Variant Label (optional)',
                hintText: _selectedTier.label,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey<String>('save-submit-button'),
              onPressed: _isSaving
                  ? null
                  : () => unawaited(_submit(existingPieces, effectivePieceId)),
              child: Text(
                _isSaving
                    ? 'Saving...'
                    : (_mode == ScoreSaveMode.update
                          ? 'Update Arrangement'
                          : 'Save to Catalog'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(
    List<Piece> existingPieces,
    String? effectivePieceId,
  ) async {
    if (_mode != ScoreSaveMode.attach && _titleController.text.trim().isEmpty) {
      setState(() => _titleError = 'Title must not be empty.');
      return;
    }
    setState(() => _isSaving = true);
    final result = await submitScoreSave(
      mode: _mode,
      catalogController: ref.read(catalogControllerProvider.notifier),
      editorState: widget.editorState,
      existingPieces: existingPieces,
      targetPieceId: effectivePieceId,
      details: CatalogScoreSaveDetails(
        title: _titleController.text,
        artist: _artistController.text,
        difficultyTier: _selectedTier,
        variantLabel: _variantLabelController.text,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _isSaving = false);
    if (result != null) {
      widget.editorController.applySaveResult(
        piece: result.piece,
        variant: result.variant,
      );
      Navigator.of(context).pop();
    }
  }
}
