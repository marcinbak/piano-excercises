import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:piano_exercises/features/catalog/catalog.dart';

void main() {
  late Directory tempDir;
  late AppDocsScoreStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('score_store_test_');
    store = AppDocsScoreStore(rootDirectory: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'saves, reads, and deletes .mxl and .musicxml scores atomically',
    () async {
      final mxlBytes = Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04, 1, 2]);
      final xmlBytes = Uint8List.fromList('<score-partwise/>'.codeUnits);

      final mxlPath = await store.saveScoreBytes(
        variantId: 'var_1',
        format: ScoreFormat.mxl,
        bytes: mxlBytes,
      );
      final xmlPath = await store.saveScoreBytes(
        variantId: 'var-2',
        format: ScoreFormat.musicXml,
        bytes: xmlBytes,
      );

      expect(mxlPath, 'scores/var_1.mxl');
      expect(xmlPath, 'scores/var-2.musicxml');
      expect(await store.readScoreBytes(mxlPath), mxlBytes);
      expect(await store.readScoreBytes(xmlPath), xmlBytes);

      await store.deleteScoreFile(mxlPath);
      await store.deleteScoreFile(mxlPath);
      await expectLater(
        () => store.readScoreBytes(mxlPath),
        throwsA(isA<CatalogStorageException>()),
      );
    },
  );

  test('rejects invalid variant IDs, traversal paths, symlinks, empty and >10 MB payloads', () async {
    final validBytes = Uint8List.fromList(<int>[1, 2, 3]);
    await expectLater(
      () => store.saveScoreBytes(
        variantId: '../evil',
        format: ScoreFormat.mxl,
        bytes: validBytes,
      ),
      throwsA(isA<CatalogStorageException>()),
    );
    await expectLater(
      () => store.saveScoreBytes(
        variantId: 'valid',
        format: ScoreFormat.mxl,
        bytes: Uint8List(0),
      ),
      throwsA(isA<CatalogStorageException>()),
    );
    await expectLater(
      () => store.saveScoreBytes(
        variantId: 'valid',
        format: ScoreFormat.mxl,
        bytes: Uint8List(AppDocsScoreStore.maxBytes + 1),
      ),
      throwsA(isA<CatalogStorageException>()),
    );
    await expectLater(
      () => store.readScoreBytes('scores/../evil.mxl'),
      throwsA(isA<CatalogStorageException>()),
    );
    await expectLater(
      () => store.deleteScoreFile('scores/evil.txt'),
      throwsA(isA<CatalogStorageException>()),
    );

    final scoresDir = Directory(p.join(tempDir.path, 'scores'))..createSync();
    final target = File(p.join(tempDir.path, 'outside.mxl'))
      ..writeAsBytesSync(validBytes);
    Link(p.join(scoresDir.path, 'sym_1.mxl')).createSync(target.path);

    await expectLater(
      () => store.readScoreBytes('scores/sym_1.mxl'),
      throwsA(isA<CatalogStorageException>()),
    );
    await expectLater(
      () => store.saveScoreBytes(
        variantId: 'sym_1',
        format: ScoreFormat.mxl,
        bytes: validBytes,
      ),
      throwsA(isA<CatalogStorageException>()),
    );
  });

  test('purgeOrphans removes temp files, symlinks, and unreferenced files while keeping active paths', () async {
    final activePath = await store.saveScoreBytes(
      variantId: 'keep_1',
      format: ScoreFormat.mxl,
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );
    final stalePath = await store.saveScoreBytes(
      variantId: 'drop_1',
      format: ScoreFormat.musicXml,
      bytes: Uint8List.fromList(<int>[4, 5, 6]),
    );
    final scoresDir = Directory(p.join(tempDir.path, 'scores'));
    File(p.join(scoresDir.path, '.tmp_leftover_123'))
        .writeAsBytesSync(<int>[9]);
    final outside = File(p.join(tempDir.path, 'outside.mxl'))
      ..writeAsBytesSync(<int>[7]);
    Link(p.join(scoresDir.path, 'drop_sym.mxl')).createSync(outside.path);

    final purged = await store.purgeOrphans(<String>{activePath});
    expect(purged, 3);
    expect(
      await store.readScoreBytes(activePath),
      Uint8List.fromList(<int>[1, 2, 3]),
    );
    await expectLater(
      () => store.readScoreBytes(stalePath),
      throwsA(isA<CatalogStorageException>()),
    );
    expect(outside.existsSync(), isTrue);
  });
}
