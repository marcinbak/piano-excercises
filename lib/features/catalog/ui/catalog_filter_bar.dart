import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Search bar and filter chips for piece difficulty tiers and key signatures.
class CatalogFilterBar extends StatefulWidget {
  const CatalogFilterBar({
    super.key,
    required this.searchText,
    required this.selectedTier,
    required this.selectedScale,
    required this.availableScales,
    required this.onSearchChanged,
    required this.onTierChanged,
    required this.onScaleChanged,
  });

  final String searchText;
  final DifficultyTier? selectedTier;
  final Scale? selectedScale;
  final List<Scale> availableScales;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<DifficultyTier?> onTierChanged;
  final ValueChanged<Scale?> onScaleChanged;

  @override
  State<CatalogFilterBar> createState() => _CatalogFilterBarState();
}

class _CatalogFilterBarState extends State<CatalogFilterBar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchText);
  }

  @override
  void didUpdateWidget(CatalogFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchText != oldWidget.searchText &&
        _searchController.text != widget.searchText) {
      _searchController.value = TextEditingValue(
        text: widget.searchText,
        selection: TextSelection.collapsed(offset: widget.searchText.length),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const ValueKey<String>('catalog-search-field'),
          controller: _searchController,
          onChanged: widget.onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search title, composer, key, or file',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: widget.searchText.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey<String>('catalog-search-clear-button'),
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      widget.onSearchChanged('');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            ChoiceChip(
              key: const ValueKey<String>('catalog-tier-chip-all'),
              showCheckmark: false,
              label: const Text('All Tiers'),
              selected: widget.selectedTier == null,
              onSelected: (_) => widget.onTierChanged(null),
            ),
            for (final tier in DifficultyTier.values)
              ChoiceChip(
                key: ValueKey<String>('catalog-tier-chip-${tier.tier}'),
                showCheckmark: false,
                label: Text(tier.label),
                selected: widget.selectedTier == tier,
                onSelected: (_) => widget.onTierChanged(
                  widget.selectedTier == tier ? null : tier,
                ),
              ),
          ],
        ),
        if (widget.availableScales.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                ChoiceChip(
                  key: const ValueKey<String>('catalog-scale-chip-all'),
                  showCheckmark: false,
                  label: const Text('All Keys'),
                  selected: widget.selectedScale == null,
                  onSelected: (_) => widget.onScaleChanged(null),
                ),
                for (final scale in widget.availableScales) ...<Widget>[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    key: ValueKey<String>('catalog-scale-chip-${scale.label}'),
                    showCheckmark: false,
                    label: Text(scale.label),
                    selected: widget.selectedScale == scale,
                    onSelected: (_) => widget.onScaleChanged(
                      widget.selectedScale == scale ? null : scale,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
