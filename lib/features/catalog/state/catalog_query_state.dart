import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_query.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Holds active search text, difficulty filter, and scale filter for the catalog.
class CatalogQueryNotifier extends Notifier<CatalogQuery> {
  @override
  CatalogQuery build() => const CatalogQuery();

  void setSearchText(String searchText) {
    if (state.searchText == searchText) {
      return;
    }
    state = state.copyWith(searchText: searchText);
  }

  void setDifficultyFilter(DifficultyTier? tier) {
    state = tier == null
        ? state.copyWith(clearDifficultyFilter: true)
        : state.copyWith(difficultyFilter: tier);
  }

  void setScaleFilter(Scale? scale) {
    state = scale == null
        ? state.copyWith(clearScaleFilter: true)
        : state.copyWith(scaleFilter: scale);
  }

  void clearFilters() {
    state = const CatalogQuery();
  }
}

final catalogQueryProvider =
    NotifierProvider<CatalogQueryNotifier, CatalogQuery>(
      CatalogQueryNotifier.new,
    );

/// Holds dismissible user-facing import or storage error messages.
class CatalogErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setError(String message) {
    state = message;
  }

  void clear() {
    state = null;
  }
}

final catalogErrorProvider = NotifierProvider<CatalogErrorNotifier, String?>(
  CatalogErrorNotifier.new,
);

/// Loaded catalog view combining filtered pieces, available scales, and total count.
final class CatalogSnapshot {
  const CatalogSnapshot({
    required this.pieces,
    required this.availableScales,
    required this.totalPieceCount,
  });

  final List<Piece> pieces;
  final List<Scale> availableScales;
  final int totalPieceCount;
}
