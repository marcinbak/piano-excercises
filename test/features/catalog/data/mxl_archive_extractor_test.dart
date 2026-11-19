import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/data/mxl_archive_extractor.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

String _containerXml(String rootPath, {String? mediaType}) {
  final mediaAttr = mediaType == null ? '' : ' media-type="$mediaType"';
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0">'
      '<rootfiles><rootfile full-path="$rootPath"$mediaAttr/></rootfiles>'
      '</container>';
}

Uint8List _encodeMxl(
  Map<String, Uint8List> entries, {
  bool compress = true,
  String? password,
  void Function(String name, ArchiveFile file)? mutateFile,
}) {
  final archive = Archive();
  for (final entry in entries.entries) {
    final file = ArchiveFile(entry.key, entry.value.length, entry.value)
      ..compress = compress;
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
  const extractor = MxlArchiveExtractor();
  const sampleScore =
      '<score-partwise version="4.0"><part id="P1"/></score-partwise>';

  group('MxlArchiveExtractor', () {
    test(
      'extracts valid DEFLATE and STORE .mxl archives and allows dir entry',
      () {
        final deflated = _encodeMxl(<String, Uint8List>{
          'META-INF/container.xml': _utf8(
            _containerXml(
              'score.musicxml',
              mediaType: 'application/vnd.recordare.musicxml+xml',
            ),
          ),
          'score.musicxml': _utf8(sampleScore),
        });
        expect(
          utf8.decode(extractor.extractMusicXmlBytes(deflated)),
          sampleScore,
        );

        final storedWithDir = _encodeMxl(<String, Uint8List>{
          'META-INF/': Uint8List(0),
          'META-INF/container.xml': _utf8(_containerXml('scores/main.xml')),
          'scores/main.xml': _utf8(sampleScore),
        }, compress: false);
        expect(
          utf8.decode(extractor.extractMusicXmlBytes(storedWithDir)),
          sampleScore,
        );
      },
    );

    test(
      'aborts spoofed-header 11 MB deflate bomb without unbounded allocation',
      () {
        final bombBytes = Uint8List(11 * 1024 * 1024);
        final zip = _encodeMxl(<String, Uint8List>{
          'META-INF/container.xml': _utf8(_containerXml('score.musicxml')),
          'score.musicxml': bombBytes,
        });

        // Patch local + central uncompressedSize of score.musicxml to lie (128 bytes).
        final secondLocal = _findSignature(zip, <int>[
          0x50,
          0x4B,
          0x03,
          0x04,
        ], start: 4);
        expect(secondLocal, greaterThan(0));
        _writeUint32Le(zip, secondLocal + 22, 128);

        final firstCentral = _findSignature(zip, <int>[0x50, 0x4B, 0x01, 0x02]);
        final secondCentral = _findSignature(zip, <int>[
          0x50,
          0x4B,
          0x01,
          0x02,
        ], start: firstCentral + 4);
        expect(secondCentral, greaterThan(0));
        _writeUint32Le(zip, secondCentral + 24, 128);

        expect(
          () => extractor.extractMusicXmlBytes(zip),
          throwsA(isA<ScoreParseException>()),
        );
      },
    );

    test('rejects cumulative multi-entry uncompressed size above 10 MB', () {
      final sixMb = Uint8List(6 * 1024 * 1024);
      final zip = _encodeMxl(<String, Uint8List>{
        'META-INF/container.xml': _utf8(_containerXml('a.musicxml')),
        'a.musicxml': sixMb,
        'b.musicxml': sixMb,
      });
      expect(
        () => extractor.extractMusicXmlBytes(zip),
        throwsA(isA<ScoreParseException>()),
      );

      // Actual cumulative decoded budget across container.xml + rootfile.
      const tinyBudgetExtractor = MxlArchiveExtractor(
        maxUncompressedBytes: 1000,
      );
      final containerXml = _utf8(
        '${_containerXml('score.musicxml')}<!-- ${'x' * 550} -->',
      );
      final scoreXml = _utf8('$sampleScore<!-- ${'y' * 500} -->');
      final smallZip = _encodeMxl(<String, Uint8List>{
        'META-INF/container.xml': containerXml,
        'score.musicxml': scoreXml,
      });
      expect(
        () => tinyBudgetExtractor.extractMusicXmlBytes(smallZip),
        throwsA(isA<ScoreParseException>()),
      );
    });

    test('rejects archives exceeding 32 entries', () {
      final entries = <String, Uint8List>{
        'META-INF/container.xml': _utf8(_containerXml('score.musicxml')),
        'score.musicxml': _utf8(sampleScore),
      };
      for (var i = 0; i < 31; i += 1) {
        entries['extra_$i.txt'] = _utf8('ok');
      }
      final zip = _encodeMxl(entries);
      expect(
        () => extractor.extractMusicXmlBytes(zip),
        throwsA(isA<ScoreParseException>()),
      );
    });

    test('rejects unsafe paths in ZIP entries and container.xml full-path', () {
      const badPaths = <String>[
        '../evil.musicxml',
        '/abs/score.musicxml',
        r'dir\score.musicxml',
        'C:/score.musicxml',
        'bad\x00name.musicxml',
      ];

      for (final badPath in badPaths) {
        final badZip = _encodeMxl(
          <String, Uint8List>{
            'META-INF/container.xml': _utf8(_containerXml('score.musicxml')),
            'score.musicxml': _utf8(sampleScore),
          },
          mutateFile: (name, file) {
            if (name == 'score.musicxml') {
              file.name = badPath;
            }
          },
        );
        expect(
          () => extractor.extractMusicXmlBytes(badZip),
          throwsA(isA<ScoreParseException>()),
          reason: 'Expected ZIP entry path "$badPath" to be rejected',
        );

        final badContainer = _encodeMxl(<String, Uint8List>{
          'META-INF/container.xml': _utf8(_containerXml(badPath)),
          'score.musicxml': _utf8(sampleScore),
        });
        expect(
          () => extractor.extractMusicXmlBytes(badContainer),
          throwsA(isA<ScoreParseException>()),
          reason: 'Expected container full-path "$badPath" to be rejected',
        );
      }
    });

    test(
      'rejects UNIX symlinks, encryption, bad CRC32, missing/self container',
      () {
        // UNIX symlink (0xA1FF in externalFileAttributes >> 16).
        final symlinkZip = _encodeMxl(
          <String, Uint8List>{
            'META-INF/container.xml': _utf8(_containerXml('score.musicxml')),
            'score.musicxml': _utf8(sampleScore),
          },
          mutateFile: (name, file) {
            if (name == 'score.musicxml') {
              file.mode = 0xA1FF;
            }
          },
        );
        expect(
          () => extractor.extractMusicXmlBytes(symlinkZip),
          throwsA(isA<ScoreParseException>()),
        );

        // Encrypted entry.
        final encryptedZip = _encodeMxl(<String, Uint8List>{
          'META-INF/container.xml': _utf8(_containerXml('score.musicxml')),
          'score.musicxml': _utf8(sampleScore),
        }, password: 'secret');
        expect(
          () => extractor.extractMusicXmlBytes(encryptedZip),
          throwsA(isA<ScoreParseException>()),
        );

        // Bad CRC-32 checksum.
        final badCrcZip = _encodeMxl(<String, Uint8List>{
          'META-INF/container.xml': _utf8(_containerXml('score.musicxml')),
          'score.musicxml': _utf8(sampleScore),
        });
        final secondCentral = _findSignature(badCrcZip, <int>[
          0x50,
          0x4B,
          0x01,
          0x02,
        ], start: _findSignature(badCrcZip, <int>[0x50, 0x4B, 0x01, 0x02]) + 4);
        badCrcZip[secondCentral + 16] ^= 0xFF;
        expect(
          () => extractor.extractMusicXmlBytes(badCrcZip),
          throwsA(isA<ScoreParseException>()),
        );

        // Missing META-INF/container.xml.
        final noContainer = _encodeMxl(<String, Uint8List>{
          'score.musicxml': _utf8(sampleScore),
        });
        expect(
          () => extractor.extractMusicXmlBytes(noContainer),
          throwsA(isA<ScoreParseException>()),
        );

        // Self-referential container.xml.
        final selfRef = _encodeMxl(<String, Uint8List>{
          'META-INF/container.xml': _utf8(
            _containerXml('META-INF/container.xml'),
          ),
        });
        expect(
          () => extractor.extractMusicXmlBytes(selfRef),
          throwsA(isA<ScoreParseException>()),
        );

        // Nested .mxl media-type in container.xml.
        final nestedMxl = _encodeMxl(<String, Uint8List>{
          'META-INF/container.xml': _utf8(
            _containerXml(
              'nested.mxl',
              mediaType: 'application/vnd.recordare.musicxml+zip',
            ),
          ),
          'nested.mxl': _utf8('PK'),
        });
        expect(
          () => extractor.extractMusicXmlBytes(nestedMxl),
          throwsA(isA<ScoreParseException>()),
        );

        // Local vs central directory filename mismatch (Zip-Slip spoofing).
        final mismatchZip = _encodeMxl(<String, Uint8List>{
          'META-INF/container.xml': _utf8(_containerXml('score.musicxml')),
          'score.musicxml': _utf8(sampleScore),
        });
        final secondLocal = _findSignature(mismatchZip, <int>[
          0x50,
          0x4B,
          0x03,
          0x04,
        ], start: 4);
        final spoof = utf8.encode(
          '../evil1.music',
        ); // 14 bytes == 'score.musicxml'
        mismatchZip.setRange(
          secondLocal + 30,
          secondLocal + 30 + spoof.length,
          spoof,
        );
        expect(
          () => extractor.extractMusicXmlBytes(mismatchZip),
          throwsA(isA<ScoreParseException>()),
        );

        // Unsupported compression method (12 = BZip2).
        final badMethodZip = _encodeMxl(<String, Uint8List>{
          'META-INF/container.xml': _utf8(_containerXml('score.musicxml')),
          'score.musicxml': _utf8(sampleScore),
        });
        final secondLocal2 = _findSignature(badMethodZip, <int>[
          0x50,
          0x4B,
          0x03,
          0x04,
        ], start: 4);
        badMethodZip[secondLocal2 + 8] = 12;
        final central1 = _findSignature(badMethodZip, <int>[
          0x50,
          0x4B,
          0x01,
          0x02,
        ]);
        final central2 = _findSignature(badMethodZip, <int>[
          0x50,
          0x4B,
          0x01,
          0x02,
        ], start: central1 + 4);
        badMethodZip[central2 + 10] = 12;
        expect(
          () => extractor.extractMusicXmlBytes(badMethodZip),
          throwsA(isA<ScoreParseException>()),
        );
      },
    );
  });
}
