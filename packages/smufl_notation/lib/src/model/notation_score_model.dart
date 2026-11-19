import 'package:smufl_notation/src/model/notation_model.dart';

/// Simultaneous rhythmic event across treble and bass staves.
final class NotationSlice {
  NotationSlice({
    required this.sliceIndex,
    required this.beatDuration,
    this.trebleChord,
    this.trebleRest,
    this.bassChord,
    this.bassRest,
  }) {
    RangeError.checkNotNegative(sliceIndex, 'sliceIndex');
    if (!beatDuration.isFinite || beatDuration <= 0) {
      throw ArgumentError.value(
        beatDuration,
        'beatDuration',
        'must be positive and finite',
      );
    }
    if (trebleChord != null && trebleRest != null) {
      throw ArgumentError('Treble staff cannot hold both a chord and a rest');
    }
    if (bassChord != null && bassRest != null) {
      throw ArgumentError('Bass staff cannot hold both a chord and a rest');
    }
    if (trebleChord != null && trebleChord!.clef != SmuflClef.treble) {
      throw ArgumentError('trebleChord must use SmuflClef.treble');
    }
    if (trebleRest != null && trebleRest!.clef != SmuflClef.treble) {
      throw ArgumentError('trebleRest must use SmuflClef.treble');
    }
    if (bassChord != null && bassChord!.clef != SmuflClef.bass) {
      throw ArgumentError('bassChord must use SmuflClef.bass');
    }
    if (bassRest != null && bassRest!.clef != SmuflClef.bass) {
      throw ArgumentError('bassRest must use SmuflClef.bass');
    }
  }

  final int sliceIndex;
  final double beatDuration;
  final NotationChord? trebleChord;
  final NotationRest? trebleRest;
  final NotationChord? bassChord;
  final NotationRest? bassRest;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is NotationSlice &&
            other.sliceIndex == sliceIndex &&
            other.beatDuration == beatDuration &&
            other.trebleChord == trebleChord &&
            other.trebleRest == trebleRest &&
            other.bassChord == bassChord &&
            other.bassRest == bassRest);
  }

  @override
  int get hashCode => Object.hash(
    sliceIndex,
    beatDuration,
    trebleChord,
    trebleRest,
    bassChord,
    bassRest,
  );
}

/// Single bar containing ordered [slices] and optional key/meter changes.
final class NotationMeasure {
  NotationMeasure({
    required this.measureNumber,
    required List<NotationSlice> slices,
    this.keyFifths,
    this.beats,
    this.beatType,
  }) : slices = List<NotationSlice>.unmodifiable(slices) {
    if (measureNumber < 1) {
      throw RangeError.range(measureNumber, 1, null, 'measureNumber');
    }
    if (keyFifths != null) {
      RangeError.checkValueInInterval(keyFifths!, -7, 7, 'keyFifths');
    }
    if ((beats == null) != (beatType == null)) {
      throw ArgumentError('beats and beatType must both be set or both null');
    }
    if (beats != null) {
      RangeError.checkValueInInterval(beats!, 1, 32, 'beats');
    }
    if (beatType != null && !_validBeatTypes.contains(beatType)) {
      throw ArgumentError.value(
        beatType,
        'beatType',
        'must be a power of two in 1..32',
      );
    }
  }

  static const Set<int> _validBeatTypes = <int>{1, 2, 4, 8, 16, 32};

  final int measureNumber;
  final List<NotationSlice> slices;
  final int? keyFifths;
  final int? beats;
  final int? beatType;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is NotationMeasure &&
            other.measureNumber == measureNumber &&
            other.keyFifths == keyFifths &&
            other.beats == beats &&
            other.beatType == beatType &&
            _sliceListsEqual(other.slices, slices));
  }

  @override
  int get hashCode => Object.hash(
    measureNumber,
    keyFifths,
    beats,
    beatType,
    Object.hashAll(slices),
  );
}

/// Complete multi-measure piano grand-staff score.
final class NotationScore {
  NotationScore({
    required this.title,
    required List<NotationMeasure> measures,
    this.subtitle = '',
  }) : measures = List<NotationMeasure>.unmodifiable(measures);

  final String title;
  final String subtitle;
  final List<NotationMeasure> measures;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is NotationScore &&
            other.title == title &&
            other.subtitle == subtitle &&
            _measureListsEqual(other.measures, measures));
  }

  @override
  int get hashCode => Object.hash(title, subtitle, Object.hashAll(measures));
}

/// Red wrong-note MIDI chord overlay anchored to [sliceIndex].
final class WrongNoteOverlay {
  WrongNoteOverlay({
    required this.sliceIndex,
    required List<NotationNote> notes,
  }) : notes = List<NotationNote>.unmodifiable(notes) {
    RangeError.checkNotNegative(sliceIndex, 'sliceIndex');
  }

  final int sliceIndex;
  final List<NotationNote> notes;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is WrongNoteOverlay &&
            other.sliceIndex == sliceIndex &&
            _noteListsEqual(other.notes, notes));
  }

  @override
  int get hashCode => Object.hash(sliceIndex, Object.hashAll(notes));
}

bool _sliceListsEqual(List<NotationSlice> a, List<NotationSlice> b) {
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

bool _measureListsEqual(List<NotationMeasure> a, List<NotationMeasure> b) {
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

bool _noteListsEqual(List<NotationNote> a, List<NotationNote> b) {
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
