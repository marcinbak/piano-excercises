import 'dart:async';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';
import 'package:piano_exercises/features/midi/data/flutter_midi_mapper.dart';
import 'package:piano_exercises/features/midi/domain/midi_device_info.dart';
import 'package:piano_exercises/features/midi/domain/midi_note_event.dart';
import 'package:piano_exercises/features/midi/domain/midi_repository.dart';

/// [MidiRepository] adapter backed by `flutter_midi_command` and `flutter_midi_command_ble`.
class FlutterMidiRepository implements MidiRepository {
  FlutterMidiRepository({MidiCommand? midiCommand})
    : _midiCommand =
          midiCommand ??
          MidiCommand(bleTransport: UniversalBleMidiTransport()) {
    _subscribeStreams();
  }

  final MidiCommand _midiCommand;
  final Map<String, MidiDevice> _devicesById = <String, MidiDevice>{};
  final StreamController<List<MidiDeviceInfo>> _devicesController =
      StreamController<List<MidiDeviceInfo>>.broadcast();
  final StreamController<MidiNoteEvent> _noteEventsController =
      StreamController<MidiNoteEvent>.broadcast();
  final StreamController<MidiBluetoothStatus> _bluetoothStateController =
      StreamController<MidiBluetoothStatus>.broadcast();

  StreamSubscription<MidiSetupChange>? _setupSubscription;
  StreamSubscription<BluetoothState>? _bluetoothSubscription;
  StreamSubscription<MidiDataReceivedEvent>? _dataSubscription;

  MidiBluetoothStatus _currentBluetoothStatus = MidiBluetoothStatus.unknown;
  bool _isDisposed = false;

  @override
  Stream<List<MidiDeviceInfo>> get devicesStream => _devicesController.stream;

  @override
  Stream<MidiNoteEvent> get noteEventsStream => _noteEventsController.stream;

  @override
  Stream<MidiBluetoothStatus> get bluetoothStateStream =>
      _bluetoothStateController.stream;

  @override
  MidiBluetoothStatus get currentBluetoothStatus => _currentBluetoothStatus;

  void _subscribeStreams() {
    _bluetoothSubscription = _midiCommand.onBluetoothStateChanged.listen(
      (state) => _updateBluetoothStatus(mapBluetoothState(state)),
      onError: (_) {},
    );
    _setupSubscription = _midiCommand.onMidiSetupChanged?.listen(
      (_) => unawaited(_refreshDevicesSnapshot()),
      onError: (_) {},
    );
    _dataSubscription = _midiCommand.onMidiDataReceived?.listen(
      _handleMidiDataEvent,
      onError: (_) {},
    );
  }

  @override
  Future<List<MidiDeviceInfo>> currentDevices() async {
    if (_isDisposed) {
      return const <MidiDeviceInfo>[];
    }
    try {
      final rawDevices = await _midiCommand.devices ?? const <MidiDevice>[];
      _devicesById
        ..clear()
        ..addEntries(
          rawDevices.map(
            (device) => MapEntry<String, MidiDevice>(device.id, device),
          ),
        );
      return rawDevices.map(mapMidiDevice).toList(growable: false);
    } catch (error) {
      throw MidiOperationException(
        'Failed to read available MIDI devices: $error',
        cause: error,
      );
    }
  }

  @override
  Future<void> startScan() async {
    _ensureNotDisposed();
    try {
      await _midiCommand.startBluetooth();
      // MidiCommand updates bluetoothState on a microtask after startBluetooth().
      if (_midiCommand.bluetoothState == BluetoothState.unknown) {
        try {
          await _midiCommand.waitUntilBluetoothIsInitialized().timeout(
            const Duration(seconds: 2),
          );
        } on TimeoutException {
          // Inspect the current adapter status below rather than hanging indefinitely.
        }
      }

      final status = mapBluetoothState(_midiCommand.bluetoothState);
      _updateBluetoothStatus(status);
      _ensureBluetoothReadyForScan(status);

      await _midiCommand.startScanningForBluetoothDevices();
      await _refreshDevicesSnapshot();
    } on MidiOperationException {
      rethrow;
    } catch (error) {
      throw MidiOperationException(
        'Failed to start BLE-MIDI scan: $error',
        cause: error,
      );
    }
  }

  @override
  Future<void> stopScan() async {
    if (_isDisposed) {
      return;
    }
    try {
      _midiCommand.stopScanningForBluetoothDevices();
    } catch (error) {
      throw MidiOperationException(
        'Failed to stop BLE-MIDI scan: $error',
        cause: error,
      );
    }
  }

  @override
  Future<void> connect(MidiDeviceInfo device) async {
    _ensureNotDisposed();
    final target = await _resolveDevice(device);
    try {
      await _midiCommand.connectToDevice(target);
    } on MidiConnectionTimeoutException catch (error) {
      throw MidiOperationException(
        'Connection to "${device.name}" timed out.',
        cause: error,
      );
    } on MidiPairingRejectedException catch (error) {
      throw MidiOperationException(
        'Bluetooth pairing was rejected or did not complete for "${device.name}".',
        cause: error,
      );
    } on MidiConnectionException catch (error) {
      throw MidiOperationException(error.message, cause: error);
    } catch (error) {
      throw MidiOperationException(
        'Failed to connect to "${device.name}": $error',
        cause: error,
      );
    } finally {
      await _refreshDevicesSnapshot();
    }
  }

  @override
  Future<void> disconnect(MidiDeviceInfo device) async {
    _ensureNotDisposed();
    final target = await _resolveDevice(device);
    try {
      _midiCommand.disconnectDevice(target);
      await _refreshDevicesSnapshot();
    } catch (error) {
      throw MidiOperationException(
        'Failed to disconnect "${device.name}": $error',
        cause: error,
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _setupSubscription?.cancel();
    await _bluetoothSubscription?.cancel();
    await _dataSubscription?.cancel();
    _setupSubscription = null;
    _bluetoothSubscription = null;
    _dataSubscription = null;
    _devicesById.clear();
    await _devicesController.close();
    await _noteEventsController.close();
    await _bluetoothStateController.close();
    _midiCommand.dispose();
  }

  Future<MidiDevice> _resolveDevice(MidiDeviceInfo info) async {
    final cached = _devicesById[info.id];
    if (cached != null) {
      return cached;
    }
    await currentDevices();
    final refreshed = _devicesById[info.id];
    if (refreshed != null) {
      return refreshed;
    }
    throw MidiOperationException(
      'Device "${info.name}" is no longer available. Scan again to rediscover it.',
    );
  }

  Future<void> _refreshDevicesSnapshot() async {
    if (_isDisposed) {
      return;
    }
    try {
      final devices = await currentDevices();
      if (!_isDisposed && !_devicesController.isClosed) {
        _devicesController.add(devices);
      }
    } on MidiOperationException {
      // Passive setup-refresh errors should not crash background listeners.
    }
  }

  void _handleMidiDataEvent(MidiDataReceivedEvent event) {
    if (_isDisposed || _noteEventsController.isClosed) {
      return;
    }
    final noteEvent = mapMidiDataEvent(event);
    if (noteEvent != null) {
      _noteEventsController.add(noteEvent);
    }
  }

  void _updateBluetoothStatus(MidiBluetoothStatus status) {
    if (_isDisposed || _currentBluetoothStatus == status) {
      return;
    }
    _currentBluetoothStatus = status;
    if (status != MidiBluetoothStatus.poweredOn &&
        status != MidiBluetoothStatus.unknown) {
      // Reset the plugin's internal _isScanning flag when Bluetooth is no longer active.
      try {
        _midiCommand.stopScanningForBluetoothDevices();
      } catch (_) {}
    }
    if (!_bluetoothStateController.isClosed) {
      _bluetoothStateController.add(status);
    }
  }

  void _ensureBluetoothReadyForScan(MidiBluetoothStatus status) {
    switch (status) {
      case MidiBluetoothStatus.poweredOn:
        return;
      case MidiBluetoothStatus.poweredOff:
        throw const MidiOperationException(
          'Bluetooth is turned off. Enable Bluetooth to scan for MIDI devices.',
        );
      case MidiBluetoothStatus.unauthorized:
        throw const MidiOperationException(
          'Bluetooth permission is denied. Allow Bluetooth access in system settings.',
        );
      case MidiBluetoothStatus.unsupported:
        throw const MidiOperationException(
          'Bluetooth Low Energy is not supported on this device.',
        );
      case MidiBluetoothStatus.unknown:
        throw const MidiOperationException(
          'Bluetooth is still initializing. Please try scanning again.',
        );
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw const MidiOperationException('MIDI repository has been disposed.');
    }
  }
}
