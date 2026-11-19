import 'package:piano_exercises/features/catalog/data/musicxml_note_parser.dart';
import 'package:piano_exercises/features/catalog/data/musicxml_xml_helpers.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:xml/xml.dart';

/// Mutable clef and division state carried across measures of one `<part>`.
final class MusicXmlPartState {
  MusicXmlPartState({required Clef defaultClef})
    : staffClefs = <int, Clef>{1: defaultClef, 2: Clef.bass};

  int? divisions;
  final Map<int, Clef> staffClefs;
}

/// Intermediate measure data extracted from a single `<part>/<measure>`.
final class ParsedPartMeasure {
  const ParsedPartMeasure({
    required this.measureNumber,
    required this.notes,
    required this.rests,
    this.keySignature,
    this.scaleMode,
    this.timeSignature,
    this.tempoMark,
  });

  final int measureNumber;
  final List<NoteTimelineInput> notes;
  final List<RestTimelineInput> rests;
  final KeySignature? keySignature;
  final ScaleMode? scaleMode;
  final TimeSignature? timeSignature;
  final TempoMark? tempoMark;
}

/// Parses one MusicXML `<measure>` element for [partIndex] using [state].
ParsedPartMeasure parseMusicXmlPartMeasure(
  XmlElement measureEl, {
  required int partIndex,
  required int fallbackMeasureNumber,
  required MusicXmlPartState state,
  required TimeSignature activeTimeSignature,
}) {
  final numberAttr = measureEl.getAttribute('number')?.trim();
  final measureNumber = (numberAttr != null && numberAttr.isNotEmpty)
      ? (int.tryParse(numberAttr) ?? fallbackMeasureNumber)
      : fallbackMeasureNumber;

  final ctx = MeasureTimelineCursor(
    partIndex: partIndex,
    measureNumber: measureNumber,
    staffClefs: state.staffClefs,
    activeTimeSignature: activeTimeSignature,
    divisions: state.divisions,
  );

  KeySignature? keySignature;
  ScaleMode? scaleMode;
  TimeSignature? timeSignature;
  TempoMark? tempoMark;

  for (final child in measureEl.childElements) {
    switch (child.name.local) {
      case 'attributes':
        final attrResult = _parseAttributes(child, ctx);
        keySignature = attrResult.keySignature ?? keySignature;
        scaleMode = attrResult.scaleMode ?? scaleMode;
        timeSignature = attrResult.timeSignature ?? timeSignature;
      case 'direction':
        tempoMark ??= _parseDirectionTempo(child);
      case 'sound':
        tempoMark ??= _parseSoundTempo(child);
      case 'backup':
        _applyCursorShift(child, ctx, forward: false);
      case 'forward':
        _applyCursorShift(child, ctx, forward: true);
      case 'note':
        parseMusicXmlNoteElement(child, ctx);
      default:
        break;
    }
  }

  state.divisions = ctx.divisions;
  return ParsedPartMeasure(
    measureNumber: measureNumber,
    notes: ctx.notes,
    rests: ctx.rests,
    keySignature: keySignature,
    scaleMode: scaleMode,
    timeSignature: timeSignature,
    tempoMark: tempoMark,
  );
}

({
  KeySignature? keySignature,
  ScaleMode? scaleMode,
  TimeSignature? timeSignature,
})
_parseAttributes(XmlElement attrs, MeasureTimelineCursor ctx) {
  final divText = xmlChildText(attrs, 'divisions');
  if (divText != null) {
    final div = int.tryParse(divText);
    if (div == null || div < 1 || div > 16384) {
      throw ScoreParseException('Invalid <divisions> value: $divText');
    }
    ctx.divisions = div;
  }
  final stavesText = xmlChildText(attrs, 'staves');
  if (stavesText != null) {
    final staves = int.tryParse(stavesText);
    if (staves == null || staves < 1 || staves > 2) {
      throw ScoreParseException('Unsupported <staves> count: $stavesText');
    }
  }

  KeySignature? keySignature;
  ScaleMode? scaleMode;
  final keyEl = xmlFirstChild(attrs, 'key');
  if (keyEl != null) {
    final fifthsText = xmlChildText(keyEl, 'fifths');
    final fifths = fifthsText == null ? null : int.tryParse(fifthsText);
    if (fifths == null || fifths < -7 || fifths > 7) {
      throw ScoreParseException('Invalid <key><fifths>: $fifthsText');
    }
    keySignature = KeySignature.validated(fifths);
    final modeText = xmlChildText(keyEl, 'mode')?.toLowerCase();
    scaleMode = modeText == 'minor' ? ScaleMode.minor : ScaleMode.major;
  }

  TimeSignature? timeSignature;
  final timeEl = xmlFirstChild(attrs, 'time');
  if (timeEl != null) {
    timeSignature = _parseTime(timeEl);
    ctx.activeTimeSignature = timeSignature;
  }

  for (final clefEl in xmlChildElements(attrs, 'clef')) {
    _parseClef(clefEl, ctx.staffClefs);
  }
  return (
    keySignature: keySignature,
    scaleMode: scaleMode,
    timeSignature: timeSignature,
  );
}

TimeSignature _parseTime(XmlElement timeEl) {
  final beatsText = xmlChildText(timeEl, 'beats');
  final beatTypeText = xmlChildText(timeEl, 'beat-type');
  final beats = beatsText == null ? null : int.tryParse(beatsText);
  final beatType = beatTypeText == null ? null : int.tryParse(beatTypeText);
  if (beats == null || beatType == null) {
    throw const ScoreParseException('Invalid <time> beats or beat-type.');
  }
  try {
    return TimeSignature(beats, beatType);
  } on ArgumentError catch (error) {
    throw ScoreParseException('Unsupported <time> signature: ${error.message}');
  }
}

void _parseClef(XmlElement clefEl, Map<int, Clef> staffClefs) {
  final numAttr = clefEl.getAttribute('number')?.trim();
  final staffNumber = numAttr == null ? 1 : int.tryParse(numAttr);
  if (staffNumber == null || staffNumber < 1 || staffNumber > 2) {
    throw ScoreParseException('Unsupported <clef number="$numAttr">.');
  }
  final sign = xmlChildText(clefEl, 'sign')?.toUpperCase();
  staffClefs[staffNumber] = switch (sign) {
    'G' => Clef.treble,
    'F' => Clef.bass,
    _ => throw ScoreParseException('Unsupported <clef><sign>: $sign'),
  };
}

TempoMark? _parseDirectionTempo(XmlElement directionEl) {
  final soundEl = xmlFirstChild(directionEl, 'sound');
  if (soundEl != null && soundEl.getAttribute('tempo') != null) {
    return _parseSoundTempo(soundEl);
  }
  for (final typeEl in xmlChildElements(directionEl, 'direction-type')) {
    final metronomeEl = xmlFirstChild(typeEl, 'metronome');
    if (metronomeEl != null) {
      return _parseMetronomeTempo(metronomeEl);
    }
  }
  return null;
}

TempoMark? _parseSoundTempo(XmlElement soundEl) {
  final rawTempo = soundEl.getAttribute('tempo')?.trim();
  if (rawTempo == null) {
    return null;
  }
  final parsed = double.tryParse(rawTempo);
  if (parsed == null || !parsed.isFinite || parsed < 0.5 || parsed > 999.4) {
    throw ScoreParseException('Invalid <sound tempo="$rawTempo">.');
  }
  return TempoMark(parsed.round());
}

TempoMark _parseMetronomeTempo(XmlElement metronomeEl) {
  final perMinuteText = xmlChildText(metronomeEl, 'per-minute');
  final perMinute = perMinuteText == null
      ? null
      : double.tryParse(perMinuteText);
  if (perMinute == null || !perMinute.isFinite || perMinute <= 0) {
    throw ScoreParseException(
      'Invalid <metronome><per-minute>: $perMinuteText',
    );
  }
  final unitText = xmlChildText(metronomeEl, 'beat-unit')?.toLowerCase();
  final base = parseMusicXmlBaseDuration(unitText ?? 'quarter');
  final dots = xmlChildElements(metronomeEl, 'beat-unit-dot').length;
  if (dots > 2) {
    throw const ScoreParseException('Unsupported >2 <beat-unit-dot> marks.');
  }
  final dotScale = ((1 << (dots + 1)) - 1) / (1 << dots);
  final scaledBpm = perMinute * base.quarterBeats.toDouble * dotScale;
  if (!scaledBpm.isFinite || scaledBpm < 0.5 || scaledBpm > 999.4) {
    throw ScoreParseException(
      'Out-of-range metronome tempo: $perMinuteText BPM.',
    );
  }
  return TempoMark(scaledBpm.round());
}

void _applyCursorShift(
  XmlElement shiftEl,
  MeasureTimelineCursor ctx, {
  required bool forward,
}) {
  final divisions = ctx.divisions;
  if (divisions == null) {
    throw const ScoreParseException('Missing <divisions> before cursor shift.');
  }
  final durText = xmlChildText(shiftEl, 'duration');
  if (durText == null) {
    throw const ScoreParseException('Missing shift <duration>.');
  }
  final ticks = parseMusicXmlDurationTicks(
    durText,
    context: forward ? '<forward>' : '<backup>',
  );
  final delta = RationalBeats(ticks, divisions);
  if (forward) {
    ctx.cursor = ctx.cursor + delta;
  } else {
    if (delta > ctx.cursor) {
      throw const ScoreParseException(
        '<backup> rewinds cursor before measure start.',
      );
    }
    ctx.cursor = ctx.cursor - delta;
  }
}
