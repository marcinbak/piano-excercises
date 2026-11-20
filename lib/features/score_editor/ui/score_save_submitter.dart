import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_state.dart';

/// Target persistence mode chosen inside `ScoreSaveSheet`.
enum ScoreSaveMode { update, newPiece, attach }

/// Executes a save/update/attach action through [CatalogController].
Future<({Piece piece, ScoreVariant variant})?> submitScoreSave({
  required ScoreSaveMode mode,
  required CatalogController catalogController,
  required ScoreEditorState editorState,
  required List<Piece> existingPieces,
  required String? targetPieceId,
  required CatalogScoreSaveDetails details,
}) async {
  final score = editorState.score;
  switch (mode) {
    case ScoreSaveMode.update:
      final binding = editorState.binding!;
      final saved = await catalogController.updateVariantScore(
        existingVariant: binding.variant,
        score: score,
        details: details,
      );
      if (saved == null) {
        return null;
      }
      final variant = saved.variants.firstWhere(
        (v) => v.id == binding.variant.id,
        orElse: () => saved.variants.first,
      );
      return (piece: saved, variant: variant);
    case ScoreSaveMode.newPiece:
      final saved = await catalogController.saveScoreAsNewPiece(
        score: score,
        details: details,
      );
      return saved == null
          ? null
          : (piece: saved, variant: saved.variants.single);
    case ScoreSaveMode.attach:
      if (targetPieceId == null) {
        return null;
      }
      final beforeIds = existingPieces
          .where((p) => p.id == targetPieceId)
          .expand((p) => p.variants)
          .map((v) => v.id)
          .toSet();
      final saved = await catalogController.saveScoreAsVariant(
        pieceId: targetPieceId,
        score: score,
        difficultyTier: details.difficultyTier,
        variantLabel: details.variantLabel,
      );
      if (saved == null) {
        return null;
      }
      final variant = saved.variants.firstWhere(
        (v) => !beforeIds.contains(v.id),
        orElse: () => saved.variants.last,
      );
      return (piece: saved, variant: variant);
  }
}
