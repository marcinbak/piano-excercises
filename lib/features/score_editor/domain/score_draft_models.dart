import 'package:piano_exercises/shared/music/music.dart';

/// How MIDI note input maps to treble vs bass staves in the score editor.
enum ClefAssignmentMode {
  autoSplit('Auto Split'),
  trebleOnly('Treble Only'),
  bassOnly('Bass Only');

  const ClefAssignmentMode(this.label);

  final String label;
}

/// Active measure and measure-relative beat offset in a [ScoreDraft].
final class EditorCursor {
  const EditorCursor({
    required this.measureIndex,
    this.beatOffset = const RationalBeats.zero(),
  }) : assert(measureIndex >= 0);

  final int measureIndex;
  final RationalBeats beatOffset;

  EditorCursor copyWith({int? measureIndex, RationalBeats? beatOffset}) {
    return EditorCursor(
      measureIndex: measureIndex ?? this.measureIndex,
      beatOffset: beatOffset ?? this.beatOffset,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is EditorCursor &&
            other.measureIndex == measureIndex &&
            other.beatOffset == beatOffset);
  }

  @override
  int get hashCode => Object.hash(measureIndex, beatOffset);
}

/// Mutable-timeline note representation preserving independent treble/bass durations.
final class DraftNoteEvent {
  const DraftNoteEvent({
    required this.staffNote,
    required this.beatOffset,
    required this.duration,
    this.tie = TieType.none,
    this.voice = 1,
    this.explicitAccidental,
  });

  final StaffNote staffNote;
  final RationalBeats beatOffset;
  final DurationValue duration;
  final TieType tie;
  final int voice;
  final Accidental? explicitAccidental;

  RationalBeats get endOffset => beatOffset + duration.quarterBeats;

  DraftNoteEvent copyWith({
    StaffNote? staffNote,
    RationalBeats? beatOffset,
    DurationValue? duration,
    TieType? tie,
    int? voice,
    Accidental? explicitAccidental,
    bool clearExplicitAccidental = false,
  }) {
    return DraftNoteEvent(
      staffNote: staffNote ?? this.staffNote,
      beatOffset: beatOffset ?? this.beatOffset,
      duration: duration ?? this.duration,
      tie: tie ?? this.tie,
      voice: voice ?? this.voice,
      explicitAccidental: clearExplicitAccidental
          ? null
          : (explicitAccidental ?? this.explicitAccidental),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DraftNoteEvent &&
            other.staffNote == staffNote &&
            other.beatOffset == beatOffset &&
            other.duration == duration &&
            other.tie == tie &&
            other.voice == voice &&
            other.explicitAccidental == explicitAccidental);
  }

  @override
  int get hashCode => Object.hash(
    staffNote,
    beatOffset,
    duration,
    tie,
    voice,
    explicitAccidental,
  );
}

/// Single editable bar of [DraftNoteEvent]s with optional measure-level changes.
final class DraftMeasure {
  DraftMeasure({
    required this.measureNumber,
    List<DraftNoteEvent> notes = const <DraftNoteEvent>[],
    this.keySignature,
    this.timeSignature,
    this.tempoMark,
  }) : notes = List<DraftNoteEvent>.unmodifiable(
         List<DraftNoteEvent>.of(notes)..sort(compareDraftNotes),
       );

  final int measureNumber;
  final List<DraftNoteEvent> notes;
  final KeySignature? keySignature;
  final TimeSignature? timeSignature;
  final TempoMark? tempoMark;

  DraftMeasure copyWith({
    int? measureNumber,
    List<DraftNoteEvent>? notes,
    KeySignature? keySignature,
    TimeSignature? timeSignature,
    TempoMark? tempoMark,
    bool clearKeySignature = false,
    bool clearTimeSignature = false,
    bool clearTempoMark = false,
  }) {
    return DraftMeasure(
      measureNumber: measureNumber ?? this.measureNumber,
      notes: notes ?? this.notes,
      keySignature: clearKeySignature
          ? null
          : (keySignature ?? this.keySignature),
      timeSignature: clearTimeSignature
          ? null
          : (timeSignature ?? this.timeSignature),
      tempoMark: clearTempoMark ? null : (tempoMark ?? this.tempoMark),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DraftMeasure &&
            other.measureNumber == measureNumber &&
            draftListsEqual(other.notes, notes) &&
            other.keySignature == keySignature &&
            other.timeSignature == timeSignature &&
            other.tempoMark == tempoMark);
  }

  @override
  int get hashCode => Object.hash(
    measureNumber,
    Object.hashAll(notes),
    keySignature,
    timeSignature,
    tempoMark,
  );
}

/// Canonical deterministic ordering for [DraftNoteEvent]s within a measure.
int compareDraftNotes(DraftNoteEvent a, DraftNoteEvent b) {
  final offsetCmp = a.beatOffset.compareTo(b.beatOffset);
  if (offsetCmp != 0) {
    return offsetCmp;
  }
  final clefCmp = a.staffNote.clef.index.compareTo(b.staffNote.clef.index);
  if (clefCmp != 0) {
    return clefCmp;
  }
  final stepCmp = a.staffNote.diatonicStep.compareTo(b.staffNote.diatonicStep);
  if (stepCmp != 0) {
    return stepCmp;
  }
  final midiCmp = a.staffNote.midiNote.number.compareTo(
    b.staffNote.midiNote.number,
  );
  return midiCmp != 0 ? midiCmp : a.voice.compareTo(b.voice);
}

bool draftListsEqual<T>(List<T> a, List<T> b) {
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
