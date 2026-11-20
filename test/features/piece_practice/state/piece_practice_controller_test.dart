import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/piece_practice/piece_practice.dart';
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

MidiNoteEvent _noteOn(int number, {String deviceId = 'ble-1'}) =>
    MidiNoteEvent.fromChannelMessage(
      noteNumber: number,
      velocity: 96,
      isNoteOn: true,
      channel: 0,
      deviceId: deviceId,
      timestampMs: 0,
    );

MidiNoteEvent _noteOff(int number, {String deviceId = 'ble-1'}) =>
    MidiNoteEvent.fromChannelMessage(
      noteNumber: number,
      velocity: 0,
      isNoteOn: false,
      channel: 0,
      deviceId: deviceId,
      timestampMs: 0,
    );

ScoreNote _scoreNote(
  DiatonicNote pitch,
  int octave,
  Clef clef, {
  TieType tie = TieType.none,
}) {
  return ScoreNote(
    staffNote: StaffNote(note: pitch, octave: octave, clef: clef),
    duration: DurationValue(base: NoteBaseDuration.quarter),
    tie: tie,
  );
}

Score _buildTestScore() {
  return Score(
    title: 'Wait Mode Fixture',
    scale: Scale.fromKeySignature(KeySignature.cMajor),
    timeSignature: TimeSignature.common,
    measures: <ScoreMeasure>[
      // M0: slice 0 is rest-only; slice 1 is C4 + E4 + C3
      ScoreMeasure(
        measureNumber: 1,
        slices: <ScoreSlice>[
          ScoreSlice(
            sliceIndex: 0,
            measureNumber: 1,
            beatOffset: const RationalBeats.zero(),
            beatDuration: RationalBeats(1),
            trebleRest: RestEvent(
              clef: Clef.treble,
              duration: DurationValue(base: NoteBaseDuration.quarter),
            ),
            bassRest: RestEvent(
              clef: Clef.bass,
              duration: DurationValue(base: NoteBaseDuration.quarter),
            ),
          ),
          ScoreSlice(
            sliceIndex: 1,
            measureNumber: 1,
            beatOffset: RationalBeats(1),
            beatDuration: RationalBeats(1),
            trebleNotes: <ScoreNote>[
              _scoreNote(DiatonicNote.c, 4, Clef.treble, tie: TieType.start),
              _scoreNote(DiatonicNote.e, 4, Clef.treble),
            ],
            bassNotes: <ScoreNote>[_scoreNote(DiatonicNote.c, 3, Clef.bass)],
          ),
        ],
      ),
      // M1: slice 2 is tie-stop C4 (no attack) + treble G4; slice 3 is bass F3
      ScoreMeasure(
        measureNumber: 2,
        slices: <ScoreSlice>[
          ScoreSlice(
            sliceIndex: 2,
            measureNumber: 2,
            beatOffset: const RationalBeats.zero(),
            beatDuration: RationalBeats(1),
            trebleNotes: <ScoreNote>[
              _scoreNote(DiatonicNote.c, 4, Clef.treble, tie: TieType.stop),
              _scoreNote(DiatonicNote.g, 4, Clef.treble),
            ],
          ),
          ScoreSlice(
            sliceIndex: 3,
            measureNumber: 2,
            beatOffset: RationalBeats(1),
            beatDuration: RationalBeats(1),
            bassNotes: <ScoreNote>[_scoreNote(DiatonicNote.f, 3, Clef.bass)],
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets(
    'skips leading rests, rolls held chords, rejects staccato pecking, and completes',
    (tester) async {
      final repo = _FakeMidiRepository();
      final score = _buildTestScore();
      final key = PracticeSessionKey(variantId: 'v1', score: score);
      final container = ProviderContainer(
        overrides: [midiRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(() async {
        container.dispose();
        await repo.dispose();
      });

      final sub = container.listen(
        piecePracticeControllerProvider(key),
        (_, _) {},
      );
      addTearDown(sub.close);

      // Leading rest slice 0 auto-skips to slice 1.
      expect(sub.read().activeSliceOrdinal, 1);
      expect(sub.read().status, PracticeSessionStatus.active);

      // Sequential staccato pecking (press & release C4) must NOT complete {C4, E4, C3}.
      repo.noteEventsController.add(_noteOn(60));
      await tester.pump(const Duration(milliseconds: 10));
      repo.noteEventsController.add(_noteOff(60));
      await tester.pump(const Duration(milliseconds: 25));
      expect(sub.read().activeSliceOrdinal, 1);
      expect(sub.read().wrongPlayedNotes, isEmpty);

      // Wrong note D4 (62) sets wrongPlayedNotes and holds cursor.
      repo.noteEventsController.add(_noteOn(62));
      await tester.pump(const Duration(milliseconds: 35));
      expect(sub.read().activeSliceOrdinal, 1);
      expect(sub.read().wrongPlayedNotes, const <StaffNote>[
        StaffNote(note: DiatonicNote.d, octave: 4, clef: Clef.treble),
      ]);
      repo.noteEventsController.add(_noteOff(62));
      await tester.pump();

      // Rolled chord across >35ms windows: hold C4 + C3, flush partial (clears red note),
      // then press E4 while holding C4 + C3.
      repo.noteEventsController.add(_noteOn(60));
      repo.noteEventsController.add(_noteOn(48));
      await tester.pump(const Duration(milliseconds: 35));
      expect(sub.read().activeSliceOrdinal, 1);
      expect(sub.read().wrongPlayedNotes, isEmpty);

      await tester.pump(const Duration(milliseconds: 60));
      repo.noteEventsController.add(_noteOn(64));
      await tester.pump(const Duration(milliseconds: 35));

      // Advances to slice 2 while C4 (60), C3 (48), E4 (64) remain held in carryover.
      expect(sub.read().activeSliceOrdinal, 2);
      expect(sub.read().completedSlicesCount, 1);

      // Release C3 and E4; keep C4 held (sustained tie-stop) and play G4 (67) -> completes slice 2.
      repo.noteEventsController.add(_noteOff(48));
      repo.noteEventsController.add(_noteOff(64));
      repo.noteEventsController.add(_noteOn(67));
      await tester.pump(const Duration(milliseconds: 35));
      expect(sub.read().activeSliceOrdinal, 3);
      expect(sub.read().completedSlicesCount, 2);

      // Play F3 (53) -> reaches final completion without advancing off slice 3.
      repo.noteEventsController.add(_noteOn(53));
      await tester.pump(const Duration(milliseconds: 35));
      expect(sub.read().status, PracticeSessionStatus.completed);
      expect(sub.read().activeSliceOrdinal, 3);
      expect(sub.read().completedSlicesCount, 3);

      // Restart returns to first playable slice 1.
      container.read(piecePracticeControllerProvider(key).notifier).restart();
      expect(sub.read().status, PracticeSessionStatus.active);
      expect(sub.read().activeSliceOrdinal, 1);
      expect(sub.read().completedSlicesCount, 0);
    },
  );

  testWidgets(
    'supports MeasureLoopRange wrap/clear, HandMode switching with noPlayableNotes, pause, and disconnect',
    (tester) async {
      const connected = MidiDeviceInfo(
        id: 'ble-1',
        name: 'FP-30X',
        typeLabel: 'BLE',
        isConnected: true,
      );
      final repo = _FakeMidiRepository()
        ..initialDevices = const <MidiDeviceInfo>[connected];
      final score = _buildTestScore();
      final key = PracticeSessionKey(variantId: 'v1', score: score);
      final container = ProviderContainer(
        overrides: [midiRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(() async {
        container.dispose();
        await repo.dispose();
      });

      final sub = container.listen(
        piecePracticeControllerProvider(key),
        (_, _) {},
      );
      addTearDown(sub.close);
      await tester.pump();

      final controller = container.read(
        piecePracticeControllerProvider(key).notifier,
      );

      // Apply loop M2 only (index 1..1) -> cursor jumps into M2 slice 2.
      controller.setLoopRange(
        const MeasureLoopRange(startMeasureIndex: 1, endMeasureIndex: 1),
      );
      expect(sub.read().activeSliceOrdinal, 2);

      // Complete slice 2 (G4 = 67) -> 3, then slice 3 (F3 = 53) -> wraps to slice 2!
      repo.noteEventsController.add(_noteOn(67));
      await tester.pump(const Duration(milliseconds: 35));
      expect(sub.read().activeSliceOrdinal, 3);
      repo.noteEventsController.add(_noteOn(53));
      await tester.pump(const Duration(milliseconds: 35));
      expect(sub.read().status, PracticeSessionStatus.active);
      expect(sub.read().activeSliceOrdinal, 2);

      // Switch to Left Hand while at slice 2 (no bass notes in slice 2) -> snaps to slice 3.
      container.read(practiceHandModeProvider.notifier).setMode(HandMode.left);
      expect(sub.read().activeSliceOrdinal, 3);

      // Loop M1 only in Right Hand -> playable at slice 1; seek outside loop clears loop.
      controller.setLoopRange(
        const MeasureLoopRange(startMeasureIndex: 0, endMeasureIndex: 0),
      );
      expect(sub.read().activeSliceOrdinal, 1);
      controller.seekToSlice(2);
      expect(sub.read().loopRange, isNull);
      expect(sub.read().activeSliceOrdinal, 3);

      // Empty measure loop -> noPlayableNotes; clearing loop recovers.
      final restOnlyScore = Score(
        title: 'Rests',
        scale: Scale.fromKeySignature(KeySignature.cMajor),
        timeSignature: TimeSignature.common,
        measures: <ScoreMeasure>[
          ScoreMeasure(
            measureNumber: 1,
            slices: <ScoreSlice>[
              ScoreSlice(
                sliceIndex: 0,
                measureNumber: 1,
                beatOffset: const RationalBeats.zero(),
                beatDuration: RationalBeats(1),
              ),
            ],
          ),
        ],
      );
      final restKey = PracticeSessionKey(
        variantId: 'rest',
        score: restOnlyScore,
      );
      final restSub = container.listen(
        piecePracticeControllerProvider(restKey),
        (_, _) {},
      );
      addTearDown(restSub.close);
      expect(restSub.read().status, PracticeSessionStatus.noPlayableNotes);
      expect(restSub.read().activeSliceOrdinal, isNull);

      // Pause ignores Note On and clears stuck note on disconnect.
      container.read(practicePausedProvider.notifier).setPaused(true);
      repo.noteEventsController.add(_noteOn(53));
      await tester.pump(const Duration(milliseconds: 35));
      expect(sub.read().completedSlicesCount, 2);

      container.read(practicePausedProvider.notifier).setPaused(false);
      repo.noteEventsController.add(_noteOn(72)); // hold wrong note C5
      await tester.pump(const Duration(milliseconds: 35));
      expect(sub.read().wrongPlayedNotes, hasLength(1));

      // Disconnect clears stuck C5 so F3 passes cleanly.
      repo.devicesController.add(<MidiDeviceInfo>[
        connected.copyWith(isConnected: false),
      ]);
      await tester.pump();
      repo.noteEventsController.add(_noteOn(53));
      await tester.pump(const Duration(milliseconds: 35));
      expect(sub.read().status, PracticeSessionStatus.completed);
    },
  );

  testWidgets(
    'isolates practiceRoutePausedProvider per routeId while still honoring global practicePausedProvider',
    (tester) async {
      final repo = _FakeMidiRepository();
      addTearDown(repo.dispose);

      final score = ScoreTimelineReducer.reduce(
        title: 'Route Pause Test',
        initialScale: Scale.fromKeySignature(KeySignature.cMajor),
        initialTimeSignature: TimeSignature.common,
        measures: <MeasureTimelineInput>[
          MeasureTimelineInput(
            measureNumber: 1,
            notes: <NoteTimelineInput>[
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.c,
                octave: 4,
                explicitAlter: 0,
                beatOffset: const RationalBeats.zero(),
                duration: DurationValue(base: NoteBaseDuration.quarter),
              ),
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.d,
                octave: 4,
                explicitAlter: 0,
                beatOffset: RationalBeats(1),
                duration: DurationValue(base: NoteBaseDuration.quarter),
              ),
            ],
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          midiRepositoryProvider.overrideWithValue(repo),
          practiceChordWindowProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
      );
      addTearDown(container.dispose);

      final parentKey = PracticeSessionKey(
        variantId: 'v1',
        score: score,
        routeId: 101,
      );
      final previewKey = PracticeSessionKey(
        variantId: 'v1',
        score: score,
        routeId: 102,
      );
      final parentSub = container.listen(
        piecePracticeControllerProvider(parentKey),
        (_, _) {},
      );
      final previewSub = container.listen(
        piecePracticeControllerProvider(previewKey),
        (_, _) {},
      );
      addTearDown(parentSub.close);
      addTearDown(previewSub.close);

      // Pause route 101 only -> route 102 still evaluates MIDI Note On.
      container.read(practiceRoutePausedProvider(101).notifier).setPaused(true);
      repo.noteEventsController.add(_noteOn(60));
      await tester.pump(const Duration(milliseconds: 25));
      expect(parentSub.read().activeSliceOrdinal, 0);
      expect(previewSub.read().activeSliceOrdinal, 1);

      // Global practicePausedProvider pauses all routes even after route 101 unpauses.
      container.read(practicePausedProvider.notifier).setPaused(true);
      container
          .read(practiceRoutePausedProvider(101).notifier)
          .setPaused(false);
      repo.noteEventsController.add(_noteOn(62));
      await tester.pump(const Duration(milliseconds: 25));
      expect(parentSub.read().activeSliceOrdinal, 0);
      expect(previewSub.read().activeSliceOrdinal, 1);

      // Clearing global pause lets both routes advance cleanly.
      container.read(practicePausedProvider.notifier).setPaused(false);
      repo.noteEventsController.add(_noteOn(60));
      await tester.pump(const Duration(milliseconds: 25));
      expect(parentSub.read().activeSliceOrdinal, 1);
    },
  );
}
