import 'package:piano_exercises/shared/music/music.dart';
import 'package:xml/xml.dart';

/// Writes a pitched `<note>` element (with optional `<chord/>`, ties, and `<beam>`).
void writeMusicXmlPitchedNote(
  XmlBuilder builder, {
  required ScoreNote note,
  required int durationTicks,
  required int staff,
  bool isChord = false,
  String? beamTag,
}) {
  builder.element(
    'note',
    nest: () {
      if (isChord) {
        builder.element('chord');
      }
      final sn = note.staffNote;
      builder.element(
        'pitch',
        nest: () {
          builder.element('step', nest: () => builder.text(sn.note.letter));
          // MusicXML 4.0 treats omitted <alter> as natural regardless of key signature.
          builder.element(
            'alter',
            nest: () => builder.text('${sn.accidental.semitoneDelta}'),
          );
          builder.element('octave', nest: () => builder.text('${sn.octave}'));
        },
      );
      builder.element('duration', nest: () => builder.text('$durationTicks'));
      _writeTieElements(builder, note.tie);
      builder.element('voice', nest: () => builder.text('${note.voice}'));
      builder.element(
        'type',
        nest: () => builder.text(_musicXmlNoteType(note.duration.base)),
      );
      for (var d = 0; d < note.duration.dots; d += 1) {
        builder.element('dot');
      }
      if (note.showAccidental) {
        builder.element(
          'accidental',
          nest: () => builder.text(_musicXmlAccidental(sn.accidental)),
        );
      }
      builder.element('staff', nest: () => builder.text('$staff'));
      if (beamTag != null) {
        builder.element(
          'beam',
          attributes: const <String, String>{'number': '1'},
          nest: () => builder.text(beamTag),
        );
      }
      if (note.tie != TieType.none) {
        builder.element(
          'notations',
          nest: () => _writeTiedNotations(builder, note.tie),
        );
      }
    },
  );
}

/// Writes a non-measure `<rest>` note element.
void writeMusicXmlRestNote(
  XmlBuilder builder, {
  required DurationValue duration,
  required int durationTicks,
  required int staff,
  required int voice,
}) {
  builder.element(
    'note',
    nest: () {
      builder.element('rest');
      builder.element('duration', nest: () => builder.text('$durationTicks'));
      builder.element('voice', nest: () => builder.text('$voice'));
      builder.element(
        'type',
        nest: () => builder.text(_musicXmlNoteType(duration.base)),
      );
      for (var d = 0; d < duration.dots; d += 1) {
        builder.element('dot');
      }
      builder.element('staff', nest: () => builder.text('$staff'));
    },
  );
}

/// Writes a full-bar `<rest measure="yes"/>` spanning [durationTicks].
void writeMusicXmlMeasureRest(
  XmlBuilder builder, {
  required int durationTicks,
  required int voice,
  required int staff,
}) {
  builder.element(
    'note',
    nest: () {
      builder.element(
        'rest',
        attributes: const <String, String>{'measure': 'yes'},
      );
      builder.element('duration', nest: () => builder.text('$durationTicks'));
      builder.element('voice', nest: () => builder.text('$voice'));
      builder.element('staff', nest: () => builder.text('$staff'));
    },
  );
}

/// Writes a `<backup>` cursor rewind of [ticks].
void writeMusicXmlBackup(XmlBuilder builder, int ticks) {
  builder.element(
    'backup',
    nest: () => builder.element('duration', nest: () => builder.text('$ticks')),
  );
}

/// Writes a `<forward>` cursor advance of [ticks].
void writeMusicXmlForward(XmlBuilder builder, int ticks) {
  builder.element(
    'forward',
    nest: () => builder.element('duration', nest: () => builder.text('$ticks')),
  );
}

/// Chooses the largest standard rest duration fitting in [remaining] at [cursor].
DurationValue largestMusicXmlRestDuration(
  RationalBeats cursor,
  RationalBeats remaining,
) {
  final candidates = <DurationValue>[
    for (final base in NoteBaseDuration.values) DurationValue(base: base),
  ];
  for (final candidate in candidates) {
    final q = candidate.quarterBeats;
    if (q > remaining) {
      continue;
    }
    if (cursor.denominator > 1 && q.denominator == 1) {
      continue;
    }
    return candidate;
  }
  for (final candidate in candidates) {
    if (candidate.quarterBeats <= remaining) {
      return candidate;
    }
  }
  return DurationValue(
    base: _closestBaseDuration(remaining),
    quarterBeats: remaining,
  );
}

int musicXmlBeatsToTicks(RationalBeats beats, int divisions) {
  return (beats.numerator * divisions) ~/ beats.denominator;
}

int musicXmlLcm(int a, int b) {
  if (a <= 0 || b <= 0) {
    return 1;
  }
  var x = a;
  var y = b;
  while (y != 0) {
    final rem = x % y;
    x = y;
    y = rem;
  }
  return (a ~/ x) * b;
}

void _writeTieElements(XmlBuilder builder, TieType tie) {
  switch (tie) {
    case TieType.none:
      return;
    case TieType.start:
      builder.element(
        'tie',
        attributes: const <String, String>{'type': 'start'},
      );
    case TieType.stop:
      builder.element(
        'tie',
        attributes: const <String, String>{'type': 'stop'},
      );
    case TieType.continueTie:
      builder.element(
        'tie',
        attributes: const <String, String>{'type': 'stop'},
      );
      builder.element(
        'tie',
        attributes: const <String, String>{'type': 'start'},
      );
  }
}

void _writeTiedNotations(XmlBuilder builder, TieType tie) {
  switch (tie) {
    case TieType.none:
      return;
    case TieType.start:
      builder.element(
        'tied',
        attributes: const <String, String>{'type': 'start'},
      );
    case TieType.stop:
      builder.element(
        'tied',
        attributes: const <String, String>{'type': 'stop'},
      );
    case TieType.continueTie:
      builder.element(
        'tied',
        attributes: const <String, String>{'type': 'stop'},
      );
      builder.element(
        'tied',
        attributes: const <String, String>{'type': 'start'},
      );
  }
}

NoteBaseDuration _closestBaseDuration(RationalBeats beats) {
  for (final base in NoteBaseDuration.values) {
    if (beats >= base.quarterBeats) {
      return base;
    }
  }
  return NoteBaseDuration.sixtyFourth;
}

String _musicXmlNoteType(NoteBaseDuration base) => switch (base) {
  NoteBaseDuration.whole => 'whole',
  NoteBaseDuration.half => 'half',
  NoteBaseDuration.quarter => 'quarter',
  NoteBaseDuration.eighth => 'eighth',
  NoteBaseDuration.sixteenth => '16th',
  NoteBaseDuration.thirtySecond => '32nd',
  NoteBaseDuration.sixtyFourth => '64th',
};

String _musicXmlAccidental(Accidental accidental) => switch (accidental) {
  Accidental.doubleFlat => 'double-flat',
  Accidental.flat => 'flat',
  Accidental.natural => 'natural',
  Accidental.sharp => 'sharp',
  Accidental.doubleSharp => 'sharp-sharp',
};
