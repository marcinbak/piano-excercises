import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/piece_practice/piece_practice.dart';

void main() {
  group('variantScoreProvider', () {
    test(
      'reads and parses simplified and polyphonic variants from ScoreFileStore',
      () async {
        final store = InMemoryScoreFileStore();
        final simpleBytes = Uint8List.fromList(
          File('test/fixtures/simplified_melody_bass.musicxml')
              .readAsBytesSync(),
        );
        final polyBytes = Uint8List.fromList(
          File('test/fixtures/polyphonic_grand_staff.musicxml')
              .readAsBytesSync(),
        );
        final simplePath = await store.saveScoreBytes(
          variantId: 'v_simple',
          format: ScoreFormat.musicXml,
          bytes: simpleBytes,
        );
        final polyPath = await store.saveScoreBytes(
          variantId: 'v_poly',
          format: ScoreFormat.musicXml,
          bytes: polyBytes,
        );

        final vSimple = ScoreVariant(
          id: 'v_simple',
          pieceId: 'p1',
          difficultyTier: DifficultyTier.beginner,
          label: 'Easy',
          fileName: 'simplified_melody_bass.musicxml',
          storedRelativePath: simplePath,
          importedAtMs: 1,
        );
        final vPoly = ScoreVariant(
          id: 'v_poly',
          pieceId: 'p1',
          difficultyTier: DifficultyTier.advanced,
          label: 'Full',
          fileName: 'polyphonic_grand_staff.musicxml',
          storedRelativePath: polyPath,
          importedAtMs: 2,
        );

        final container = ProviderContainer(
          overrides: [
            scoreFileStoreProvider.overrideWithValue(store),
            scoreParserProvider.overrideWithValue(const MusicXmlScoreParser()),
          ],
        );
        addTearDown(container.dispose);

        final subSimple = container.listen(
          variantScoreProvider(vSimple),
          (_, _) {},
        );
        final subPoly = container.listen(
          variantScoreProvider(vPoly),
          (_, _) {},
        );
        addTearDown(() {
          subSimple.close();
          subPoly.close();
        });

        final parsedSimple = await container.read(
          variantScoreProvider(vSimple).future,
        );
        final parsedPoly = await container.read(
          variantScoreProvider(vPoly).future,
        );

        expect(parsedSimple.score.measures, hasLength(8));
        expect(parsedSimple.score.slices, hasLength(22));
        expect(parsedPoly.score.measures, hasLength(32));
        expect(parsedPoly.score.slices, hasLength(184));
      },
    );

    test(
      'surfaces CatalogStorageException when variant file is missing',
      () async {
        final store = InMemoryScoreFileStore();
        final missing = ScoreVariant(
          id: 'missing',
          pieceId: 'p1',
          difficultyTier: DifficultyTier.beginner,
          label: 'Missing',
          fileName: 'missing.musicxml',
          storedRelativePath: 'scores/missing.musicxml',
          importedAtMs: 1,
        );
        final container = ProviderContainer(
          overrides: [
            scoreFileStoreProvider.overrideWithValue(store),
            scoreParserProvider.overrideWithValue(const MusicXmlScoreParser()),
          ],
        );
        addTearDown(container.dispose);

        final sub = container.listen(variantScoreProvider(missing), (_, _) {});
        addTearDown(sub.close);

        await expectLater(
          container.read(variantScoreProvider(missing).future),
          throwsA(isA<CatalogStorageException>()),
        );
      },
    );
  });
}
