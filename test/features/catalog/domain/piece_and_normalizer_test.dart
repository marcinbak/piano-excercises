import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('DifficultyTier', () {
    test('maps tiers 1..5, compares ascending, and rejects invalid values', () {
      expect(DifficultyTier.values.map((t) => t.tier), [1, 2, 3, 4, 5]);
      expect(DifficultyTier.values.map((t) => t.label), [
        'Beginner',
        'Elementary',
        'Intermediate',
        'Advanced',
        'Original',
      ]);
      for (final tier in DifficultyTier.values) {
        expect(DifficultyTier.fromTier(tier.tier), tier);
      }
      expect(
        DifficultyTier.beginner.compareTo(DifficultyTier.original),
        lessThan(0),
      );
      expect(() => DifficultyTier.fromTier(0), throwsArgumentError);
      expect(() => DifficultyTier.fromTier(6), throwsArgumentError);
    });
  });

  group('ScoreVariant & Piece', () {
    ScoreVariant makeVariant({
      required String id,
      String pieceId = 'p1',
      required DifficultyTier tier,
      required int importedAtMs,
      String label = 'Custom',
      String fileName = 'score.mxl',
    }) {
      return ScoreVariant(
        id: id,
        pieceId: pieceId,
        difficultyTier: tier,
        label: label,
        fileName: fileName,
        storedRelativePath: 'scores/$id.mxl',
        importedAtMs: importedAtMs,
      );
    }

    test('validates required fields and importedAtMs', () {
      expect(
        () => ScoreVariant(
          id: ' ',
          pieceId: 'p1',
          difficultyTier: DifficultyTier.beginner,
          label: 'Beginner',
          fileName: 'a.mxl',
          storedRelativePath: 'scores/v1.mxl',
          importedAtMs: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => ScoreVariant(
          id: 'v1',
          pieceId: 'p1',
          difficultyTier: DifficultyTier.beginner,
          label: 'Beginner',
          fileName: 'a.mxl',
          storedRelativePath: 'scores/v1.mxl',
          importedAtMs: -1,
        ),
        throwsArgumentError,
      );
      final cMajor = Scale.fromKeySignature(KeySignature.cMajor);
      expect(
        () => Piece(
          id: 'p1',
          title: 'Title',
          artist: '',
          scale: cMajor,
          variants: const <ScoreVariant>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => Piece(
          id: 'p1',
          title: 'Title',
          artist: '',
          scale: cMajor,
          variants: <ScoreVariant>[
            makeVariant(
              id: 'v1',
              pieceId: 'other',
              tier: DifficultyTier.beginner,
              importedAtMs: 10,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test(
      'sorts variants unmodifiably and computes difficulty/timestamp getters',
      () {
        final vOrig = makeVariant(
          id: 'v3',
          tier: DifficultyTier.original,
          importedAtMs: 100,
        );
        final vBegLate = makeVariant(
          id: 'v2',
          tier: DifficultyTier.beginner,
          importedAtMs: 300,
        );
        final vBegEarly = makeVariant(
          id: 'v1',
          tier: DifficultyTier.beginner,
          importedAtMs: 200,
        );

        final piece = Piece(
          id: 'p1',
          title: 'Humoresque',
          artist: '',
          scale: Scale.fromKeySignature(const KeySignature(6)),
          variants: <ScoreVariant>[vOrig, vBegLate, vBegEarly],
        );

        expect(piece.variants.map((v) => v.id), ['v1', 'v2', 'v3']);
        expect(() => piece.variants.add(vOrig), throwsUnsupportedError);
        expect(piece.minDifficulty, DifficultyTier.beginner);
        expect(piece.maxDifficulty, DifficultyTier.original);
        expect(piece.difficultySummary, 'Beginner – Original');
        expect(piece.latestImportedAtMs, 300);

        final single = Piece(
          id: 'p2',
          title: 'Solo',
          artist: 'Bach',
          scale: Scale.fromKeySignature(KeySignature.cMajor),
          variants: <ScoreVariant>[
            makeVariant(
              id: 's1',
              pieceId: 'p2',
              tier: DifficultyTier.intermediate,
              importedAtMs: 50,
            ),
          ],
        );
        expect(single.difficultySummary, 'Intermediate');
        expect(single == piece, isFalse);
        expect(
          single,
          Piece(
            id: 'p2',
            title: 'Solo',
            artist: 'Bach',
            scale: Scale.fromKeySignature(KeySignature.cMajor),
            variants: <ScoreVariant>[
              makeVariant(
                id: 's1',
                pieceId: 'p2',
                tier: DifficultyTier.intermediate,
                importedAtMs: 50,
              ),
            ],
          ),
        );
      },
    );
  });

  group('CatalogQuery', () {
    test('copyWith clears nullable filters and computes hasActiveFilters', () {
      const empty = CatalogQuery();
      expect(empty.hasActiveFilters, isFalse);

      final fSharp = Scale.fromKeySignature(const KeySignature(6));
      final active = empty.copyWith(
        searchText: 'sonata',
        difficultyFilter: DifficultyTier.advanced,
        scaleFilter: fSharp,
      );
      expect(active.hasActiveFilters, isTrue);

      final cleared = active.copyWith(
        searchText: '',
        clearDifficultyFilter: true,
        clearScaleFilter: true,
      );
      expect(cleared, empty);
      expect(cleared.hashCode, empty.hashCode);
    });
  });

  group('CatalogSearchNormalizer', () {
    test(
      'folds Latin diacritics, ligatures, special letters, and control chars',
      () {
        expect(
          CatalogSearchNormalizer.normalizeText('Antonín Dvořák'),
          'antonin dvorak',
        );
        expect(
          CatalogSearchNormalizer.normalizeText('Étude Op. 10'),
          'etude op 10',
        );
        expect(CatalogSearchNormalizer.normalizeText('Łódź'), 'lodz');
        expect(CatalogSearchNormalizer.normalizeText('Straße'), 'strasse');
        expect(CatalogSearchNormalizer.normalizeText('GROẞE'), 'grosse');
        expect(
          CatalogSearchNormalizer.normalizeText('æ œ ø đ ð þ'),
          'ae oe o d d th',
        );
        expect(
          CatalogSearchNormalizer.normalizeText('İ\x00stanbul'),
          'istanbul',
        );
        expect(
          CatalogSearchNormalizer.normalizeText('e\u0301 c\u0327 n\u0303'),
          'e c n',
        );
        expect(
          CatalogSearchNormalizer.normalizeText(
            'àáâãäåāăąçćĉċčďđèéêëēĕėęěĝğġģĥħìíîïĩīĭįıĵķĺļľŀłñńņňòóôõöøōŏőŕŗřśŝşšßťŧùúûüũūŭůűųŵýÿŷźżž',
          ),
          'aaaaaaaaacccccddeeeeeeeeegggghhiiiiiiiiijklllllnnnnooooooooorrrssssssttuuuuuuuuuuwyyyzzz',
        );
      },
    );

    test(
      'normalizes musical accidentals so F# matches F# Major and not F Major',
      () {
        expect(
          CatalogSearchNormalizer.normalizeText('F# Major'),
          'fsharp major',
        );
        expect(
          CatalogSearchNormalizer.normalizeText('F♯ Major'),
          'fsharp major',
        );
        expect(CatalogSearchNormalizer.normalizeText('F Major'), 'f major');
        expect(CatalogSearchNormalizer.normalizeText('B♭ Major'), 'bb major');
        expect(CatalogSearchNormalizer.normalizeText('Bb Major'), 'bb major');
        expect(CatalogSearchNormalizer.normalizeText('# minor'), 'sharp minor');
      },
    );

    test('buildDocumentIndex includes metadata, scale, and filename stems', () {
      final fSharp = Scale.fromKeySignature(const KeySignature(6));
      final index = CatalogSearchNormalizer.buildDocumentIndex(
        title: 'Étude',
        artist: 'Antonín Dvořák',
        scale: fSharp,
        fileNames: const <String>['sonata_k545.mxl'],
      );
      final tokens = index.split(' ');
      expect(
        tokens,
        containsAll(<String>[
          'etude',
          'antonin',
          'dvorak',
          'fsharp',
          'major',
          'sonata',
          'k545',
          'mxl',
        ]),
      );
    });

    test('buildFtsMatchQuery sanitizes operators, respects dialects, and caps tokens', () {
      expect(CatalogSearchNormalizer.buildFtsMatchQuery(''), isNull);
      expect(CatalogSearchNormalizer.buildFtsMatchQuery('   \x00  '), isNull);
      expect(
        CatalogSearchNormalizer.buildFtsMatchQuery("''' *** : - ()"),
        isNull,
      );

      expect(
        CatalogSearchNormalizer.buildFtsMatchQuery(
          '"dvorak"* : - NEAR AND OR NOT ()',
          dialect: FtsDialect.fts5,
        ),
        '"dvorak"* "near"* "and"* "or"* "not"*',
      );
      expect(
        CatalogSearchNormalizer.buildFtsMatchQuery(
          '"dvorak"* : - NEAR AND OR NOT ()',
          dialect: FtsDialect.fts4,
        ),
        '"dvorak*" "near*" "and*" "or*" "not*"',
      );

      final manyWords = List<String>.generate(20, (i) => 'w$i').join(' ');
      expect(CatalogSearchNormalizer.tokenize(manyWords), hasLength(16));
    });
  });

  group('InMemoryCatalogRepository', () {
    test('supports prefix search, filters, deterministic sort, and variant cascade', () async {
      final repo = InMemoryCatalogRepository();
      addTearDown(repo.close);

      final fSharp = Scale.fromKeySignature(const KeySignature(6));
      final fMajor = Scale.fromKeySignature(const KeySignature(-1));
      await repo.createPiece(
        Piece(
          id: 'p1',
          title: 'Étude Op. 10',
          artist: 'Antonín Dvořák',
          scale: fSharp,
          variants: <ScoreVariant>[
            ScoreVariant(
              id: 'v1',
              pieceId: 'p1',
              difficultyTier: DifficultyTier.beginner,
              label: 'Beginner',
              fileName: 'etude_easy.mxl',
              storedRelativePath: 'scores/v1.mxl',
              importedAtMs: 10,
            ),
          ],
        ),
      );
      await repo.createPiece(
        Piece(
          id: 'p2',
          title: 'Air in F',
          artist: 'Bach',
          scale: fMajor,
          variants: <ScoreVariant>[
            ScoreVariant(
              id: 'v2',
              pieceId: 'p2',
              difficultyTier: DifficultyTier.advanced,
              label: 'Advanced',
              fileName: 'air_f.musicxml',
              storedRelativePath: 'scores/v2.musicxml',
              importedAtMs: 20,
            ),
          ],
        ),
      );

      expect((await repo.queryPieces()).map((p) => p.id), ['p2', 'p1']);
      expect(
        (await repo.queryPieces(const CatalogQuery(searchText: 'F♯')))
            .map((p) => p.id),
        ['p1'],
      );
      expect(
        (await repo.queryPieces(const CatalogQuery(searchText: 'dvor')))
            .map((p) => p.id),
        ['p1'],
      );
      expect(
        (await repo.queryPieces(
          CatalogQuery(
            difficultyFilter: DifficultyTier.advanced,
            scaleFilter: fMajor,
          ),
        )).map((p) => p.id),
        ['p2'],
      );
      expect(await repo.deleteVariant(pieceId: 'p2', variantId: 'v2'), isNull);
      expect(await repo.getPieceById('p2'), isNull);
      expect(await repo.listAvailableScales(), [fSharp]);
    });
  });
}
