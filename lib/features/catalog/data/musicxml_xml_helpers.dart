import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:xml/xml.dart';

/// Direct child elements of [parent] matching local tag name [localName].
Iterable<XmlElement> xmlChildElements(XmlElement parent, String localName) {
  return parent.childElements.where((el) => el.name.local == localName);
}

/// First direct child element of [parent] matching [localName], or `null`.
XmlElement? xmlFirstChild(XmlElement parent, String localName) {
  for (final child in parent.childElements) {
    if (child.name.local == localName) {
      return child;
    }
  }
  return null;
}

/// Trimmed text content of first direct child matching [localName], or `null`.
String? xmlChildText(XmlElement parent, String localName) {
  final child = xmlFirstChild(parent, localName);
  if (child == null) {
    return null;
  }
  final text = child.innerText.trim();
  return text.isEmpty ? null : text;
}

/// Maximum accepted MusicXML `<duration>` tick value (`16384 * 128`).
const int maxMusicXmlDurationTicks = 16384 * 128;

/// Parses and bounds-checks a MusicXML `<duration>` integer tick value.
int parseMusicXmlDurationTicks(String raw, {required String context}) {
  final ticks = int.tryParse(raw);
  if (ticks == null || ticks < 1 || ticks > maxMusicXmlDurationTicks) {
    throw ScoreParseException(
      'Invalid $context <duration> (expected 1..$maxMusicXmlDurationTicks): $raw',
    );
  }
  return ticks;
}

/// Maps MusicXML `<type>` / `<beat-unit>` strings to [NoteBaseDuration].
NoteBaseDuration parseMusicXmlBaseDuration(String type) {
  return switch (type) {
    'whole' => NoteBaseDuration.whole,
    'half' => NoteBaseDuration.half,
    'quarter' => NoteBaseDuration.quarter,
    'eighth' => NoteBaseDuration.eighth,
    '16th' => NoteBaseDuration.sixteenth,
    '32nd' => NoteBaseDuration.thirtySecond,
    '64th' => NoteBaseDuration.sixtyFourth,
    _ => throw ScoreParseException('Unsupported note duration type: $type'),
  };
}
