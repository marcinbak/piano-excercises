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
  final measureBeats = activeDraftTimeAt(
    draft.timeSignature,
    measures,
    sourceMeasureIdx,
  ).measureQuarterBeats;
  final int partnerIdx;
  final RationalBeats partnerOffset;
  if (source.endOffset >= measureBeats) {
    partnerIdx = sourceMeasureIdx + 1;
    partnerOffset = const RationalBeats.zero();
  } else {
    partnerIdx = sourceMeasureIdx;
    partnerOffset = source.endOffset;
  }
  if (partnerIdx >= measures.length) {
    return;
  }
  for (final candidate in measures[partnerIdx].notes) {
    if (candidate.beatOffset == partnerOffset &&
        candidate.staffNote.clef == source.staffNote.clef &&
        candidate.staffNote.midiNote == source.staffNote.midiNote) {
      final nextTie = enableTie
          ? (candidate.tie == TieType.start
                ? TieType.continueTie
                : TieType.stop)
          : (candidate.tie == TieType.continueTie
                ? TieType.start
                : TieType.none);
      replaceSingleDraftNote(
        measures,
        partnerIdx,
        candidate,
        candidate.copyWith(tie: nextTie),
      );
      return;
    }
  }
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
    final keepBefore = <DraftNoteEvent>[];
    final candidates = <DraftNoteEvent>[...incoming];

    for (final note in measure.notes) {
      if (mIdx == cursor.measureIndex && note.beatOffset < cursor.beatOffset) {
        keepBefore.add(note);
      } else {
        candidates.add(
          note.copyWith(beatOffset: note.beatOffset + shiftAmount),
        );
      }
    }

    final keptInMeasure = <DraftNoteEvent>[...keepBefore];
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
        final inParts = splitDuration(measureBeats - note.beatOffset);
        final outParts = splitDuration(note.endOffset - measureBeats);
        final hadIncoming =
            note.tie == TieType.stop || note.tie == TieType.continueTie;
        final hadOutgoing =
            note.tie == TieType.start || note.tie == TieType.continueTie;
        final total = inParts.length + outParts.length;
        var pos = note.beatOffset;
        var combinedIdx = 0;
        for (final dur in inParts) {
          keptInMeasure.add(
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
        var outPos = const RationalBeats.zero();
        for (final dur in outParts) {
          nextIncoming.add(
            note.copyWith(
              beatOffset: outPos,
              duration: dur,
              tie: _splitPartTie(
                combinedIdx,
                total,
                hadIncoming: hadIncoming,
                hadOutgoing: hadOutgoing,
              ),
              clearExplicitAccidental: true,
            ),
          );
          outPos = outPos + dur.quarterBeats;
          combinedIdx += 1;
        }
        if (outPos > maxOverflowEnd) {
          maxOverflowEnd = outPos;
        }
      } else {
        keptInMeasure.add(note);
      }
    }

    measures[mIdx] = measure.copyWith(notes: keptInMeasure);
    incoming = nextIncoming;
    shiftAmount = maxOverflowEnd;
  }
  return measures;
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
  final measureBeats = activeDraftTimeAt(
    draft.timeSignature,
    draft.measures,
    measureIdx,
  ).measureQuarterBeats;
  final int targetIdx;
  final RationalBeats targetOffset;
  if (source.endOffset >= measureBeats) {
    targetIdx = measureIdx + 1;
    targetOffset = const RationalBeats.zero();
  } else {
    targetIdx = measureIdx;
    targetOffset = source.endOffset;
  }
  if (targetIdx < 0 || targetIdx >= measures.length) {
    return;
  }
  final targetMeasure = measures[targetIdx];
  var changed = false;
  final nextNotes = <DraftNoteEvent>[
    for (final note in targetMeasure.notes)
      if (!changed &&
          note.beatOffset == targetOffset &&
          note.staffNote.clef == source.staffNote.clef &&
          note.staffNote.midiNote == source.staffNote.midiNote &&
          (note.tie == TieType.stop || note.tie == TieType.continueTie))
        (() {
          changed = true;
          return note.copyWith(
            tie: note.tie == TieType.continueTie ? TieType.start : TieType.none,
          );
        })()
      else
        note,
  ];
  if (changed) {
    measures[targetIdx] = targetMeasure.copyWith(notes: nextNotes);
  }
}

void _clearOutgoingPartnerTie(
  ScoreDraft draft,
  List<DraftMeasure> measures,
  int measureIdx,
  DraftNoteEvent source,
) {
  final int targetIdx;
  final RationalBeats targetEnd;
  if (source.beatOffset.isZero) {
    targetIdx = measureIdx - 1;
    if (targetIdx < 0) {
      return;
    }
    targetEnd = activeDraftTimeAt(
      draft.timeSignature,
      draft.measures,
      targetIdx,
    ).measureQuarterBeats;
  } else {
    targetIdx = measureIdx;
    targetEnd = source.beatOffset;
  }
  final targetMeasure = measures[targetIdx];
  var changed = false;
  final nextNotes = <DraftNoteEvent>[
    for (final note in targetMeasure.notes)
      if (!changed &&
          note.endOffset == targetEnd &&
          note.staffNote.clef == source.staffNote.clef &&
          note.staffNote.midiNote == source.staffNote.midiNote &&
          (note.tie == TieType.start || note.tie == TieType.continueTie))
        (() {
          changed = true;
          return note.copyWith(
            tie: note.tie == TieType.continueTie ? TieType.stop : TieType.none,
          );
        })()
      else
        note,
  ];
  if (changed) {
    measures[targetIdx] = targetMeasure.copyWith(notes: nextNotes);
  }
}
