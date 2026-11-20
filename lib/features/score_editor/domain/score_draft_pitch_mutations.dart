import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_tie_and_ripple_ops.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_timeline_ops.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Touch-input pitch and clef editing transitions for [ScoreDraft].
extension ScoreDraftPitchMutations on ScoreDraft {
  /// Adds a key-spelled `C4`/`C3` on an empty slice or a diatonic 3rd above the top note.
  ScoreDraft addTouchNote() {
    final current = notesAtCursor;
    final activeKey = activeKeySignatureAt(cursor.measureIndex);
    final targetClef = _resolveTouchTargetClef(current);
    final clefNotes = current
        .where((n) => n.staffNote.clef == targetClef)
        .toList(growable: false);

    if (clefNotes.isEmpty) {
      final defaultMidi = targetClef == Clef.treble
          ? const MidiNote(60)
          : const MidiNote(48);
      final spelled = KeyPitchSpeller.spellMidiNote(
        defaultMidi,
        clef: targetClef,
        keySignature: activeKey,
      );
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
        segments: plan.segments,
        entries: <({StaffNote staffNote, Accidental? explicitAccidental})>[
          (staffNote: spelled, explicitAccidental: null),
        ],
        affectedClefs: <Clef>{targetClef},
      );
      return copyWith(measures: plan.measures);
    }

    final top = clefNotes.last;
    var candidate = KeyPitchSpeller.stepDiatonic(
      top.staffNote,
      deltaSteps: 2,
      keySignature: activeKey,
    );
    if (clefNotes.any((n) => n.staffNote == candidate)) {
      candidate = KeyPitchSpeller.stepDiatonic(
        top.staffNote,
        deltaSteps: -2,
        keySignature: activeKey,
      );
      if (clefNotes.any((n) => n.staffNote == candidate)) {
        return this;
      }
    }
    final nextMeasures = List<DraftMeasure>.of(measures);
    final dm = nextMeasures[cursor.measureIndex];
    nextMeasures[cursor.measureIndex] = dm.copyWith(
      notes: <DraftNoteEvent>[
        ...dm.notes,
        DraftNoteEvent(
          staffNote: candidate,
          beatOffset: cursor.beatOffset,
          duration: top.duration,
        ),
      ],
    );
    return copyWith(measures: nextMeasures);
  }

  /// Steps the note at [noteIndex] within [notesAtCursor] by [deltaSteps] diatonically.
  ScoreDraft stepNotePitch(int noteIndex, int deltaSteps) {
    final current = notesAtCursor;
    if (deltaSteps == 0 || noteIndex < 0 || noteIndex >= current.length) {
      return this;
    }
    final target = current[noteIndex];
    final activeKey = activeKeySignatureAt(cursor.measureIndex);
    final stepped = KeyPitchSpeller.stepDiatonic(
      target.staffNote,
      deltaSteps: deltaSteps,
      keySignature: activeKey,
    );
    if (stepped == target.staffNote) {
      return this;
    }
    final nextMeasures = List<DraftMeasure>.of(measures);
    healNeighborTies(
      this,
      nextMeasures,
      measureIdx: cursor.measureIndex,
      removed: <DraftNoteEvent>[target],
    );
    replaceSingleDraftNote(
      nextMeasures,
      cursor.measureIndex,
      target,
      target.copyWith(
        staffNote: stepped,
        tie: TieType.none,
        clearExplicitAccidental: true,
      ),
    );
    return copyWith(measures: nextMeasures);
  }

  /// Sets [accidental] on note [noteIndex] (`null` resets to key-signature default).
  ScoreDraft setNoteAccidental(int noteIndex, Accidental? accidental) {
    final current = notesAtCursor;
    if (noteIndex < 0 || noteIndex >= current.length) {
      return this;
    }
    final target = current[noteIndex];
    final activeKey = activeKeySignatureAt(cursor.measureIndex);
    final StaffNote updatedStaffNote;
    final Accidental? forced;
    if (accidental == null) {
      final keyDefault = activeKey.defaultAccidentalFor(target.staffNote.note);
      updatedStaffNote = KeyPitchSpeller.withAccidental(
        target.staffNote,
        keyDefault,
      );
      forced = null;
    } else {
      updatedStaffNote = KeyPitchSpeller.withAccidental(
        target.staffNote,
        accidental,
      );
      forced = updatedStaffNote.accidental == accidental
          ? accidental
          : target.explicitAccidental;
    }
    final nextMeasures = List<DraftMeasure>.of(measures);
    replaceSingleDraftNote(
      nextMeasures,
      cursor.measureIndex,
      target,
      target.copyWith(
        staffNote: updatedStaffNote,
        explicitAccidental: forced,
        clearExplicitAccidental: forced == null,
      ),
    );
    return copyWith(measures: nextMeasures);
  }

  /// Moves note [noteIndex] at [cursor] between treble and bass clefs.
  ScoreDraft flipNoteClef(int noteIndex) {
    final current = notesAtCursor;
    if (noteIndex < 0 || noteIndex >= current.length) {
      return this;
    }
    final target = current[noteIndex];
    final flippedClef = target.staffNote.clef == Clef.treble
        ? Clef.bass
        : Clef.treble;
    final updatedNote = StaffNote(
      note: target.staffNote.note,
      octave: target.staffNote.octave,
      clef: flippedClef,
      accidental: target.staffNote.accidental,
    );
    final nextMeasures = List<DraftMeasure>.of(measures);
    replaceSingleDraftNote(
      nextMeasures,
      cursor.measureIndex,
      target,
      target.copyWith(staffNote: updatedNote),
    );
    return copyWith(measures: nextMeasures);
  }

  Clef _resolveTouchTargetClef(List<DraftNoteEvent> current) {
    return switch (clefMode) {
      ClefAssignmentMode.trebleOnly => Clef.treble,
      ClefAssignmentMode.bassOnly => Clef.bass,
      ClefAssignmentMode.autoSplit =>
        current.any((n) => n.staffNote.clef == Clef.treble) || current.isEmpty
            ? Clef.treble
            : Clef.bass,
    };
  }
}
