import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/midi/state/midi_session_providers.dart';
import 'package:piano_exercises/features/midi/ui/midi_connection_screen.dart';

/// AppBar action displaying live BLE-MIDI connection status and opening setup.
class MidiStatusActionButton extends ConsumerStatefulWidget {
  const MidiStatusActionButton({
    super.key,
    this.onBeforeOpen,
    this.onAfterClose,
  });

  final VoidCallback? onBeforeOpen;
  final VoidCallback? onAfterClose;

  @override
  ConsumerState<MidiStatusActionButton> createState() =>
      _MidiStatusActionButtonState();
}

class _MidiStatusActionButtonState
    extends ConsumerState<MidiStatusActionButton> {
  // Prevent duplicate route pushes when tapped twice before frame navigation settles.
  bool _isOpening = false;

  @override
  Widget build(BuildContext context) {
    final connectedDevices = ref.watch(connectedMidiDevicesProvider);
    final statusLabel = switch (connectedDevices.length) {
      0 => 'Disconnected',
      1 => 'Connected (${connectedDevices.first.name})',
      final count => 'Connected ($count)',
    };

    return TextButton.icon(
      key: const ValueKey<String>('midi-status-button'),
      onPressed: () => unawaited(_openConnectionScreen()),
      icon: Icon(
        connectedDevices.isEmpty
            ? Icons.bluetooth_disabled
            : Icons.bluetooth_connected,
      ),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(statusLabel, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Future<void> _openConnectionScreen() async {
    if (_isOpening) {
      return;
    }
    _isOpening = true;
    try {
      widget.onBeforeOpen?.call();
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const MidiConnectionScreen()),
      );
    } finally {
      _isOpening = false;
      widget.onAfterClose?.call();
    }
  }
}
