import 'package:piano_exercises/features/catalog/domain/catalog_search_normalizer.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';

const List<({DifficultyTier tier, Set<String> keywords, String tierDigit})>
_tierRules = <({DifficultyTier tier, Set<String> keywords, String tierDigit})>[
  (
    tier: DifficultyTier.beginner,
    keywords: <String>{'beginner', 'easy', 'novice', 'tier1'},
    tierDigit: '1',
  ),
  (
    tier: DifficultyTier.elementary,
    keywords: <String>{'elementary', 'tier2'},
    tierDigit: '2',
  ),
  (
    tier: DifficultyTier.intermediate,
    keywords: <String>{'intermediate', 'medium', 'tier3'},
    tierDigit: '3',
  ),
  (
    tier: DifficultyTier.advanced,
    keywords: <String>{'advanced', 'hard', 'difficult', 'tier4'},
    tierDigit: '4',
  ),
  (
    tier: DifficultyTier.original,
    keywords: <String>{'original', 'urtext', 'unabridged', 'tier5'},
    tierDigit: '5',
  ),
];

const Map<String, DifficultyTier> _mikrokosmosVolumeTiers =
    <String, DifficultyTier>{
      '1': DifficultyTier.beginner,
      '2': DifficultyTier.elementary,
      '3': DifficultyTier.intermediate,
      '4': DifficultyTier.intermediate,
      '5': DifficultyTier.advanced,
      '6': DifficultyTier.advanced,
    };

/// Infers a [DifficultyTier] from archive/file path tokens first, then title tokens.
DifficultyTier? inferDifficultyTier({
  String? archiveEntryPath,
  required String fileName,
  required String title,
}) {
  final pathSource = archiveEntryPath == null || archiveEntryPath.trim().isEmpty
      ? fileName
      : '$archiveEntryPath $fileName';
  final pathTokens = _tokenizeHint(pathSource);
  final fromPath = _inferTierFromTokens(pathTokens);
  if (fromPath != null) {
    return fromPath;
  }
  final titleTokens = _tokenizeHint(title);
  final fromTitle = _inferTierFromTokens(titleTokens);
  if (fromTitle != null) {
    return fromTitle;
  }
  return _inferMikrokosmosTier(<String>[...pathTokens, ...titleTokens]);
}

List<String> _tokenizeHint(String input) {
  final normalized = CatalogSearchNormalizer.normalizeText(input);
  return normalized.isEmpty ? const <String>[] : normalized.split(' ');
}

DifficultyTier? _inferTierFromTokens(List<String> tokens) {
  if (tokens.isEmpty) {
    return null;
  }
  for (final rule in _tierRules) {
    if (tokens.any(rule.keywords.contains) ||
        _hasPair(tokens, 'tier', rule.tierDigit)) {
      return rule.tier;
    }
  }
  return _inferMikrokosmosTier(tokens);
}

DifficultyTier? _inferMikrokosmosTier(List<String> tokens) {
  if (!tokens.contains('mikrokosmos')) {
    return null;
  }
  for (final entry in _mikrokosmosVolumeTiers.entries) {
    if (tokens.contains('vol${entry.key}') ||
        _hasPair(tokens, 'vol', entry.key)) {
      return entry.value;
    }
  }
  return null;
}

bool _hasPair(List<String> tokens, String first, String second) {
  for (var i = 0; i < tokens.length - 1; i += 1) {
    if (tokens[i] == first && tokens[i + 1] == second) {
      return true;
    }
  }
  return false;
}
