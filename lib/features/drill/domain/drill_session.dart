import 'dart:math' as math;

import 'package:piano_exercises/features/drill/domain/played_staff_mapper.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Feedback classification for the most recent evaluated MIDI attempt.
enum DrillFeedbackStatus { idle, correct, wrongSingleNote, multipleNotesPlayed }

/// Side effect an evaluated attempt should apply to progression statistics.
enum DrillProgressionAction { none, recordCleanHit, recordMistake }

/// Immutable summary of a single evaluated MIDI note or chord attempt.
final class DrillAttemptResult {
  DrillAttemptResult({
    required this.status,
    required this.targetNote,
    required List<MidiNote> playedNotes,
    required this.reactionTimeMs,
    required this.wasCleanFirstTry,
    required this.progressionAction,
  }) : assert(reactionTimeMs >= 0),
       playedNotes = List<MidiNote>.unmodifiable(playedNotes);

  final DrillFeedbackStatus status;
  final StaffNote targetNote;
  final List<MidiNote> playedNotes;
  final int reactionTimeMs;
  final bool wasCleanFirstTry;
  final DrillProgressionAction progressionAction;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DrillAttemptResult &&
            other.status == status &&
            other.targetNote == targetNote &&
            _listEquals(other.playedNotes, playedNotes) &&
            other.reactionTimeMs == reactionTimeMs &&
            other.wasCleanFirstTry == wasCleanFirstTry &&
            other.progressionAction == progressionAction);
  }

  @override
  int get hashCode => Object.hash(
    status,
    targetNote,
    Object.hashAll(playedNotes),
    reactionTimeMs,
    wasCleanFirstTry,
    progressionAction,
  );
}

/// Immutable state of an active sight-reading drill prompt.
final class DrillSessionState {
  DrillSessionState({
    required this.targetNote,
    required this.promptStartedAtMs,
    this.hasMistakeOnCurrentPrompt = false,
    List<StaffNote> wrongPlayedNotes = const <StaffNote>[],
    this.lastResult,
  }) : wrongPlayedNotes = List<StaffNote>.unmodifiable(wrongPlayedNotes);

  final StaffNote targetNote;
  final int promptStartedAtMs;
  final bool hasMistakeOnCurrentPrompt;
  final List<StaffNote> wrongPlayedNotes;
  final DrillAttemptResult? lastResult;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DrillSessionState &&
            other.targetNote == targetNote &&
            other.promptStartedAtMs == promptStartedAtMs &&
            other.hasMistakeOnCurrentPrompt == hasMistakeOnCurrentPrompt &&
            _listEquals(other.wrongPlayedNotes, wrongPlayedNotes) &&
            other.lastResult == lastResult);
  }

  @override
  int get hashCode => Object.hash(
    targetNote,
    promptStartedAtMs,
    hasMistakeOnCurrentPrompt,
    Object.hashAll(wrongPlayedNotes),
    lastResult,
  );
}

/// Output of evaluating an attempt against the current [DrillSessionState].
final class DrillEvaluation {
  const DrillEvaluation({required this.nextState, required this.result});

  final DrillSessionState nextState;
  final DrillAttemptResult result;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DrillEvaluation &&
            other.nextState == nextState &&
            other.result == result);
  }

  @override
  int get hashCode => Object.hash(nextState, result);
}

/// Pure evaluator translating played MIDI notes into feedback and state transitions.
abstract final class DrillEvaluator {
  static DrillEvaluation evaluate({
    required DrillSessionState state,
    required Iterable<MidiNote> playedNotes,
    required int attemptStartedAtMs,
    required int evaluatedAtMs,
    required StaffNote Function(StaffNote previousTarget) selectNextTarget,
  }) {
    final distinctNotes = playedNotes.toSet().toList(growable: false)..sort();
    if (distinctNotes.isEmpty) {
      throw ArgumentError.value(
        playedNotes,
        'playedNotes',
        'At least one played note is required.',
      );
    }

    final reactionTimeMs = math.max(
      0,
      attemptStartedAtMs - state.promptStartedAtMs,
    );

    if (distinctNotes.length > 1) {
      return _buildMistakeEvaluation(
        state: state,
        distinctNotes: distinctNotes,
        reactionTimeMs: reactionTimeMs,
        status: DrillFeedbackStatus.multipleNotesPlayed,
      );
    }

    final played = distinctNotes.single;
    if (!state.targetNote.matchesMidi(played)) {
      return _buildMistakeEvaluation(
        state: state,
        distinctNotes: distinctNotes,
        reactionTimeMs: reactionTimeMs,
        status: DrillFeedbackStatus.wrongSingleNote,
      );
    }

    final wasCleanFirstTry = !state.hasMistakeOnCurrentPrompt;
    final result = DrillAttemptResult(
      status: DrillFeedbackStatus.correct,
      targetNote: state.targetNote,
      playedNotes: distinctNotes,
      reactionTimeMs: reactionTimeMs,
      wasCleanFirstTry: wasCleanFirstTry,
      progressionAction: wasCleanFirstTry
          ? DrillProgressionAction.recordCleanHit
          : DrillProgressionAction.none,
    );
    final nextState = DrillSessionState(
      targetNote: selectNextTarget(state.targetNote),
      promptStartedAtMs: evaluatedAtMs,
      hasMistakeOnCurrentPrompt: false,
      wrongPlayedNotes: const <StaffNote>[],
      lastResult: result,
    );
    return DrillEvaluation(nextState: nextState, result: result);
  }

  static DrillEvaluation _buildMistakeEvaluation({
    required DrillSessionState state,
    required List<MidiNote> distinctNotes,
    required int reactionTimeMs,
    required DrillFeedbackStatus status,
  }) {
    final wrongNotes = distinctNotes
        .map(
          (note) => mapMidiNoteToStaffNote(
            note,
            referenceClef: state.targetNote.clef,
          ),
        )
        .toList(growable: false);
    final result = DrillAttemptResult(
      status: status,
      targetNote: state.targetNote,
      playedNotes: distinctNotes,
      reactionTimeMs: reactionTimeMs,
      wasCleanFirstTry: false,
      progressionAction: DrillProgressionAction.recordMistake,
    );
    final nextState = DrillSessionState(
      targetNote: state.targetNote,
      promptStartedAtMs: state.promptStartedAtMs,
      hasMistakeOnCurrentPrompt: true,
      wrongPlayedNotes: wrongNotes,
      lastResult: result,
    );
    return DrillEvaluation(nextState: nextState, result: result);
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
