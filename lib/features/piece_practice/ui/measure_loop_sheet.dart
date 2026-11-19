import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/piece_practice/domain/measure_loop_range.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// User choice returned by [MeasureLoopSheet.show].
sealed class MeasureLoopSheetResult {
  const MeasureLoopSheetResult();
}

/// Applies the chosen inclusive [MeasureLoopRange].
final class MeasureLoopApply extends MeasureLoopSheetResult {
  const MeasureLoopApply(this.range);

  final MeasureLoopRange range;
}

/// Clears the active measure loop without discarding sheet cancellation semantics.
final class MeasureLoopClear extends MeasureLoopSheetResult {
  const MeasureLoopClear();
}

/// Modal bottom sheet configuring an inclusive measure loop range.
class MeasureLoopSheet extends StatefulWidget {
  const MeasureLoopSheet({
    super.key,
    required this.measures,
    required this.initialMeasureIndex,
    this.currentLoop,
  });

  final List<ScoreMeasure> measures;
  final int initialMeasureIndex;
  final MeasureLoopRange? currentLoop;

  /// Opens the measure-loop picker; returns `null` when dismissed without action.
  static Future<MeasureLoopSheetResult?> show(
    BuildContext context, {
    required List<ScoreMeasure> measures,
    required int initialMeasureIndex,
    MeasureLoopRange? currentLoop,
  }) {
    return showModalBottomSheet<MeasureLoopSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MeasureLoopSheet(
        measures: measures,
        initialMeasureIndex: initialMeasureIndex,
        currentLoop: currentLoop,
      ),
    );
  }

  @override
  State<MeasureLoopSheet> createState() => _MeasureLoopSheetState();
}

class _MeasureLoopSheetState extends State<MeasureLoopSheet> {
  late int _startIndex;
  late int _endIndex;

  @override
  void initState() {
    super.initState();
    final count = widget.measures.length;
    if (count <= 0) {
      _startIndex = 0;
      _endIndex = 0;
      return;
    }
    final clampedLoop = widget.currentLoop?.clampToMeasureCount(count);
    if (clampedLoop != null) {
      _startIndex = clampedLoop.startMeasureIndex;
      _endIndex = clampedLoop.endMeasureIndex;
      return;
    }
    final initial = widget.initialMeasureIndex.clamp(0, count - 1);
    _startIndex = initial;
    _endIndex = initial;
  }

  int _displayNumber(int index) {
    if (index >= 0 && index < widget.measures.length) {
      final number = widget.measures[index].measureNumber;
      if (number > 0) {
        return number;
      }
    }
    return index + 1;
  }

  @override
  Widget build(BuildContext context) {
    final measureCount = widget.measures.length;
    final hasMeasures = measureCount > 0;
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Measure Loop', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _MeasureBoundRow(
              label: 'Start',
              measureLabel: 'M.${_displayNumber(_startIndex)}',
              keyPrefix: 'loop_start',
              onDecrement: hasMeasures && _startIndex > 0
                  ? () => setState(() => _startIndex -= 1)
                  : null,
              onIncrement: hasMeasures && _startIndex + 1 < measureCount
                  ? () => setState(() {
                      _startIndex += 1;
                      if (_endIndex < _startIndex) {
                        _endIndex = _startIndex;
                      }
                    })
                  : null,
            ),
            const SizedBox(height: 8),
            _MeasureBoundRow(
              label: 'End',
              measureLabel: 'M.${_displayNumber(_endIndex)}',
              keyPrefix: 'loop_end',
              onDecrement: hasMeasures && _endIndex > 0
                  ? () => setState(() {
                      _endIndex -= 1;
                      if (_startIndex > _endIndex) {
                        _startIndex = _endIndex;
                      }
                    })
                  : null,
              onIncrement: hasMeasures && _endIndex + 1 < measureCount
                  ? () => setState(() => _endIndex += 1)
                  : null,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: <Widget>[
                OutlinedButton(
                  key: const ValueKey<String>('loop_clear_button'),
                  onPressed: widget.currentLoop != null
                      ? () =>
                            Navigator.of(context).pop(const MeasureLoopClear())
                      : null,
                  child: const Text('Clear Loop'),
                ),
                FilledButton(
                  key: const ValueKey<String>('loop_apply_button'),
                  onPressed: hasMeasures
                      ? () => Navigator.of(context).pop(
                          MeasureLoopApply(
                            MeasureLoopRange(
                              startMeasureIndex: _startIndex,
                              endMeasureIndex: _endIndex,
                            ),
                          ),
                        )
                      : null,
                  child: const Text('Apply Loop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MeasureBoundRow extends StatelessWidget {
  const _MeasureBoundRow({
    required this.label,
    required this.measureLabel,
    required this.keyPrefix,
    this.onDecrement,
    this.onIncrement,
  });

  final String label;
  final String measureLabel;
  final String keyPrefix;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        IconButton(
          key: ValueKey<String>('${keyPrefix}_dec'),
          tooltip: 'Decrease $label measure',
          onPressed: onDecrement,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 64,
          child: Text(
            measureLabel,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
        ),
        IconButton(
          key: ValueKey<String>('${keyPrefix}_inc'),
          tooltip: 'Increase $label measure',
          onPressed: onIncrement,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
