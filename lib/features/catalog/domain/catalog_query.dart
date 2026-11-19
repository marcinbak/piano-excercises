import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Filter and search criteria for querying catalog [Piece]s.
final class CatalogQuery {
  const CatalogQuery({
    this.searchText = '',
    this.difficultyFilter,
    this.scaleFilter,
  });

  final String searchText;
  final DifficultyTier? difficultyFilter;
  final Scale? scaleFilter;

  bool get hasActiveFilters =>
      searchText.trim().isNotEmpty ||
      difficultyFilter != null ||
      scaleFilter != null;

  CatalogQuery copyWith({
    String? searchText,
    DifficultyTier? difficultyFilter,
    bool clearDifficultyFilter = false,
    Scale? scaleFilter,
    bool clearScaleFilter = false,
  }) {
    return CatalogQuery(
      searchText: searchText ?? this.searchText,
      difficultyFilter: clearDifficultyFilter
          ? null
          : (difficultyFilter ?? this.difficultyFilter),
      scaleFilter: clearScaleFilter ? null : (scaleFilter ?? this.scaleFilter),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is CatalogQuery &&
            other.searchText == searchText &&
            other.difficultyFilter == difficultyFilter &&
            other.scaleFilter == scaleFilter);
  }

  @override
  int get hashCode => Object.hash(searchText, difficultyFilter, scaleFilter);
}
