import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/domain/score_practice_navigator.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Wait-mode grading classification for a coalesced chord against one slice.
enum ChordEvaluationStatus { completeMatch, partialChord, wrongNotes }

/// Immutable evaluation output comparing played MIDI pitches against a slice.
final class ChordEvaluationResult {
  ChordEvaluationResult({
    required this.status,
    required Set<MidiNote> wrongPitches,
    required Set<MidiNote> missingPitches,
    required List<StaffNote> wrongStaffNotes,
  }) : wrongPitches = Set<MidiNote>.unmodifiable(wrongPitches),
       missingPitches = Set<MidiNote>.unmodifiable(missingPitches),
       wrongStaffNotes = List<StaffNote>.unmodifiable(wrongStaffNotes);

  final ChordEvaluationStatus status;
  final Set<MidiNote> wrongPitches;
  final Set<MidiNote> missingPitches;
  final List<StaffNote> wrongStaffNotes;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ChordEvaluationResult &&
            other.status == status &&
            _setEquals(other.wrongPitches, wrongPitches) &&
            _setEquals(other.missingPitches, missingPitches) &&
            _listEquals(other.wrongStaffNotes, wrongStaffNotes));
  }

  @override
  int get hashCode => Object.hash(
    status,
    Object.hashAllUnordered(wrongPitches),
    Object.hashAllUnordered(missingPitches),
    Object.hashAll(wrongStaffNotes),
  );
}

/// Pure Wait-Mode polyphonic evaluator for grand-staff [ScoreSlice]s.
abstract final class PolyphonicEvaluator {
  /// Evaluates [playedPitches] against [slice] under [handMode].
  static ChordEvaluationResult evaluateSlice({
    required ScoreSlice slice,
    required HandMode handMode,
    required Set<MidiNote> playedPitches,
    required KeySignature activeKeySignature,
  }) {
    final requiredPitches = <MidiNote>{
      for (final note in ScorePracticeNavigator.requiredNotesFor(
        slice,
        handMode,
      ))
        note.midiNote,
    };
    final sustainedPitches = <MidiNote>{
      for (final note in ScorePracticeNavigator.sustainedNotesFor(
        slice,
        handMode,
      ))
        note.midiNote,
    }.difference(requiredPitches);

    final allowedPitches = requiredPitches.union(sustainedPitches);
    final wrongPitches = playedPitches.difference(allowedPitches);
    final missingPitches = requiredPitches.difference(playedPitches);

    final status = wrongPitches.isNotEmpty
        ? ChordEvaluationStatus.wrongNotes
        : missingPitches.isNotEmpty
        ? ChordEvaluationStatus.partialChord
        : ChordEvaluationStatus.completeMatch;

    final sortedWrong = wrongPitches.toList(growable: false)..sort();
    final referenceClef = referenceClefForSlice(slice, handMode);
    final wrongStaffNotes = <StaffNote>[
      for (final midiNote in sortedWrong)
        spellMidiNoteForScore(
          midiNote: midiNote,
          referenceClef: referenceClef,
          activeKeySignature: activeKeySignature,
        ),
    ];

    return ChordEvaluationResult(
      status: status,
      wrongPitches: wrongPitches,
      missingPitches: missingPitches,
      wrongStaffNotes: wrongStaffNotes,
    );
  }

  /// Resolves the reference clef for Middle C (`60`) on [slice] under [handMode].
  static Clef referenceClefForSlice(ScoreSlice slice, HandMode handMode) {
    return switch (handMode) {
      HandMode.right => Clef.treble,
      HandMode.left => Clef.bass,
      HandMode.both =>
        slice.requiredBassNotes.isNotEmpty && slice.requiredTrebleNotes.isEmpty
            ? Clef.bass
            : Clef.treble,
    };
  }

  /// Spells a played [midiNote] using [activeKeySignature] and Middle C [referenceClef].
  static StaffNote spellMidiNoteForScore({
    required MidiNote midiNote,
    required Clef referenceClef,
    required KeySignature activeKeySignature,
  }) {
    final clef = switch (midiNote.number) {
      > 60 => Clef.treble,
      < 60 => Clef.bass,
      _ => referenceClef,
    };
    return KeyPitchSpeller.spellMidiNote(
      midiNote,
      clef: clef,
      keySignature: activeKeySignature,
    );
  }
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) {
    return true;
  }
  return a.length == b.length && a.containsAll(b);
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
