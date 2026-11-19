import 'package:piano_exercises/features/catalog/data/musicxml_xml_helpers.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:xml/xml.dart';

/// Parses MusicXML `<pitch>` into `(diatonicNote, octave, explicitAlter)`.
(DiatonicNote, int, int?) parseMusicXmlPitch(XmlElement pitchEl) {
  final stepText = xmlChildText(pitchEl, 'step')?.toUpperCase();
  final step = switch (stepText) {
    'C' => DiatonicNote.c,
    'D' => DiatonicNote.d,
    'E' => DiatonicNote.e,
    'F' => DiatonicNote.f,
    'G' => DiatonicNote.g,
    'A' => DiatonicNote.a,
    'B' => DiatonicNote.b,
    _ => throw ScoreParseException('Invalid <pitch><step>: $stepText'),
  };
  final octaveText = xmlChildText(pitchEl, 'octave');
  final octave = octaveText == null ? null : int.tryParse(octaveText);
  if (octave == null || octave < -2 || octave > 10) {
    throw ScoreParseException('Invalid <pitch><octave>: $octaveText');
  }
  final alterText = xmlChildText(pitchEl, 'alter');
  int? explicitAlter;
  if (alterText != null) {
    final parsed = int.tryParse(alterText);
    if (parsed == null || parsed < -2 || parsed > 2) {
      throw ScoreParseException(
        'Unsupported or microtonal <pitch><alter>: $alterText',
      );
    }
    explicitAlter = parsed;
  }
  return (step, octave, explicitAlter);
}

/// Parses MusicXML `<accidental>` text into an [Accidental].
Accidental? parseMusicXmlAccidental(String? raw) {
  if (raw == null) {
    return null;
  }
  return switch (raw.toLowerCase()) {
    'sharp' => Accidental.sharp,
    'flat' => Accidental.flat,
    'natural' => Accidental.natural,
    'double-sharp' || 'sharp-sharp' => Accidental.doubleSharp,
    'flat-flat' || 'double-flat' => Accidental.doubleFlat,
    _ => throw ScoreParseException('Unsupported <accidental>: $raw'),
  };
}

/// Resolves `<tie>` and `<notations><tied>` children on a `<note>` into [TieType].
TieType parseMusicXmlTie(XmlElement noteEl) {
  var hasStart = false;
  var hasStop = false;
  var hasContinue = false;

  void recordType(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'start':
        hasStart = true;
      case 'stop':
        hasStop = true;
      case 'continue':
        hasContinue = true;
    }
  }

  for (final tieEl in xmlChildElements(noteEl, 'tie')) {
    recordType(tieEl.getAttribute('type'));
  }
  final notationsEl = xmlFirstChild(noteEl, 'notations');
  if (notationsEl != null) {
    for (final tiedEl in xmlChildElements(notationsEl, 'tied')) {
      recordType(tiedEl.getAttribute('type'));
    }
  }
  if (hasContinue || (hasStart && hasStop)) {
    return TieType.continueTie;
  }
  if (hasStart) {
    return TieType.start;
  }
  return hasStop ? TieType.stop : TieType.none;
}
