/// Difficulty arrangement tier (`1..5`) for a score variant.
enum DifficultyTier implements Comparable<DifficultyTier> {
  beginner(1, 'Beginner'),
  elementary(2, 'Elementary'),
  intermediate(3, 'Intermediate'),
  advanced(4, 'Advanced'),
  original(5, 'Original');

  const DifficultyTier(this.tier, this.label);

  final int tier;
  final String label;

  /// Resolves numeric [tier] (`1..5`) to its [DifficultyTier] value.
  static DifficultyTier fromTier(int tier) {
    return switch (tier) {
      1 => beginner,
      2 => elementary,
      3 => intermediate,
      4 => advanced,
      5 => original,
      _ => throw ArgumentError.value(tier, 'tier', 'Must be in 1..5.'),
    };
  }

  @override
  int compareTo(DifficultyTier other) => tier.compareTo(other.tier);
}
