import 'package:piano_exercises/features/score_editor/domain/rhythm_duration_splitter.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_timeline_ops.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Clears tie flags on immediate predecessors/successors of [removed] at [measureIdx].
void healNeighborTies(
  ScoreDraft draft,
  List<DraftMeasure> measures, {
  required int measureIdx,
  required List<DraftNoteEvent> removed,
}) {
  for (final gone in removed) {
    if (gone.tie == TieType.start || gone.tie == TieType.continueTie) {
      _clearIncomingPartnerTie(draft, measures, measureIdx, gone);
    }
    if (gone.tie == TieType.stop || gone.tie == TieType.continueTie) {
      _clearOutgoingPartnerTie(draft, measures, measureIdx, gone);
    }
  }
}

/// Toggles the incoming tie flag on the immediate next matching-pitch partner.
void toggleNextPartnerTie(
  ScoreDraft draft,
  List<DraftMeasure> measures, {
  required int sourceMeasureIdx,
  required DraftNoteEvent source,
  required bool enableTie,
}) {
  final measureBeats = effectiveDraftMeasureBeats(
    draft.timeSignature,
    draft.measures,
    sourceMeasureIdx,
  );
  final crossesBar = source.endOffset >= measureBeats;
  final partnerIdx = crossesBar ? sourceMeasureIdx + 1 : sourceMeasureIdx;
  final partnerOffset = crossesBar
      ? const RationalBeats.zero()
      : source.endOffset;
  _updateMatchingPartnerTie(
    measures,
    partnerIdx,
    matches: (n) =>
        n.beatOffset == partnerOffset &&
        n.staffNote.clef == source.staffNote.clef &&
        n.staffNote.midiNote == source.staffNote.midiNote,
    nextTie: (t) => enableTie
        ? (t == TieType.start ? TieType.continueTie : TieType.stop)
        : (t == TieType.continueTie ? TieType.start : TieType.none),
  );
}

/// Inserts a beat-width gap at [cursor] and cascades overflow into subsequent bars.
List<DraftMeasure> rippleInsertGap(
  ScoreDraft draft, {
  required EditorCursor cursor,
  required RationalBeats delta,
}) {
  final measures = List<DraftMeasure>.of(draft.measures);
  var incoming = <DraftNoteEvent>[];
  var shiftAmount = delta;

  for (
    var mIdx = cursor.measureIndex;
    mIdx < ScoreDraft.maxMeasures &&
        (mIdx == cursor.measureIndex || incoming.isNotEmpty);
    mIdx += 1
  ) {
    ensureDraftMeasureExists(measures, mIdx);
    final measure = measures[mIdx];
    final measureBeats = activeDraftTimeAt(
      draft.timeSignature,
      measures,
      mIdx,
    ).measureQuarterBeats;
    final split = _ripplePartitionMeasure(
      measure,
      incoming: incoming,
      measureBeats: measureBeats,
      shiftAmount: shiftAmount,
      splitAtBeat: mIdx == cursor.measureIndex ? cursor.beatOffset : null,
    );
    measures[mIdx] = measure.copyWith(notes: split.kept);
    incoming = split.overflow;
    shiftAmount = split.maxOverflowEnd;
  }
  return measures;
}

({
  List<DraftNoteEvent> kept,
  List<DraftNoteEvent> overflow,
  RationalBeats maxOverflowEnd,
})
_ripplePartitionMeasure(
  DraftMeasure measure, {
  required List<DraftNoteEvent> incoming,
  required RationalBeats measureBeats,
  required RationalBeats shiftAmount,
  RationalBeats? splitAtBeat,
}) {
  final keptInMeasure = <DraftNoteEvent>[];
  final candidates = <DraftNoteEvent>[...incoming];
  for (final note in measure.notes) {
    if (splitAtBeat != null && note.beatOffset < splitAtBeat) {
      keptInMeasure.add(note);
    } else {
      candidates.add(note.copyWith(beatOffset: note.beatOffset + shiftAmount));
    }
  }

  final nextIncoming = <DraftNoteEvent>[];
  var maxOverflowEnd = const RationalBeats.zero();
  for (final note in candidates) {
    if (note.beatOffset >= measureBeats) {
      final overflow = note.copyWith(
        beatOffset: note.beatOffset - measureBeats,
      );
      nextIncoming.add(overflow);
      if (overflow.endOffset > maxOverflowEnd) {
        maxOverflowEnd = overflow.endOffset;
      }
    } else if (note.endOffset > measureBeats) {
      final overflowEnd = _splitBarlineCrossingNote(
        note,
        measureBeats: measureBeats,
        keptInMeasure: keptInMeasure,
        nextIncoming: nextIncoming,
      );
      if (overflowEnd > maxOverflowEnd) {
        maxOverflowEnd = overflowEnd;
      }
    } else {
      keptInMeasure.add(note);
    }
  }
  return (
    kept: keptInMeasure,
    overflow: nextIncoming,
    maxOverflowEnd: maxOverflowEnd,
  );
}

RationalBeats _splitBarlineCrossingNote(
  DraftNoteEvent note, {
  required RationalBeats measureBeats,
  required List<DraftNoteEvent> keptInMeasure,
  required List<DraftNoteEvent> nextIncoming,
}) {
  final inParts = splitDuration(measureBeats - note.beatOffset);
  final outParts = splitDuration(note.endOffset - measureBeats);
  final hadIncoming =
      note.tie == TieType.stop || note.tie == TieType.continueTie;
  final hadOutgoing =
      note.tie == TieType.start || note.tie == TieType.continueTie;
  final total = inParts.length + outParts.length;
  var combinedIdx = 0;
  var lastPos = const RationalBeats.zero();
  for (final phase
      in <(List<DurationValue>, RationalBeats, List<DraftNoteEvent>)>[
        (inParts, note.beatOffset, keptInMeasure),
        (outParts, const RationalBeats.zero(), nextIncoming),
      ]) {
    var pos = phase.$2;
    for (final dur in phase.$1) {
      phase.$3.add(
        note.copyWith(
          beatOffset: pos,
          duration: dur,
          tie: _splitPartTie(
            combinedIdx,
            total,
            hadIncoming: hadIncoming,
            hadOutgoing: hadOutgoing,
          ),
          clearExplicitAccidental: combinedIdx > 0,
        ),
      );
      pos = pos + dur.quarterBeats;
      combinedIdx += 1;
    }
    lastPos = pos;
  }
  return lastPos;
}

TieType _splitPartTie(
  int index,
  int total, {
  required bool hadIncoming,
  required bool hadOutgoing,
}) {
  if (index == 0) {
    return hadIncoming ? TieType.continueTie : TieType.start;
  }
  if (index == total - 1) {
    return hadOutgoing ? TieType.continueTie : TieType.stop;
  }
  return TieType.continueTie;
}

void _clearIncomingPartnerTie(
  ScoreDraft draft,
  List<DraftMeasure> measures,
  int measureIdx,
  DraftNoteEvent source,
) {
  final measureBeats = effectiveDraftMeasureBeats(
    draft.timeSignature,
    draft.measures,
    measureIdx,
  );
  final crossesBar = source.endOffset >= measureBeats;
  final targetIdx = crossesBar ? measureIdx + 1 : measureIdx;
  final targetOffset = crossesBar
      ? const RationalBeats.zero()
      : source.endOffset;
  _updateMatchingPartnerTie(
    measures,
    targetIdx,
    matches: (n) =>
        n.beatOffset == targetOffset &&
        n.staffNote.clef == source.staffNote.clef &&
        n.staffNote.midiNote == source.staffNote.midiNote &&
        (n.tie == TieType.stop || n.tie == TieType.continueTie),
    nextTie: (t) => t == TieType.continueTie ? TieType.start : TieType.none,
  );
}

void _clearOutgoingPartnerTie(
  ScoreDraft draft,
  List<DraftMeasure> measures,
  int measureIdx,
  DraftNoteEvent source,
) {
  final crossesBack = source.beatOffset.isZero;
  final targetIdx = crossesBack ? measureIdx - 1 : measureIdx;
  if (targetIdx < 0) {
    return;
  }
  final targetEnd = crossesBack
      ? effectiveDraftMeasureBeats(
          draft.timeSignature,
          draft.measures,
          targetIdx,
        )
      : source.beatOffset;
  _updateMatchingPartnerTie(
    measures,
    targetIdx,
    matches: (n) =>
        n.endOffset == targetEnd &&
        n.staffNote.clef == source.staffNote.clef &&
        n.staffNote.midiNote == source.staffNote.midiNote &&
        (n.tie == TieType.start || n.tie == TieType.continueTie),
    nextTie: (t) => t == TieType.continueTie ? TieType.stop : TieType.none,
  );
}

void _updateMatchingPartnerTie(
  List<DraftMeasure> measures,
  int targetIdx, {
  required bool Function(DraftNoteEvent note) matches,
  required TieType Function(TieType current) nextTie,
}) {
  if (targetIdx < 0 || targetIdx >= measures.length) {
    return;
  }
  final targetMeasure = measures[targetIdx];
  var changed = false;
  final nextNotes = <DraftNoteEvent>[
    for (final note in targetMeasure.notes)
      if (!changed && matches(note))
        (() {
          changed = true;
          return note.copyWith(tie: nextTie(note.tie));
        })()
      else
        note,
  ];
  if (changed) {
    measures[targetIdx] = targetMeasure.copyWith(notes: nextNotes);
  }
}
