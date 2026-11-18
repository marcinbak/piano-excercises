import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/midi/domain/midi_device_info.dart';

/// Displays a discovered MIDI device with its transport badge and connect action.
class MidiDeviceTile extends StatelessWidget {
  const MidiDeviceTile({
    super.key,
    required this.device,
    required this.isBusyConnecting,
    required this.onConnect,
    required this.onDisconnect,
  });

  final MidiDeviceInfo device;
  final bool isBusyConnecting;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showSpinner = device.isConnecting || isBusyConnecting;
    final statusLabel = device.isConnected
        ? '${device.typeLabel} · Connected'
        : showSpinner
        ? '${device.typeLabel} · Connecting...'
        : '${device.typeLabel} · Available';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          device.isConnected ? Icons.piano : Icons.bluetooth,
          color: device.isConnected ? colorScheme.primary : null,
        ),
        title: Text(device.name),
        subtitle: Text(statusLabel),
        trailing: showSpinner
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : device.isConnected
            ? OutlinedButton(
                onPressed: onDisconnect,
                child: const Text('Disconnect'),
              )
            : FilledButton(onPressed: onConnect, child: const Text('Connect')),
      ),
    );
  }
}
