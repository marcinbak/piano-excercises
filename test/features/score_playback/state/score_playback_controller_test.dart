import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/score_playback/score_playback.dart';
import 'package:piano_exercises/shared/music/music.dart';

class _FakeMidiRepo implements MidiRepository {
  final StreamController<List<MidiDeviceInfo>> devicesCtrl =
      StreamController<List<MidiDeviceInfo>>.broadcast();
  final StreamController<MidiNoteEvent> notesCtrl =
      StreamController<MidiNoteEvent>.broadcast();
  final StreamController<MidiBluetoothStatus> btCtrl =
      StreamController<MidiBluetoothStatus>.broadcast();
  List<MidiDeviceInfo> snapshot = const <MidiDeviceInfo>[];

  @override
  Stream<List<MidiDeviceInfo>> get devicesStream => devicesCtrl.stream;
  @override
  Stream<MidiNoteEvent> get noteEventsStream => notesCtrl.stream;
  @override
  Stream<MidiBluetoothStatus> get bluetoothStateStream => btCtrl.stream;
  @override
  MidiBluetoothStatus get currentBluetoothStatus =>
      MidiBluetoothStatus.poweredOn;
  @override
  Future<List<MidiDeviceInfo>> currentDevices() async => snapshot;
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
    await devicesCtrl.close();
    await notesCtrl.close();
    await btCtrl.close();
  }
}

class _RecordingMidiSink implements MidiOutputSink {
  final List<String> log = <String>[];

  @override
  Future<void> sendNoteOn(
    MidiNote note, {
    int velocity = 96,
    int channel = 0,
    String? deviceId,
  }) async {
    log.add('on:${note.number}:$velocity');
  }

  @override
  Future<void> sendNoteOff(
    MidiNote note, {
    int channel = 0,
    String? deviceId,
  }) async {
    log.add('off:${note.number}');
  }

  @override
  Future<void> sendAllNotesOff({int channel = 0, String? deviceId}) async {
    log.add('allOff');
  }
}

class _RecordingPcmOutput implements PcmAudioOutput {
  @override
  int get sampleRate => 24000;

  final List<int> enqueuedByteLengths = <int>[];
  int stopCalls = 0;

  @override
  Future<void> enqueuePcm16Mono(Uint8List pcmBytes) async {
    enqueuedByteLengths.add(pcmBytes.length);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> dispose() async {}
}

Score _twoBeatScore() {
  final quarter = DurationValue(base: NoteBaseDuration.quarter);
  return ScoreTimelineReducer.reduce(
    title: 'Short',
    initialTempo: TempoMark(120), // 500ms per quarter beat -> 1000ms total
    measures: <MeasureTimelineInput>[
      MeasureTimelineInput(
        measureNumber: 1,
        notes: <NoteTimelineInput>[
          NoteTimelineInput(
            clef: Clef.treble,
            diatonicNote: DiatonicNote.c,
            octave: 4,
            beatOffset: const RationalBeats.zero(),
            duration: quarter,
          ),
          NoteTimelineInput(
            clef: Clef.treble,
            diatonicNote: DiatonicNote.e,
            octave: 4,
            beatOffset: RationalBeats(1),
            duration: quarter,
          ),
        ],
        rests: const <RestTimelineInput>[],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScorePlaybackController', () {
    const session = ScorePlaybackSessionId('test_session');
    late _FakeMidiRepo midiRepo;
    late _RecordingMidiSink midiSink;
    late _RecordingPcmOutput pcmOutput;

    setUp(() {
      midiRepo = _FakeMidiRepo();
      midiSink = _RecordingMidiSink();
      pcmOutput = _RecordingPcmOutput();
    });

    tearDown(() async {
      await midiRepo.dispose();
    });

    testWidgets(
      'routes Auto to Device PCM when disconnected and to MIDI Piano when connected, with loop support',
      (tester) async {
        var fakeClockMs = 0;
        final container = ProviderContainer(
          overrides: [
            midiRepositoryProvider.overrideWithValue(midiRepo),
            midiOutputSinkProvider.overrideWithValue(midiSink),
            pcmAudioOutputProvider.overrideWithValue(pcmOutput),
            scorePlaybackClockMsProvider.overrideWithValue(() => fakeClockMs),
            scorePlaybackTickIntervalProvider.overrideWithValue(
              const Duration(milliseconds: 50),
            ),
          ],
        );
        addTearDown(container.dispose);

        final sub = container.listen(
          scorePlaybackControllerProvider(session),
          (_, _) {},
        );
        addTearDown(sub.close);
        final devicesSub = container.listen(midiDevicesProvider, (_, _) {});
        addTearDown(devicesSub.close);
        await tester.pump();

        final score = _twoBeatScore();
        final controller = container.read(
          scorePlaybackControllerProvider(session).notifier,
        );

        // 1. Disconnected -> Auto selects deviceAudio and streams PCM chunks.
        expect(controller.playScore(score), isTrue);
        expect(
          container.read(scorePlaybackControllerProvider(session)).activeTarget,
          PlaybackTarget.deviceAudio,
        );
        expect(pcmOutput.enqueuedByteLengths, isNotEmpty);
        expect(midiSink.log, isEmpty);

        fakeClockMs = 600;
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          container
              .read(scorePlaybackControllerProvider(session))
              .activeSliceOrdinal,
          1,
        );

        controller.stop();
        expect(pcmOutput.stopCalls, 1);
        expect(
          container.read(scorePlaybackControllerProvider(session)).isPlaying,
          isFalse,
        );

        // 2. Connect BLE-MIDI piano -> Auto routes to midiPiano.
        midiRepo.devicesCtrl.add(const <MidiDeviceInfo>[
          MidiDeviceInfo(
            id: 'piano-1',
            name: 'Digital Piano',
            typeLabel: 'BLE',
            isConnected: true,
          ),
        ]);
        await tester.pump();

        fakeClockMs = 1000;
        expect(controller.playScore(score, loop: true), isTrue);
        expect(
          container.read(scorePlaybackControllerProvider(session)).activeTarget,
          PlaybackTarget.midiPiano,
        );
        expect(midiSink.log, <String>['on:60:94']);

        fakeClockMs = 1520;
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          midiSink.log,
          containsAllInOrder(<String>['off:60', 'on:64:94']),
        );

        // Loop wraps at +1000ms (2000ms clock) and re-attacks C4!
        fakeClockMs = 2050;
        await tester.pump(const Duration(milliseconds: 50));
        expect(midiSink.log.where((entry) => entry == 'on:60:94').length, 2);

        // Manual override to Speaker while connected stops MIDI and flushes AllNotesOff.
        container
            .read(playbackOutputModeProvider.notifier)
            .setMode(PlaybackOutputMode.device);
        await tester.pump();
        expect(
          container.read(scorePlaybackControllerProvider(session)).isPlaying,
          isFalse,
        );
        expect(midiSink.log.last, 'allOff');
      },
    );

    test(
      'MethodChannelPcmAudioOutput forwards enqueue and stop calls',
      () async {
        final calls = <MethodCall>[];
        const channel = MethodChannel('piano_exercises/pcm_audio_test');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final output = MethodChannelPcmAudioOutput(channel: channel);
        await output.enqueuePcm16Mono(Uint8List.fromList(<int>[1, 2, 3, 4]));
        await output.stop();
        await output.dispose();

        expect(calls.map((c) => c.method).toList(), <String>[
          'enqueue',
          'stop',
          'stop',
        ]);
      },
    );
  });
}
