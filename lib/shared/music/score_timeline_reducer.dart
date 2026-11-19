import 'package:piano_exercises/shared/music/clef.dart';
import 'package:piano_exercises/shared/music/key_signature.dart';
import 'package:piano_exercises/shared/music/pitch_class.dart';
import 'package:piano_exercises/shared/music/rhythm.dart';
import 'package:piano_exercises/shared/music/score.dart';
import 'package:piano_exercises/shared/music/score_slice_builder.dart';
import 'package:piano_exercises/shared/music/score_timeline_inputs.dart';
import 'package:piano_exercises/shared/music/staff_note.dart';

export 'package:piano_exercises/shared/music/score_timeline_inputs.dart'
    show MeasureTimelineInput, NoteTimelineInput, RestTimelineInput;

/// Pure reducer turning raw measure timelines into an engraved/playable [Score].
abstract final class ScoreTimelineReducer {
  /// Resolves key/intra-measure accidentals and groups simultaneous [ScoreSlice]s.
  static Score reduce({
    required String title,
    String artist = '',
    Scale? initialScale,
    TimeSignature? initialTimeSignature,
    TempoMark? initialTempo,
    required List<MeasureTimelineInput> measures,
  }) {
    final first = measures.isEmpty ? null : measures.first;
    final scoreScale =
        initialScale ??
        Scale.fromKeySignature(first?.keySignature ?? KeySignature.cMajor);
    final scoreTime =
        initialTimeSignature ?? first?.timeSignature ?? TimeSignature.common;
    var activeKey = scoreScale.keySignature;
    var activeTime = scoreTime;
    var nextSliceIndex = 0;
    final reducedMeasures = <ScoreMeasure>[];
    for (final measureInput in measures) {
      activeKey = measureInput.keySignature ?? activeKey;
      activeTime = measureInput.timeSignature ?? activeTime;
      final (measure, updatedIndex) = _reduceMeasure(
        measureInput,
        activeKey: activeKey,
        activeTime: activeTime,
        startSliceIndex: nextSliceIndex,
      );
      nextSliceIndex = updatedIndex;
      reducedMeasures.add(measure);
    }
    return Score(
      title: title,
      artist: artist,
      scale: scoreScale,
      timeSignature: scoreTime,
      initialTempo: initialTempo ?? _findFirstTempo(measures),
      measures: reducedMeasures,
    );
  }

  static (ScoreMeasure, int) _reduceMeasure(
    MeasureTimelineInput measureInput, {
    required KeySignature activeKey,
    required TimeSignature activeTime,
    required int startSliceIndex,
  }) {
    final notesByOffset = <RationalBeats, List<ScoreNote>>{};
    final restsByOffset = <RationalBeats, List<RestEvent>>{};
    final noteMaxEnd = _collectNotes(
      measureInput.notes,
      activeKey: activeKey,
      notesByOffset: notesByOffset,
    );
    final restMaxEnd = _collectRests(
      measureInput.rests,
      restsByOffset: restsByOffset,
    );
    final maxEnd = noteMaxEnd > restMaxEnd ? noteMaxEnd : restMaxEnd;
    final (slices, nextSliceIndex) = _buildMeasureSlices(
      measureNumber: measureInput.measureNumber,
      activeTime: activeTime,
      startSliceIndex: startSliceIndex,
      maxEndOffset: maxEnd,
      notesByOffset: notesByOffset,
      restsByOffset: restsByOffset,
    );
    return (
      ScoreMeasure(
        measureNumber: measureInput.measureNumber,
        slices: slices,
        keySignature: measureInput.keySignature,
        timeSignature: measureInput.timeSignature,
        tempoMark: measureInput.tempoMark,
      ),
      nextSliceIndex,
    );
  }

  static RationalBeats _collectNotes(
    List<NoteTimelineInput> rawNotes, {
    required KeySignature activeKey,
    required Map<RationalBeats, List<ScoreNote>> notesByOffset,
  }) {
    // Accidental alterations reset at every barline.
    final activeAlterations = <(Clef, DiatonicNote, int), Accidental>{};
    var maxEnd = const RationalBeats.zero();
    for (final input in List<NoteTimelineInput>.of(
      rawNotes,
    )..sort(compareNoteTimelineInputs)) {
      final note = _resolveScoreNote(
        input,
        activeKey: activeKey,
        activeAlterations: activeAlterations,
      );
      notesByOffset
          .putIfAbsent(input.beatOffset, () => <ScoreNote>[])
          .add(note);
      final end = input.beatOffset + input.duration.quarterBeats;
      if (end > maxEnd) {
        maxEnd = end;
      }
    }
    return maxEnd;
  }

  static RationalBeats _collectRests(
    List<RestTimelineInput> rawRests, {
    required Map<RationalBeats, List<RestEvent>> restsByOffset,
  }) {
    var maxEnd = const RationalBeats.zero();
    for (final input in List<RestTimelineInput>.of(
      rawRests,
    )..sort(compareRestTimelineInputs)) {
      final rest = RestEvent(
        clef: input.clef,
        duration: input.duration,
        voice: input.voice,
      );
      restsByOffset
          .putIfAbsent(input.beatOffset, () => <RestEvent>[])
          .add(rest);
      final end = input.beatOffset + input.duration.quarterBeats;
      if (end > maxEnd) {
        maxEnd = end;
      }
    }
    return maxEnd;
  }

  static (List<ScoreSlice>, int) _buildMeasureSlices({
    required int measureNumber,
    required TimeSignature activeTime,
    required int startSliceIndex,
    required RationalBeats maxEndOffset,
    required Map<RationalBeats, List<ScoreNote>> notesByOffset,
    required Map<RationalBeats, List<RestEvent>> restsByOffset,
  }) {
    final offsets = <RationalBeats>{
      ...notesByOffset.keys,
      ...restsByOffset.keys,
    }.toList()..sort();
    final measureEnd = maxEndOffset.isZero
        ? activeTime.measureQuarterBeats
        : maxEndOffset;
    var nextSliceIndex = startSliceIndex;
    final slices = <ScoreSlice>[];
    for (var i = 0; i < offsets.length; i += 1) {
      final offset = offsets[i];
      final nextOffset = (i + 1 < offsets.length) ? offsets[i + 1] : measureEnd;
      slices.add(
        buildScoreSlice(
          sliceIndex: nextSliceIndex++,
          measureNumber: measureNumber,
          beatOffset: offset,
          beatDuration: nextOffset - offset,
          notes: notesByOffset[offset] ?? const <ScoreNote>[],
          rests: restsByOffset[offset] ?? const <RestEvent>[],
        ),
      );
    }
    return (slices, nextSliceIndex);
  }

  static TempoMark? _findFirstTempo(List<MeasureTimelineInput> measures) {
    for (final measure in measures) {
      if (measure.tempoMark != null) {
        return measure.tempoMark;
      }
    }
    return null;
  }

  static ScoreNote _resolveScoreNote(
    NoteTimelineInput input, {
    required KeySignature activeKey,
    required Map<(Clef, DiatonicNote, int), Accidental> activeAlterations,
  }) {
    final key = (input.clef, input.diatonicNote, input.octave);
    final currentActive =
        activeAlterations[key] ??
        activeKey.defaultAccidentalFor(input.diatonicNote);
    final resolvedAccidental = input.explicitAlter != null
        ? Accidental.fromSemitoneDelta(input.explicitAlter!)
        : (input.writtenAccidental ?? currentActive);
    final showAccidental = input.tie.requiresAttack
        ? (input.writtenAccidental != null ||
              resolvedAccidental != currentActive)
        : input.writtenAccidental != null;
    // Update bar accidental state only on new attacks or explicit cautionary accidentals.
    if (input.tie.requiresAttack || input.writtenAccidental != null) {
      activeAlterations[key] = resolvedAccidental;
    }

    return ScoreNote(
      staffNote: StaffNote.validated(
        note: input.diatonicNote,
        octave: input.octave,
        clef: input.clef,
        accidental: resolvedAccidental,
      ),
      duration: input.duration,
      tie: input.tie,
      showAccidental: showAccidental,
      voice: input.voice,
      beamGroupId: input.beamGroupId,
    );
  }
}
