import 'package:piano_exercises/features/score_editor/domain/score_draft.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_tie_and_ripple_ops.dart';
import 'package:piano_exercises/features/score_editor/domain/score_draft_timeline_ops.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Measure-structure and global setup mutations for [ScoreDraft].
extension ScoreDraftSetupMutations on ScoreDraft {
  /// Appends an empty bar (up to [ScoreDraft.maxMeasures]) and focuses it.
  ScoreDraft addMeasure() {
    if (measures.length >= ScoreDraft.maxMeasures) {
      return this;
    }
    final nextMeasures = <DraftMeasure>[
      ...measures,
      DraftMeasure(measureNumber: measures.length + 1),
    ];
    return copyWith(
      measures: nextMeasures,
      cursor: EditorCursor(measureIndex: nextMeasures.length - 1),
    );
  }

  /// Deletes the measure at [cursor.measureIndex], keeping at least one bar.
  ScoreDraft deleteCurrentMeasure() {
    if (measures.length <= 1) {
      if (measures.first.notes.isEmpty) {
        return copyWith(cursor: const EditorCursor(measureIndex: 0));
      }
      return copyWith(
        measures: <DraftMeasure>[measures.first.copyWith(notes: const [])],
        cursor: const EditorCursor(measureIndex: 0),
      );
    }

    final removedIdx = cursor.measureIndex;
    final nextMeasures = List<DraftMeasure>.of(measures);
    healNeighborTies(
      this,
      nextMeasures,
      measureIdx: removedIdx,
      removed: nextMeasures[removedIdx].notes,
    );
    nextMeasures.removeAt(removedIdx);

    final hasPickup = nextMeasures.first.measureNumber == 0 && removedIdx != 0;
    final renumbered = <DraftMeasure>[
      for (var i = 0; i < nextMeasures.length; i += 1)
        nextMeasures[i].copyWith(measureNumber: hasPickup ? i : i + 1),
    ];
    final nextIdx = removedIdx >= renumbered.length
        ? renumbered.length - 1
        : removedIdx;
    return copyWith(
      measures: renumbered,
      cursor: EditorCursor(measureIndex: nextIdx),
    );
  }

  /// Updates score key, meter, split point, or clef routing, clamping overflowing bars.
  ScoreDraft updateSetup({
    Scale? scale,
    TimeSignature? timeSignature,
    int? splitPointMidi,
    ClefAssignmentMode? clefMode,
  }) {
    final nextSplit = splitPointMidi == null
        ? this.splitPointMidi
        : splitPointMidi.clamp(MidiNote.minNumber, MidiNote.maxNumber);
    final nextMeasures = List<DraftMeasure>.of(measures);

    if (scale != null && nextMeasures.first.keySignature != null) {
      nextMeasures[0] = nextMeasures[0].copyWith(clearKeySignature: true);
    }
    var nextCursor = cursor;
    if (timeSignature != null) {
      if (nextMeasures.first.timeSignature != null) {
        nextMeasures[0] = nextMeasures[0].copyWith(clearTimeSignature: true);
      }
      final newSpan = timeSignature.measureQuarterBeats;
      for (var i = 0; i < nextMeasures.length; i += 1) {
        if (i > 0 && nextMeasures[i].timeSignature != null) {
          break;
        }
        nextMeasures[i] = clampMeasureNotesToSpan(nextMeasures[i], newSpan);
      }
      final activeSpan = activeDraftTimeAt(
        timeSignature,
        nextMeasures,
        nextCursor.measureIndex,
      ).measureQuarterBeats;
      if (nextCursor.beatOffset >= activeSpan) {
        nextCursor = EditorCursor(measureIndex: nextCursor.measureIndex);
      }
    }

    return copyWith(
      scale: scale,
      timeSignature: timeSignature,
      splitPointMidi: nextSplit,
      clefMode: clefMode,
      measures: nextMeasures,
      cursor: nextCursor,
    );
  }

  /// Resets all measures to four empty bars under the current meter and key.
  ScoreDraft clearScore() {
    return copyWith(
      measures: ScoreDraft.defaultMeasures(),
      cursor: const EditorCursor(measureIndex: 0),
    );
  }
}
