import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/app/app.dart';
import 'package:piano_exercises/features/midi/midi.dart';

class _StubMidiRepository implements MidiRepository {
  @override
  Stream<List<MidiDeviceInfo>> get devicesStream =>
      const Stream<List<MidiDeviceInfo>>.empty();

  @override
  Stream<MidiNoteEvent> get noteEventsStream =>
      const Stream<MidiNoteEvent>.empty();

  @override
  Stream<MidiBluetoothStatus> get bluetoothStateStream =>
      const Stream<MidiBluetoothStatus>.empty();

  @override
  MidiBluetoothStatus get currentBluetoothStatus => MidiBluetoothStatus.unknown;

  @override
  Future<List<MidiDeviceInfo>> currentDevices() async =>
      const <MidiDeviceInfo>[];

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(MidiDeviceInfo device) async {}

  @override
  Future<void> disconnect(MidiDeviceInfo device) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('PianoExercisesApp renders BLE-MIDI Spike screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          midiRepositoryProvider.overrideWithValue(_StubMidiRepository()),
        ],
        child: const PianoExercisesApp(),
      ),
    );
    await tester.pump();

    expect(find.text('BLE-MIDI Spike'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });
}
