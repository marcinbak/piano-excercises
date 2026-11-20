import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_tie_and_ripple_ops.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_timeline_ops.dart';
import 'package:piano_exercises/shared/music/music.dart';

export 'package:piano_exercises/features/score_editor/domain/score_draft_pitch_mutations.dart'
    show ScoreDraftPitchMutations;
export 'package:piano_exercises/features/score_editor/domain/score_draft_setup_mutations.dart'
    show ScoreDraftSetupMutations;

/// Step-time MIDI, rhythm, measure, and setup mutations for [ScoreDraft].
extension ScoreDraftMutations on ScoreDraft {
  /// Enters a coalesced MIDI chord at [cursor], splitting across barlines and advancing cursor.
  ScoreDraft enterMidiChord(Set<MidiNote> midiNotes) {
    if (midiNotes.isEmpty) {
      return this;
    }
    final activeKey = activeKeySignatureAt(cursor.measureIndex);
    final sorted = midiNotes.toList()..sort();
    final entries = <({StaffNote staffNote, Accidental? explicitAccidental})>[
      for (final midi in sorted)
        (
          staffNote: KeyPitchSpeller.spellMidiNote(
            midi,
            clef: _clefForMidi(midi),
            keySignature: activeKey,
          ),
          explicitAccidental: null,
        ),
    ];
    final affectedClefs = <Clef>{for (final e in entries) e.staffNote.clef};
    final plan = planBarlineSegments(
      this,
      start: cursor,
      totalBeats: selectedDuration.quarterBeats,
    );
    if (plan.segments.isEmpty) {
      return this;
    }
    writeSegmentedChord(
      plan.measures,
      draft: this,
      segments: plan.segments,
      entries: entries,
      affectedClefs: affectedClefs,
    );
    return copyWith(measures: plan.measures, cursor: plan.nextCursor);
  }

  /// Moves [cursor] to the measure and beat offset of [sliceIndex] in [score].
  ScoreDraft selectSlice(Score score, int sliceIndex) {
    for (var mIdx = 0; mIdx < score.measures.length; mIdx += 1) {
      for (final slice in score.measures[mIdx].slices) {
        if (slice.sliceIndex == sliceIndex && mIdx < measures.length) {
          return copyWith(
            cursor: EditorCursor(
              measureIndex: mIdx,
              beatOffset: slice.beatOffset,
            ),
          );
        }
      }
    }
    return this;
  }

  /// Steps [cursor] backward to the previous slice position in the score.
  ScoreDraft moveCursorPrev() {
    final positions = _orderedSlicePositions();
    final idx = positions.lastIndexWhere(
      (pos) =>
          pos.measureIndex < cursor.measureIndex ||
          (pos.measureIndex == cursor.measureIndex &&
              pos.beatOffset < cursor.beatOffset),
    );
    return idx < 0 ? this : copyWith(cursor: positions[idx]);
  }

  /// Steps [cursor] forward to the next slice position in the score.
  ScoreDraft moveCursorNext() {
    final positions = _orderedSlicePositions();
    final idx = positions.indexWhere(
      (pos) =>
          pos.measureIndex > cursor.measureIndex ||
          (pos.measureIndex == cursor.measureIndex &&
              pos.beatOffset > cursor.beatOffset),
    );
    return idx < 0 ? this : copyWith(cursor: positions[idx]);
  }

  /// Updates [selectedDuration] base value and re-times notes sitting at [cursor].
  ScoreDraft setBaseDuration(NoteBaseDuration base) {
    final nextDuration = DurationValue(base: base, dots: selectedDuration.dots);
    return _applySelectedDuration(nextDuration);
  }

  /// Toggles single-dot augmentation on [selectedDuration] and re-times notes at [cursor].
  ScoreDraft toggleDot() {
    final nextDots = selectedDuration.dots == 0 ? 1 : 0;
    final nextDuration = DurationValue(
      base: selectedDuration.base,
      dots: nextDots,
    );
    return _applySelectedDuration(nextDuration);
  }

  /// Clears notes across `[cursor, cursor + selectedDuration)` and advances cursor.
  ScoreDraft insertRest() {
    final plan = planBarlineSegments(
      this,
      start: cursor,
      totalBeats: selectedDuration.quarterBeats,
    );
    if (plan.segments.isEmpty) {
      return this;
    }
    for (final seg in plan.segments) {
      final cleared = clearNoteSpanInMeasure(
        plan.measures[seg.measureIndex],
        clefs: const <Clef>{Clef.treble, Clef.bass},
        start: seg.beatOffset,
        end: seg.endOffset,
      );
      plan.measures[seg.measureIndex] = cleared.measure;
      healNeighborTies(
        this,
        plan.measures,
        measureIdx: seg.measureIndex,
        removed: cleared.brokenNotes,
      );
    }
    return copyWith(measures: plan.measures, cursor: plan.nextCursor);
  }

  /// Inserts a rest gap of [selectedDuration] at [cursor], shifting later notes right.
  ScoreDraft insertEmptySlice() {
    final nextMeasures = rippleInsertGap(
      this,
      cursor: cursor,
      delta: selectedDuration.quarterBeats,
    );
    return copyWith(measures: nextMeasures);
  }

  /// Removes all notes starting at [cursor] and heals broken neighbor ties.
  ScoreDraft deleteAtCursor() {
    final current = notesAtCursor;
    if (current.isEmpty) {
      return this;
    }
    final nextMeasures = List<DraftMeasure>.of(measures);
    final measure = nextMeasures[cursor.measureIndex];
    final remaining = measure.notes
        .where((n) => n.beatOffset != cursor.beatOffset)
        .toList(growable: false);
    nextMeasures[cursor.measureIndex] = measure.copyWith(notes: remaining);
    healNeighborTies(
      this,
      nextMeasures,
      measureIdx: cursor.measureIndex,
      removed: current,
    );
    return copyWith(measures: nextMeasures);
  }

  /// Toggles ties on note(s) at [cursor] (pairing with the next matching pitch when present).
  ScoreDraft toggleTieAtCursor({int? noteIndex}) {
    final current = notesAtCursor;
    if (current.isEmpty) {
      return this;
    }
    final targets =
        (noteIndex != null && noteIndex >= 0 && noteIndex < current.length)
        ? <DraftNoteEvent>[current[noteIndex]]
        : current;
    final nextMeasures = List<DraftMeasure>.of(measures);

    for (final target in targets) {
      final hasOutgoing =
          target.tie == TieType.start || target.tie == TieType.continueTie;
      final nextSelfTie = hasOutgoing
          ? (target.tie == TieType.continueTie ? TieType.stop : TieType.none)
          : (target.tie == TieType.stop ? TieType.continueTie : TieType.start);
      replaceSingleDraftNote(
        nextMeasures,
        cursor.measureIndex,
        target,
        target.copyWith(tie: nextSelfTie),
      );
      toggleNextPartnerTie(
        this,
        nextMeasures,
        sourceMeasureIdx: cursor.measureIndex,
        source: target,
        enableTie: !hasOutgoing,
      );
    }
    return copyWith(measures: nextMeasures);
  }

  ScoreDraft _applySelectedDuration(DurationValue nextDuration) {
    final current = notesAtCursor;
    if (current.isEmpty) {
      return copyWith(selectedDuration: nextDuration);
    }
    final nextMeasures = List<DraftMeasure>.of(measures);
    final dm = nextMeasures[cursor.measureIndex];
    nextMeasures[cursor.measureIndex] = dm.copyWith(
      notes: dm.notes
          .where((n) => n.beatOffset != cursor.beatOffset)
          .toList(growable: false),
    );
    healNeighborTies(
      this,
      nextMeasures,
      measureIdx: cursor.measureIndex,
      removed: current,
    );

    final tempDraft = copyWith(
      measures: nextMeasures,
      selectedDuration: nextDuration,
    );
    final plan = planBarlineSegments(
      tempDraft,
      start: cursor,
      totalBeats: nextDuration.quarterBeats,
    );
    if (plan.segments.isEmpty) {
      return copyWith(selectedDuration: nextDuration);
    }
    final affectedClefs = <Clef>{for (final n in current) n.staffNote.clef};
    final entries = <({StaffNote staffNote, Accidental? explicitAccidental})>[
      for (final n in current)
        (staffNote: n.staffNote, explicitAccidental: n.explicitAccidental),
    ];
    writeSegmentedChord(
      plan.measures,
      draft: tempDraft,
      segments: plan.segments,
      entries: entries,
      affectedClefs: affectedClefs,
    );
    return copyWith(measures: plan.measures, selectedDuration: nextDuration);
  }

  List<EditorCursor> _orderedSlicePositions() {
    final score = toScore();
    return <EditorCursor>[
      for (var mIdx = 0; mIdx < score.measures.length; mIdx += 1)
        for (final slice in score.measures[mIdx].slices)
          EditorCursor(measureIndex: mIdx, beatOffset: slice.beatOffset),
    ];
  }

  Clef _clefForMidi(MidiNote midi) => switch (clefMode) {
    ClefAssignmentMode.trebleOnly => Clef.treble,
    ClefAssignmentMode.bassOnly => Clef.bass,
    ClefAssignmentMode.autoSplit =>
      midi.number >= splitPointMidi ? Clef.treble : Clef.bass,
  };
}
