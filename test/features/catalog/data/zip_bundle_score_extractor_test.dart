import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _wrapMxl(Uint8List musicXmlBytes) {
  const container =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0"><rootfiles>'
      '<rootfile full-path="score.musicxml" media-type="application/vnd.recordare.musicxml+xml"/>'
      '</rootfiles></container>';
  final archive = Archive()
    ..addFile(
      ArchiveFile('META-INF/container.xml', container.length, _utf8(container)),
    )
    ..addFile(
      ArchiveFile('score.musicxml', musicXmlBytes.length, musicXmlBytes),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

Uint8List _encodeZip(
  Map<String, Uint8List> entries, {
  String? password,
  void Function(String name, ArchiveFile file)? mutateFile,
}) {
  final archive = Archive();
  for (final entry in entries.entries) {
    final file = ArchiveFile(entry.key, entry.value.length, entry.value);
    mutateFile?.call(entry.key, file);
    archive.addFile(file);
  }
  return Uint8List.fromList(ZipEncoder(password: password).encode(archive)!);
}

void _writeUint32Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}

int _findSignature(Uint8List bytes, List<int> sig, {int start = 0}) {
  for (var i = start; i <= bytes.length - sig.length; i += 1) {
    var matched = true;
    for (var j = 0; j < sig.length; j += 1) {
      if (bytes[i + j] != sig[j]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return i;
    }
  }
  return -1;
}

void main() {
  const parser = MusicXmlScoreParser();
  const extractor = ZipBundleScoreExtractor(parser: parser);
  late Uint8List simpleXml;
  late Uint8List polyXml;
  late Uint8List simpleMxl;

  setUpAll(() {
    simpleXml = File('test/fixtures/simplified_melody_bass.musicxml')
        .readAsBytesSync();
    polyXml = File('test/fixtures/polyphonic_grand_staff.musicxml')
        .readAsBytesSync();
    simpleMxl = _wrapMxl(simpleXml);
  });

  group('ZipBundleScoreExtractor', () {
    test('extracts multi-folder .mxl + .musicxml while counting non-scores and skipping OS metadata', () async {
      final entries = <String, Uint8List>{
        'beginner/': Uint8List(0),
        'beginner/simple.mxl': simpleMxl,
        'advanced/poly.musicxml': polyXml,
        'validation_report.json': _utf8('{"ok":true}'),
        '__MACOSX/beginner/._simple.mxl': _utf8('appledouble'),
        '.DS_Store': _utf8('finder'),
        'beginner/Thumbs.db': _utf8('thumbs'),
        'desktop.ini': _utf8('ini'),
      };
      // Include >8 score entries to exercise periodic event-loop yields.
      for (var i = 0; i < 8; i += 1) {
        entries['extra/score_$i.musicxml'] = simpleXml;
      }

      final zip = _encodeZip(entries);
      final selection = await extractor.extractBundle(zip);

      expect(selection.isBundle, isTrue);
      expect(selection.ignoredNonScoreCount, 1);
      expect(selection.failures, isEmpty);
      expect(selection.candidates, hasLength(10));
      expect(selection.candidates[0].fileName, 'simple.mxl');
      expect(selection.candidates[0].archiveEntryPath, 'beginner/simple.mxl');
      expect(
        selection.candidates[0].parsedScore.metadata.sourceFormat,
        ScoreFormat.mxl,
      );
      expect(selection.candidates[1].fileName, 'poly.musicxml');
      expect(
        selection.candidates[1].archiveEntryPath,
        'advanced/poly.musicxml',
      );
      expect(
        selection.candidates[1].parsedScore.metadata.sourceFormat,
        ScoreFormat.musicXml,
      );
    });

    test('records per-entry failures for corrupt .mxl and nested .zip without blocking valid scores', () async {
      final zip = _encodeZip(<String, Uint8List>{
        'valid/simple.mxl': simpleMxl,
        'broken/corrupt.mxl': _utf8('not a zip'),
        'nested/inner.zip': _encodeZip(<String, Uint8List>{
          'inner.musicxml': simpleXml,
        }),
      });

      final selection = await extractor.extractBundle(zip);
      expect(selection.candidates, hasLength(1));
      expect(selection.candidates.single.archiveEntryPath, 'valid/simple.mxl');
      expect(selection.failures, hasLength(2));
      expect(
        selection.failures.map((f) => f.sourceName),
        containsAll(<String>['broken/corrupt.mxl', 'nested/inner.zip']),
      );
      expect(
        selection.failures
            .firstWhere((f) => f.sourceName == 'nested/inner.zip')
            .message,
        contains('Nested .zip'),
      );
    });

    test(
      'throws ScoreParseException when bundle yields zero valid scores',
      () async {
        final onlyMetadataAndJson = _encodeZip(<String, Uint8List>{
          'validation_report.json': _utf8('{}'),
          '__MACOSX/._ghost.mxl': _utf8('ghost'),
          '.DS_Store': _utf8('ds'),
        });
        await expectLater(
          () => extractor.extractBundle(onlyMetadataAndJson),
          throwsA(isA<ScoreParseException>()),
        );

        final onlyBadEntries = _encodeZip(<String, Uint8List>{
          'corrupt.mxl': _utf8('bad'),
          'nested.zip': _utf8('PK'),
        });
        await expectLater(
          () => extractor.extractBundle(onlyBadEntries),
          throwsA(isA<ScoreParseException>()),
        );
      },
    );

    test(
      'rejects >500 entries, ZIP64, and bad EOCDR before decompression',
      () async {
        final manyEntries = <String, Uint8List>{
          for (var i = 0; i < 501; i += 1) 's_$i.musicxml': simpleXml,
        };
        final over500Zip = _encodeZip(manyEntries);
        await expectLater(
          () => extractor.extractBundle(over500Zip),
          throwsA(isA<ScoreParseException>()),
        );

        final baseZip = _encodeZip(<String, Uint8List>{
          's.musicxml': simpleXml,
        });
        final eocdrPos = _findSignature(baseZip, <int>[0x50, 0x4B, 0x05, 0x06]);
        expect(eocdrPos, greaterThan(0));

        final zip64 = Uint8List.fromList(baseZip);
        zip64[eocdrPos + 10] = 0xFF;
        zip64[eocdrPos + 11] = 0xFF;
        await expectLater(
          () => extractor.extractBundle(zip64),
          throwsA(isA<ScoreParseException>()),
        );

        final badEocdr = Uint8List.fromList(baseZip);
        badEocdr[eocdrPos + 20] = 10;
        badEocdr[eocdrPos + 21] = 0;
        await expectLater(
          () => extractor.extractBundle(badEocdr),
          throwsA(isA<ScoreParseException>()),
        );
      },
    );

    test('aborts deflate bombs, >10 MB single entry, and >50 MB cumulative declared bundles', () async {
      final bombZip = _encodeZip(<String, Uint8List>{
        'bomb.musicxml': Uint8List(11 * 1024 * 1024),
      });
      final localPos = _findSignature(bombZip, <int>[0x50, 0x4B, 0x03, 0x04]);
      _writeUint32Le(bombZip, localPos + 22, 128);
      final centralPos = _findSignature(bombZip, <int>[0x50, 0x4B, 0x01, 0x02]);
      _writeUint32Le(bombZip, centralPos + 24, 128);
      await expectLater(
        () => extractor.extractBundle(bombZip),
        throwsA(isA<ScoreParseException>()),
      );

      final over10MbZip = _encodeZip(<String, Uint8List>{
        'huge.musicxml': Uint8List(10 * 1024 * 1024 + 1),
      });
      await expectLater(
        () => extractor.extractBundle(over10MbZip),
        throwsA(isA<ScoreParseException>()),
      );

      final companionOver10MbPdf = _encodeZip(<String, Uint8List>{
        'valid.mxl': simpleMxl,
        'companion_booklet.pdf': Uint8List(15 * 1024 * 1024),
      });
      final companionSelection = await extractor.extractBundle(
        companionOver10MbPdf,
      );
      expect(companionSelection.candidates, hasLength(1));
      expect(companionSelection.candidates.single.fileName, 'valid.mxl');
      expect(companionSelection.ignoredNonScoreCount, 1);
      expect(companionSelection.failures, isEmpty);

      final nineMb = Uint8List(9 * 1024 * 1024);
      final over50MbCumulative = _encodeZip(<String, Uint8List>{
        'a.musicxml': nineMb,
        'b.musicxml': nineMb,
        'c.musicxml': nineMb,
        'd.musicxml': nineMb,
        'e.musicxml': nineMb,
        'f.musicxml': nineMb,
      });
      await expectLater(
        () => extractor.extractBundle(over50MbCumulative),
        throwsA(isA<ScoreParseException>()),
      );
    });

    test('rejects UNIX symlinks, encrypted entries, path traversal, and local/central mismatch', () async {
      final symlinkZip = _encodeZip(<String, Uint8List>{
        'link.musicxml': simpleXml,
      }, mutateFile: (_, file) => file.mode = 0xA1FF);
      await expectLater(
        () => extractor.extractBundle(symlinkZip),
        throwsA(isA<ScoreParseException>()),
      );

      final encryptedZip = _encodeZip(<String, Uint8List>{
        'secret.musicxml': simpleXml,
      }, password: 'pw');
      await expectLater(
        () => extractor.extractBundle(encryptedZip),
        throwsA(isA<ScoreParseException>()),
      );

      final traversalZip = _encodeZip(<String, Uint8List>{
        'score.musicxml': simpleXml,
      }, mutateFile: (_, file) => file.name = '../evil.musicxml');
      await expectLater(
        () => extractor.extractBundle(traversalZip),
        throwsA(isA<ScoreParseException>()),
      );

      final mismatchZip = _encodeZip(<String, Uint8List>{
        'score.musicxml': simpleXml,
      });
      final localOffset = _findSignature(mismatchZip, <int>[
        0x50,
        0x4B,
        0x03,
        0x04,
      ]);
      final spoof = utf8.encode('../evil1.music'); // 14 bytes == score.musicxml
      mismatchZip.setRange(
        localOffset + 30,
        localOffset + 30 + spoof.length,
        spoof,
      );
      await expectLater(
        () => extractor.extractBundle(mismatchZip),
        throwsA(isA<ScoreParseException>()),
      );
    });
  });
}
