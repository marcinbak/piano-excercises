import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/midi/domain/midi_device_info.dart';
import 'package:piano_exercises/features/midi/domain/midi_repository.dart';
import 'package:piano_exercises/features/midi/state/midi_providers.dart';
import 'package:piano_exercises/features/midi/ui/midi_device_tile.dart';
import 'package:piano_exercises/features/midi/ui/midi_input_check_card.dart';

/// Production BLE-MIDI discovery, device pairing, and live input-check screen.
class MidiConnectionScreen extends ConsumerStatefulWidget {
  const MidiConnectionScreen({super.key});

  @override
  ConsumerState<MidiConnectionScreen> createState() =>
      _MidiConnectionScreenState();
}

class _MidiConnectionScreenState extends ConsumerState<MidiConnectionScreen> {
  MidiScanController? _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = ref.read(midiScanControllerProvider.notifier);
  }

  @override
  void dispose() {
    _scanController?.stopScanIfActive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothAsync = ref.watch(midiBluetoothStatusProvider);
    final devicesAsync = ref.watch(midiDevicesProvider);
    final scanState = ref.watch(midiScanControllerProvider);
    final noteLog = ref.watch(midiNoteLogProvider);
    final controller = ref.read(midiScanControllerProvider.notifier);
    _scanController = controller;

    final btStatus = bluetoothAsync.value ?? MidiBluetoothStatus.unknown;

    return Scaffold(
      appBar: AppBar(title: const Text('BLE-MIDI Connection')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
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
            Text(
              'MIDI Devices',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._buildDeviceEntries(
              devicesAsync: devicesAsync,
              connectingDeviceId: scanState.connectingDeviceId,
              onConnect: (device) => unawaited(controller.connect(device)),
              onDisconnect: (device) =>
                  unawaited(controller.disconnect(device)),
            ),
            const SizedBox(height: 16),
            MidiInputCheckCard(
              latestEvent: noteLog.isEmpty ? null : noteLog.first.event,
              onClear: ref.read(midiNoteLogProvider.notifier).clear,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDeviceEntries({
    required AsyncValue<List<MidiDeviceInfo>> devicesAsync,
    required String? connectingDeviceId,
    required ValueChanged<MidiDeviceInfo> onConnect,
    required ValueChanged<MidiDeviceInfo> onDisconnect,
  }) {
    return devicesAsync.when(
      loading: () => const <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (error, _) => <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(child: Text('Could not load MIDI devices: $error')),
        ),
      ],
      data: (devices) {
        if (devices.isEmpty) {
          return const <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No MIDI devices found.\nTurn on your BLE-MIDI piano and tap Scan.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ];
        }
        return <Widget>[
          for (final device in devices)
            MidiDeviceTile(
              device: device,
              isBusyConnecting: connectingDeviceId == device.id,
              onConnect: () => onConnect(device),
              onDisconnect: () => onDisconnect(device),
            ),
        ];
      },
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
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _BluetoothStatusPill(status: bluetoothStatus),
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
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: fg),
            ),
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
