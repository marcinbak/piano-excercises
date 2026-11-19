import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';

/// Toggle between creating a new piece and attaching to an existing piece.
class ImportModeChips extends StatelessWidget {
  const ImportModeChips({
    super.key,
    required this.isAttachMode,
    required this.onChanged,
  });

  final bool isAttachMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: <Widget>[
        ChoiceChip(
          key: const ValueKey<String>('import-mode-new-piece'),
          showCheckmark: false,
          label: const Text('New piece'),
          selected: !isAttachMode,
          onSelected: (_) => onChanged(false),
        ),
        ChoiceChip(
          key: const ValueKey<String>('import-mode-attach-piece'),
          showCheckmark: false,
          label: const Text('Attach to piece'),
          selected: isAttachMode,
          onSelected: (_) => onChanged(true),
        ),
      ],
    );
  }
}

/// Selector for choosing which existing [Piece] receives an attached variant.
class TargetPieceDropdown extends StatelessWidget {
  const TargetPieceDropdown({
    super.key,
    required this.pieces,
    required this.selectedPieceId,
    required this.onChanged,
  });

  final List<Piece> pieces;
  final String? selectedPieceId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: const ValueKey<String>('import-target-piece-selector'),
      initialValue: selectedPieceId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Target Piece',
        border: OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<String>>[
        for (final piece in pieces)
          DropdownMenuItem<String>(
            value: piece.id,
            child: Text(
              piece.artist.isEmpty
                  ? piece.title
                  : '${piece.title} — ${piece.artist}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Five-tier difficulty selector chips for imported score variants.
class DifficultyTierSelector extends StatelessWidget {
  const DifficultyTierSelector({
    super.key,
    required this.selectedTier,
    required this.onChanged,
  });

  final DifficultyTier selectedTier;
  final ValueChanged<DifficultyTier> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: <Widget>[
        for (final tier in DifficultyTier.values)
          ChoiceChip(
            key: ValueKey<String>('import-tier-chip-${tier.tier}'),
            showCheckmark: false,
            label: Text(tier.label),
            selected: selectedTier == tier,
            onSelected: (_) => onChanged(tier),
          ),
      ],
    );
  }
}
