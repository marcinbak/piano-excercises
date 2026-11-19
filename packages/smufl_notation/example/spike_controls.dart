import 'package:flutter/widgets.dart';
import 'package:smufl_notation/smufl_notation.dart';

/// Compact pure-Widgets header controls for the `[M5]` spike harness.
class SpikeControls extends StatelessWidget {
  const SpikeControls({
    required this.usePolyphonic,
    required this.dimmedClef,
    required this.showWrongNotes,
    required this.compactWidth,
    required this.metricsText,
    required this.onSelectSimplified,
    required this.onSelectPolyphonic,
    required this.onPrevSlice,
    required this.onNextSlice,
    required this.onSelectHand,
    required this.onToggleWrongNotes,
    required this.onSelectCompactWidth,
    super.key,
  });

  final bool usePolyphonic;
  final SmuflClef? dimmedClef;
  final bool showWrongNotes;
  final bool compactWidth;
  final ValueNotifier<String> metricsText;
  final VoidCallback onSelectSimplified;
  final VoidCallback onSelectPolyphonic;
  final VoidCallback onPrevSlice;
  final VoidCallback onNextSlice;
  final ValueChanged<SmuflClef?> onSelectHand;
  final VoidCallback onToggleWrongNotes;
  final ValueChanged<bool> onSelectCompactWidth;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _SpikePill(
          key: const Key('spike-fixture-simplified'),
          label: 'Simplified',
          selected: !usePolyphonic,
          onTap: onSelectSimplified,
        ),
        _SpikePill(
          key: const Key('spike-fixture-polyphonic'),
          label: '32m Poly',
          selected: usePolyphonic,
          onTap: onSelectPolyphonic,
        ),
        _SpikePill(
          key: const Key('spike-prev-slice'),
          label: 'Prev',
          selected: false,
          onTap: onPrevSlice,
        ),
        _SpikePill(
          key: const Key('spike-next-slice'),
          label: 'Next',
          selected: false,
          onTap: onNextSlice,
        ),
        _SpikePill(
          key: const Key('spike-hand-both'),
          label: 'Both',
          selected: dimmedClef == null,
          onTap: () => onSelectHand(null),
        ),
        _SpikePill(
          key: const Key('spike-hand-right'),
          label: 'RH',
          selected: dimmedClef == SmuflClef.bass,
          onTap: () => onSelectHand(SmuflClef.bass),
        ),
        _SpikePill(
          key: const Key('spike-hand-left'),
          label: 'LH',
          selected: dimmedClef == SmuflClef.treble,
          onTap: () => onSelectHand(SmuflClef.treble),
        ),
        _SpikePill(
          key: const Key('spike-wrong-note-toggle'),
          label: 'Wrong',
          selected: showWrongNotes,
          onTap: onToggleWrongNotes,
        ),
        _SpikePill(
          key: const Key('spike-width-compact'),
          label: '340px',
          selected: compactWidth,
          onTap: () => onSelectCompactWidth(true),
        ),
        _SpikePill(
          key: const Key('spike-width-full'),
          label: 'Full',
          selected: !compactWidth,
          onTap: () => onSelectCompactWidth(false),
        ),
        ValueListenableBuilder<String>(
          valueListenable: metricsText,
          builder: (context, text, _) => Text(
            text,
            key: const Key('spike-frame-metrics'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF334155)),
          ),
        ),
      ],
    );
  }
}

class _SpikePill extends StatelessWidget {
  const _SpikePill({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1E40AF) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1E40AF)
                  : const Color(0xFFCBD5E1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF0F172A),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
