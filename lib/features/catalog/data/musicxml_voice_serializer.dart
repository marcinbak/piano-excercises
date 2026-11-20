import 'package:piano_exercises/features/catalog/data/musicxml_note_serializer.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:xml/xml.dart';

/// Note event paired with its measure-relative [beatOffset].
final class TimedScoreNote {
  const TimedScoreNote(this.beatOffset, this.note);

  final RationalBeats beatOffset;
  final ScoreNote note;
}

/// Rest event paired with its measure-relative [beatOffset].
final class TimedRestEvent {
  const TimedRestEvent(this.beatOffset, this.rest);

  final RationalBeats beatOffset;
  final RestEvent rest;
}

/// Stream parameters for serializing one `(staff, voice)` track in a measure.
final class MusicXmlVoiceStreamInput {
  const MusicXmlVoiceStreamInput({
    required this.notes,
    required this.explicitRests,
    required this.staff,
    required this.voice,
    required this.isPrimaryVoice,
    required this.divisions,
    required this.measureBeats,
  });

  final List<TimedScoreNote> notes;
  final List<TimedRestEvent> explicitRests;
  final int staff;
  final int voice;
  final bool isPrimaryVoice;
  final int divisions;
  final RationalBeats measureBeats;
}

/// Writes one voice stream across a measure and returns emitted cursor ticks.
int writeMusicXmlVoiceStream(
  XmlBuilder builder,
  MusicXmlVoiceStreamInput input,
) {
  final anchors = _buildAnchors(input.notes);
  final beamTags = _computeBeamTags(anchors);
  final explicitRestByOffset = <RationalBeats, DurationValue>{
    for (final rest in input.explicitRests) rest.beatOffset: rest.rest.duration,
  };

  var cursorBeats = const RationalBeats.zero();
  var cursorTicks = 0;

  for (var i = 0; i < anchors.length; i += 1) {
    final anchor = anchors[i];
    if (anchor.beatOffset > cursorBeats) {
      cursorTicks += _writeGap(
        builder,
        input: input,
        from: cursorBeats,
        to: anchor.beatOffset,
        explicitRestByOffset: explicitRestByOffset,
      );
      cursorBeats = anchor.beatOffset;
    } else if (anchor.beatOffset < cursorBeats) {
      final rewindTicks = musicXmlBeatsToTicks(
        cursorBeats - anchor.beatOffset,
        input.divisions,
      );
      if (rewindTicks > 0) {
        writeMusicXmlBackup(builder, rewindTicks);
        cursorTicks -= rewindTicks;
      }
      cursorBeats = anchor.beatOffset;
    }

    final durTicks = musicXmlBeatsToTicks(
      anchor.duration.quarterBeats,
      input.divisions,
    );
    for (var n = 0; n < anchor.notes.length; n += 1) {
      final isChord = n > 0;
      writeMusicXmlPitchedNote(
        builder,
        note: anchor.notes[n],
        durationTicks: durTicks,
        staff: input.staff,
        isChord: isChord,
        beamTag: isChord ? null : beamTags[i],
      );
    }
    cursorBeats = anchor.beatOffset + anchor.duration.quarterBeats;
    cursorTicks += durTicks;
  }

  if (input.isPrimaryVoice && cursorBeats < input.measureBeats) {
    cursorTicks += _writeGap(
      builder,
      input: input,
      from: cursorBeats,
      to: input.measureBeats,
      explicitRestByOffset: explicitRestByOffset,
    );
  }
  return cursorTicks;
}

int _writeGap(
  XmlBuilder builder, {
  required MusicXmlVoiceStreamInput input,
  required RationalBeats from,
  required RationalBeats to,
  required Map<RationalBeats, DurationValue> explicitRestByOffset,
}) {
  var cursor = from;
  var writtenTicks = 0;
  while (cursor < to) {
    final remaining = to - cursor;
    final explicit = explicitRestByOffset[cursor];
    if (explicit != null && explicit.quarterBeats <= remaining) {
      final ticks = musicXmlBeatsToTicks(
        explicit.quarterBeats,
        input.divisions,
      );
      writeMusicXmlRestNote(
        builder,
        duration: explicit,
        durationTicks: ticks,
        staff: input.staff,
        voice: input.voice,
      );
      cursor = cursor + explicit.quarterBeats;
      writtenTicks += ticks;
      continue;
    }
    if (!input.isPrimaryVoice) {
      final gapTicks = musicXmlBeatsToTicks(remaining, input.divisions);
      if (gapTicks > 0) {
        writeMusicXmlForward(builder, gapTicks);
      }
      return writtenTicks + gapTicks;
    }
    final part = largestMusicXmlRestDuration(cursor, remaining);
    final ticks = musicXmlBeatsToTicks(part.quarterBeats, input.divisions);
    writeMusicXmlRestNote(
      builder,
      duration: part,
      durationTicks: ticks,
      staff: input.staff,
      voice: input.voice,
    );
    cursor = cursor + part.quarterBeats;
    writtenTicks += ticks;
  }
  return writtenTicks;
}

List<_NoteAnchor> _buildAnchors(List<TimedScoreNote> timedNotes) {
  final grouped = <(RationalBeats, DurationValue), List<ScoreNote>>{};
  for (final item in timedNotes) {
    final key = (item.beatOffset, item.note.duration);
    grouped.putIfAbsent(key, () => <ScoreNote>[]).add(item.note);
  }
  final keys = grouped.keys.toList()
    ..sort((a, b) {
      final offsetCmp = a.$1.compareTo(b.$1);
      if (offsetCmp != 0) {
        return offsetCmp;
      }
      return b.$2.quarterBeats.compareTo(a.$2.quarterBeats);
    });
  return <_NoteAnchor>[
    for (final key in keys) _NoteAnchor(key.$1, key.$2, grouped[key]!),
  ];
}

List<String?> _computeBeamTags(List<_NoteAnchor> anchors) {
  final ids = <String?>[
    for (final anchor in anchors) _resolveAnchorBeamId(anchor),
  ];
  return List<String?>.generate(anchors.length, (i) {
    final id = ids[i];
    if (id == null) {
      return null;
    }
    final hasPrev = i > 0 && ids[i - 1] == id;
    final hasNext = i + 1 < anchors.length && ids[i + 1] == id;
    if (!hasPrev && !hasNext) {
      return null;
    }
    if (!hasPrev && hasNext) {
      return 'begin';
    }
    if (hasPrev && hasNext) {
      return 'continue';
    }
    return 'end';
  });
}

String? _resolveAnchorBeamId(_NoteAnchor anchor) {
  for (final note in anchor.notes) {
    if (note.beamGroupId != null) {
      return note.beamGroupId;
    }
  }
  return null;
}

final class _NoteAnchor {
  const _NoteAnchor(this.beatOffset, this.duration, this.notes);

  final RationalBeats beatOffset;
  final DurationValue duration;
  final List<ScoreNote> notes;
}

/// Computes integer quarter-note subdivisions for [measure] under [activeTime].
int computeMusicXmlMeasureDivisions(
  ScoreMeasure measure,
  TimeSignature activeTime,
) {
  var lcm = activeTime.measureQuarterBeats.denominator;
  for (final slice in measure.slices) {
    lcm = musicXmlLcm(lcm, slice.beatOffset.denominator);
    for (final note in slice.trebleNotes) {
      lcm = musicXmlLcm(lcm, note.duration.quarterBeats.denominator);
    }
    for (final note in slice.bassNotes) {
      lcm = musicXmlLcm(lcm, note.duration.quarterBeats.denominator);
    }
    if (slice.trebleRest != null) {
      lcm = musicXmlLcm(
        lcm,
        slice.trebleRest!.duration.quarterBeats.denominator,
      );
    }
    if (slice.bassRest != null) {
      lcm = musicXmlLcm(lcm, slice.bassRest!.duration.quarterBeats.denominator);
    }
  }
  return lcm < 1 ? 1 : lcm;
}

/// Resolves written quarter-beat span for [measure] (preserving pickup bar lengths).
RationalBeats resolveMusicXmlMeasureBeats(
  ScoreMeasure measure,
  TimeSignature activeTime,
) {
  if (measure.measureNumber == 0 && measure.slices.isNotEmpty) {
    var maxEnd = const RationalBeats.zero();
    for (final slice in measure.slices) {
      final sliceEnd = slice.beatOffset + slice.beatDuration;
      if (sliceEnd > maxEnd) {
        maxEnd = sliceEnd;
      }
    }
    if (!maxEnd.isZero && maxEnd < activeTime.measureQuarterBeats) {
      return maxEnd;
    }
  }
  return activeTime.measureQuarterBeats;
}
