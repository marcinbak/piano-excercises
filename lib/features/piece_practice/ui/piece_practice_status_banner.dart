import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/piece_practice/state/practice_session_state.dart';

/// Compact status banner rendered above the score viewport on completion or empty hand/range.
class PiecePracticeStatusBanner extends StatelessWidget {
  const PiecePracticeStatusBanner({
    super.key,
    required this.status,
    required this.onRestart,
    this.isCompact = false,
  });

  final PracticeSessionStatus status;
  final VoidCallback onRestart;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    if (status == PracticeSessionStatus.active) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isCompleted = status == PracticeSessionStatus.completed;
    final bgColor = isCompleted
        ? colorScheme.primaryContainer
        : colorScheme.secondaryContainer;
    final fgColor = isCompleted
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSecondaryContainer;
    final padding = isCompact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 6 : 12,
        isCompact ? 4 : 8,
        isCompact ? 6 : 12,
        0,
      ),
      child: Material(
        key: ValueKey<String>(
          isCompleted
              ? 'practice_completed_banner'
              : 'practice_no_playable_banner',
        ),
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: padding,
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    isCompleted
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 18,
                    color: fgColor,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isCompleted ? 'Piece complete!' : 'No playable notes for selected hand or measure loop.',
                      style: textTheme.bodyMedium?.copyWith(color: fgColor),
                    ),
                  ),
                ],
              ),
              if (isCompleted)
                FilledButton.tonalIcon(
                  key: const ValueKey<String>('practice_play_again_button'),
                  onPressed: onRestart,
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Play Again'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
