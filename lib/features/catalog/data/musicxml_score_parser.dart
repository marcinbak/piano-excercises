import 'dart:typed_data';

import 'package:piano_exercises/features/catalog/data/hardened_xml_loader.dart';
import 'package:piano_exercises/features/catalog/data/musicxml_measure_parser.dart';
import 'package:piano_exercises/features/catalog/data/musicxml_xml_helpers.dart';
import 'package:piano_exercises/features/catalog/data/mxl_archive_extractor.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:xml/xml.dart';

/// Parses `.musicxml` and compressed `.mxl` bytes into a domain [ParsedScore].
final class MusicXmlScoreParser implements ScoreParser {
  const MusicXmlScoreParser({
    HardenedXmlLoader? xmlLoader,
    MxlArchiveExtractor? mxlExtractor,
  }) : _xmlLoader = xmlLoader ?? const HardenedXmlLoader(),
       _mxlExtractor = mxlExtractor ?? const MxlArchiveExtractor();

  static const int maxMeasures = 2000;

  final HardenedXmlLoader _xmlLoader;
  final MxlArchiveExtractor _mxlExtractor;

  @override
  ParsedScore parseBytes(Uint8List bytes, {String? fileName}) {
    if (bytes.isEmpty) {
      throw const ScoreParseException('Score input is empty.');
    }
    final isZip = _hasZipHeader(bytes);
    final hasMxlExt =
        fileName != null && fileName.trim().toLowerCase().endsWith('.mxl');
    if (hasMxlExt && !isZip) {
      throw const ScoreParseException(
        'File with .mxl extension does not contain a valid ZIP header.',
      );
    }

    final sourceFormat = isZip ? ScoreFormat.mxl : ScoreFormat.musicXml;
    final xmlBytes = isZip ? _mxlExtractor.extractMusicXmlBytes(bytes) : bytes;
    final document = _xmlLoader.parseBytes(xmlBytes);
    final root = document.rootElement;
    if (root.name.local != 'score-partwise') {
      throw ScoreParseException(
        'Expected <score-partwise> root element, found <${root.name.local}>.',
      );
    }

    final title = _extractTitle(root, fileName: fileName);
    final artist = _extractArtist(root);
    final partElements = xmlChildElements(root, 'part').toList(growable: false);
    if (partElements.isEmpty || partElements.length > 2) {
      throw ScoreParseException(
        'Expected 1 or 2 <part> elements, found ${partElements.length}.',
      );
    }

    final measureInputs = _parsePartMeasures(partElements);
    final initialScale = _resolveInitialScale(measureInputs);
    final initialTime =
        measureInputs.first.timeSignature ?? TimeSignature.common;
    final timelineInputs = measureInputs
        .map((m) => m.timeline)
        .toList(growable: false);

    final Score score;
    try {
      score = ScoreTimelineReducer.reduce(
        title: title,
        artist: artist,
        initialScale: initialScale,
        initialTimeSignature: initialTime,
        measures: timelineInputs,
      );
    } on ArgumentError catch (error) {
      throw ScoreParseException('Invalid pitch or duration: ${error.message}');
    }

    final metadata = ScoreMetadata(
      title: score.title,
      artist: score.artist,
      scale: score.scale,
      timeSignature: score.timeSignature,
      initialTempo: score.initialTempo,
      measureCount: score.measures.length,
      sourceFormat: sourceFormat,
    );
    return ParsedScore(score: score, metadata: metadata);
  }

  List<_MergedPartMeasure> _parsePartMeasures(List<XmlElement> partElements) {
    final partMeasureLists = partElements
        .map(
          (part) => xmlChildElements(part, 'measure').toList(growable: false),
        )
        .toList(growable: false);
    final measureCount = partMeasureLists.first.length;
    if (measureCount < 1 || measureCount > maxMeasures) {
      throw ScoreParseException(
        'Measure count must be between 1 and $maxMeasures (found $measureCount).',
      );
    }
    if (partMeasureLists.length == 2 &&
        partMeasureLists[1].length != measureCount) {
      throw const ScoreParseException(
        'Two-part piano score parts have mismatched measure counts.',
      );
    }

    final states = <MusicXmlPartState>[
      MusicXmlPartState(defaultClef: Clef.treble),
      if (partElements.length == 2) MusicXmlPartState(defaultClef: Clef.bass),
    ];

    var activeTime = TimeSignature.common;
    final merged = <_MergedPartMeasure>[];

    for (var i = 0; i < measureCount; i += 1) {
      final primary = parseMusicXmlPartMeasure(
        partMeasureLists[0][i],
        partIndex: 0,
        fallbackMeasureNumber: i + 1,
        state: states[0],
        activeTimeSignature: activeTime,
      );
      if (primary.timeSignature != null) {
        activeTime = primary.timeSignature!;
      }

      ParsedPartMeasure? secondary;
      if (partElements.length == 2) {
        states[1].divisions ??= states[0].divisions;
        secondary = parseMusicXmlPartMeasure(
          partMeasureLists[1][i],
          partIndex: 1,
          fallbackMeasureNumber: i + 1,
          state: states[1],
          activeTimeSignature: activeTime,
        );
        if (primary.timeSignature == null && secondary.timeSignature != null) {
          activeTime = secondary.timeSignature!;
        }
      }

      final timeline = MeasureTimelineInput(
        measureNumber: primary.measureNumber,
        keySignature: primary.keySignature ?? secondary?.keySignature,
        timeSignature: primary.timeSignature ?? secondary?.timeSignature,
        tempoMark: primary.tempoMark ?? secondary?.tempoMark,
        notes: <NoteTimelineInput>[
          ...primary.notes,
          if (secondary != null) ...secondary.notes,
        ],
        rests: <RestTimelineInput>[
          ...primary.rests,
          if (secondary != null) ...secondary.rests,
        ],
      );
      merged.add(
        _MergedPartMeasure(
          timeline: timeline,
          keySignature: timeline.keySignature,
          scaleMode: primary.scaleMode ?? secondary?.scaleMode,
          timeSignature: timeline.timeSignature,
        ),
      );
    }
    return merged;
  }

  static Scale _resolveInitialScale(List<_MergedPartMeasure> measures) {
    final first = measures.first;
    final key = first.keySignature ?? KeySignature.cMajor;
    final mode = first.scaleMode ?? ScaleMode.major;
    return Scale.fromKeySignature(key, mode: mode);
  }

  static bool _hasZipHeader(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  static String _extractTitle(XmlElement root, {String? fileName}) {
    final workEl = xmlFirstChild(root, 'work');
    final workTitle = workEl == null
        ? null
        : xmlChildText(workEl, 'work-title');
    if (workTitle != null) {
      return workTitle;
    }

    final movementTitle = xmlChildText(root, 'movement-title');
    if (movementTitle != null) {
      return movementTitle;
    }

    for (final creditEl in xmlChildElements(root, 'credit')) {
      if (creditEl.getAttribute('credit-type')?.trim().toLowerCase() ==
          'title') {
        final creditWords = xmlChildText(creditEl, 'credit-words');
        if (creditWords != null) {
          return creditWords;
        }
      }
    }

    return _cleanFileNameStem(fileName) ?? 'Untitled';
  }

  static String? _cleanFileNameStem(String? fileName) {
    if (fileName == null || fileName.trim().isEmpty) {
      return null;
    }
    final normalized = fileName.replaceAll(r'\', '/');
    final baseName = normalized.split('/').last.trim();
    if (baseName.isEmpty) {
      return null;
    }
    final dotIndex = baseName.lastIndexOf('.');
    final stem = dotIndex >= 0 ? baseName.substring(0, dotIndex) : baseName;
    final cleaned = stem.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static String _extractArtist(XmlElement root) {
    final idEl = xmlFirstChild(root, 'identification');
    if (idEl == null) {
      return '';
    }
    String? untypedCreator;
    for (final creatorEl in xmlChildElements(idEl, 'creator')) {
      final text = creatorEl.innerText.trim();
      if (text.isEmpty) {
        continue;
      }
      final type = creatorEl.getAttribute('type')?.trim().toLowerCase();
      if (type == 'composer') {
        return text;
      }
      if (type == null || type.isEmpty) {
        untypedCreator ??= text;
      }
    }
    return untypedCreator ?? '';
  }
}

final class _MergedPartMeasure {
  const _MergedPartMeasure({
    required this.timeline,
    required this.keySignature,
    required this.scaleMode,
    required this.timeSignature,
  });

  final MeasureTimelineInput timeline;
  final KeySignature? keySignature;
  final ScaleMode? scaleMode;
  final TimeSignature? timeSignature;
}
