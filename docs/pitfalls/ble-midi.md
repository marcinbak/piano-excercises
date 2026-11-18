# BLE-MIDI Pitfalls

## Stuck scan flag after Bluetooth power-off

- **Symptom:** Subsequent BLE-MIDI scans fail to start or stay blocked after Bluetooth powers off or loses permission mid-scan.
- **Root cause:** `flutter_midi_command_ble` keeps its internal `_isScanning` flag `true` when Bluetooth powers off without an explicit stop call.
- **Fix:** Call `stopScanningForBluetoothDevices()` when Bluetooth state leaves `poweredOn`/`unknown` (see [flutter_midi_repository.dart](../../lib/features/midi/data/flutter_midi_repository.dart)).

## Unbounded Bluetooth initialization wait

- **Symptom:** `startScan()` hangs indefinitely if the host adapter never completes initialization.
- **Root cause:** `MidiCommand.waitUntilBluetoothIsInitialized()` has no built-in timeout after `startBluetooth()`.
- **Fix:** Bound `waitUntilBluetoothIsInitialized()` with a 2-second timeout and check `bluetoothState` explicitly before calling `startScanningForBluetoothDevices()`.
