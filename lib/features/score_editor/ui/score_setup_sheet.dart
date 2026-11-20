import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Result returned from [ScoreSetupSheet].
sealed class ScoreSetupResult {
  const ScoreSetupResult();
}

/// Applies updated key, meter, split point, and clef routing to the draft.
final class ScoreSetupApply extends ScoreSetupResult {
  const ScoreSetupApply({
    required this.scale,
    required this.timeSignature,
    required this.splitPointMidi,
    required this.clefMode,
  });

  final Scale scale;
  final TimeSignature timeSignature;
  final int splitPointMidi;
  final ClefAssignmentMode clefMode;
}

/// Clears all measures in the editor back to four empty bars.
final class ScoreSetupClear extends ScoreSetupResult {
  const ScoreSetupClear();
}

/// Modal bottom sheet configuring key signature, meter, split point, and clef routing.
class ScoreSetupSheet extends StatefulWidget {
  const ScoreSetupSheet({super.key, required this.draft});

  final ScoreDraft draft;

  static Future<ScoreSetupResult?> show(
    BuildContext context, {
    required ScoreDraft draft,
  }) {
    return showModalBottomSheet<ScoreSetupResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ScoreSetupSheet(draft: draft),
    );
  }

  @override
  State<ScoreSetupSheet> createState() => _ScoreSetupSheetState();
}

class _ScoreSetupSheetState extends State<ScoreSetupSheet> {
  static final List<TimeSignature> _presetMeters = <TimeSignature>[
    TimeSignature(2, 4),
    TimeSignature(3, 4),
    TimeSignature.common,
    TimeSignature(3, 8),
    TimeSignature(6, 8),
    TimeSignature(2, 2),
  ];

  static const List<int> _presetSplitMidis = <int>[
    48,
    53,
    55,
    57,
    60,
    62,
    64,
    65,
    67,
    72,
  ];

  late int _fifths;
  late ScaleMode _mode;
  late TimeSignature _timeSignature;
  late int _splitPointMidi;
  late ClefAssignmentMode _clefMode;

  @override
  void initState() {
    super.initState();
    _fifths = widget.draft.scale.keySignature.fifths;
    _mode = widget.draft.scale.mode;
    _timeSignature = widget.draft.timeSignature;
    _splitPointMidi = widget.draft.splitPointMidi;
    _clefMode = widget.draft.clefMode;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meters = <TimeSignature>[
      ..._presetMeters,
      if (!_presetMeters.contains(_timeSignature)) _timeSignature,
    ];
    final splitOptions = <int>[
      ..._presetSplitMidis,
      if (!_presetSplitMidis.contains(_splitPointMidi)) _splitPointMidi,
    ]..sort();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Score Setup', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: const ValueKey<String>('setup-key-fifths-dropdown'),
              initialValue: _fifths,
              decoration: const InputDecoration(
                labelText: 'Key Signature',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<int>>[
                for (var f = -7; f <= 7; f += 1)
                  DropdownMenuItem<int>(
                    value: f,
                    child: Text(_keyLabel(f, _mode)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _fifths = value);
                }
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final mode in ScaleMode.values)
                  ChoiceChip(
                    key: ValueKey<String>('setup-scale-mode-${mode.name}'),
                    showCheckmark: false,
                    label: Text(mode.label),
                    selected: _mode == mode,
                    onSelected: (_) => setState(() => _mode = mode),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Time Signature', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                for (final meter in meters)
                  ChoiceChip(
                    key: ValueKey<String>(
                      'setup-time-sig-${meter.beats}-${meter.beatType}',
                    ),
                    showCheckmark: false,
                    label: Text(meter.label),
                    selected: _timeSignature == meter,
                    onSelected: (_) => setState(() => _timeSignature = meter),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: const ValueKey<String>('setup-split-point-dropdown'),
              initialValue: _splitPointMidi,
              decoration: const InputDecoration(
                labelText: 'MIDI Split Point (RH >= note)',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<int>>[
                for (final midi in splitOptions)
                  DropdownMenuItem<int>(
                    value: midi,
                    child: Text('${MidiNote(midi).name} (MIDI $midi)'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _splitPointMidi = value);
                }
              },
            ),
            const SizedBox(height: 12),
            Text('Clef Routing', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                for (final mode in ClefAssignmentMode.values)
                  ChoiceChip(
                    key: ValueKey<String>('setup-clef-mode-${mode.name}'),
                    showCheckmark: false,
                    label: Text(mode.label),
                    selected: _clefMode == mode,
                    onSelected: (_) => setState(() => _clefMode = mode),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                OutlinedButton(
                  key: const ValueKey<String>('setup-clear-score-button'),
                  onPressed: () =>
                      Navigator.of(context).pop(const ScoreSetupClear()),
                  child: const Text('Clear Score'),
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey<String>('setup-apply-button'),
                  onPressed: () => Navigator.of(context).pop(
                    ScoreSetupApply(
                      scale: Scale.fromKeySignature(
                        KeySignature(_fifths),
                        mode: _mode,
                      ),
                      timeSignature: _timeSignature,
                      splitPointMidi: _splitPointMidi,
                      clefMode: _clefMode,
                    ),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _keyLabel(int fifths, ScaleMode mode) {
    final scale = Scale.fromKeySignature(KeySignature(fifths), mode: mode);
    final sign = fifths > 0 ? '+$fifths' : '$fifths';
    return '${scale.label} ($sign)';
  }
}
