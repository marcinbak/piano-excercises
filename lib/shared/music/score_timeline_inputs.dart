import 'package:piano_exercises/shared/music/clef.dart';
import 'package:piano_exercises/shared/music/key_signature.dart';
import 'package:piano_exercises/shared/music/pitch_class.dart';
import 'package:piano_exercises/shared/music/rhythm.dart';
import 'package:piano_exercises/shared/music/score.dart';

/// Raw pitched note event inside a [MeasureTimelineInput] prior to reduction.
final class NoteTimelineInput {
  const NoteTimelineInput({
    required this.clef,
    required this.diatonicNote,
    required this.octave,
    this.explicitAlter,
    this.writtenAccidental,
    required this.beatOffset,
    required this.duration,
    this.tie = TieType.none,
    this.voice = 1,
    this.beamGroupId,
  });

  final Clef clef;
  final DiatonicNote diatonicNote;
  final int octave;
  final int? explicitAlter;
  final Accidental? writtenAccidental;
  final RationalBeats beatOffset;
  final DurationValue duration;
  final TieType tie;
  final int voice;
  final String? beamGroupId;
}

/// Raw rest event inside a [MeasureTimelineInput] prior to reduction.
final class RestTimelineInput {
  const RestTimelineInput({
    required this.clef,
    required this.beatOffset,
    required this.duration,
    this.voice = 1,
  });

  final Clef clef;
  final RationalBeats beatOffset;
  final DurationValue duration;
  final int voice;
}

/// Raw bar container passed to `ScoreTimelineReducer.reduce`.
final class MeasureTimelineInput {
  MeasureTimelineInput({
    required this.measureNumber,
    this.keySignature,
    this.timeSignature,
    this.tempoMark,
    List<NoteTimelineInput> notes = const <NoteTimelineInput>[],
    List<RestTimelineInput> rests = const <RestTimelineInput>[],
  }) : notes = List<NoteTimelineInput>.unmodifiable(notes),
       rests = List<RestTimelineInput>.unmodifiable(rests);

  final int measureNumber;
  final KeySignature? keySignature;
  final TimeSignature? timeSignature;
  final TempoMark? tempoMark;
  final List<NoteTimelineInput> notes;
  final List<RestTimelineInput> rests;
}

/// Deterministic chronological ordering for [NoteTimelineInput] events.
int compareNoteTimelineInputs(NoteTimelineInput a, NoteTimelineInput b) {
  final offsetCmp = a.beatOffset.compareTo(b.beatOffset);
  if (offsetCmp != 0) {
    return offsetCmp;
  }
  final clefCmp = a.clef.index.compareTo(b.clef.index);
  if (clefCmp != 0) {
    return clefCmp;
  }
  final voiceCmp = a.voice.compareTo(b.voice);
  if (voiceCmp != 0) {
    return voiceCmp;
  }
  final octaveCmp = a.octave.compareTo(b.octave);
  return octaveCmp != 0
      ? octaveCmp
      : a.diatonicNote.index.compareTo(b.diatonicNote.index);
}

/// Deterministic chronological ordering for [RestTimelineInput] events.
int compareRestTimelineInputs(RestTimelineInput a, RestTimelineInput b) {
  final offsetCmp = a.beatOffset.compareTo(b.beatOffset);
  if (offsetCmp != 0) {
    return offsetCmp;
  }
  final clefCmp = a.clef.index.compareTo(b.clef.index);
  return clefCmp != 0 ? clefCmp : a.voice.compareTo(b.voice);
}
