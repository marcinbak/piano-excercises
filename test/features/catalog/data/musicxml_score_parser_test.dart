import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/catalog/data/hardened_xml_loader.dart';
import 'package:piano_exercises/shared/music/music.dart';

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _wrapMxl(String musicXml, {String? customContainer}) {
  final container =
      customContainer ??
      '<?xml version="1.0" encoding="UTF-8"?>'
          '<container version="1.0"><rootfiles>'
          '<rootfile full-path="score.musicxml" media-type="application/vnd.recordare.musicxml+xml"/>'
          '</rootfiles></container>';
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'META-INF/container.xml',
        utf8.encode(container).length,
        _utf8(container),
      ),
    )
    ..addFile(
      ArchiveFile(
        'score.musicxml',
        utf8.encode(musicXml).length,
        _utf8(musicXml),
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  const parser = MusicXmlScoreParser();

  group('Golden MusicXML fixtures', () {
    test(
      'parses simplified_melody_bass.musicxml into 8 measures and 22 slices',
      () {
        final bytes = File('test/fixtures/simplified_melody_bass.musicxml')
            .readAsBytesSync();
        final parsed = parser.parseBytes(
          bytes,
          fileName: 'simplified_melody_bass.musicxml',
        );

        expect(parsed.metadata.title, 'Simplified Melody + Bass');
        expect(parsed.metadata.artist, '');
        expect(parsed.metadata.scale.label, 'G Major');
        expect(parsed.metadata.timeSignature, TimeSignature(3, 4));
        expect(parsed.metadata.measureCount, 8);
        expect(parsed.metadata.sourceFormat, ScoreFormat.musicXml);

        expect(parsed.score.measures, hasLength(8));
        expect(parsed.score.slices, hasLength(22));
        for (var i = 0; i < parsed.score.slices.length; i += 1) {
          expect(parsed.score.slices[i].sliceIndex, i);
        }

        // Measure 3 beat 0 has tied-stop E5 (requiresAttack == false), beat 2 is rest-only.
        final m3 = parsed.score.measures[2];
        expect(m3.slices, hasLength(3));
        expect(m3.slices[0].trebleNotes.single.staffNote.pitchName, 'E5');
        expect(m3.slices[0].trebleNotes.single.tie, TieType.stop);
        expect(m3.slices[0].trebleNotes.single.requiresAttack, isFalse);
        expect(m3.slices[2].isRestOnly, isTrue);
        expect(m3.slices[2].trebleRest, isNotNull);
        expect(m3.slices[2].bassRest, isNotNull);

        // Measure 7 beat 0 has tied-stop D5.
        final m7 = parsed.score.measures[6];
        expect(m7.slices[0].trebleNotes.single.staffNote.pitchName, 'D5');
        expect(m7.slices[0].trebleNotes.single.requiresAttack, isFalse);
      },
    );

    test(
      'parses polyphonic_grand_staff.musicxml into 32 measures and 184 slices',
      () {
        final bytes = File('test/fixtures/polyphonic_grand_staff.musicxml')
            .readAsBytesSync();
        final parsed = parser.parseBytes(bytes);

        expect(parsed.metadata.title, 'Polyphonic Grand Staff — 32m');
        expect(parsed.metadata.scale.label, 'Eb Major');
        expect(parsed.metadata.timeSignature, TimeSignature(4, 4));
        expect(parsed.metadata.measureCount, 32);
        expect(parsed.score.measures, hasLength(32));
        expect(parsed.score.slices, hasLength(184));

        // Measure 1 slice 0: 4-note treble chord, 4-note bass chord.
        final m1s0 = parsed.score.measures[0].slices[0];
        expect(m1s0.trebleNotes, hasLength(4));
        expect(m1s0.bassNotes, hasLength(4));
        expect(m1s0.trebleNotes.every((n) => !n.showAccidental), isTrue);

        // Measure 1 beat 2 (sliceIndex 3): A4 natural override has showAccidental == true.
        final m1A4Slice = parsed.score.measures[0].slices[3];
        expect(m1A4Slice.beatOffset, RationalBeats(2));
        final a4 = m1A4Slice.trebleNotes.first;
        expect(a4.staffNote.pitchName, 'A4');
        expect(a4.showAccidental, isTrue);

        // Measure 2: 16th subdivisions and tied chord continuation on Bb4.
        final m2 = parsed.score.measures[1];
        expect(m2.slices[0].trebleNotes, hasLength(3));
        final tiedBb4 = m2.slices[0].trebleNotes.firstWhere(
          (n) => n.staffNote.note == DiatonicNote.b,
        );
        expect(tiedBb4.tie, TieType.stop);
        expect(tiedBb4.requiresAttack, isFalse);
        expect(m2.slices[0].requiredTrebleNotes, hasLength(2));
        expect(m2.slices[2].beatOffset, RationalBeats(5, 4));
        expect(m2.slices[2].beatDuration, RationalBeats(1, 4));
      },
    );
  });

  group('MusicXML features & fallbacks', () {
    test('round-trips .mxl archives and merges 2-part P1+P2 scores', () {
      const twoPartXml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <movement-title>Two Part Invention</movement-title>
  <identification>
    <creator type="composer">J. S. Bach</creator>
  </identification>
  <part-list>
    <score-part id="P1"><part-name>RH</part-name></score-part>
    <score-part id="P2"><part-name>LH</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <key><fifths>-3</fifths><mode>minor</mode></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <direction><sound tempo="108"/></direction>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><type>half</type></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>4</duration><type>half</type></note>
    </measure>
  </part>
  <part id="P2">
    <measure number="1">
      <attributes><clef><sign>F</sign><line>4</line></clef></attributes>
      <note><pitch><step>C</step><octave>3</octave></pitch><duration>8</duration><type>whole</type></note>
    </measure>
  </part>
</score-partwise>''';

      final mxlBytes = _wrapMxl(twoPartXml);
      final parsed = parser.parseBytes(mxlBytes, fileName: 'ignored.mxl');
      expect(parsed.metadata.sourceFormat, ScoreFormat.mxl);
      expect(parsed.metadata.title, 'Two Part Invention');
      expect(parsed.metadata.artist, 'J. S. Bach');
      expect(parsed.metadata.scale.label, 'C Minor');
      expect(parsed.metadata.initialTempo, TempoMark(108));
      expect(parsed.score.slices, hasLength(2));
      expect(
        parsed.score.slices[0].trebleNotes.single.staffNote.pitchName,
        'C5',
      );
      expect(parsed.score.slices[0].bassNotes.single.staffNote.pitchName, 'C3');
      expect(
        parsed.score.slices[1].trebleNotes.single.staffNote.pitchName,
        'G4',
      );
    });

    test('handles filename fallback, metronome, backup/forward, grace, print-object, 3-bar tie, double accidentals', () {
      const richXml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <key><fifths>0</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <staves>2</staves>
        <clef number="1"><sign>G</sign></clef>
        <clef number="2"><sign>F</sign></clef>
      </attributes>
      <direction>
        <direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>92</per-minute></metronome></direction-type>
      </direction>
      <note><grace/><pitch><step>D</step><octave>5</octave></pitch><type>eighth</type><staff>1</staff></note>
      <note><pitch><step>F</step><alter>2</alter><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><accidental>double-sharp</accidental><staff>1</staff></note>
      <note><pitch><step>F</step><alter>2</alter><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <note><pitch><step>B</step><alter>-2</alter><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><accidental>flat-flat</accidental><staff>1</staff></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><tie type="start"/><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <backup><duration>8</duration></backup>
      <forward><duration>4</duration></forward>
      <note print-object="no"><rest/><duration>4</duration><voice>2</voice><staff>2</staff></note>
    </measure>
    <measure number="2">
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>8</duration><tie type="stop"/><tie type="start"/><voice>1</voice><type>whole</type><staff>1</staff></note>
    </measure>
    <measure number="3">
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><tie type="stop"/><voice>1</voice><type>half</type><staff>1</staff></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice><type>half</type><staff>1</staff></note>
    </measure>
  </part>
</score-partwise>''';

      final parsed = parser.parseBytes(
        _utf8(richXml),
        fileName: '/Users/dev/scores/Nocturne Op 9.musicxml',
      );
      expect(parsed.metadata.title, 'Nocturne Op 9');
      expect(parsed.metadata.initialTempo, TempoMark(92));
      expect(parsed.score.measures, hasLength(3));

      final m1 = parsed.score.measures[0];
      // Grace note skipped, print-object="no" skipped; Fx4 carries over to second F4 in m1.
      expect(m1.slices[0].trebleNotes.single.staffNote.pitchName, 'Fx4');
      expect(m1.slices[0].trebleNotes.single.showAccidental, isTrue);
      expect(m1.slices[1].trebleNotes.single.staffNote.pitchName, 'Fx4');
      expect(m1.slices[1].trebleNotes.single.showAccidental, isFalse);
      expect(m1.slices[2].trebleNotes.single.staffNote.pitchName, 'Bbb4');
      expect(m1.slices[2].bassRest, isNull);
      expect(m1.slices[3].trebleNotes.single.tie, TieType.start);

      // 3-bar tie: m1 start -> m2 continueTie -> m3 stop; m3 F4 reset to natural!
      final m2Note = parsed.score.measures[1].slices.single.trebleNotes.single;
      expect(m2Note.tie, TieType.continueTie);
      expect(m2Note.requiresAttack, isFalse);

      final m3 = parsed.score.measures[2];
      expect(m3.slices[0].trebleNotes.single.tie, TieType.stop);
      expect(m3.slices[0].trebleNotes.single.requiresAttack, isFalse);
      expect(m3.slices[1].trebleNotes.single.staffNote.pitchName, 'F4');
    });

    test('supports credit title, untyped creator, Untitled fallback, single-staff F-clef, beams, and equality', () {
      const creditXml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <credit credit-type="title"><credit-words>Credit Title</credit-words></credit>
  <identification><creator>Anonymous</creator></identification>
  <part-list><score-part id="P1"><part-name>Bass</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <clef><sign>F</sign><line>4</line></clef>
      </attributes>
      <note><pitch><step>C</step><octave>3</octave></pitch><duration>1</duration><type>eighth</type><beam number="1">begin</beam></note>
      <note><pitch><step>D</step><octave>3</octave></pitch><duration>1</duration><type>eighth</type><beam number="1">end</beam></note>
    </measure>
  </part>
</score-partwise>''';

      final p1 = parser.parseBytes(_utf8(creditXml));
      final p2 = parser.parseBytes(_utf8(creditXml));
      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1.metadata.title, 'Credit Title');
      expect(p1.metadata.artist, 'Anonymous');
      expect(p1.score.slices[0].bassNotes.single.staffNote.pitchName, 'C3');
      expect(p1.score.slices[0].bassNotes.single.beamGroupId, isNotNull);
      expect(
        p1.score.slices[0].bassNotes.single.beamGroupId,
        p1.score.slices[1].bassNotes.single.beamGroupId,
      );

      const noTitleXml =
          '<score-partwise><part id="P1"><measure number="1">'
          '<attributes><divisions>1</divisions></attributes>'
          '<note><rest measure="yes"/></note></measure></part></score-partwise>';
      expect(parser.parseBytes(_utf8(noTitleXml)).metadata.title, 'Untitled');
      expect(
        parser
            .parseBytes(_utf8(noTitleXml), fileName: '  .musicxml')
            .metadata
            .title,
        'Untitled',
      );
    });

    test('treats omitted <alter> as natural 0 and suppresses unwritten accidental on tied continuation', () {
      const gMajorNaturalsXml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <key><fifths>1</fifths></key>
        <time><beats>3</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type><accidental>natural</accidental></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><tie type="start"/><type>quarter</type><notations><tied type="start"/></notations></note>
    </measure>
    <measure number="2">
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>3</duration><tie type="stop"/><type>half</type><dot/><notations><tied type="stop"/></notations></note>
    </measure>
  </part>
</score-partwise>''';

      final parsed = parser.parseBytes(_utf8(gMajorNaturalsXml));
      expect(parsed.score.scale.label, 'G Major');
      final m1 = parsed.score.measures[0];
      expect(m1.slices, hasLength(3));
      expect(m1.slices[0].trebleNotes.single.staffNote.pitchName, 'F4');
      expect(m1.slices[0].trebleNotes.single.midiNote.number, 65);
      expect(m1.slices[0].trebleNotes.single.showAccidental, isTrue);

      // Omitted <alter> without <accidental> stays natural F4 (MIDI 65).
      expect(m1.slices[1].trebleNotes.single.staffNote.pitchName, 'F4');
      expect(m1.slices[1].trebleNotes.single.midiNote.number, 65);
      expect(m1.slices[1].trebleNotes.single.showAccidental, isFalse);

      expect(m1.slices[2].trebleNotes.single.staffNote.pitchName, 'F4');
      expect(m1.slices[2].trebleNotes.single.midiNote.number, 65);
      expect(m1.slices[2].trebleNotes.single.showAccidental, isFalse);
      expect(m1.slices[2].trebleNotes.single.requiresAttack, isTrue);

      // Tied across barline with omitted <alter> -> F4 (MIDI 65), no unwritten accidental, no attack.
      final m2Note = parsed.score.measures[1].slices.single.trebleNotes.single;
      expect(m2Note.staffNote.pitchName, 'F4');
      expect(m2Note.midiNote.number, 65);
      expect(m2Note.showAccidental, isFalse);
      expect(m2Note.requiresAttack, isFalse);
    });
  });

  group('Hardened XML & security rejections', () {
    const validBody =
        '<score-partwise version="4.0"><part id="P1"><measure number="1">'
        '<attributes><divisions>1</divisions></attributes>'
        '<note><rest measure="yes"/></note></measure></part></score-partwise>';

    test('blocks XXE, Billion Laughs, unsafe DOCTYPE, custom entities, and invalid numeric refs', () {
      const payloads = <String>[
        '<?xml version="1.0"?><!DOCTYPE score-partwise [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>$validBody',
        '<?xml version="1.0"?><!DOCTYPE lolz [<!ENTITY lol "lol"><!ENTITY lol2 "&lol;&lol;">]>$validBody',
        '<?xml version="1.0"?><!DOCTYPE score-partwise SYSTEM "file:///etc/passwd">$validBody',
        '<?xml version="1.0"?><!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "file:///etc/passwd">$validBody',
        '<score-partwise><work><work-title>&xxe;</work-title></work><part id="P1"><measure number="1"><note><rest measure="yes"/></note></measure></part></score-partwise>',
        '<score-partwise><work><work-title>&#0;</work-title></work><part id="P1"><measure number="1"><note><rest measure="yes"/></note></measure></part></score-partwise>',
        '<score-partwise><work><work-title>&#xD800;</work-title></work><part id="P1"><measure number="1"><note><rest measure="yes"/></note></measure></part></score-partwise>',
        '<score-partwise><work><work-title>&#x110000;</work-title></work><part id="P1"><measure number="1"><note><rest measure="yes"/></note></measure></part></score-partwise>',
      ];

      for (final payload in payloads) {
        expect(
          () => parser.parseBytes(_utf8(payload)),
          throwsA(isA<ScoreParseException>()),
          reason: 'Payload should be rejected: $payload',
        );
      }

      // DOCTYPE inside META-INF/container.xml must be rejected.
      final doctypeContainerMxl = _wrapMxl(
        validBody,
        customContainer:
            '<?xml version="1.0"?><!DOCTYPE container><container><rootfiles>'
            '<rootfile full-path="score.musicxml"/></rootfiles></container>',
      );
      expect(
        () => parser.parseBytes(doctypeContainerMxl),
        throwsA(isA<ScoreParseException>()),
      );
    });

    test('enforces depth > 64, maxElements, maxByteLength, UTF-8, and MusicXML bounds', () {
      // Depth 65 (> 64).
      final openTags = List<String>.filled(65, '<a>').join();
      final closeTags = List<String>.filled(65, '</a>').join();
      expect(
        () => parser.parseBytes(_utf8('$openTags$closeTags')),
        throwsA(isA<ScoreParseException>()),
      );

      // maxElements bound.
      const smallElemParser = MusicXmlScoreParser(
        xmlLoader: HardenedXmlLoader(maxElements: 5),
      );
      expect(
        () => smallElemParser.parseBytes(_utf8(validBody)),
        throwsA(isA<ScoreParseException>()),
      );

      // maxByteLength bound.
      const smallByteParser = MusicXmlScoreParser(
        xmlLoader: HardenedXmlLoader(maxByteLength: 32),
      );
      expect(
        () => smallByteParser.parseBytes(_utf8(validBody)),
        throwsA(isA<ScoreParseException>()),
      );

      // <score-timewise>, malformed UTF-8, truncated XML, microtonal alter, bad .mxl header.
      expect(
        () => parser.parseBytes(_utf8('<score-timewise/>')),
        throwsA(isA<ScoreParseException>()),
      );
      expect(
        () => parser.parseBytes(Uint8List.fromList(<int>[0xFF, 0xFE, 0x00])),
        throwsA(isA<ScoreParseException>()),
      );
      expect(
        () => parser.parseBytes(_utf8('<score-partwise><part id="P1">')),
        throwsA(isA<ScoreParseException>()),
      );
      expect(
        () =>
            parser.parseBytes(_utf8('<score-partwise/>'), fileName: 'bad.mxl'),
        throwsA(isA<ScoreParseException>()),
      );
      expect(
        () => parser.parseBytes(
          _utf8(
            '<score-partwise><part id="P1"><measure number="1">'
            '<attributes><divisions>1</divisions></attributes>'
            '<note><pitch><step>C</step><alter>0.5</alter><octave>4</octave></pitch><duration>1</duration></note>'
            '</measure></part></score-partwise>',
          ),
        ),
        throwsA(isA<ScoreParseException>()),
      );

      // <backup> rewinding before measure start.
      expect(
        () => parser.parseBytes(
          _utf8(
            '<score-partwise><part id="P1"><measure number="1">'
            '<attributes><divisions>1</divisions></attributes>'
            '<backup><duration>2</duration></backup>'
            '</measure></part></score-partwise>',
          ),
        ),
        throwsA(isA<ScoreParseException>()),
      );

      // Mismatched 2-part measure counts.
      expect(
        () => parser.parseBytes(
          _utf8(
            '<score-partwise>'
            '<part id="P1"><measure number="1"><note><rest measure="yes"/></note></measure></part>'
            '<part id="P2"><measure number="1"><note><rest measure="yes"/></note></measure><measure number="2"><note><rest measure="yes"/></note></measure></part>'
            '</score-partwise>',
          ),
        ),
        throwsA(isA<ScoreParseException>()),
      );

      // Non-Recordare PUBLIC DOCTYPE.
      expect(
        () => parser.parseBytes(
          _utf8(
            '<?xml version="1.0"?>'
            '<!DOCTYPE score-partwise PUBLIC "-//Evil//DTD Foo//EN" "http://example.com/a.dtd">'
            '$validBody',
          ),
        ),
        throwsA(isA<ScoreParseException>()),
      );

      // Element attribute count > 32.
      final attrs = List<String>.generate(33, (i) => 'a$i="1"').join(' ');
      expect(
        () => parser.parseBytes(_utf8('<score-partwise $attrs/>')),
        throwsA(isA<ScoreParseException>()),
      );

      // Huge unclosed '&' payload fails fast in O(n) without quadratic scan.
      final stopwatch = Stopwatch()..start();
      final unclosedAmps = '&' * 200000;
      expect(
        () => parser.parseBytes(
          _utf8(
            '<score-partwise><work><work-title>$unclosedAmps</work-title></work>'
            '<part id="P1"><measure number="1"><note><rest measure="yes"/></note></measure></part></score-partwise>',
          ),
        ),
        throwsA(isA<ScoreParseException>()),
      );
      expect(
        () => parser.parseBytes(
          _utf8(
            '<score-partwise><work><work-title>&${'a' * 200000}</work-title></work>'
            '<part id="P1"><measure number="1"><note><rest measure="yes"/></note></measure></part></score-partwise>',
          ),
        ),
        throwsA(isA<ScoreParseException>()),
      );
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));

      // Max int64 <duration> ticks on note / backup / forward reject cleanly with ScoreParseException.
      for (final giantDurationSnippet in <String>[
        '<note><pitch><step>C</step><octave>4</octave></pitch><duration>9223372036854775807</duration></note>',
        '<forward><duration>9223372036854775807</duration></forward>',
        '<backup><duration>9223372036854775807</duration></backup>',
      ]) {
        expect(
          () => parser.parseBytes(
            _utf8(
              '<score-partwise><part id="P1"><measure number="1">'
              '<attributes><divisions>1</divisions></attributes>'
              '$giantDurationSnippet'
              '</measure></part></score-partwise>',
            ),
          ),
          throwsA(isA<ScoreParseException>()),
        );
      }

      // Non-finite or huge tempo values reject cleanly with ScoreParseException.
      for (final badTempoSnippet in <String>[
        '<sound tempo="NaN"/>',
        '<sound tempo="Infinity"/>',
        '<sound tempo="1e309"/>',
        '<direction><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>NaN</per-minute></metronome></direction-type></direction>',
        '<direction><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>1e309</per-minute></metronome></direction-type></direction>',
      ]) {
        expect(
          () => parser.parseBytes(
            _utf8(
              '<score-partwise><part id="P1"><measure number="1">'
              '<attributes><divisions>1</divisions></attributes>'
              '$badTempoSnippet'
              '<note><rest measure="yes"/></note>'
              '</measure></part></score-partwise>',
            ),
          ),
          throwsA(isA<ScoreParseException>()),
        );
      }
    });
  });
}
