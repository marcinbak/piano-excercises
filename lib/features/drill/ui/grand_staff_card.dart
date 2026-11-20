import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/drill/ui/grand_staff_painter.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Card wrapping the responsive [GrandStaffPainter] canvas.
class GrandStaffCard extends StatelessWidget {
  const GrandStaffCard({
    super.key,
    required this.targetNote,
    required this.wrongPlayedNotes,
    this.isTargetCorrect = false,
  });

  final StaffNote targetNote;
  final List<StaffNote> wrongPlayedNotes;
  final bool isTargetCorrect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final successColor = theme.brightness == Brightness.dark
        ? const Color(0xFF66BB6A)
        : const Color(0xFF2E7D32);

    return Card(
      key: const ValueKey<String>('grand-staff-card'),
      elevation: 1,
      child: Semantics(
        label: 'Grand staff displaying target note',
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox.expand(
            child: CustomPaint(
              painter: GrandStaffPainter(
                targetNote: targetNote,
                wrongPlayedNotes: wrongPlayedNotes,
                inkColor: colorScheme.onSurface,
                errorColor: colorScheme.error,
                staffLineColor: colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.72,
                ),
                isTargetCorrect: isTargetCorrect,
                successColor: successColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
