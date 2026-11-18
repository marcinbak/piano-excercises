import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/drill/drill.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/progression/progression.dart';
import 'package:piano_exercises/shared/music/music.dart';

class _FakeMidiRepository implements MidiRepository {
  final StreamController<List<MidiDeviceInfo>> devicesController =
      StreamController<List<MidiDeviceInfo>>.broadcast();
  final StreamController<MidiNoteEvent> noteEventsController =
      StreamController<MidiNoteEvent>.broadcast();
  final StreamController<MidiBluetoothStatus> bluetoothController =
      StreamController<MidiBluetoothStatus>.broadcast();

  List<MidiDeviceInfo> initialDevices = const <MidiDeviceInfo>[];

  @override
  Stream<List<MidiDeviceInfo>> get devicesStream => devicesController.stream;

  @override
  Stream<MidiNoteEvent> get noteEventsStream => noteEventsController.stream;

  @override
  Stream<MidiBluetoothStatus> get bluetoothStateStream =>
      bluetoothController.stream;

  @override
  MidiBluetoothStatus get currentBluetoothStatus =>
      MidiBluetoothStatus.poweredOn;

  @override
  Future<List<MidiDeviceInfo>> currentDevices() async => initialDevices;

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(MidiDeviceInfo device) async {}

  @override
  Future<void> disconnect(MidiDeviceInfo device) async {}

  @override
  Future<void> dispose() async {
    await devicesController.close();
    await noteEventsController.close();
    await bluetoothController.close();
  }
}

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
  testWidgets(
    'clean single NoteOn advances prompt, tracks streak, and unlocks Stage 2 on mastery',
    (tester) async {
      final repository = _FakeMidiRepository();
      var nowMs = 1000;
      final container = ProviderContainer(
        overrides: [
          midiRepositoryProvider.overrideWithValue(repository),
          drillRandomIntProvider.overrideWithValue((_) => 0),
          drillClockMsProvider.overrideWithValue(() => nowMs),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      final drillSub = container.listen(drillControllerProvider, (_, _) {});
      final progSub = container.listen(
        progressionControllerProvider,
        (_, _) {},
      );
      addTearDown(drillSub.close);
      addTearDown(progSub.close);

      final firstTarget = drillSub.read().targetNote;
      expect(
        firstTarget,
        const StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble),
      );

      for (var i = 0; i < 10; i += 1) {
        nowMs += 150;
        repository.noteEventsController.add(
          _noteEvent(noteNumber: 60, isNoteOn: true),
        );
        await tester.pump();
        nowMs += 35;
        await tester.pump(const Duration(milliseconds: 35));
        repository.noteEventsController.add(
          _noteEvent(noteNumber: 60, isNoteOn: false),
        );
        await tester.pump();

        final progression = progSub.read();
        final stats = progression.statsFor(StageId.stage1);
        expect(stats.attempts, i + 1);
        expect(stats.currentStreak, i + 1);
        expect(drillSub.read().lastResult?.status, DrillFeedbackStatus.correct);
        expect(drillSub.read().lastResult?.reactionTimeMs, 150);
      }

      expect(progSub.read().highestUnlockedStageId, StageId.stage2);
      expect(progSub.read().isUnlocked(StageId.stage2), isTrue);
    },
  );

  testWidgets(
    'wrong single NoteOn resets streak, holds target, and clearing afterwards keeps streak at 0',
    (tester) async {
      final repository = _FakeMidiRepository();
      var nowMs = 500;
      final container = ProviderContainer(
        overrides: [
          midiRepositoryProvider.overrideWithValue(repository),
          drillRandomIntProvider.overrideWithValue((_) => 0),
          drillClockMsProvider.overrideWithValue(() => nowMs),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      final drillSub = container.listen(drillControllerProvider, (_, _) {});
      final progSub = container.listen(
        progressionControllerProvider,
        (_, _) {},
      );
      addTearDown(drillSub.close);
      addTearDown(progSub.close);

      // Build streak = 1 first.
      nowMs += 100;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 60, isNoteOn: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 60, isNoteOn: false),
      );
      await tester.pump();
      expect(progSub.read().statsFor(StageId.stage1).currentStreak, 1);

      final heldTarget = drillSub.read().targetNote;

      // Play wrong note D4 (62).
      nowMs += 200;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 62, isNoteOn: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 62, isNoteOn: false),
      );
      await tester.pump();

      expect(drillSub.read().targetNote, heldTarget);
      expect(
        drillSub.read().lastResult?.status,
        DrillFeedbackStatus.wrongSingleNote,
      );
      expect(drillSub.read().wrongPlayedNotes, const <StaffNote>[
        StaffNote(note: DiatonicNote.d, octave: 4, clef: Clef.treble),
      ]);
      expect(progSub.read().statsFor(StageId.stage1).currentStreak, 0);
      expect(progSub.read().statsFor(StageId.stage1).attempts, 2);

      // Now clear the held prompt by playing C4 (60): prompt advances, streak stays 0!
      nowMs += 250;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 60, isNoteOn: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));

      expect(drillSub.read().targetNote, isNot(heldTarget));
      expect(drillSub.read().wrongPlayedNotes, isEmpty);
      expect(drillSub.read().lastResult?.status, DrillFeedbackStatus.correct);
      expect(drillSub.read().lastResult?.wasCleanFirstTry, isFalse);
      expect(progSub.read().statsFor(StageId.stage1).currentStreak, 0);
      expect(progSub.read().statsFor(StageId.stage1).attempts, 2);
    },
  );

  testWidgets(
    'simultaneous chord within 35ms (forward and reversed with staccato NoteOff) evaluates once as multipleNotesPlayed',
    (tester) async {
      final repository = _FakeMidiRepository();
      var nowMs = 0;
      final container = ProviderContainer(
        overrides: [
          midiRepositoryProvider.overrideWithValue(repository),
          drillRandomIntProvider.overrideWithValue((_) => 0),
          drillClockMsProvider.overrideWithValue(() => nowMs),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      final drillSub = container.listen(drillControllerProvider, (_, _) {});
      final progSub = container.listen(
        progressionControllerProvider,
        (_, _) {},
      );
      addTearDown(drillSub.close);
      addTearDown(progSub.close);

      final target = drillSub.read().targetNote;

      // Forward order: target C4 (60) at 0ms + E4 (64) at 10ms.
      nowMs = 100;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 60, isNoteOn: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      nowMs = 110;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 64, isNoteOn: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));

      expect(drillSub.read().targetNote, target);
      expect(
        drillSub.read().lastResult?.status,
        DrillFeedbackStatus.multipleNotesPlayed,
      );
      expect(drillSub.read().wrongPlayedNotes.length, 2);
      expect(progSub.read().statsFor(StageId.stage1).attempts, 1);
      expect(progSub.read().statsFor(StageId.stage1).currentStreak, 0);

      // Release both keys.
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 60, isNoteOn: false),
      );
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 64, isNoteOn: false),
      );
      await tester.pump();

      // Reversed order with staccato NoteOff(E4) at 8ms before C4 arrives at 10ms!
      nowMs = 300;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 64, isNoteOn: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 8));
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 64, isNoteOn: false),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2));
      nowMs = 310;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 60, isNoteOn: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));

      expect(drillSub.read().targetNote, target);
      expect(
        drillSub.read().lastResult?.status,
        DrillFeedbackStatus.multipleNotesPlayed,
      );
      expect(progSub.read().statsFor(StageId.stage1).attempts, 2);
      expect(progSub.read().statsFor(StageId.stage1).currentStreak, 0);
    },
  );

  testWidgets(
    'held-key overlap on same prompt evaluates as multipleNotesPlayed',
    (tester) async {
      final repository = _FakeMidiRepository();
      var nowMs = 0;
      final container = ProviderContainer(
        overrides: [
          midiRepositoryProvider.overrideWithValue(repository),
          drillRandomIntProvider.overrideWithValue((_) => 0),
          drillClockMsProvider.overrideWithValue(() => nowMs),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      final drillSub = container.listen(drillControllerProvider, (_, _) {});
      addTearDown(drillSub.close);

      // E4 pressed at 0ms, flushed at 35ms as wrong, and KEPT HELD.
      nowMs = 50;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 64, isNoteOn: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      expect(
        drillSub.read().lastResult?.status,
        DrillFeedbackStatus.wrongSingleNote,
      );

      // C4 pressed at 200ms while E4 is still held down.
      await tester.pump(const Duration(milliseconds: 165));
      nowMs = 250;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 60, isNoteOn: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));

      expect(
        drillSub.read().lastResult?.status,
        DrillFeedbackStatus.multipleNotesPlayed,
      );
      expect(drillSub.read().lastResult?.playedNotes, const <MidiNote>[
        MidiNote(60),
        MidiNote(64),
      ]);
    },
  );

  testWidgets(
    'legato carryover across prompt boundary does not misclassify next clean single note as chord',
    (tester) async {
      final repository = _FakeMidiRepository();
      var nowMs = 0;
      final container = ProviderContainer(
        overrides: [
          midiRepositoryProvider.overrideWithValue(repository),
          drillRandomIntProvider.overrideWithValue((_) => 0),
          drillClockMsProvider.overrideWithValue(() => nowMs),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      // Jump to Stage 4 so Stage has C4, C3, C5, C2, C6, F3, G4.
      container
          .read(progressionControllerProvider.notifier)
          .selectStage(StageId.stage4);
      final drillSub = container.listen(drillControllerProvider, (_, _) {});
      addTearDown(drillSub.close);

      // First prompt with nextInt == 0 is C4 treble. Solve and KEEP C4 HELD.
      expect(drillSub.read().targetNote.midiNote, const MidiNote(60));
      nowMs = 100;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 60, isNoteOn: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));

      expect(drillSub.read().lastResult?.status, DrillFeedbackStatus.correct);
      final nextTarget = drillSub.read().targetNote;
      expect(
        nextTarget,
        isNot(
          const StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble),
        ),
      );

      // Press nextTarget while C4 (60) from prompt 1 is STILL HELD.
      nowMs = 250;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: nextTarget.midiNote.number, isNoteOn: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));

      expect(drillSub.read().lastResult?.status, DrillFeedbackStatus.correct);
      expect(drillSub.read().lastResult?.wasCleanFirstTry, isTrue);
      expect(drillSub.read().lastResult?.playedNotes, <MidiNote>[
        nextTarget.midiNote,
      ]);
    },
  );

  testWidgets(
    'device disconnect clears stuck held keys for disconnected deviceId',
    (tester) async {
      const connected = MidiDeviceInfo(
        id: 'ble-1',
        name: 'FP-30X',
        typeLabel: 'BLE',
        isConnected: true,
      );
      const disconnected = MidiDeviceInfo(
        id: 'ble-1',
        name: 'FP-30X',
        typeLabel: 'BLE',
        isConnected: false,
      );
      final repository = _FakeMidiRepository()
        ..initialDevices = const <MidiDeviceInfo>[connected];
      var nowMs = 0;
      final container = ProviderContainer(
        overrides: [
          midiRepositoryProvider.overrideWithValue(repository),
          drillRandomIntProvider.overrideWithValue((_) => 0),
          drillClockMsProvider.overrideWithValue(() => nowMs),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      final drillSub = container.listen(drillControllerProvider, (_, _) {});
      addTearDown(drillSub.close);
      await tester.pump();

      // Hold wrong key E4 on ble-1 without releasing NoteOff.
      nowMs = 100;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 64, isNoteOn: true, deviceId: 'ble-1'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      expect(
        drillSub.read().lastResult?.status,
        DrillFeedbackStatus.wrongSingleNote,
      );

      // Disconnect ble-1 -> stuck E4 is cleared!
      repository.devicesController.add(const <MidiDeviceInfo>[disconnected]);
      await tester.pump();

      // Playing C4 (60) now evaluates as single correct note, NOT chord {60, 64}!
      nowMs = 300;
      repository.noteEventsController.add(
        _noteEvent(noteNumber: 60, isNoteOn: true, deviceId: 'ble-1'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));

      expect(drillSub.read().lastResult?.status, DrillFeedbackStatus.correct);
      expect(drillSub.read().lastResult?.playedNotes, const <MidiNote>[
        MidiNote(60),
      ]);
    },
  );

  testWidgets('stage change and resetSession reset pending attempts cleanly', (
    tester,
  ) async {
    final repository = _FakeMidiRepository();
    var nowMs = 0;
    final container = ProviderContainer(
      overrides: [
        midiRepositoryProvider.overrideWithValue(repository),
        drillRandomIntProvider.overrideWithValue((_) => 0),
        drillClockMsProvider.overrideWithValue(() => nowMs),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await repository.dispose();
    });

    final drillSub = container.listen(drillControllerProvider, (_, _) {});
    final progSub = container.listen(progressionControllerProvider, (_, _) {});
    addTearDown(drillSub.close);
    addTearDown(progSub.close);

    // Start a pending chord timer, then switch stage before 35ms elapses.
    repository.noteEventsController.add(
      _noteEvent(noteNumber: 64, isNoteOn: true),
    );
    await tester.pump();
    container
        .read(progressionControllerProvider.notifier)
        .selectStage(StageId.stage3);
    await tester.pump(const Duration(milliseconds: 50));

    // Pending mistake from Stage 1 must not leak into Stage 3.
    expect(progSub.read().statsFor(StageId.stage1).attempts, 0);
    expect(progSub.read().statsFor(StageId.stage3).attempts, 0);
    expect(drillSub.read().lastResult, isNull);

    // Record a hit on Stage 3, then resetSession back to Stage 1.
    nowMs = 200;
    final stage3Target = drillSub.read().targetNote;
    repository.noteEventsController.add(
      _noteEvent(noteNumber: stage3Target.midiNote.number, isNoteOn: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 35));
    expect(progSub.read().statsFor(StageId.stage3).attempts, 1);

    container.read(drillControllerProvider.notifier).resetSession();
    expect(progSub.read().activeStageId, StageId.stage1);
    expect(progSub.read().statsByStage, isEmpty);
    expect(drillSub.read().lastResult, isNull);
  });
}
