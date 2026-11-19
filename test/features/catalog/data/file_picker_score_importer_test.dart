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

Uint8List _wrapBundleZip(Map<String, Uint8List> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  test('returns null when picker is cancelled', () async {
    final importer = FilePickerScoreImporter(
      pickFiles: () async => const <PlatformFile>[],
    );
    expect(await importer.pickAndParseScores(), isNull);
  });

  test(
    'rejects unsupported extension, empty payload, >maxBytes, and >500 files',
    () async {
      final badExt = FilePickerScoreImporter(
        pickFiles: () async => <PlatformFile>[
          _FakePlatformFile(
            name: 'score.pdf',
            knownLength: 4,
            chunks: <Uint8List>[
              Uint8List.fromList(<int>[1, 2, 3, 4]),
            ],
          ),
        ],
      );
      await expectLater(
        badExt.pickAndParseScores,
        throwsA(isA<ScoreParseException>()),
      );

      final emptyFile = FilePickerScoreImporter(
        pickFiles: () async => <PlatformFile>[
          _FakePlatformFile(
            name: 'empty.musicxml',
            knownLength: null,
            chunks: const <Uint8List>[],
          ),
        ],
      );
      await expectLater(
        emptyFile.pickAndParseScores,
        throwsA(isA<ScoreParseException>()),
      );

      final oversizedSync = FilePickerScoreImporter(
        maxBytes: 100,
        pickFiles: () async => <PlatformFile>[
          _FakePlatformFile(
            name: 'big.mxl',
            knownLength: 101,
            chunks: const <Uint8List>[],
          ),
        ],
      );
      await expectLater(
        oversizedSync.pickAndParseScores,
        throwsA(isA<ScoreParseException>()),
      );

      final oversizedStream = FilePickerScoreImporter(
        maxBytes: 100,
        pickFiles: () async => <PlatformFile>[
          _FakePlatformFile(
            name: 'big_stream.musicxml',
            knownLength: null,
            chunks: <Uint8List>[Uint8List(60), Uint8List(41)],
          ),
        ],
      );
      await expectLater(
        oversizedStream.pickAndParseScores,
        throwsA(isA<ScoreParseException>()),
      );

      final tooManyFiles = FilePickerScoreImporter(
        pickFiles: () async => List<PlatformFile>.generate(
          501,
          (i) => _FakePlatformFile(
            name: 'score_$i.musicxml',
            knownLength: 10,
            chunks: <Uint8List>[Uint8List(10)],
          ),
        ),
      );
      await expectLater(
        tooManyFiles.pickAndParseScores,
        throwsA(isA<ScoreParseException>()),
      );
    },
  );

  test('parses valid single .musicxml and .mxl files from stream', () async {
    final xmlBytes = File('test/fixtures/simplified_melody_bass.musicxml')
        .readAsBytesSync();

    final xmlImporter = FilePickerScoreImporter(
      pickFiles: () async => <PlatformFile>[
        _FakePlatformFile(
          name: 'simplified_melody_bass.musicxml',
          knownLength: xmlBytes.length,
          chunks: <Uint8List>[xmlBytes.sublist(0, 128), xmlBytes.sublist(128)],
        ),
      ],
    );
    final xmlSelection = await xmlImporter.pickAndParseScores();
    expect(xmlSelection, isNotNull);
    expect(xmlSelection!.isBundle, isFalse);
    expect(xmlSelection.candidates, hasLength(1));
    final xmlCandidate = xmlSelection.candidates.single;
    expect(xmlCandidate.parsedScore.metadata.title, 'Simplified Melody + Bass');
    expect(
      xmlCandidate.parsedScore.metadata.sourceFormat,
      ScoreFormat.musicXml,
    );

    final mxlBytes = _wrapMxl(xmlBytes);
    final mxlImporter = FilePickerScoreImporter(
      pickFiles: () async => <PlatformFile>[
        _FakePlatformFile(
          name: 'simplified.MXL',
          knownLength: mxlBytes.length,
          chunks: <Uint8List>[mxlBytes],
        ),
      ],
    );
    final mxlSelection = await mxlImporter.pickAndParseScores();
    expect(mxlSelection, isNotNull);
    expect(
      mxlSelection!.candidates.single.parsedScore.metadata.scale.label,
      'G Major',
    );
    expect(
      mxlSelection.candidates.single.parsedScore.metadata.sourceFormat,
      ScoreFormat.mxl,
    );
  });

  test('parses .zip bundle and multi-file selections with partial failures and cumulative cap', () async {
    final xmlBytes = File('test/fixtures/simplified_melody_bass.musicxml')
        .readAsBytesSync();
    final mxlBytes = _wrapMxl(xmlBytes);
    final zipBytes = _wrapBundleZip(<String, Uint8List>{
      'beginner/simple.mxl': mxlBytes,
      'readme.txt': Uint8List.fromList(utf8.encode('notes')),
    });

    final zipImporter = FilePickerScoreImporter(
      pickFiles: () async => <PlatformFile>[
        _FakePlatformFile(
          name: 'bundle.zip',
          knownLength: zipBytes.length,
          chunks: <Uint8List>[zipBytes],
        ),
      ],
    );
    final zipSelection = await zipImporter.pickAndParseScores();
    expect(zipSelection, isNotNull);
    expect(zipSelection!.isBundle, isTrue);
    expect(zipSelection.candidates, hasLength(1));
    expect(zipSelection.ignoredNonScoreCount, 1);
    expect(
      zipSelection.shouldUseSingleScoreSheet(hasInitialTargetPiece: false),
      isFalse,
    );
    expect(
      zipSelection.shouldUseSingleScoreSheet(hasInitialTargetPiece: true),
      isTrue,
    );

    final multiImporter = FilePickerScoreImporter(
      pickFiles: () async => <PlatformFile>[
        _FakePlatformFile(
          name: 'good.musicxml',
          knownLength: xmlBytes.length,
          chunks: <Uint8List>[xmlBytes],
        ),
        _FakePlatformFile(
          name: 'broken.mxl',
          knownLength: 4,
          chunks: <Uint8List>[
            Uint8List.fromList(<int>[1, 2, 3, 4]),
          ],
        ),
      ],
    );
    final multiSelection = await multiImporter.pickAndParseScores();
    expect(multiSelection, isNotNull);
    expect(multiSelection!.candidates, hasLength(1));
    expect(multiSelection.failures, hasLength(1));
    expect(multiSelection.failures.single.sourceName, 'broken.mxl');

    final overBundleCap = FilePickerScoreImporter(
      maxBytes: 10000,
      maxBundleBytes: xmlBytes.length + 10,
      pickFiles: () async => <PlatformFile>[
        _FakePlatformFile(
          name: 'one.musicxml',
          knownLength: xmlBytes.length,
          chunks: <Uint8List>[xmlBytes],
        ),
        _FakePlatformFile(
          name: 'two.musicxml',
          knownLength: xmlBytes.length,
          chunks: <Uint8List>[xmlBytes],
        ),
      ],
    );
    await expectLater(
      overBundleCap.pickAndParseScores,
      throwsA(isA<ScoreParseException>()),
    );
  });

  test('enforces cumulative uncompressed byte and 500-candidate caps across multi-.zip selections', () async {
    final xmlBytes = File('test/fixtures/simplified_melody_bass.musicxml')
        .readAsBytesSync();
    final xmlText = utf8.decode(xmlBytes);
    final paddedXml = utf8.encode(
      xmlText.replaceFirst(
        '</score-partwise>',
        '<!-- ${'a' * 8000} --></score-partwise>',
      ),
    );
    final paddedBytes = Uint8List.fromList(paddedXml);

    final zipA = _wrapBundleZip(<String, Uint8List>{
      'a1.musicxml': paddedBytes,
      'a2.musicxml': paddedBytes,
    });
    final zipB = _wrapBundleZip(<String, Uint8List>{
      'b1.musicxml': paddedBytes,
      'b2.musicxml': paddedBytes,
    });
    final maxBundleCap = (paddedBytes.length * 3);
    expect(zipA.length + zipB.length, lessThan(maxBundleCap));

    final multiZipOverBytes = FilePickerScoreImporter(
      maxBytes: paddedBytes.length + 1024,
      maxBundleBytes: maxBundleCap,
      pickFiles: () async => <PlatformFile>[
        _FakePlatformFile(
          name: 'bundle_a.zip',
          knownLength: zipA.length,
          chunks: <Uint8List>[zipA],
        ),
        _FakePlatformFile(
          name: 'bundle_b.zip',
          knownLength: zipB.length,
          chunks: <Uint8List>[zipB],
        ),
      ],
    );
    await expectLater(
      multiZipOverBytes.pickAndParseScores,
      throwsA(isA<ScoreParseException>()),
    );

    final zip300 = _wrapBundleZip(<String, Uint8List>{
      for (var i = 0; i < 300; i += 1) 's_$i.musicxml': xmlBytes,
    });
    final zip201 = _wrapBundleZip(<String, Uint8List>{
      for (var i = 0; i < 201; i += 1) 't_$i.musicxml': xmlBytes,
    });
    final multiZipOver500 = FilePickerScoreImporter(
      pickFiles: () async => <PlatformFile>[
        _FakePlatformFile(
          name: 'part1.zip',
          knownLength: zip300.length,
          chunks: <Uint8List>[zip300],
        ),
        _FakePlatformFile(
          name: 'part2.zip',
          knownLength: zip201.length,
          chunks: <Uint8List>[zip201],
        ),
      ],
    );
    await expectLater(
      multiZipOver500.pickAndParseScores,
      throwsA(isA<ScoreParseException>()),
    );
  });

  test('records >10 MB zip score entry as failure in multi-select without aborting valid siblings, while single >10 MB zip throws', () async {
    final xmlBytes = File('test/fixtures/simplified_melody_bass.musicxml')
        .readAsBytesSync();
    final over10MbZip = _wrapBundleZip(<String, Uint8List>{
      'huge.musicxml': Uint8List(10 * 1024 * 1024 + 1),
    });

    final multiImporter = FilePickerScoreImporter(
      pickFiles: () async => <PlatformFile>[
        _FakePlatformFile(
          name: 'good.musicxml',
          knownLength: xmlBytes.length,
          chunks: <Uint8List>[xmlBytes],
        ),
        _FakePlatformFile(
          name: 'bundle_with_11mb_score.zip',
          knownLength: over10MbZip.length,
          chunks: <Uint8List>[over10MbZip],
        ),
      ],
    );
    final selection = await multiImporter.pickAndParseScores();
    expect(selection, isNotNull);
    expect(selection!.candidates, hasLength(1));
    expect(selection.candidates.single.fileName, 'good.musicxml');
    expect(selection.failures, hasLength(1));
    expect(selection.failures.single.sourceName, 'bundle_with_11mb_score.zip');

    final singleOver10MbImporter = FilePickerScoreImporter(
      pickFiles: () async => <PlatformFile>[
        _FakePlatformFile(
          name: 'only_huge.zip',
          knownLength: over10MbZip.length,
          chunks: <Uint8List>[over10MbZip],
        ),
      ],
    );
    await expectLater(
      singleOver10MbImporter.pickAndParseScores,
      throwsA(isA<ScoreParseException>()),
    );
  });

  test('enforces tight remainingByteBudget independently of picked file order when ignoring companion files and rejected entries', () async {
    final xmlBytes = File('test/fixtures/simplified_melody_bass.musicxml')
        .readAsBytesSync();
    final xmlText = utf8.decode(xmlBytes);

    Uint8List padXml(int targetBytes) {
      final padLen = targetBytes - xmlBytes.length - 10;
      return Uint8List.fromList(
        utf8.encode(
          xmlText.replaceFirst(
            '</score-partwise>',
            '<!-- ${'x' * padLen} --></score-partwise>',
          ),
        ),
      );
    }

    final validLargeBytes = padXml(40 * 1024);
    final validMxlBytes = _wrapMxl(xmlBytes);
    final companionPdfBytes = Uint8List.fromList(
      List<int>.generate(15 * 1024, (i) => (i * 37 + 13) & 0xFF),
    );
    final pdfAndMxlZip = _wrapBundleZip(<String, Uint8List>{
      'companion.pdf': companionPdfBytes,
      'valid.mxl': validMxlBytes,
    });
    final oversizedScoreZip = _wrapBundleZip(<String, Uint8List>{
      'oversized.musicxml': padXml(46 * 1024),
    });

    final validLargeFile = _FakePlatformFile(
      name: 'valid_large.musicxml',
      knownLength: validLargeBytes.length,
      chunks: <Uint8List>[validLargeBytes],
    );
    final pdfAndMxlFile = _FakePlatformFile(
      name: 'bundle_with_15kb_pdf_and_valid_mxl.zip',
      knownLength: pdfAndMxlZip.length,
      chunks: <Uint8List>[pdfAndMxlZip],
    );
    final oversizedFile = _FakePlatformFile(
      name: 'bundle_with_oversized_single_score.zip',
      knownLength: oversizedScoreZip.length,
      chunks: <Uint8List>[oversizedScoreZip],
    );

    for (final order in <List<PlatformFile>>[
      <PlatformFile>[validLargeFile, pdfAndMxlFile, oversizedFile],
      <PlatformFile>[oversizedFile, pdfAndMxlFile, validLargeFile],
    ]) {
      final importer = FilePickerScoreImporter(
        maxBytes: 45 * 1024,
        maxBundleBytes: 50 * 1024,
        pickFiles: () async => order,
      );
      final selection = await importer.pickAndParseScores();
      expect(selection, isNotNull);
      expect(selection!.candidates, hasLength(2));
      expect(
        selection.candidates.map((c) => c.fileName),
        containsAll(<String>['valid_large.musicxml', 'valid.mxl']),
      );
      expect(selection.ignoredNonScoreCount, 1);
      expect(selection.failures, hasLength(1));
      expect(
        selection.failures.single.sourceName,
        'bundle_with_oversized_single_score.zip',
      );
    }
  });
}
