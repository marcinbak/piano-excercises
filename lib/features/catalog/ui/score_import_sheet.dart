import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';
import 'package:piano_exercises/features/catalog/state/catalog_providers.dart';
import 'package:piano_exercises/features/catalog/ui/score_import_fields.dart';

/// Modal bottom sheet configuring piece metadata and difficulty for an imported score.
class ScoreImportSheet extends ConsumerStatefulWidget {
  const ScoreImportSheet({
    super.key,
    required this.candidate,
    required this.existingPieces,
    this.initialTargetPiece,
  });

  final ImportedScoreCandidate candidate;
  final List<Piece> existingPieces;
  final Piece? initialTargetPiece;

  static Future<void> show(
    BuildContext context, {
    required ImportedScoreCandidate candidate,
    required List<Piece> existingPieces,
    Piece? initialTargetPiece,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ScoreImportSheet(
        candidate: candidate,
        existingPieces: existingPieces,
        initialTargetPiece: initialTargetPiece,
      ),
    );
  }

  @override
  ConsumerState<ScoreImportSheet> createState() => _ScoreImportSheetState();
}

class _ScoreImportSheetState extends ConsumerState<ScoreImportSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _variantLabelController;
  late bool _attachMode;
  late DifficultyTier _selectedTier;
  String? _selectedPieceId;
  String? _titleError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final meta = widget.candidate.parsedScore.metadata;
    _titleController = TextEditingController(text: meta.title);
    _artistController = TextEditingController(text: meta.artist);
    _variantLabelController = TextEditingController();
    _selectedTier = DifficultyTier.beginner;
    _attachMode =
        widget.initialTargetPiece != null && widget.existingPieces.isNotEmpty;
    if (widget.existingPieces.isNotEmpty) {
      _selectedPieceId =
          widget.initialTargetPiece?.id ?? widget.existingPieces.first.id;
    }
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
    final meta = widget.candidate.parsedScore.metadata;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final catalogError = ref.watch(catalogErrorProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Import Score', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '${widget.candidate.fileName} • ${meta.scale.label} • '
              '${meta.measureCount} measures',
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
            if (widget.existingPieces.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              ImportModeChips(
                isAttachMode: _attachMode,
                onChanged: (attach) => setState(() {
                  _attachMode = attach;
                  if (attach) {
                    _selectedPieceId ??= widget.existingPieces.first.id;
                  }
                }),
              ),
            ],
            const SizedBox(height: 12),
            if (!_attachMode) ...<Widget>[
              TextField(
                key: const ValueKey<String>('import-title-field'),
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
                key: const ValueKey<String>('import-artist-field'),
                controller: _artistController,
                decoration: const InputDecoration(
                  labelText: 'Composer / Artist',
                  border: OutlineInputBorder(),
                ),
              ),
            ] else
              TargetPieceDropdown(
                pieces: widget.existingPieces,
                selectedPieceId: _selectedPieceId,
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
              key: const ValueKey<String>('import-variant-label-field'),
              controller: _variantLabelController,
              decoration: InputDecoration(
                labelText: 'Variant Label (optional)',
                hintText: _selectedTier.label,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey<String>('import-save-button'),
              onPressed: _isSaving ? null : () => unawaited(_submit()),
              child: Text(_isSaving ? 'Saving...' : 'Save to Catalog'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final controller = ref.read(catalogControllerProvider.notifier);
    if (!_attachMode && _titleController.text.trim().isEmpty) {
      setState(() => _titleError = 'Title must not be empty.');
      return;
    }
    setState(() => _isSaving = true);
    final Piece? saved;
    if (!_attachMode) {
      saved = await controller.importAsNewPiece(
        candidate: widget.candidate,
        title: _titleController.text,
        artist: _artistController.text,
        difficultyTier: _selectedTier,
        variantLabel: _variantLabelController.text,
      );
    } else {
      final targetId = _selectedPieceId;
      if (targetId == null) {
        setState(() => _isSaving = false);
        return;
      }
      saved = await controller.importAsVariant(
        pieceId: targetId,
        candidate: widget.candidate,
        difficultyTier: _selectedTier,
        variantLabel: _variantLabelController.text,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() => _isSaving = false);
    if (saved != null) {
      Navigator.of(context).pop();
    }
  }
}
