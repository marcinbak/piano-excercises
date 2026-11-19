import 'package:piano_exercises/shared/music/clef.dart';
import 'package:piano_exercises/shared/music/key_signature.dart';
import 'package:piano_exercises/shared/music/midi_note.dart';
import 'package:piano_exercises/shared/music/rhythm.dart';
import 'package:piano_exercises/shared/music/staff_note.dart';

/// Tie endpoint role determining whether a [ScoreNote] requires a MIDI key attack.
enum TieType {
  none,
  start,
  stop,
  continueTie;

  bool get requiresAttack => this == none || this == start;
}

/// Pitched note event placed within a [ScoreSlice].
final class ScoreNote {
  const ScoreNote({
    required this.staffNote,
    required this.duration,
    this.tie = TieType.none,
    this.showAccidental = false,
    this.voice = 1,
    this.beamGroupId,
  });

  final StaffNote staffNote;
  final DurationValue duration;
  final TieType tie;
  final bool showAccidental;
  final int voice;
  final String? beamGroupId;

  MidiNote get midiNote => staffNote.midiNote;

  bool get requiresAttack => tie.requiresAttack;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScoreNote &&
            other.staffNote == staffNote &&
            other.duration == duration &&
            other.tie == tie &&
            other.showAccidental == showAccidental &&
            other.voice == voice &&
            other.beamGroupId == beamGroupId);
  }

  @override
  int get hashCode =>
      Object.hash(staffNote, duration, tie, showAccidental, voice, beamGroupId);
}

/// Written rest event on a single [clef] staff.
final class RestEvent {
  const RestEvent({required this.clef, required this.duration, this.voice = 1});

  final Clef clef;
  final DurationValue duration;
  final int voice;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is RestEvent &&
            other.clef == clef &&
            other.duration == duration &&
            other.voice == voice);
  }

  @override
  int get hashCode => Object.hash(clef, duration, voice);
}

/// Simultaneous grand-staff beat slice with chronological [sliceIndex].
final class ScoreSlice {
  ScoreSlice({
    required this.sliceIndex,
    required this.measureNumber,
    required this.beatOffset,
    required this.beatDuration,
    List<ScoreNote> trebleNotes = const <ScoreNote>[],
    List<ScoreNote> bassNotes = const <ScoreNote>[],
    this.trebleRest,
    this.bassRest,
  }) : trebleNotes = List<ScoreNote>.unmodifiable(trebleNotes),
       bassNotes = List<ScoreNote>.unmodifiable(bassNotes);

  final int sliceIndex;
  final int measureNumber;
  final RationalBeats beatOffset;
  final RationalBeats beatDuration;
  final List<ScoreNote> trebleNotes;
  final List<ScoreNote> bassNotes;
  final RestEvent? trebleRest;
  final RestEvent? bassRest;

  List<ScoreNote> get requiredTrebleNotes => List<ScoreNote>.unmodifiable(
    trebleNotes.where((note) => note.requiresAttack),
  );

  List<ScoreNote> get requiredBassNotes => List<ScoreNote>.unmodifiable(
    bassNotes.where((note) => note.requiresAttack),
  );

  bool get isRestOnly => trebleNotes.isEmpty && bassNotes.isEmpty;

  bool get requiresAnyAttack =>
      trebleNotes.any((note) => note.requiresAttack) ||
      bassNotes.any((note) => note.requiresAttack);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScoreSlice &&
            other.sliceIndex == sliceIndex &&
            other.measureNumber == measureNumber &&
            other.beatOffset == beatOffset &&
            other.beatDuration == beatDuration &&
            _listsEqual(other.trebleNotes, trebleNotes) &&
            _listsEqual(other.bassNotes, bassNotes) &&
            other.trebleRest == trebleRest &&
            other.bassRest == bassRest);
  }

  @override
  int get hashCode => Object.hash(
    sliceIndex,
    measureNumber,
    beatOffset,
    beatDuration,
    Object.hashAll(trebleNotes),
    Object.hashAll(bassNotes),
    trebleRest,
    bassRest,
  );
}

/// Single bar containing ordered [ScoreSlice]s and optional header changes.
final class ScoreMeasure {
  ScoreMeasure({
    required this.measureNumber,
    required List<ScoreSlice> slices,
    this.keySignature,
    this.timeSignature,
    this.tempoMark,
  }) : slices = List<ScoreSlice>.unmodifiable(slices);

  final int measureNumber;
  final List<ScoreSlice> slices;
  final KeySignature? keySignature;
  final TimeSignature? timeSignature;
  final TempoMark? tempoMark;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScoreMeasure &&
            other.measureNumber == measureNumber &&
            _listsEqual(other.slices, slices) &&
            other.keySignature == keySignature &&
            other.timeSignature == timeSignature &&
            other.tempoMark == tempoMark);
  }

  @override
  int get hashCode => Object.hash(
    measureNumber,
    Object.hashAll(slices),
    keySignature,
    timeSignature,
    tempoMark,
  );
}

/// Immutable piano grand-staff score with pre-flattened chronological [slices].
final class Score {
  Score({
    required this.title,
    this.artist = '',
    required this.scale,
    required this.timeSignature,
    this.initialTempo,
    required List<ScoreMeasure> measures,
  }) : measures = List<ScoreMeasure>.unmodifiable(measures),
       slices = List<ScoreSlice>.unmodifiable(
         measures.expand((measure) => measure.slices),
       );

  final String title;
  final String artist;
  final Scale scale;
  final TimeSignature timeSignature;
  final TempoMark? initialTempo;
  final List<ScoreMeasure> measures;
  final List<ScoreSlice> slices;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Score &&
            other.title == title &&
            other.artist == artist &&
            other.scale == scale &&
            other.timeSignature == timeSignature &&
            other.initialTempo == initialTempo &&
            _listsEqual(other.measures, measures));
  }

  @override
  int get hashCode => Object.hash(
    title,
    artist,
    scale,
    timeSignature,
    initialTempo,
    Object.hashAll(measures),
  );
}

bool _listsEqual<T>(List<T> a, List<T> b) {
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
