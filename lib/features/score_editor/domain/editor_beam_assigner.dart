import 'package:piano_exercises/shared/music/music.dart';

/// Assigns beat-grouped MusicXML-compatible `beamGroupId`s to measure notes.
abstract final class EditorBeamAssigner {
  static const Set<NoteBaseDuration> _beamableDurations = <NoteBaseDuration>{
    NoteBaseDuration.eighth,
    NoteBaseDuration.sixteenth,
    NoteBaseDuration.thirtySecond,
    NoteBaseDuration.sixtyFourth,
  };

  /// Recomputes `beamGroupId`s for runs of `>= 2` contiguous same-beat beamable notes.
  static List<NoteTimelineInput> assign({
    required int measureNumber,
    required TimeSignature timeSignature,
    required List<NoteTimelineInput> notes,
  }) {
    if (notes.isEmpty) {
      return const <NoteTimelineInput>[];
    }
    final beatSpan = _beatGroupSpan(timeSignature);
    final byStream = <(Clef, int), List<int>>{};
    for (var i = 0; i < notes.length; i += 1) {
      final note = notes[i];
      byStream.putIfAbsent((note.clef, note.voice), () => <int>[]).add(i);
    }

    final beamIds = List<String?>.filled(notes.length, null);
    final streamKeys = byStream.keys.toList()
      ..sort((a, b) {
        final clefCmp = a.$1.index.compareTo(b.$1.index);
        return clefCmp != 0 ? clefCmp : a.$2.compareTo(b.$2);
      });

    var seq = 0;
    for (final key in streamKeys) {
      final indices = byStream[key]!;
      seq = _assignStreamBeams(
        measureNumber: measureNumber,
        voice: key.$2,
        initialSeq: seq,
        beatSpan: beatSpan,
        notes: notes,
        streamIndices: indices,
        beamIdsOut: beamIds,
      );
    }

    return List<NoteTimelineInput>.unmodifiable(<NoteTimelineInput>[
      for (var i = 0; i < notes.length; i += 1)
        _copyWithBeamId(notes[i], beamIds[i]),
    ]);
  }

  static int _assignStreamBeams({
    required int measureNumber,
    required int voice,
    required int initialSeq,
    required RationalBeats beatSpan,
    required List<NoteTimelineInput> notes,
    required List<int> streamIndices,
    required List<String?> beamIdsOut,
  }) {
    final byOffset = <RationalBeats, List<int>>{};
    for (final idx in streamIndices) {
      byOffset.putIfAbsent(notes[idx].beatOffset, () => <int>[]).add(idx);
    }
    final offsets = byOffset.keys.toList()..sort();
    var seq = initialSeq;
    var runStart = 0;

    while (runStart < offsets.length) {
      if (!_isAnchorBeamable(notes, byOffset[offsets[runStart]]!)) {
        runStart += 1;
        continue;
      }
      var runEnd = runStart;
      while (runEnd + 1 < offsets.length) {
        final currIndices = byOffset[offsets[runEnd]]!;
        final nextOffset = offsets[runEnd + 1];
        final nextIndices = byOffset[nextOffset]!;
        if (!_isAnchorBeamable(notes, nextIndices)) {
          break;
        }
        final currEnd = offsets[runEnd] + _anchorDuration(notes, currIndices);
        if (currEnd != nextOffset ||
            _beatBucket(offsets[runEnd], beatSpan) !=
                _beatBucket(nextOffset, beatSpan)) {
          break;
        }
        runEnd += 1;
      }

      if (runEnd > runStart) {
        final id = 'm$measureNumber-p0-v$voice-b$seq';
        seq += 1;
        for (var pos = runStart; pos <= runEnd; pos += 1) {
          for (final idx in byOffset[offsets[pos]]!) {
            beamIdsOut[idx] = id;
          }
        }
      }
      runStart = runEnd + 1;
    }
    return seq;
  }

  static bool _isAnchorBeamable(
    List<NoteTimelineInput> notes,
    List<int> indices,
  ) {
    for (final idx in indices) {
      if (!_beamableDurations.contains(notes[idx].duration.base)) {
        return false;
      }
    }
    return true;
  }

  static RationalBeats _anchorDuration(
    List<NoteTimelineInput> notes,
    List<int> indices,
  ) {
    var shortest = notes[indices.first].duration.quarterBeats;
    for (final idx in indices.skip(1)) {
      final candidate = notes[idx].duration.quarterBeats;
      if (candidate < shortest) {
        shortest = candidate;
      }
    }
    return shortest;
  }

  static RationalBeats _beatGroupSpan(TimeSignature time) {
    final isCompound = time.beatType == 8 && time.beats % 3 == 0;
    return isCompound ? RationalBeats(3, 2) : RationalBeats(4, time.beatType);
  }

  static int _beatBucket(RationalBeats offset, RationalBeats span) {
    final num = BigInt.from(offset.numerator) * BigInt.from(span.denominator);
    final den = BigInt.from(offset.denominator) * BigInt.from(span.numerator);
    return (num ~/ den).toInt();
  }

  static NoteTimelineInput _copyWithBeamId(
    NoteTimelineInput note,
    String? beamGroupId,
  ) {
    return NoteTimelineInput(
      clef: note.clef,
      diatonicNote: note.diatonicNote,
      octave: note.octave,
      explicitAlter: note.explicitAlter,
      writtenAccidental: note.writtenAccidental,
      beatOffset: note.beatOffset,
      duration: note.duration,
      tie: note.tie,
      voice: note.voice,
      beamGroupId: beamGroupId,
    );
  }
}
