import 'package:piano_exercises/features/score_editor/domain/rhythm_duration_splitter.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_tie_and_ripple_ops.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Single measure-bounded rhythmic segment produced by splitting across barlines.
final class DraftSegment {
  const DraftSegment({
    required this.measureIndex,
    required this.beatOffset,
    required this.duration,
  });

  final int measureIndex;
  final RationalBeats beatOffset;
  final DurationValue duration;

  RationalBeats get endOffset => beatOffset + duration.quarterBeats;
}

/// Ensures [measures] has an entry at [index] within [ScoreDraft.maxMeasures].
void ensureDraftMeasureExists(List<DraftMeasure> measures, int index) {
  while (measures.length <= index && measures.length < ScoreDraft.maxMeasures) {
    measures.add(DraftMeasure(measureNumber: measures.length + 1));
  }
}

/// Resolves active [TimeSignature] at [measureIndex] over mutable [measures].
TimeSignature activeDraftTimeAt(
  TimeSignature rootTime,
  List<DraftMeasure> measures,
  int measureIndex,
) {
  var active = rootTime;
  final limit = measureIndex.clamp(0, measures.length - 1);
  for (var i = 0; i <= limit; i += 1) {
    if (measures[i].timeSignature != null) {
      active = measures[i].timeSignature!;
    }
  }
  return active;
}

/// Replaces [oldNote] with [newNote] inside `measures[measureIdx]`.
void replaceSingleDraftNote(
  List<DraftMeasure> measures,
  int measureIdx,
  DraftNoteEvent oldNote,
  DraftNoteEvent newNote,
) {
  final dm = measures[measureIdx];
  final nextNotes = List<DraftNoteEvent>.of(dm.notes);
  final idx = nextNotes.indexOf(oldNote);
  if (idx >= 0) {
    nextNotes[idx] = newNote;
    measures[measureIdx] = dm.copyWith(notes: nextNotes);
  }
}

/// Plans barline-split segments starting at [start] for [totalBeats].
({
  List<DraftSegment> segments,
  List<DraftMeasure> measures,
  EditorCursor nextCursor,
})
planBarlineSegments(
  ScoreDraft draft, {
  required EditorCursor start,
  required RationalBeats totalBeats,
}) {
  final measures = List<DraftMeasure>.of(draft.measures);
  final segments = <DraftSegment>[];
  var remaining = totalBeats;
  var curMeasureIdx = start.measureIndex;
  var curOffset = start.beatOffset;

  while (!remaining.isZero && curMeasureIdx < ScoreDraft.maxMeasures) {
    ensureDraftMeasureExists(measures, curMeasureIdx);
    final measureBeats = activeDraftTimeAt(
      draft.timeSignature,
      measures,
      curMeasureIdx,
    ).measureQuarterBeats;
    if (curOffset >= measureBeats) {
      curMeasureIdx += 1;
      curOffset = const RationalBeats.zero();
      continue;
    }
    final available = measureBeats - curOffset;
    final chunk = remaining <= available ? remaining : available;
    for (final part in splitDuration(chunk)) {
      segments.add(
        DraftSegment(
          measureIndex: curMeasureIdx,
          beatOffset: curOffset,
          duration: part,
        ),
      );
      curOffset = curOffset + part.quarterBeats;
    }
    remaining = remaining - chunk;
    if (!remaining.isZero) {
      curMeasureIdx += 1;
      curOffset = const RationalBeats.zero();
    }
  }

  if (segments.isEmpty) {
    return (segments: segments, measures: measures, nextCursor: start);
  }
  final last = segments.last;
  final lastMeasureBeats = activeDraftTimeAt(
    draft.timeSignature,
    measures,
    last.measureIndex,
  ).measureQuarterBeats;
  final EditorCursor nextCursor;
  if (last.endOffset >= lastMeasureBeats) {
    final nextIdx = last.measureIndex + 1;
    if (nextIdx < ScoreDraft.maxMeasures) {
      ensureDraftMeasureExists(measures, nextIdx);
      nextCursor = EditorCursor(measureIndex: nextIdx);
    } else {
      nextCursor = EditorCursor(
        measureIndex: last.measureIndex,
        beatOffset: last.beatOffset,
      );
    }
  } else {
    nextCursor = EditorCursor(
      measureIndex: last.measureIndex,
      beatOffset: last.endOffset,
    );
  }
  return (segments: segments, measures: measures, nextCursor: nextCursor);
}

/// Removes or trims notes on [clefs] overlapping `[start, end)` and reports broken ties.
({DraftMeasure measure, List<DraftNoteEvent> brokenNotes})
clearNoteSpanInMeasure(
  DraftMeasure measure, {
  required Set<Clef> clefs,
  required RationalBeats start,
  required RationalBeats end,
}) {
  final nextNotes = <DraftNoteEvent>[];
  final brokenNotes = <DraftNoteEvent>[];
  for (final note in measure.notes) {
    if (!clefs.contains(note.staffNote.clef) ||
        note.endOffset <= start ||
        note.beatOffset >= end) {
      nextNotes.add(note);
      continue;
    }
    if (note.beatOffset < start) {
      _appendTruncatedParts(nextNotes, note, start - note.beatOffset);
      _recordBrokenOutgoingTie(brokenNotes, note);
    } else {
      brokenNotes.add(note);
    }
  }
  return (
    measure: measure.copyWith(notes: nextNotes),
    brokenNotes: brokenNotes,
  );
}

/// Writes [entries] across barline [segments] on [measures], healing overwritten ties.
void writeSegmentedChord(
  List<DraftMeasure> measures, {
  required ScoreDraft draft,
  required List<DraftSegment> segments,
  required List<({StaffNote staffNote, Accidental? explicitAccidental})>
  entries,
  required Set<Clef> affectedClefs,
}) {
  // Clear and heal all overwritten spans before inserting new segments so tie healing never strips newly written notes.
  for (final seg in segments) {
    final cleared = clearNoteSpanInMeasure(
      measures[seg.measureIndex],
      clefs: affectedClefs,
      start: seg.beatOffset,
      end: seg.endOffset,
    );
    measures[seg.measureIndex] = cleared.measure;
    healNeighborTies(
      draft,
      measures,
      measureIdx: seg.measureIndex,
      removed: cleared.brokenNotes,
    );
  }
  final total = segments.length;
  for (var s = 0; s < total; s += 1) {
    final seg = segments[s];
    final tie = total == 1
        ? TieType.none
        : s == 0
        ? TieType.start
        : s == total - 1
        ? TieType.stop
        : TieType.continueTie;
    final dm = measures[seg.measureIndex];
    final added = <DraftNoteEvent>[
      ...dm.notes,
      for (final entry in entries)
        DraftNoteEvent(
          staffNote: entry.staffNote,
          beatOffset: seg.beatOffset,
          duration: seg.duration,
          tie: tie,
          explicitAccidental: s == 0 ? entry.explicitAccidental : null,
        ),
    ];
    measures[seg.measureIndex] = dm.copyWith(notes: added);
  }
}

/// Trims or drops notes exceeding [measureBeats] and reports notes needing neighbor tie healing.
({DraftMeasure measure, List<DraftNoteEvent> brokenNotes})
clampMeasureNotesToSpan(DraftMeasure measure, RationalBeats measureBeats) {
  final kept = <DraftNoteEvent>[];
  final brokenNotes = <DraftNoteEvent>[];
  for (final note in measure.notes) {
    if (note.beatOffset >= measureBeats) {
      brokenNotes.add(note);
      continue;
    }
    if (note.endOffset <= measureBeats) {
      kept.add(note);
      continue;
    }
    _appendTruncatedParts(kept, note, measureBeats - note.beatOffset);
    _recordBrokenOutgoingTie(brokenNotes, note);
  }
  return (measure: measure.copyWith(notes: kept), brokenNotes: brokenNotes);
}

void _appendTruncatedParts(
  List<DraftNoteEvent> out,
  DraftNoteEvent note,
  RationalBeats keepSpan,
) {
  final parts = splitDuration(keepSpan);
  final hadIncoming =
      note.tie == TieType.stop || note.tie == TieType.continueTie;
  var offset = note.beatOffset;
  for (var i = 0; i < parts.length; i += 1) {
    final isFirst = i == 0;
    final nextTie = parts.length == 1
        ? (hadIncoming ? TieType.stop : TieType.none)
        : (isFirst
              ? (hadIncoming ? TieType.continueTie : TieType.start)
              : (i == parts.length - 1 ? TieType.stop : TieType.continueTie));
    out.add(
      note.copyWith(
        beatOffset: offset,
        duration: parts[i],
        tie: nextTie,
        clearExplicitAccidental: !isFirst,
      ),
    );
    offset = offset + parts[i].quarterBeats;
  }
}

void _recordBrokenOutgoingTie(
  List<DraftNoteEvent> brokenNotes,
  DraftNoteEvent note,
) {
  if (note.tie == TieType.start || note.tie == TieType.continueTie) {
    brokenNotes.add(note.copyWith(tie: TieType.start));
  }
}
