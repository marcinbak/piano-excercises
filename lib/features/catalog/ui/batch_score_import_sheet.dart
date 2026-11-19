import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_batch_import_planner.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/features/catalog/domain/score_import_source.dart';
import 'package:piano_exercises/features/catalog/state/catalog_providers.dart';
import 'package:piano_exercises/features/catalog/ui/batch_score_import_preview.dart';
import 'package:piano_exercises/features/catalog/ui/batch_score_import_widgets.dart';

/// Modal bottom sheet previewing and configuring a bulk `.zip` or multi-score import.
class BatchScoreImportSheet extends ConsumerStatefulWidget {
  const BatchScoreImportSheet({
    super.key,
    required this.selection,
    required this.existingPieces,
  });

  final ScoreImportSelection selection;
  final List<Piece> existingPieces;

  static Future<void> show(
    BuildContext context, {
    required ScoreImportSelection selection,
    required List<Piece> existingPieces,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BatchScoreImportSheet(
        selection: selection,
        existingPieces: existingPieces,
      ),
    );
  }

  @override
  ConsumerState<BatchScoreImportSheet> createState() =>
      _BatchScoreImportSheetState();
}

class _BatchScoreImportSheetState extends ConsumerState<BatchScoreImportSheet> {
  DifficultyTier _selectedTier = DifficultyTier.intermediate;
  bool _overrideInferredTiers = false;
  bool _isSubmitting = false;
  late CatalogBatchImportPlan _plan;

  @override
  void initState() {
    super.initState();
    _plan = _computePlan();
  }

  @override
  void didUpdateWidget(covariant BatchScoreImportSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection ||
        oldWidget.existingPieces != widget.existingPieces) {
      _plan = _computePlan();
    }
  }

  CatalogBatchImportPlan _computePlan() {
    return CatalogBatchImportPlanner.plan(
      candidates: widget.selection.candidates,
      existingPieces: widget.existingPieces,
      defaultTier: _selectedTier,
      overrideInferredTiers: _overrideInferredTiers,
    );
  }

  void _updateTierMode(bool overrideTiers) {
    setState(() {
      _overrideInferredTiers = overrideTiers;
      _plan = _computePlan();
    });
  }

  void _updateSelectedTier(DifficultyTier tier) {
    setState(() {
      _selectedTier = tier;
      _plan = _computePlan();
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_plan.hasImports) {
      return;
    }
    setState(() => _isSubmitting = true);
    final result = await ref
        .read(catalogControllerProvider.notifier)
        .importBatch(_plan);
    if (!mounted) {
      return;
    }
    setState(() => _isSubmitting = false);
    if (result != null) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final catalogError = ref.watch(catalogErrorProvider);
    final totalToImport = _plan.totalVariantsToImport;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Batch Score Import', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              BatchImportSummaryChips(plan: _plan, selection: widget.selection),
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
              BatchTierModeControls(
                overrideInferredTiers: _overrideInferredTiers,
                selectedTier: _selectedTier,
                enabled: !_isSubmitting,
                onModeChanged: _updateTierMode,
                onTierChanged: _updateSelectedTier,
              ),
              if (widget.selection.failures.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                BatchFailuresPreview(failures: widget.selection.failures),
              ],
              if (!_plan.hasImports) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'All selected scores are already in your catalog.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...<Widget>[
                const SizedBox(height: 12),
                BatchPlanPreviewList(plan: _plan),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  TextButton(
                    key: const ValueKey<String>('batch-import-cancel-button'),
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  if (_plan.hasImports)
                    FilledButton(
                      key: const ValueKey<String>('batch-import-submit-button'),
                      onPressed: _isSubmitting
                          ? null
                          : () => unawaited(_submit()),
                      child: Text(
                        _isSubmitting
                            ? 'Importing...'
                            : 'Import $totalToImport ${totalToImport == 1 ? 'Score' : 'Scores'}',
                      ),
                    )
                  else
                    FilledButton(
                      key: const ValueKey<String>('batch-import-close-button'),
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
