import 'dart:convert';
import 'dart:typed_data';

import 'package:piano_exercises/features/catalog/data/musicxml_measure_serializer.dart';
import 'package:piano_exercises/features/catalog/domain/score_serializer.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:xml/xml.dart';

/// Serializes a domain [Score] into UTF-8 MusicXML 4.0 `<score-partwise>` bytes.
final class MusicXmlScoreSerializer implements ScoreSerializer {
  const MusicXmlScoreSerializer();

  @override
  Uint8List serialize(Score score) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'score-partwise',
      attributes: const <String, String>{'version': '4.0'},
      nest: () {
        builder.element(
          'work',
          nest: () {
            builder.element(
              'work-title',
              nest: () => builder.text(score.title),
            );
          },
        );
        if (score.artist.trim().isNotEmpty) {
          builder.element(
            'identification',
            nest: () {
              builder.element(
                'creator',
                attributes: const <String, String>{'type': 'composer'},
                nest: () => builder.text(score.artist.trim()),
              );
            },
          );
        }
        builder.element(
          'part-list',
          nest: () {
            builder.element(
              'score-part',
              attributes: const <String, String>{'id': 'P1'},
              nest: () {
                builder.element('part-name', nest: () => builder.text('Piano'));
              },
            );
          },
        );
        builder.element(
          'part',
          attributes: const <String, String>{'id': 'P1'},
          nest: () {
            final measures = score.measures.isEmpty
                ? <ScoreMeasure>[
                    ScoreMeasure(
                      measureNumber: 1,
                      slices: const <ScoreSlice>[],
                    ),
                  ]
                : score.measures;
            final ctx = MusicXmlWriteContext(
              activeKey: score.scale.keySignature,
              activeTime: score.timeSignature,
              initialScale: score.scale,
              initialTempo: score.initialTempo,
            );
            for (var i = 0; i < measures.length; i += 1) {
              writeMusicXmlMeasure(
                builder,
                measures[i],
                measureIndex: i,
                ctx: ctx,
              );
            }
          },
        );
      },
    );

    final xmlString = builder.buildDocument().toXmlString(pretty: true);
    return Uint8List.fromList(utf8.encode(xmlString));
  }
}
