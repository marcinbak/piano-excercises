import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/drill/domain/drill_session.dart';
import 'package:piano_exercises/features/progression/progression.dart';

/// Selectable chips for switching between curriculum Stages 1–5.
class DrillStageSelector extends StatelessWidget {
  const DrillStageSelector({
    super.key,
    required this.progression,
    required this.onSelectStage,
  });

  final ProgressionSnapshot progression;
  final ValueChanged<StageId> onSelectStage;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: <Widget>[
        for (final stage in ProgressionCatalog.stages)
          ChoiceChip(
            key: ValueKey<String>('drill-stage-chip-${stage.id.number}'),
            avatar: Icon(
              progression.isUnlocked(stage.id)
                  ? Icons.lock_open
                  : Icons.lock_outline,
              size: 16,
            ),
            label: Text('${stage.id.number}. ${stage.title}'),
            selected: progression.activeStageId == stage.id,
            onSelected: (_) => onSelectStage(stage.id),
          ),
      ],
    );
  }
}

/// Summary strip displaying active stage title and attempt/reaction metrics.
class DrillStatsBar extends StatelessWidget {
  const DrillStatsBar({
    super.key,
    required this.progression,
    required this.lastResult,
  });

  final ProgressionSnapshot progression;
  final DrillAttemptResult? lastResult;

  @override
  Widget build(BuildContext context) {
    final stage = progression.activeStage;
    final stats = progression.statsFor(stage.id);
    final accuracyPct = (stats.accuracy * 100).round();
    final reactionLabel = lastResult != null
        ? '${lastResult!.reactionTimeMs} ms'
        : '—';

    return Card(
      key: const ValueKey<String>('drill-stats-bar'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Stage ${stage.id.number}: ${stage.title}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: <Widget>[
                _MetricItem(label: 'Accuracy', value: '$accuracyPct%'),
                _MetricItem(label: 'Streak', value: '${stats.currentStreak}'),
                _MetricItem(label: 'Best', value: '${stats.bestStreak}'),
                _MetricItem(label: 'Attempts', value: '${stats.attempts}'),
                _MetricItem(label: 'Reaction', value: reactionLabel),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$label: ',
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Immediate right/wrong feedback strip reflecting [lastResult].
class DrillFeedbackBanner extends StatelessWidget {
  const DrillFeedbackBanner({super.key, required this.lastResult});

  final DrillAttemptResult? lastResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (message, icon, bg, fg) = _resolveFeedbackPresentation(theme);

    return Container(
      key: const ValueKey<String>('drill-feedback-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }

  (String, IconData, Color, Color) _resolveFeedbackPresentation(
    ThemeData theme,
  ) {
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final result = lastResult;

    return switch (result?.status) {
      null || DrillFeedbackStatus.idle => (
        'Play the note shown on the grand staff via BLE-MIDI.',
        Icons.piano,
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
      DrillFeedbackStatus.correct when result!.wasCleanFirstTry => (
        'Correct: ${result.targetNote.pitchName} (${result.reactionTimeMs} ms)',
        Icons.check_circle_outline,
        isDark ? const Color(0xFF1B4332) : const Color(0xFFDFF4E4),
        isDark ? const Color(0xFFD8F3DC) : const Color(0xFF14532D),
      ),
      DrillFeedbackStatus.correct => (
        'Cleared ${result!.targetNote.pitchName} — next note ready',
        Icons.check_circle_outline,
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
      ),
      DrillFeedbackStatus.wrongSingleNote => (
        'Wrong note (${result!.playedNotes.single.name}) — target held, try again',
        Icons.error_outline,
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      DrillFeedbackStatus.multipleNotesPlayed => (
        'Multiple notes played (${result!.playedNotes.map((n) => n.name).join(', ')}) — play a single key',
        Icons.warning_amber_rounded,
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
    };
  }
}
