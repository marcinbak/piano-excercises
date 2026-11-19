import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';

base class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile({
    required this.name,
    this.knownLength,
    required this.chunks,
  });

  @override
  final String name;

  final int? knownLength;
  final List<Uint8List> chunks;

  @override
  Uri get uri => Uri.file('/tmp/$name');

  @override
  Never get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => knownLength;

  @override
  Future<int?> length() async => knownLength;

  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(chunks.expand((c) => c).toList(growable: false));

  @override
  Stream<Uint8List> readAsByteStream() =>
      Stream<Uint8List>.fromIterable(chunks);
}

Uint8List _wrapMxl(Uint8List musicXmlBytes) {
  const container =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0"><rootfiles>'
      '<rootfile full-path="score.musicxml" media-type="application/vnd.recordare.musicxml+xml"/>'
      '</rootfiles></container>';
  final containerBytes = utf8.encode(container);
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'META-INF/container.xml',
        containerBytes.length,
        containerBytes,
      ),
    )
    ..addFile(
      ArchiveFile('score.musicxml', musicXmlBytes.length, musicXmlBytes),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  test('returns null when picker is cancelled', () async {
    final importer = FilePickerScoreImporter(pickFile: () async => null);
    expect(await importer.pickAndParseScore(), isNull);
  });

  test(
    'rejects unsupported extension, empty payload, and >maxBytes streaming cap',
    () async {
      final badExt = FilePickerScoreImporter(
        pickFile: () async => _FakePlatformFile(
          name: 'score.pdf',
          knownLength: 4,
          chunks: <Uint8List>[
            Uint8List.fromList(<int>[1, 2, 3, 4]),
          ],
        ),
      );
      await expectLater(
        badExt.pickAndParseScore,
        throwsA(isA<ScoreParseException>()),
      );

      final emptyFile = FilePickerScoreImporter(
        pickFile: () async => _FakePlatformFile(
          name: 'empty.musicxml',
          knownLength: null,
          chunks: const <Uint8List>[],
        ),
      );
      await expectLater(
        emptyFile.pickAndParseScore,
        throwsA(isA<ScoreParseException>()),
      );

      final oversizedSync = FilePickerScoreImporter(
        maxBytes: 100,
        pickFile: () async => _FakePlatformFile(
          name: 'big.mxl',
          knownLength: 101,
          chunks: const <Uint8List>[],
        ),
      );
      await expectLater(
        oversizedSync.pickAndParseScore,
        throwsA(isA<ScoreParseException>()),
      );

      final oversizedStream = FilePickerScoreImporter(
        maxBytes: 100,
        pickFile: () async => _FakePlatformFile(
          name: 'big_stream.musicxml',
          knownLength: null,
          chunks: <Uint8List>[Uint8List(60), Uint8List(41)],
        ),
      );
      await expectLater(
        oversizedStream.pickAndParseScore,
        throwsA(isA<ScoreParseException>()),
      );
    },
  );

  test('parses valid .musicxml and .mxl files from stream', () async {
    final xmlBytes = File('test/fixtures/simplified_melody_bass.musicxml')
        .readAsBytesSync();

    final xmlImporter = FilePickerScoreImporter(
      pickFile: () async => _FakePlatformFile(
        name: 'simplified_melody_bass.musicxml',
        knownLength: xmlBytes.length,
        chunks: <Uint8List>[xmlBytes.sublist(0, 128), xmlBytes.sublist(128)],
      ),
    );
    final xmlCandidate = await xmlImporter.pickAndParseScore();
    expect(xmlCandidate, isNotNull);
    expect(
      xmlCandidate!.parsedScore.metadata.title,
      'Simplified Melody + Bass',
    );
    expect(
      xmlCandidate.parsedScore.metadata.sourceFormat,
      ScoreFormat.musicXml,
    );

    final mxlBytes = _wrapMxl(xmlBytes);
    final mxlImporter = FilePickerScoreImporter(
      pickFile: () async => _FakePlatformFile(
        name: 'simplified.MXL',
        knownLength: mxlBytes.length,
        chunks: <Uint8List>[mxlBytes],
      ),
    );
    final mxlCandidate = await mxlImporter.pickAndParseScore();
    expect(mxlCandidate, isNotNull);
    expect(mxlCandidate!.parsedScore.metadata.scale.label, 'G Major');
    expect(mxlCandidate.parsedScore.metadata.sourceFormat, ScoreFormat.mxl);
  });
}
