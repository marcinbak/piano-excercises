import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/midi/domain/midi_chord_coalescer.dart';
import 'package:piano_exercises/features/midi/domain/midi_device_info.dart';
import 'package:piano_exercises/features/midi/domain/midi_note_event.dart';
import 'package:piano_exercises/shared/music/music.dart';

MidiNoteEvent _noteEvent({
  required int noteNumber,
  required bool isNoteOn,
  String deviceId = 'ble-1',
  int timestampMs = 0,
}) {
  return MidiNoteEvent.fromChannelMessage(
    noteNumber: noteNumber,
    velocity: isNoteOn ? 96 : 0,
    isNoteOn: isNoteOn,
    channel: 0,
    deviceId: deviceId,
    timestampMs: timestampMs,
  );
}

void main() {
  testWidgets('coalesces Note On bursts within 35ms window into one flush', (
    tester,
  ) async {
    var nowMs = 100;
    final flushes = <MidiChordFlush>[];
    final coalescer = MidiChordCoalescer(
      chordWindow: const Duration(milliseconds: 35),
      clockMs: () => nowMs,
      onFlush: flushes.add,
    );
    addTearDown(coalescer.dispose);

    coalescer.onNoteEvent(_noteEvent(noteNumber: 60, isNoteOn: true));
    await tester.pump(const Duration(milliseconds: 15));
    nowMs = 115;
    coalescer.onNoteEvent(_noteEvent(noteNumber: 64, isNoteOn: true));
    await tester.pump(const Duration(milliseconds: 19));
    expect(flushes, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(flushes, hasLength(1));
    expect(flushes.single.startedAtMs, 100);
    expect(flushes.single.batchNotes, <MidiNote>{
      const MidiNote(60),
      const MidiNote(64),
    });
    expect(flushes.single.combinedNotes, <MidiNote>{
      const MidiNote(60),
      const MidiNote(64),
    });
  });

  testWidgets(
    'staccato Note Off within window keeps note in batchNotes while dropping from later combinedNotes',
    (tester) async {
      var nowMs = 200;
      final flushes = <MidiChordFlush>[];
      final coalescer = MidiChordCoalescer(
        chordWindow: const Duration(milliseconds: 35),
        clockMs: () => nowMs,
        onFlush: flushes.add,
      );
      addTearDown(coalescer.dispose);

      coalescer.onNoteEvent(_noteEvent(noteNumber: 60, isNoteOn: true));
      await tester.pump(const Duration(milliseconds: 8));
      coalescer.onNoteEvent(_noteEvent(noteNumber: 60, isNoteOn: false));
      await tester.pump(const Duration(milliseconds: 5));
      coalescer.onNoteEvent(_noteEvent(noteNumber: 64, isNoteOn: true));
      await tester.pump(const Duration(milliseconds: 22));

      expect(flushes, hasLength(1));
      expect(flushes.first.batchNotes, <MidiNote>{
        const MidiNote(60),
        const MidiNote(64),
      });

      // Only E4 (64) remained held after window 1; pressing G4 (67) later omits released C4.
      nowMs = 300;
      coalescer.onNoteEvent(_noteEvent(noteNumber: 67, isNoteOn: true));
      await tester.pump(const Duration(milliseconds: 35));

      expect(flushes, hasLength(2));
      expect(flushes.last.combinedNotes, <MidiNote>{
        const MidiNote(64),
        const MidiNote(67),
      });
    },
  );

  testWidgets(
    'accumulates held notes across windows in combinedNotes until resetActivePrompt',
    (tester) async {
      var nowMs = 10;
      final flushes = <MidiChordFlush>[];
      final coalescer = MidiChordCoalescer(
        chordWindow: const Duration(milliseconds: 35),
        clockMs: () => nowMs,
        onFlush: flushes.add,
      );
      addTearDown(coalescer.dispose);

      coalescer.onNoteEvent(_noteEvent(noteNumber: 60, isNoteOn: true));
      await tester.pump(const Duration(milliseconds: 35));
      expect(flushes.last.combinedNotes, <MidiNote>{const MidiNote(60)});

      // Hold C4 across a rolled second note E4 outside the initial 35ms window.
      nowMs = 120;
      coalescer.onNoteEvent(_noteEvent(noteNumber: 64, isNoteOn: true));
      await tester.pump(const Duration(milliseconds: 35));
      expect(flushes.last.combinedNotes, <MidiNote>{
        const MidiNote(60),
        const MidiNote(64),
      });

      // Completing a prompt/slice carries still-held keys out of the next prompt.
      coalescer.resetActivePrompt();
      nowMs = 240;
      coalescer.onNoteEvent(_noteEvent(noteNumber: 67, isNoteOn: true));
      await tester.pump(const Duration(milliseconds: 35));
      expect(flushes.last.combinedNotes, <MidiNote>{const MidiNote(67)});

      // Releasing and re-striking carried-over C4 evaluates it on the new prompt.
      coalescer.onNoteEvent(_noteEvent(noteNumber: 60, isNoteOn: false));
      nowMs = 360;
      coalescer.onNoteEvent(_noteEvent(noteNumber: 60, isNoteOn: true));
      await tester.pump(const Duration(milliseconds: 35));
      expect(flushes.last.combinedNotes, <MidiNote>{
        const MidiNote(60),
        const MidiNote(67),
      });
    },
  );

  testWidgets(
    'setPaused cancels pending batches and carries keys held during pause across resume',
    (tester) async {
      var nowMs = 50;
      final flushes = <MidiChordFlush>[];
      final coalescer = MidiChordCoalescer(
        chordWindow: const Duration(milliseconds: 35),
        clockMs: () => nowMs,
        onFlush: flushes.add,
      );
      addTearDown(coalescer.dispose);

      coalescer.onNoteEvent(_noteEvent(noteNumber: 64, isNoteOn: true));
      coalescer.setPaused(true);
      expect(coalescer.isPaused, isTrue);
      await tester.pump(const Duration(milliseconds: 50));
      expect(flushes, isEmpty);

      coalescer.onNoteEvent(_noteEvent(noteNumber: 62, isNoteOn: true));
      coalescer.onNoteEvent(_noteEvent(noteNumber: 62, isNoteOn: false));
      coalescer.onNoteEvent(_noteEvent(noteNumber: 67, isNoteOn: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(flushes, isEmpty);

      coalescer.setPaused(false);
      expect(coalescer.isPaused, isFalse);

      nowMs = 300;
      coalescer.onNoteEvent(_noteEvent(noteNumber: 60, isNoteOn: true));
      await tester.pump(const Duration(milliseconds: 35));
      expect(flushes, hasLength(1));
      expect(flushes.single.batchNotes, <MidiNote>{const MidiNote(60)});
      expect(flushes.single.combinedNotes, <MidiNote>{const MidiNote(60)});
    },
  );

  testWidgets(
    'syncConnectedDevices clears held notes only when not held on another connected device',
    (tester) async {
      final flushes = <MidiChordFlush>[];
      final coalescer = MidiChordCoalescer(
        chordWindow: Duration.zero,
        clockMs: () => 100,
        onFlush: flushes.add,
      );
      addTearDown(coalescer.dispose);

      const dev1 = MidiDeviceInfo(
        id: 'dev-1',
        name: 'Piano 1',
        typeLabel: 'BLE',
        isConnected: true,
      );
      const dev2 = MidiDeviceInfo(
        id: 'dev-2',
        name: 'Piano 2',
        typeLabel: 'BLE',
        isConnected: true,
      );

      coalescer.syncConnectedDevices(const <MidiDeviceInfo>[dev1, dev2]);
      coalescer.onNoteEvent(
        _noteEvent(noteNumber: 60, isNoteOn: true, deviceId: 'dev-1'),
      );
      coalescer.onNoteEvent(
        _noteEvent(noteNumber: 64, isNoteOn: true, deviceId: 'dev-1'),
      );
      coalescer.onNoteEvent(
        _noteEvent(noteNumber: 64, isNoteOn: true, deviceId: 'dev-2'),
      );

      // Disconnect dev-1: C4 (60) releases, E4 (64) remains held via dev-2.
      coalescer.syncConnectedDevices(<MidiDeviceInfo>[
        dev1.copyWith(isConnected: false),
        dev2,
      ]);

      coalescer.onNoteEvent(
        _noteEvent(noteNumber: 67, isNoteOn: true, deviceId: 'dev-2'),
      );
      expect(flushes.last.combinedNotes, <MidiNote>{
        const MidiNote(64),
        const MidiNote(67),
      });
    },
  );

  testWidgets('dispose cancels pending timer without invoking onFlush', (
    tester,
  ) async {
    final flushes = <MidiChordFlush>[];
    final coalescer = MidiChordCoalescer(
      chordWindow: const Duration(milliseconds: 35),
      clockMs: () => 0,
      onFlush: flushes.add,
    );

    coalescer.onNoteEvent(_noteEvent(noteNumber: 60, isNoteOn: true));
    coalescer.dispose();
    await tester.pump(const Duration(milliseconds: 50));

    expect(flushes, isEmpty);
  });
}
