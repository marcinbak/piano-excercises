import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/drill/domain/drill_session.dart';
import 'package:piano_exercises/features/drill/domain/played_staff_mapper.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('mapMidiNoteToStaffNote', () {
    test(
      'maps all MIDI 0..127 notes with expected clefs and sharp spellings',
      () {
        for (var number = 0; number <= 127; number += 1) {
          final midi = MidiNote.fromNumber(number);
          final mappedTrebleRef = mapMidiNoteToStaffNote(
            midi,
            referenceClef: Clef.treble,
          );
          final mappedBassRef = mapMidiNoteToStaffNote(
            midi,
            referenceClef: Clef.bass,
          );

          expect(mappedTrebleRef.midiNote, midi);
          expect(mappedBassRef.midiNote, midi);
          expect(mappedTrebleRef.accidental, isNot(Accidental.flat));

          if (number < 60) {
            expect(mappedTrebleRef.clef, Clef.bass);
            expect(mappedBassRef.clef, Clef.bass);
          } else if (number > 60) {
            expect(mappedTrebleRef.clef, Clef.treble);
            expect(mappedBassRef.clef, Clef.treble);
          } else {
            expect(mappedTrebleRef.clef, Clef.treble);
            expect(mappedBassRef.clef, Clef.bass);
          }
        }

        expect(
          mapMidiNoteToStaffNote(
            const MidiNote(61),
            referenceClef: Clef.bass,
          ).pitchName,
          'C#4',
        );
        expect(
          mapMidiNoteToStaffNote(
            const MidiNote(63),
            referenceClef: Clef.treble,
          ).pitchName,
          'D#4',
        );
        expect(
          mapMidiNoteToStaffNote(
            const MidiNote(66),
            referenceClef: Clef.treble,
          ).pitchName,
          'F#4',
        );
        expect(
          mapMidiNoteToStaffNote(
            const MidiNote(68),
            referenceClef: Clef.treble,
          ).pitchName,
          'G#4',
        );
        expect(
          mapMidiNoteToStaffNote(
            const MidiNote(70),
            referenceClef: Clef.treble,
          ).pitchName,
          'A#4',
        );
      },
    );
  });

  group('DrillEvaluator', () {
    const trebleC4 = StaffNote(
      note: DiatonicNote.c,
      octave: 4,
      clef: Clef.treble,
    );
    const bassC4 = StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.bass);

    test('throws ArgumentError on empty playedNotes', () {
      final state = DrillSessionState(
        targetNote: trebleC4,
        promptStartedAtMs: 100,
      );
      expect(
        () => DrillEvaluator.evaluate(
          state: state,
          playedNotes: const <MidiNote>[],
          attemptStartedAtMs: 150,
          evaluatedAtMs: 185,
          selectNextTarget: (_) => bassC4,
        ),
        throwsArgumentError,
      );
    });

    test('clean first-try hit advances target and records clean hit', () {
      final initial = DrillSessionState(
        targetNote: trebleC4,
        promptStartedAtMs: 100,
      );

      final evaluation = DrillEvaluator.evaluate(
        state: initial,
        playedNotes: const <MidiNote>[MidiNote(60)],
        attemptStartedAtMs: 320,
        evaluatedAtMs: 355,
        selectNextTarget: (_) => bassC4,
      );

      expect(evaluation.result.status, DrillFeedbackStatus.correct);
      expect(evaluation.result.targetNote, trebleC4);
      expect(evaluation.result.playedNotes, const <MidiNote>[MidiNote(60)]);
      expect(evaluation.result.reactionTimeMs, 220);
      expect(evaluation.result.wasCleanFirstTry, isTrue);
      expect(
        evaluation.result.progressionAction,
        DrillProgressionAction.recordCleanHit,
      );

      expect(evaluation.nextState.targetNote, bassC4);
      expect(evaluation.nextState.promptStartedAtMs, 355);
      expect(evaluation.nextState.hasMistakeOnCurrentPrompt, isFalse);
      expect(evaluation.nextState.wrongPlayedNotes, isEmpty);
      expect(evaluation.nextState.lastResult, evaluation.result);
    });

    test('single wrong note holds target and records mistake', () {
      final initial = DrillSessionState(
        targetNote: trebleC4,
        promptStartedAtMs: 100,
      );

      final evaluation = DrillEvaluator.evaluate(
        state: initial,
        playedNotes: const <MidiNote>[MidiNote(62)],
        attemptStartedAtMs: 250,
        evaluatedAtMs: 285,
        selectNextTarget: (_) => bassC4,
      );

      expect(evaluation.result.status, DrillFeedbackStatus.wrongSingleNote);
      expect(evaluation.result.wasCleanFirstTry, isFalse);
      expect(
        evaluation.result.progressionAction,
        DrillProgressionAction.recordMistake,
      );

      expect(evaluation.nextState.targetNote, trebleC4);
      expect(evaluation.nextState.promptStartedAtMs, 100);
      expect(evaluation.nextState.hasMistakeOnCurrentPrompt, isTrue);
      expect(evaluation.nextState.wrongPlayedNotes, const <StaffNote>[
        StaffNote(note: DiatonicNote.d, octave: 4, clef: Clef.treble),
      ]);
    });

    test(
      'multi-note chord in either arrival order holds target and sorts notes',
      () {
        final initial = DrillSessionState(
          targetNote: trebleC4,
          promptStartedAtMs: 100,
        );

        final forward = DrillEvaluator.evaluate(
          state: initial,
          playedNotes: const <MidiNote>[MidiNote(60), MidiNote(64)],
          attemptStartedAtMs: 210,
          evaluatedAtMs: 245,
          selectNextTarget: (_) => bassC4,
        );
        final reversed = DrillEvaluator.evaluate(
          state: initial,
          playedNotes: const <MidiNote>[MidiNote(64), MidiNote(60)],
          attemptStartedAtMs: 210,
          evaluatedAtMs: 245,
          selectNextTarget: (_) => bassC4,
        );

        for (final evaluation in <DrillEvaluation>[forward, reversed]) {
          expect(
            evaluation.result.status,
            DrillFeedbackStatus.multipleNotesPlayed,
          );
          expect(evaluation.result.playedNotes, const <MidiNote>[
            MidiNote(60),
            MidiNote(64),
          ]);
          expect(
            evaluation.result.progressionAction,
            DrillProgressionAction.recordMistake,
          );
          expect(evaluation.nextState.targetNote, trebleC4);
          expect(evaluation.nextState.hasMistakeOnCurrentPrompt, isTrue);
          expect(evaluation.nextState.wrongPlayedNotes, const <StaffNote>[
            trebleC4,
            StaffNote(note: DiatonicNote.e, octave: 4, clef: Clef.treble),
          ]);
        }
      },
    );

    test(
      'clearing target after mistake advances with progressionAction.none',
      () {
        final afterWrong = DrillEvaluator.evaluate(
          state: DrillSessionState(
            targetNote: trebleC4,
            promptStartedAtMs: 100,
          ),
          playedNotes: const <MidiNote>[MidiNote(61)],
          attemptStartedAtMs: 200,
          evaluatedAtMs: 235,
          selectNextTarget: (_) => bassC4,
        ).nextState;

        final cleared = DrillEvaluator.evaluate(
          state: afterWrong,
          playedNotes: const <MidiNote>[MidiNote(60)],
          attemptStartedAtMs: 420,
          evaluatedAtMs: 455,
          selectNextTarget: (_) => bassC4,
        );

        expect(cleared.result.status, DrillFeedbackStatus.correct);
        expect(cleared.result.wasCleanFirstTry, isFalse);
        expect(cleared.result.progressionAction, DrillProgressionAction.none);
        expect(cleared.result.reactionTimeMs, 320);
        expect(cleared.nextState.targetNote, bassC4);
        expect(cleared.nextState.promptStartedAtMs, 455);
        expect(cleared.nextState.hasMistakeOnCurrentPrompt, isFalse);
        expect(cleared.nextState.wrongPlayedNotes, isEmpty);
      },
    );
  });
}
