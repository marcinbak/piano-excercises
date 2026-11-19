import 'package:piano_exercises/shared/music/clef.dart';
import 'package:piano_exercises/shared/music/key_signature.dart';
import 'package:piano_exercises/shared/music/pitch_class.dart';
import 'package:piano_exercises/shared/music/rhythm.dart';
import 'package:piano_exercises/shared/music/score.dart';
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
    final scoreScale = _resolveInitialScale(initialScale, measures);
    final scoreTimeSignature = _resolveInitialTimeSignature(
      initialTimeSignature,
      measures,
    );
    final scoreInitialTempo = initialTempo ?? _findFirstTempo(measures);

    var activeKey = scoreScale.keySignature;
    var activeTime = scoreTimeSignature;
    var nextSliceIndex = 0;
    final reducedMeasures = <ScoreMeasure>[];

    for (final measureInput in measures) {
      if (measureInput.keySignature != null) {
        activeKey = measureInput.keySignature!;
      }
      if (measureInput.timeSignature != null) {
        activeTime = measureInput.timeSignature!;
      }

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
      timeSignature: scoreTimeSignature,
      initialTempo: scoreInitialTempo,
      measures: reducedMeasures,
    );
  }

  static (ScoreMeasure, int) _reduceMeasure(
    MeasureTimelineInput measureInput, {
    required KeySignature activeKey,
    required TimeSignature activeTime,
    required int startSliceIndex,
  }) {
    // Accidental alterations reset at every barline.
    final activeAlterations = <(Clef, DiatonicNote, int), Accidental>{};
    final notesByOffset = <RationalBeats, List<ScoreNote>>{};
    final restsByOffset = <RationalBeats, List<RestEvent>>{};
    var maxEndOffset = const RationalBeats.zero();

    final sortedNotes = List<NoteTimelineInput>.of(measureInput.notes)
      ..sort(compareNoteTimelineInputs);
    for (final input in sortedNotes) {
      final note = _resolveScoreNote(
        input,
        activeKey: activeKey,
        activeAlterations: activeAlterations,
      );
      notesByOffset
          .putIfAbsent(input.beatOffset, () => <ScoreNote>[])
          .add(note);
      final endOffset = input.beatOffset + input.duration.quarterBeats;
      if (endOffset > maxEndOffset) {
        maxEndOffset = endOffset;
      }
    }

    final sortedRests = List<RestTimelineInput>.of(measureInput.rests)
      ..sort(compareRestTimelineInputs);
    for (final restInput in sortedRests) {
      final rest = RestEvent(
        clef: restInput.clef,
        duration: restInput.duration,
        voice: restInput.voice,
      );
      restsByOffset
          .putIfAbsent(restInput.beatOffset, () => <RestEvent>[])
          .add(rest);
      final endOffset = restInput.beatOffset + restInput.duration.quarterBeats;
      if (endOffset > maxEndOffset) {
        maxEndOffset = endOffset;
      }
    }

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
        _buildSlice(
          sliceIndex: nextSliceIndex++,
          measureNumber: measureInput.measureNumber,
          beatOffset: offset,
          beatDuration: nextOffset - offset,
          notes: notesByOffset[offset] ?? const <ScoreNote>[],
          rests: restsByOffset[offset] ?? const <RestEvent>[],
        ),
      );
    }

    final measure = ScoreMeasure(
      measureNumber: measureInput.measureNumber,
      slices: slices,
      keySignature: measureInput.keySignature,
      timeSignature: measureInput.timeSignature,
      tempoMark: measureInput.tempoMark,
    );
    return (measure, nextSliceIndex);
  }

  static ScoreSlice _buildSlice({
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

  static Scale _resolveInitialScale(
    Scale? initialScale,
    List<MeasureTimelineInput> measures,
  ) {
    if (initialScale != null) {
      return initialScale;
    }
    final firstKey = measures.isEmpty ? null : measures.first.keySignature;
    return Scale.fromKeySignature(firstKey ?? KeySignature.cMajor);
  }

  static TimeSignature _resolveInitialTimeSignature(
    TimeSignature? initialTimeSignature,
    List<MeasureTimelineInput> measures,
  ) {
    if (initialTimeSignature != null) {
      return initialTimeSignature;
    }
    final firstTime = measures.isEmpty ? null : measures.first.timeSignature;
    return firstTime ?? TimeSignature.common;
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
    final showAccidental =
        input.writtenAccidental != null || resolvedAccidental != currentActive;
    activeAlterations[key] = resolvedAccidental;

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

  static RestEvent? _firstRestForClef(List<RestEvent> rests, Clef clef) {
    for (final rest in rests) {
      if (rest.clef == clef) {
        return rest;
      }
    }
    return null;
  }

  static int _compareSliceNotes(ScoreNote a, ScoreNote b) {
    final stepCmp = a.staffNote.diatonicStep.compareTo(
      b.staffNote.diatonicStep,
    );
    return stepCmp != 0
        ? stepCmp
        : a.midiNote.number.compareTo(b.midiNote.number);
  }
}
