import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/drill/drill.dart';
import 'package:piano_exercises/features/midi/midi.dart';
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

MidiNoteEvent _noteOn(int noteNumber, {int timestampMs = 10}) {
  return MidiNoteEvent.fromChannelMessage(
    noteNumber: noteNumber,
    velocity: 100,
    isNoteOn: true,
    channel: 0,
    deviceId: 'ble-1',
    timestampMs: timestampMs,
  );
}

MidiNoteEvent _noteOff(int noteNumber, {int timestampMs = 20}) {
  return MidiNoteEvent.fromChannelMessage(
    noteNumber: noteNumber,
    velocity: 0,
    isNoteOn: false,
    channel: 0,
    deviceId: 'ble-1',
    timestampMs: timestampMs,
  );
}

GrandStaffPainter _findStaffPainter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byKey(const ValueKey<String>('grand-staff-card')),
      matching: find.byType(CustomPaint),
    ),
  );
  return paints.map((w) => w.painter).whereType<GrandStaffPainter>().single;
}

void main() {
  testWidgets(
    'renders grand staff without leaking target note, handles wrong note, chord, and clean hit',
    (tester) async {
      final repository = _FakeMidiRepository();
      var nowMs = 1000;
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            midiRepositoryProvider.overrideWithValue(repository),
            drillRandomIntProvider.overrideWithValue((_) => 0),
            drillClockMsProvider.overrideWithValue(() => nowMs),
          ],
          child: const MaterialApp(home: DrillScreen()),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('grand-staff-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('drill-stats-bar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('drill-feedback-banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('midi-status-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('drill-reset-button')),
        findsOneWidget,
      );
      for (var stage = 1; stage <= 5; stage += 1) {
        expect(
          find.byKey(ValueKey<String>('drill-stage-chip-$stage')),
          findsOneWidget,
        );
      }

      // Target note C4 must NEVER appear in visible text before solving.
      expect(find.textContaining('C4'), findsNothing);
      expect(
        find.text('Play the note shown on the grand staff via BLE-MIDI.'),
        findsOneWidget,
      );

      final initialPainter = _findStaffPainter(tester);
      expect(
        initialPainter.targetNote,
        const StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble),
      );
      expect(initialPainter.wrongPlayedNotes, isEmpty);

      // 1) Wrong single note C#4 (61): target stays held and red wrong note renders.
      nowMs = 1200;
      repository.noteEventsController.add(_noteOn(61));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      repository.noteEventsController.add(_noteOff(61));
      await tester.pump();

      final afterWrong = _findStaffPainter(tester);
      expect(afterWrong.targetNote, initialPainter.targetNote);
      expect(afterWrong.wrongPlayedNotes, const <StaffNote>[
        StaffNote(
          note: DiatonicNote.c,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.sharp,
        ),
      ]);
      expect(find.textContaining('Wrong note (C#4)'), findsOneWidget);
      expect(find.textContaining('C4'), findsNothing);

      // 2) Simultaneous 2-note chord C4 + E4 within 35ms.
      nowMs = 1500;
      repository.noteEventsController.add(_noteOn(60));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      repository.noteEventsController.add(_noteOn(64));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      repository.noteEventsController.add(_noteOff(60));
      repository.noteEventsController.add(_noteOff(64));
      await tester.pump();

      final afterChord = _findStaffPainter(tester);
      expect(afterChord.targetNote, initialPainter.targetNote);
      expect(afterChord.wrongPlayedNotes.length, 2);
      expect(
        find.textContaining('Multiple notes played (C4, E4)'),
        findsOneWidget,
      );

      // 3) Clear held prompt after mistake: advances prompt without raising streak.
      nowMs = 1650;
      repository.noteEventsController.add(_noteOn(60));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      repository.noteEventsController.add(_noteOff(60));
      await tester.pump();

      expect(
        find.textContaining('Cleared C4 — next note ready'),
        findsOneWidget,
      );
      expect(_findStaffPainter(tester).wrongPlayedNotes, isEmpty);

      // 4) Reset session so we can verify a clean first-try hit updates stats.
      await tester.tap(
        find.byKey(const ValueKey<String>('drill-reset-button')),
      );
      await tester.pump();
      expect(_findStaffPainter(tester).wrongPlayedNotes, isEmpty);

      // 5) Clean target hit C4 (60).
      nowMs = 1750;
      repository.noteEventsController.add(_noteOn(60));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      repository.noteEventsController.add(_noteOff(60));
      await tester.pump();

      final afterHit = _findStaffPainter(tester);
      expect(
        afterHit.targetNote,
        const StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.bass),
      );
      expect(afterHit.wrongPlayedNotes, isEmpty);
      expect(find.textContaining('Correct: C4 (100 ms)'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('100 ms'), findsOneWidget);
    },
  );

  testWidgets(
    'stage chips switch active stage, status shows device name, and midi button navigates to MidiSpikeScreen',
    (tester) async {
      const piano = MidiDeviceInfo(
        id: 'ble-1',
        name: 'FP-30X',
        typeLabel: 'BLE',
        isConnected: true,
      );
      final repository = _FakeMidiRepository()
        ..initialDevices = const <MidiDeviceInfo>[piano];
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [midiRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: DrillScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Connected (FP-30X)'), findsOneWidget);

      const expectedStages = <(int, String)>[
        (2, 'Stage 2: Additional Cs'),
        (3, 'Stage 3: All Treble & Bass Cs'),
        (4, 'Stage 4: Base Landmark Notes'),
        (5, 'Stage 5: All Natural Notes'),
        (1, 'Stage 1: Middle C'),
      ];
      for (final (number, header) in expectedStages) {
        await tester.tap(
          find.byKey(ValueKey<String>('drill-stage-chip-$number')),
        );
        await tester.pump();
        expect(find.text(header), findsOneWidget);
      }

      await tester.tap(
        find.byKey(const ValueKey<String>('midi-status-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('BLE-MIDI Spike'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Sight-Reading Drill'), findsOneWidget);
    },
  );

  testWidgets(
    'lays out cleanly on narrow portrait and short landscape viewports',
    (tester) async {
      final repository = _FakeMidiRepository();
      addTearDown(repository.dispose);

      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [midiRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: DrillScreen()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(780, 340));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'GrandStaffPainter handles extreme notes, seconds, and shouldRepaint',
    () {
      const target = StaffNote(
        note: DiatonicNote.c,
        octave: 4,
        clef: Clef.treble,
      );
      const wrong = <StaffNote>[
        StaffNote(note: DiatonicNote.c, octave: -1, clef: Clef.bass),
        StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble),
        StaffNote(
          note: DiatonicNote.d,
          octave: 4,
          clef: Clef.treble,
          accidental: Accidental.sharp,
        ),
        StaffNote(note: DiatonicNote.g, octave: 9, clef: Clef.treble),
      ];

      const painterA = GrandStaffPainter(
        targetNote: target,
        wrongPlayedNotes: wrong,
        inkColor: Colors.black,
        errorColor: Colors.red,
        staffLineColor: Colors.grey,
      );
      const painterSame = GrandStaffPainter(
        targetNote: target,
        wrongPlayedNotes: wrong,
        inkColor: Colors.black,
        errorColor: Colors.red,
        staffLineColor: Colors.grey,
      );
      const painterDifferent = GrandStaffPainter(
        targetNote: StaffNote(
          note: DiatonicNote.g,
          octave: 4,
          clef: Clef.treble,
        ),
        wrongPlayedNotes: wrong,
        inkColor: Colors.black,
        errorColor: Colors.red,
        staffLineColor: Colors.grey,
      );

      expect(painterA.shouldRepaint(painterSame), isFalse);
      expect(painterA.shouldRepaint(painterDifferent), isTrue);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      painterA.paint(canvas, const Size(320, 240));
      painterA.paint(canvas, Size.zero);
      final picture = recorder.endRecording();
      picture.dispose();
    },
  );
}
