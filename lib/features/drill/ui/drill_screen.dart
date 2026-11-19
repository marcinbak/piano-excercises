import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/drill/state/drill_providers.dart';
import 'package:piano_exercises/features/drill/ui/drill_header_bar.dart';
import 'package:piano_exercises/features/drill/ui/grand_staff_card.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/progression/progression.dart';

/// Primary sight-reading drill screen displaying grand staff and BLE-MIDI feedback.
class DrillScreen extends ConsumerStatefulWidget {
  const DrillScreen({super.key});

  @override
  ConsumerState<DrillScreen> createState() => _DrillScreenState();
}

class _DrillScreenState extends ConsumerState<DrillScreen> {
  bool _wasPausedBeforeMidi = false;

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(drillControllerProvider);
    final progression = ref.watch(progressionControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sight-Reading Drill'),
        actions: <Widget>[
          MidiStatusActionButton(
            onBeforeOpen: () {
              final drill = ref.read(drillControllerProvider.notifier);
              _wasPausedBeforeMidi = drill.isPaused;
              drill.setPaused(true);
            },
            onAfterClose: () {
              if (!mounted || _wasPausedBeforeMidi) {
                return;
              }
              ref.read(drillControllerProvider.notifier).setPaused(false);
            },
          ),
          IconButton(
            key: const ValueKey<String>('drill-reset-button'),
            onPressed: () =>
                ref.read(drillControllerProvider.notifier).resetSession(),
            tooltip: 'Reset session',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DrillStageSelector(
                      progression: progression,
                      onSelectStage: (stageId) => ref
                          .read(progressionControllerProvider.notifier)
                          .selectStage(stageId),
                    ),
                    const SizedBox(height: 12),
                    DrillStatsBar(
                      progression: progression,
                      lastResult: sessionState.lastResult,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 200),
                        child: GrandStaffCard(
                          targetNote: sessionState.targetNote,
                          wrongPlayedNotes: sessionState.wrongPlayedNotes,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DrillFeedbackBanner(lastResult: sessionState.lastResult),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
