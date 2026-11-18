import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/drill/state/drill_providers.dart';
import 'package:piano_exercises/features/drill/ui/drill_header_bar.dart';
import 'package:piano_exercises/features/drill/ui/grand_staff_card.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/progression/progression.dart';

/// Primary sight-reading drill screen displaying grand staff and BLE-MIDI feedback.
class DrillScreen extends ConsumerWidget {
  const DrillScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(drillControllerProvider);
    final progression = ref.watch(progressionControllerProvider);
    final connectedDevices = ref.watch(connectedMidiDevicesProvider);

    final statusLabel = switch (connectedDevices.length) {
      0 => 'Disconnected',
      1 => 'Connected (${connectedDevices.first.name})',
      final count => 'Connected ($count)',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sight-Reading Drill'),
        actions: <Widget>[
          TextButton.icon(
            key: const ValueKey<String>('midi-status-button'),
            onPressed: () {
              unawaited(
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const MidiSpikeScreen(),
                  ),
                ),
              );
            },
            icon: Icon(
              connectedDevices.isEmpty
                  ? Icons.bluetooth_disabled
                  : Icons.bluetooth_connected,
            ),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(statusLabel, overflow: TextOverflow.ellipsis),
            ),
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
