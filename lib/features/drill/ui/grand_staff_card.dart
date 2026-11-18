import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/drill/ui/grand_staff_painter.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Card wrapping the responsive [GrandStaffPainter] canvas.
class GrandStaffCard extends StatelessWidget {
  const GrandStaffCard({
    super.key,
    required this.targetNote,
    required this.wrongPlayedNotes,
  });

  final StaffNote targetNote;
  final List<StaffNote> wrongPlayedNotes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
