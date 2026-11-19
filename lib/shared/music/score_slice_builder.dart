import 'package:piano_exercises/shared/music/clef.dart';
import 'package:piano_exercises/shared/music/rhythm.dart';
import 'package:piano_exercises/shared/music/score.dart';

/// Builds a sorted grand-staff [ScoreSlice] with clef-scoped rest fallback.
ScoreSlice buildScoreSlice({
  required int sliceIndex,
  required int measureNumber,
  required RationalBeats beatOffset,
  required RationalBeats beatDuration,
  required List<ScoreNote> notes,
  required List<RestEvent> rests,
}) {
  final trebleNotes =
      notes.where((note) => note.staffNote.clef == Clef.treble).toList()
        ..sort(_compareSliceNotes);
  final bassNotes =
      notes.where((note) => note.staffNote.clef == Clef.bass).toList()
        ..sort(_compareSliceNotes);
  return ScoreSlice(
    sliceIndex: sliceIndex,
    measureNumber: measureNumber,
    beatOffset: beatOffset,
    beatDuration: beatDuration,
    trebleNotes: trebleNotes,
    bassNotes: bassNotes,
    trebleRest: trebleNotes.isEmpty
        ? _firstRestForClef(rests, Clef.treble)
        : null,
    bassRest: bassNotes.isEmpty ? _firstRestForClef(rests, Clef.bass) : null,
  );
}

RestEvent? _firstRestForClef(List<RestEvent> rests, Clef clef) {
  for (final rest in rests) {
    if (rest.clef == clef) {
      return rest;
    }
  }
  return null;
}

int _compareSliceNotes(ScoreNote a, ScoreNote b) {
  final stepCmp = a.staffNote.diatonicStep.compareTo(b.staffNote.diatonicStep);
  return stepCmp != 0
      ? stepCmp
      : a.midiNote.number.compareTo(b.midiNote.number);
}
