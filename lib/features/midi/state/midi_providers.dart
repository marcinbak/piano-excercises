import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/midi/domain/midi_device_info.dart';
import 'package:piano_exercises/features/midi/domain/midi_note_event.dart';
import 'package:piano_exercises/features/midi/domain/midi_repository.dart';

/// DI boundary for [MidiRepository]; overridden in `app/` and tests.
final midiRepositoryProvider = Provider<MidiRepository>((ref) {
  throw UnimplementedError(
    'midiRepositoryProvider must be overridden in ProviderScope.',
  );
});

/// Emits the initial MIDI device snapshot followed by live discovery/connection updates.
final midiDevicesProvider = StreamProvider<List<MidiDeviceInfo>>((ref) {
  final repository = ref.watch(midiRepositoryProvider);
  return Stream<List<MidiDeviceInfo>>.multi((controller) {
    // Subscribe before fetching initial snapshot so updates during the async read are not lost.
    var hasLiveUpdate = false;
    final subscription = repository.devicesStream.listen(
      (devices) {
        hasLiveUpdate = true;
        controller.add(devices);
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
    unawaited(
      repository.currentDevices().then(
        (initial) {
          if (!hasLiveUpdate && !controller.isClosed) {
            controller.add(initial);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!controller.isClosed) {
            controller.addError(error, stackTrace);
          }
        },
      ),
    );
  });
});

/// Emits the current Bluetooth status followed by adapter state transitions.
final midiBluetoothStatusProvider = StreamProvider<MidiBluetoothStatus>((ref) {
  final repository = ref.watch(midiRepositoryProvider);
  return Stream<MidiBluetoothStatus>.multi((controller) {
    final subscription = repository.bluetoothStateStream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
    controller.add(repository.currentBluetoothStatus);
  });
});

/// Note event paired with a stable monotonic sequence number for live logging.
final class MidiNoteLogEntry {
  const MidiNoteLogEntry({required this.sequence, required this.event});

  final int sequence;
  final MidiNoteEvent event;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MidiNoteLogEntry &&
            other.sequence == sequence &&
            other.event == event);
  }

  @override
  int get hashCode => Object.hash(sequence, event);
}

/// Collects recent Note On/Off events (newest first) for the spike monitor feed.
class MidiNoteLogNotifier extends Notifier<List<MidiNoteLogEntry>> {
  static const int maxEntries = 30;
  int _nextSequence = 0;

  @override
  List<MidiNoteLogEntry> build() {
    final repository = ref.watch(midiRepositoryProvider);
    _nextSequence = 0;
    final subscription = repository.noteEventsStream.listen(_appendEvent);
    ref.onDispose(subscription.cancel);
    return const <MidiNoteLogEntry>[];
  }

  void _appendEvent(MidiNoteEvent event) {
    if (!ref.mounted) {
      return;
    }
    final entry = MidiNoteLogEntry(sequence: ++_nextSequence, event: event);
    final next = <MidiNoteLogEntry>[entry, ...state];
    state = next.length > maxEntries ? next.sublist(0, maxEntries) : next;
  }

  void clear() {
    _nextSequence = 0;
    state = const <MidiNoteLogEntry>[];
  }
}

final midiNoteLogProvider =
    NotifierProvider<MidiNoteLogNotifier, List<MidiNoteLogEntry>>(
      MidiNoteLogNotifier.new,
    );

/// UI control state for BLE-MIDI scanning and device connection operations.
final class MidiScanState {
  const MidiScanState({
    this.isScanning = false,
    this.connectingDeviceId,
    this.errorMessage,
  });

  final bool isScanning;
  final String? connectingDeviceId;
  final String? errorMessage;

  MidiScanState copyWith({
    bool? isScanning,
    String? connectingDeviceId,
    bool clearConnectingDeviceId = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return MidiScanState(
      isScanning: isScanning ?? this.isScanning,
      connectingDeviceId: clearConnectingDeviceId
          ? null
          : (connectingDeviceId ?? this.connectingDeviceId),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MidiScanState &&
            other.isScanning == isScanning &&
            other.connectingDeviceId == connectingDeviceId &&
            other.errorMessage == errorMessage);
  }

  @override
  int get hashCode => Object.hash(isScanning, connectingDeviceId, errorMessage);
}

/// Manages BLE-MIDI scan and connect/disconnect actions with error surfacing.
class MidiScanController extends Notifier<MidiScanState> {
  late MidiRepository _repository;
  int _scanGeneration = 0;
  bool _isScanActive = false;

  @override
  MidiScanState build() {
    _repository = ref.watch(midiRepositoryProvider);
    _isScanActive = false;
    ref.onDispose(() {
      _scanGeneration += 1;
      // Use a plain field here because ref/state are already unmounted during dispose.
      if (_isScanActive) {
        _isScanActive = false;
        unawaited(_repository.stopScan().catchError((Object _) {}));
      }
    });
    ref.listen<AsyncValue<MidiBluetoothStatus>>(midiBluetoothStatusProvider, (
      _,
      next,
    ) {
      final status = next.value;
      if (status != null &&
          status != MidiBluetoothStatus.poweredOn &&
          status != MidiBluetoothStatus.unknown &&
          state.isScanning) {
        // Keep _scanGeneration unchanged so an in-flight startScan() error still surfaces.
        _isScanActive = false;
        state = state.copyWith(isScanning: false);
        unawaited(_repository.stopScan().catchError((Object _) {}));
      }
    });
    return const MidiScanState();
  }

  Future<void> startScan() async {
    if (state.isScanning) {
      return;
    }
    final generation = ++_scanGeneration;
    _isScanActive = true;
    state = state.copyWith(isScanning: true, clearErrorMessage: true);
    try {
      await _repository.startScan();
      if (!ref.mounted || generation != _scanGeneration || !state.isScanning) {
        if (!ref.mounted || !state.isScanning) {
          _isScanActive = false;
          await _stopScanSafely();
        }
        return;
      }
    } catch (error) {
      if (!ref.mounted || generation != _scanGeneration) {
        if (!ref.mounted) {
          _isScanActive = false;
        }
        return;
      }
      _isScanActive = false;
      state = state.copyWith(
        isScanning: false,
        errorMessage: _formatError(error),
      );
    }
  }

  Future<void> stopScan() async {
    _scanGeneration += 1;
    _isScanActive = false;
    state = state.copyWith(isScanning: false, clearErrorMessage: true);
    try {
      await _repository.stopScan();
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  Future<void> _stopScanSafely() async {
    try {
      await _repository.stopScan();
    } catch (_) {}
  }

  Future<void> connect(MidiDeviceInfo device) async {
    if (state.connectingDeviceId != null) {
      return;
    }
    state = state.copyWith(
      connectingDeviceId: device.id,
      clearErrorMessage: true,
    );
    try {
      await _repository.connect(device);
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(clearConnectingDeviceId: true);
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        clearConnectingDeviceId: true,
        errorMessage: _formatError(error),
      );
    }
  }

  Future<void> disconnect(MidiDeviceInfo device) async {
    state = state.copyWith(clearErrorMessage: true);
    try {
      await _repository.disconnect(device);
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  void dismissError() {
    state = state.copyWith(clearErrorMessage: true);
  }

  String _formatError(Object error) {
    if (error is MidiOperationException) {
      return error.message;
    }
    return error.toString();
  }
}

final midiScanControllerProvider =
    NotifierProvider<MidiScanController, MidiScanState>(MidiScanController.new);
