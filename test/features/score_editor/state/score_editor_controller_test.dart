import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_controller.dart';
import 'package:piano_exercises/features/score_editor/state/score_editor_state.dart';
import 'package:piano_exercises/shared/music/music.dart';

class _FakeMidiRepository implements MidiRepository {
  final StreamController<List<MidiDeviceInfo>> devicesController =
      StreamController<List<MidiDeviceInfo>>.broadcast();
  final StreamController<MidiNoteEvent> noteEventsController =
      StreamController<MidiNoteEvent>.broadcast();
  final StreamController<MidiBluetoothStatus> bluetoothController =
      StreamController<MidiBluetoothStatus>.broadcast();

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

void main() {
  group('ScoreEditorController', () {
    late _FakeMidiRepository midiRepo;
    late InMemoryScoreFileStore fileStore;
    late ProviderContainer container;
    late ProviderSubscription<ScoreEditorState> sub;

    setUp(() {
      midiRepo = _FakeMidiRepository();
      fileStore = InMemoryScoreFileStore();
      container = ProviderContainer(
        overrides: [
          midiRepositoryProvider.overrideWith((ref) {
            ref.onDispose(() => unawaited(midiRepo.dispose()));
            return midiRepo;
          }),
          scoreFileStoreProvider.overrideWithValue(fileStore),
          scoreParserProvider.overrideWithValue(const MusicXmlScoreParser()),
          scoreEditorChordWindowProvider.overrideWithValue(
            const Duration(milliseconds: 10),
          ),
        ],
      );
      sub = container.listen(
        scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
        (_, _) {},
      );
    });

    tearDown(() {
      sub.close();
      container.dispose();
    });

    test('coalesces MIDI Note On bursts, honors pause/carryover, and tracks undo/redo (capped at 100)', () async {
      final controller = container.read(
        scoreEditorControllerProvider(ScoreEditorSessionId.composeTab).notifier,
      );

      // Simultaneous chord entry (C4 + E4).
      midiRepo.noteEventsController.add(_noteOn(60));
      midiRepo.noteEventsController.add(_noteOn(64));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      var state = container.read(
        scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
      );
      expect(state.isDirty, isTrue);
      expect(state.draft.measures[0].notes, hasLength(2));
      expect(state.draft.cursor.beatOffset, RationalBeats(1));
      expect(state.canUndo, isTrue);

      // Release keys, pause editor, press key while paused -> ignored even after unpause (carryover).
      midiRepo.noteEventsController.add(_noteOff(60));
      midiRepo.noteEventsController.add(_noteOff(64));
      container.read(scoreEditorPausedProvider.notifier).setPaused(true);
      midiRepo.noteEventsController.add(_noteOn(67));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        container
            .read(
              scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
            )
            .draft
            .measures[0]
            .notes,
        hasLength(2),
      );

      // Undo and redo.
      controller.undo();
      state = container.read(
        scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
      );
      expect(state.draft.measures[0].notes, isEmpty);
      expect(state.canRedo, isTrue);

      controller.redo();
      state = container.read(
        scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
      );
      expect(state.draft.measures[0].notes, hasLength(2));

      // Verify bounded 100-step undo history.
      for (var i = 0; i < 110; i += 1) {
        controller.addTouchNote();
        if (i.isEven) {
          controller.stepSelectedNotePitch(1);
        } else {
          controller.stepSelectedNotePitch(-1);
        }
      }
      state = container.read(
        scoreEditorControllerProvider(ScoreEditorSessionId.composeTab),
      );
      expect(state.undoStack.length, ScoreEditorState.maxUndoSteps);
    });

    test('loadVariantForEditing populates draft, handles missing files, and applySaveResult clears isDirty', () async {
      final sampleScore = ScoreTimelineReducer.reduce(
        title: 'XML Title',
        artist: 'XML Artist',
        initialScale: Scale.fromKeySignature(const KeySignature(-1)),
        initialTimeSignature: TimeSignature(3, 4),
        measures: <MeasureTimelineInput>[
          MeasureTimelineInput(
            measureNumber: 1,
            notes: <NoteTimelineInput>[
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.f,
                octave: 4,
                explicitAlter: 0,
                beatOffset: const RationalBeats.zero(),
                duration: DurationValue(base: NoteBaseDuration.half),
              ),
            ],
          ),
        ],
      );
      final bytes = const MusicXmlScoreSerializer().serialize(sampleScore);
      final path = await fileStore.saveScoreBytes(
        variantId: 'v_edit',
        format: ScoreFormat.musicXml,
        bytes: bytes,
      );
      final variant = ScoreVariant(
        id: 'v_edit',
        pieceId: 'p_edit',
        difficultyTier: DifficultyTier.beginner,
        label: 'Easy',
        fileName: 'edit.musicxml',
        storedRelativePath: path,
        importedAtMs: 1,
      );
      final piece = Piece(
        id: 'p_edit',
        title: 'Catalog Title',
        artist: 'Catalog Artist',
        scale: Scale.fromKeySignature(const KeySignature(-1)),
        variants: <ScoreVariant>[variant],
      );

      const session = ScoreEditorSessionId('edit_v_edit');
      final editSub = container.listen(
        scoreEditorControllerProvider(session),
        (_, _) {},
      );
      addTearDown(editSub.close);
      final controller = container.read(
        scoreEditorControllerProvider(session).notifier,
      );

      await controller.loadVariantForEditing(piece, variant);
      var state = container.read(scoreEditorControllerProvider(session));
      expect(state.isLoadingVariant, isFalse);
      expect(state.loadError, isNull);
      expect(state.isDirty, isFalse);
      expect(state.binding, ScoreEditorBinding(piece: piece, variant: variant));
      expect(state.draft.title, 'Catalog Title');
      expect(state.draft.measures[0].notes.single.staffNote.pitchName, 'F4');

      controller.addTouchNote();
      expect(
        container.read(scoreEditorControllerProvider(session)).isDirty,
        isTrue,
      );

      controller.applySaveResult(piece: piece, variant: variant);
      expect(
        container.read(scoreEditorControllerProvider(session)).isDirty,
        isFalse,
      );

      // Missing file surfaces loadError cleanly.
      final missingVariant = ScoreVariant(
        id: 'v_missing',
        pieceId: 'p_edit',
        difficultyTier: DifficultyTier.beginner,
        label: 'Missing',
        fileName: 'missing.musicxml',
        storedRelativePath: 'scores/v_missing.musicxml',
        importedAtMs: 2,
      );
      await controller.loadVariantForEditing(piece, missingVariant);
      state = container.read(scoreEditorControllerProvider(session));
      expect(state.isLoadingVariant, isFalse);
      expect(state.loadError, isNotNull);

      // While loadError != null, MIDI Note On and mutations are ignored.
      final failedDraft = state.draft;
      midiRepo.noteEventsController.add(_noteOn(60));
      await Future<void>.delayed(const Duration(milliseconds: 25));
      controller.addTouchNote();
      controller.updateSetup(timeSignature: TimeSignature(3, 4));
      controller.undo();
      controller.redo();
      state = container.read(scoreEditorControllerProvider(session));
      expect(state.loadError, isNotNull);
      expect(state.isDirty, isFalse);
      expect(state.draft, failedDraft);
    });
  });
}
