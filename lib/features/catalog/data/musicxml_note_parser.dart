import 'package:piano_exercises/features/catalog/data/musicxml_pitch_tie_parser.dart';
import 'package:piano_exercises/features/catalog/data/musicxml_xml_helpers.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:xml/xml.dart';

/// Mutable per-measure cursor and beam state shared between measure and note parsers.
final class MeasureTimelineCursor {
  MeasureTimelineCursor({
    required this.partIndex,
    required this.measureNumber,
    required this.staffClefs,
    required this.activeTimeSignature,
    this.divisions,
  });

  final int partIndex;
  final int measureNumber;
  final Map<int, Clef> staffClefs;
  TimeSignature activeTimeSignature;
  int? divisions;

  RationalBeats cursor = const RationalBeats.zero();
  RationalBeats? lastNoteStart;
  RationalBeats? lastNoteEnd;
  final Map<int, RationalBeats> lastVoiceNoteStart = <int, RationalBeats>{};
  final Map<int, RationalBeats> lastVoiceNoteEnd = <int, RationalBeats>{};
  final Map<(Clef, int), String> activeBeamIds = <(Clef, int), String>{};
  int beamSequence = 0;
  final List<NoteTimelineInput> notes = <NoteTimelineInput>[];
  final List<RestTimelineInput> rests = <RestTimelineInput>[];
}

/// Parses a `<note>` element and updates [ctx] cursor and collected events.
void parseMusicXmlNoteElement(XmlElement noteEl, MeasureTimelineCursor ctx) {
  if (xmlFirstChild(noteEl, 'grace') != null) {
    return;
  }
  final isChord = xmlFirstChild(noteEl, 'chord') != null;
  final restEl = xmlFirstChild(noteEl, 'rest');
  final isMeasureRest = restEl?.getAttribute('measure') == 'yes';
  final duration = _parseDuration(noteEl, ctx, isMeasureRest: isMeasureRest);
  final voice = _parseVoice(noteEl);
  final startOffset = _advanceOrAnchorCursor(
    ctx,
    isChord: isChord,
    voice: voice,
    durationBeats: duration.quarterBeats,
  );
  if (noteEl.getAttribute('print-object') == 'no') {
    return;
  }

  final clef = _resolveClef(noteEl, ctx.staffClefs);
  if (restEl != null) {
    ctx.rests.add(
      RestTimelineInput(
        clef: clef,
        beatOffset: startOffset,
        duration: duration,
        voice: voice,
      ),
    );
    return;
  }

  final pitchEl = xmlFirstChild(noteEl, 'pitch');
  if (pitchEl == null) {
    throw const ScoreParseException('<note> missing <pitch> or <rest>.');
  }
  final (step, octave, explicitAlter) = parseMusicXmlPitch(pitchEl);
  final writtenAccidental = parseMusicXmlAccidental(
    xmlChildText(noteEl, 'accidental'),
  );
  final tie = parseMusicXmlTie(noteEl);
  final beamGroupId = _parseBeamGroup(noteEl, ctx, clef: clef, voice: voice);

  ctx.notes.add(
    NoteTimelineInput(
      clef: clef,
      diatonicNote: step,
      octave: octave,
      explicitAlter: explicitAlter,
      writtenAccidental: writtenAccidental,
      beatOffset: startOffset,
      duration: duration,
      tie: tie,
      voice: voice,
      beamGroupId: beamGroupId,
    ),
  );
}

RationalBeats _advanceOrAnchorCursor(
  MeasureTimelineCursor ctx, {
  required bool isChord,
  required int voice,
  required RationalBeats durationBeats,
}) {
  if (isChord) {
    final anchorStart = ctx.lastVoiceNoteStart[voice] ?? ctx.lastNoteStart;
    final anchorEnd = ctx.lastVoiceNoteEnd[voice] ?? ctx.lastNoteEnd;
    if (anchorStart == null || anchorEnd == null) {
      throw const ScoreParseException(
        'Unexpected <chord/> without preceding note.',
      );
    }
    final endOffset = anchorStart + durationBeats;
    if (endOffset > anchorEnd && ctx.cursor == anchorEnd) {
      ctx.cursor = endOffset;
      ctx.lastVoiceNoteEnd[voice] = endOffset;
      ctx.lastNoteEnd = endOffset;
    }
    return anchorStart;
  }

  final startOffset = ctx.cursor;
  final endOffset = startOffset + durationBeats;
  ctx.cursor = endOffset;
  ctx.lastVoiceNoteStart[voice] = startOffset;
  ctx.lastVoiceNoteEnd[voice] = endOffset;
  ctx.lastNoteStart = startOffset;
  ctx.lastNoteEnd = endOffset;
  return startOffset;
}

DurationValue _parseDuration(
  XmlElement noteEl,
  MeasureTimelineCursor ctx, {
  required bool isMeasureRest,
}) {
  final durText = xmlChildText(noteEl, 'duration');
  final RationalBeats beats;
  if (durText != null) {
    final divisions = ctx.divisions;
    if (divisions == null) {
      throw const ScoreParseException('Missing <divisions> before <duration>.');
    }
    final ticks = int.tryParse(durText);
    if (ticks == null || ticks <= 0) {
      throw ScoreParseException('Invalid <note><duration>: $durText');
    }
    beats = RationalBeats(ticks, divisions);
  } else if (isMeasureRest) {
    beats = ctx.activeTimeSignature.measureQuarterBeats;
  } else {
    throw const ScoreParseException('<note> missing <duration>.');
  }

  final dots = xmlChildElements(noteEl, 'dot').length;
  if (dots > 2) {
    throw ScoreParseException('Unsupported augmentation dot count: $dots');
  }
  final typeText = xmlChildText(noteEl, 'type')?.toLowerCase();
  final base = typeText != null
      ? parseMusicXmlBaseDuration(typeText)
      : (isMeasureRest ? NoteBaseDuration.whole : _inferBaseDuration(beats));
  return DurationValue(base: base, dots: dots, quarterBeats: beats);
}

int _parseVoice(XmlElement noteEl) {
  final voiceText = xmlChildText(noteEl, 'voice');
  if (voiceText == null) {
    return 1;
  }
  final voice = int.tryParse(voiceText);
  if (voice == null || voice < 1) {
    throw ScoreParseException('Invalid <voice>: $voiceText');
  }
  return voice;
}

Clef _resolveClef(XmlElement noteEl, Map<int, Clef> staffClefs) {
  final staffText = xmlChildText(noteEl, 'staff');
  final staff = staffText == null ? 1 : int.tryParse(staffText);
  if (staff == null || staff < 1 || staff > 2) {
    throw ScoreParseException('Unsupported <staff> number: $staffText');
  }
  return staffClefs[staff] ?? (staff == 2 ? Clef.bass : Clef.treble);
}

String? _parseBeamGroup(
  XmlElement noteEl,
  MeasureTimelineCursor ctx, {
  required Clef clef,
  required int voice,
}) {
  for (final beamEl in xmlChildElements(noteEl, 'beam')) {
    final numAttr = beamEl.getAttribute('number')?.trim();
    if (numAttr != null && numAttr != '1') {
      continue;
    }
    final key = (clef, voice);
    switch (beamEl.innerText.trim().toLowerCase()) {
      case 'begin':
        final id =
            'm${ctx.measureNumber}-p${ctx.partIndex}-v$voice-b${ctx.beamSequence++}';
        ctx.activeBeamIds[key] = id;
        return id;
      case 'continue':
        return ctx.activeBeamIds[key];
      case 'end':
        return ctx.activeBeamIds.remove(key);
      default:
        return null;
    }
  }
  return null;
}

NoteBaseDuration _inferBaseDuration(RationalBeats beats) {
  for (final candidate in NoteBaseDuration.values) {
    if (beats >= candidate.quarterBeats) {
      return candidate;
    }
  }
  return NoteBaseDuration.sixtyFourth;
}
