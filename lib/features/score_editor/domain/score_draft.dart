import 'package:piano_exercises/features/score_editor/domain/editor_beam_assigner.dart';
import 'package:piano_exercises/features/score_editor/domain/rhythm_duration_splitter.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_models.dart';
import 'package:piano_exercises/shared/music/music.dart';

export 'package:piano_exercises/features/score_editor/domain/score_draft_models.dart'
    show
        ClefAssignmentMode,
        DraftMeasure,
        DraftNoteEvent,
        EditorCursor,
        compareDraftNotes,
        effectiveDraftMeasureBeats;

/// Immutable score-editor document state lowered to a playable [Score] on demand.
final class ScoreDraft {
  ScoreDraft({
    this.title = 'Untitled',
    this.artist = '',
    Scale? scale,
    this.timeSignature = TimeSignature.common,
    this.initialTempo,
    List<DraftMeasure>? measures,
    this.splitPointMidi = 60,
    this.clefMode = ClefAssignmentMode.autoSplit,
    DurationValue? selectedDuration,
    this.cursor = const EditorCursor(measureIndex: 0),
  }) : scale = scale ?? Scale.fromKeySignature(KeySignature.cMajor),
       measures = List<DraftMeasure>.unmodifiable(
         (measures == null || measures.isEmpty) ? defaultMeasures() : measures,
       ),
       selectedDuration =
           selectedDuration ?? DurationValue(base: NoteBaseDuration.quarter);

  /// Reconstructs an editable [ScoreDraft] from an existing [Score], keeping
  /// independent treble/bass note durations intact.
  factory ScoreDraft.fromScore(Score score) {
    final draftMeasures = <DraftMeasure>[
      for (final measure in score.measures)
        DraftMeasure(
          measureNumber: measure.measureNumber,
          keySignature: measure.keySignature,
          timeSignature: measure.timeSignature,
          tempoMark: measure.tempoMark,
          notes: <DraftNoteEvent>[
            for (final slice in measure.slices)
              for (final note in <ScoreNote>[
                ...slice.trebleNotes,
                ...slice.bassNotes,
              ])
                DraftNoteEvent(
                  staffNote: note.staffNote,
                  beatOffset: slice.beatOffset,
                  duration: note.duration,
                  tie: note.tie,
                  voice: note.voice,
                  explicitAccidental: note.showAccidental
                      ? note.staffNote.accidental
                      : null,
                ),
          ],
        ),
    ];
    return ScoreDraft(
      title: score.title,
      artist: score.artist,
      scale: score.scale,
      timeSignature: score.timeSignature,
      initialTempo: score.initialTempo,
      measures: draftMeasures.isEmpty ? defaultMeasures() : draftMeasures,
    );
  }

  static const int maxMeasures = 2000;

  final String title;
  final String artist;
  final Scale scale;
  final TimeSignature timeSignature;
  final TempoMark? initialTempo;
  final List<DraftMeasure> measures;
  final int splitPointMidi;
  final ClefAssignmentMode clefMode;
  final DurationValue selectedDuration;
  final EditorCursor cursor;

  /// Active [KeySignature] governing [measureIndex].
  KeySignature activeKeySignatureAt(int measureIndex) {
    var active = scale.keySignature;
    final limit = measureIndex.clamp(0, measures.length - 1);
    for (var i = 0; i <= limit; i += 1) {
      if (measures[i].keySignature != null) {
        active = measures[i].keySignature!;
      }
    }
    return active;
  }

  /// Active [TimeSignature] governing [measureIndex].
  TimeSignature activeTimeSignatureAt(int measureIndex) {
    var active = timeSignature;
    final limit = measureIndex.clamp(0, measures.length - 1);
    for (var i = 0; i <= limit; i += 1) {
      if (measures[i].timeSignature != null) {
        active = measures[i].timeSignature!;
      }
    }
    return active;
  }

  /// Ordered notes at [cursor] (`treble` then `bass`, low-to-high pitch).
  List<DraftNoteEvent> get notesAtCursor {
    final measure = measures[cursor.measureIndex];
    final matches = measure.notes
        .where((n) => n.beatOffset == cursor.beatOffset)
        .toList(growable: false);
    return List<DraftNoteEvent>.unmodifiable(matches);
  }

  /// Resolves the best-matching `sliceIndex` in [score] for [cursor].
  int? activeSliceIndexIn(Score score) {
    if (cursor.measureIndex < 0 ||
        cursor.measureIndex >= score.measures.length) {
      return null;
    }
    final measureSlices = score.measures[cursor.measureIndex].slices;
    if (measureSlices.isEmpty) {
      return null;
    }
    ScoreSlice best = measureSlices.first;
    for (final slice in measureSlices) {
      if (slice.beatOffset <= cursor.beatOffset) {
        best = slice;
      } else {
        break;
      }
    }
    return best.sliceIndex;
  }

  /// Lowers this draft to an engravable and playable [Score].
  Score toScore() {
    var activeTime = timeSignature;
    final timelineMeasures = <MeasureTimelineInput>[];
    for (var i = 0; i < measures.length; i += 1) {
      final dm = measures[i];
      activeTime = dm.timeSignature ?? activeTime;
      final effectiveMeasureBeats = effectiveDraftMeasureBeats(
        timeSignature,
        measures,
        i,
      );
      final rawNotes = <NoteTimelineInput>[
        for (final note in dm.notes)
          NoteTimelineInput(
            clef: note.staffNote.clef,
            diatonicNote: note.staffNote.note,
            octave: note.staffNote.octave,
            explicitAlter: note.staffNote.accidental.semitoneDelta,
            writtenAccidental: note.explicitAccidental,
            beatOffset: note.beatOffset,
            duration: note.duration,
            tie: note.tie,
            voice: note.voice,
          ),
      ];
      final beamedNotes = EditorBeamAssigner.assign(
        measureNumber: dm.measureNumber,
        timeSignature: activeTime,
        notes: rawNotes,
      );
      final trebleRests = fillRestGaps(
        measureBeats: effectiveMeasureBeats,
        occupiedSpans: dm.notes
            .where((n) => n.staffNote.clef == Clef.treble)
            .map((n) => (start: n.beatOffset, end: n.endOffset)),
        clef: Clef.treble,
      );
      final bassRests = fillRestGaps(
        measureBeats: effectiveMeasureBeats,
        occupiedSpans: dm.notes
            .where((n) => n.staffNote.clef == Clef.bass)
            .map((n) => (start: n.beatOffset, end: n.endOffset)),
        clef: Clef.bass,
      );
      timelineMeasures.add(
        MeasureTimelineInput(
          measureNumber: dm.measureNumber,
          keySignature: dm.keySignature,
          timeSignature: dm.timeSignature,
          tempoMark: dm.tempoMark,
          notes: beamedNotes,
          rests: <RestTimelineInput>[...trebleRests, ...bassRests],
        ),
      );
    }
    return ScoreTimelineReducer.reduce(
      title: title,
      artist: artist,
      initialScale: scale,
      initialTimeSignature: timeSignature,
      initialTempo: initialTempo,
      measures: timelineMeasures,
    );
  }

  ScoreDraft copyWith({
    String? title,
    String? artist,
    Scale? scale,
    TimeSignature? timeSignature,
    TempoMark? initialTempo,
    bool clearInitialTempo = false,
    List<DraftMeasure>? measures,
    int? splitPointMidi,
    ClefAssignmentMode? clefMode,
    DurationValue? selectedDuration,
    EditorCursor? cursor,
  }) {
    return ScoreDraft(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      scale: scale ?? this.scale,
      timeSignature: timeSignature ?? this.timeSignature,
      initialTempo: clearInitialTempo
          ? null
          : (initialTempo ?? this.initialTempo),
      measures: measures ?? this.measures,
      splitPointMidi: splitPointMidi ?? this.splitPointMidi,
      clefMode: clefMode ?? this.clefMode,
      selectedDuration: selectedDuration ?? this.selectedDuration,
      cursor: cursor ?? this.cursor,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScoreDraft &&
            other.title == title &&
            other.artist == artist &&
            other.scale == scale &&
            other.timeSignature == timeSignature &&
            other.initialTempo == initialTempo &&
            draftListsEqual(other.measures, measures) &&
            other.splitPointMidi == splitPointMidi &&
            other.clefMode == clefMode &&
            other.selectedDuration == selectedDuration &&
            other.cursor == cursor);
  }

  @override
  int get hashCode => Object.hash(
    title,
    artist,
    scale,
    timeSignature,
    initialTempo,
    Object.hashAll(measures),
    splitPointMidi,
    clefMode,
    selectedDuration,
    cursor,
  );

  /// Default four empty `4/4` bars starting at measure `1`.
  static List<DraftMeasure> defaultMeasures() => <DraftMeasure>[
    for (var i = 1; i <= 4; i += 1) DraftMeasure(measureNumber: i),
  ];
}
