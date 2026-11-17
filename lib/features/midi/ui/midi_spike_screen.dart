import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/midi/domain/midi_device_info.dart';
import 'package:piano_exercises/features/midi/domain/midi_repository.dart';
import 'package:piano_exercises/features/midi/state/midi_providers.dart';
import 'package:piano_exercises/features/midi/ui/midi_device_tile.dart';
import 'package:piano_exercises/features/midi/ui/midi_note_log_section.dart';

/// Diagnostic screen for Milestone 1 BLE-MIDI discovery, connection, and note input.
class MidiSpikeScreen extends ConsumerWidget {
  const MidiSpikeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bluetoothAsync = ref.watch(midiBluetoothStatusProvider);
    final devicesAsync = ref.watch(midiDevicesProvider);
    final scanState = ref.watch(midiScanControllerProvider);
    final noteLog = ref.watch(midiNoteLogProvider);
    final controller = ref.read(midiScanControllerProvider.notifier);

    final btStatus = bluetoothAsync.value ?? MidiBluetoothStatus.unknown;

    return Scaffold(
      appBar: AppBar(title: const Text('BLE-MIDI Spike')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ControlBar(
                bluetoothStatus: btStatus,
                isScanning: scanState.isScanning,
                onStartScan: () => unawaited(controller.startScan()),
                onStopScan: () => unawaited(controller.stopScan()),
              ),
              if (scanState.errorMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                _ErrorBanner(
                  message: scanState.errorMessage!,
                  onDismiss: controller.dismissError,
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                flex: 2,
                child: _DevicesSection(
                  devicesAsync: devicesAsync,
                  connectingDeviceId: scanState.connectingDeviceId,
                  onConnect: (device) => unawaited(controller.connect(device)),
                  onDisconnect: (device) =>
                      unawaited(controller.disconnect(device)),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                flex: 3,
                child: MidiNoteLogSection(
                  entries: noteLog,
                  onClear: ref.read(midiNoteLogProvider.notifier).clear,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.bluetoothStatus,
    required this.isScanning,
    required this.onStartScan,
    required this.onStopScan,
  });

  final MidiBluetoothStatus bluetoothStatus;
  final bool isScanning;
  final VoidCallback onStartScan;
  final VoidCallback onStopScan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _BluetoothStatusPill(status: bluetoothStatus),
        const Spacer(),
        if (isScanning)
          OutlinedButton.icon(
            onPressed: onStopScan,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          )
        else
          FilledButton.icon(
            onPressed: onStartScan,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Scan'),
          ),
      ],
    );
  }
}

class _BluetoothStatusPill extends StatelessWidget {
  const _BluetoothStatusPill({required this.status});

  final MidiBluetoothStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (String label, IconData icon, Color bg, Color fg) = switch (status) {
      MidiBluetoothStatus.poweredOn => (
        'Bluetooth On',
        Icons.bluetooth_connected,
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      MidiBluetoothStatus.poweredOff => (
        'Bluetooth Off',
        Icons.bluetooth_disabled,
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      MidiBluetoothStatus.unauthorized => (
        'Permission Denied',
        Icons.lock_outline,
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      MidiBluetoothStatus.unsupported => (
        'BLE Unsupported',
        Icons.block,
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
      MidiBluetoothStatus.unknown => (
        'Bluetooth Unknown',
        Icons.bluetooth,
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss error',
              icon: Icon(Icons.close, color: colorScheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicesSection extends StatelessWidget {
  const _DevicesSection({
    required this.devicesAsync,
    required this.connectingDeviceId,
    required this.onConnect,
    required this.onDisconnect,
  });

  final AsyncValue<List<MidiDeviceInfo>> devicesAsync;
  final String? connectingDeviceId;
  final ValueChanged<MidiDeviceInfo> onConnect;
  final ValueChanged<MidiDeviceInfo> onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('MIDI Devices', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(
          child: devicesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('Could not load MIDI devices: $error')),
            data: (devices) {
              if (devices.isEmpty) {
                return const Center(
                  child: Text(
                    'No MIDI devices found.\nTurn on your BLE-MIDI piano and tap Scan.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return MidiDeviceTile(
                    device: device,
                    isBusyConnecting: connectingDeviceId == device.id,
                    onConnect: () => onConnect(device),
                    onDisconnect: () => onDisconnect(device),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
