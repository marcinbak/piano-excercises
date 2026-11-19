import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/catalog/data/sqlite_catalog_codec.dart';
import 'package:piano_exercises/features/catalog/data/sqlite_catalog_schema.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _FakeDatabaseException extends Fake implements DatabaseException {
  _FakeDatabaseException(this.message);

  final String message;

  @override
  String toString() => 'DatabaseException($message)';
}

final class _FakeSchemaDatabase extends Fake implements Database {
  _FakeSchemaDatabase({this.fts5Error, this.masterRows = const []});

  final DatabaseException? fts5Error;
  final List<Map<String, Object?>> masterRows;
  final List<String> executedSql = <String>[];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    executedSql.add(sql);
    if (fts5Error != null && sql.contains('USING fts5')) {
      throw fts5Error!;
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return masterRows;
  }
}

void main() {
  sqfliteFfiInit();

  group('SqliteCatalogRepository (fts5)', () {
    late Directory tempDir;
    late String dbPath;
    late SqliteCatalogRepository repo;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('catalog_sqlite_test_');
      dbPath = p.join(tempDir.path, 'catalog.db');
      repo = await SqliteCatalogRepository.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: dbPath,
      );
    });

    tearDown(() async {
      await repo.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('enables PRAGMA foreign_keys across cold restart and preserves FTS dialect', () async {
      expect(repo.ftsDialect, FtsDialect.fts5);
      expect(await repo.debugIsForeignKeysEnabled(), isTrue);

      final fSharp = Scale.fromKeySignature(const KeySignature(6));
      await repo.createPiece(
        Piece(
          id: 'p1',
          title: 'Humoresque',
          artist: 'Antonín Dvořák',
          scale: fSharp,
          variants: <ScoreVariant>[
            ScoreVariant(
              id: 'v1',
              pieceId: 'p1',
              difficultyTier: DifficultyTier.beginner,
              label: 'Beginner',
              fileName: 'humoresque_easy.mxl',
              storedRelativePath: 'scores/v1.mxl',
              importedAtMs: 1000,
            ),
          ],
        ),
      );

      await repo.close();
      repo = await SqliteCatalogRepository.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: dbPath,
      );

      expect(repo.ftsDialect, FtsDialect.fts5);
      expect(await repo.debugIsForeignKeysEnabled(), isTrue);
      final fetched = await repo.getPieceById('p1');
      expect(fetched?.title, 'Humoresque');
      expect(fetched?.scale, fSharp);
    });

    test('synchronizes pieces_fts across create, attach, deleteVariant, and deletePiece', () async {
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
              fileName: 'etude_beginner.mxl',
              storedRelativePath: 'scores/v1.mxl',
              importedAtMs: 100,
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
              difficultyTier: DifficultyTier.intermediate,
              label: 'Intermediate',
              fileName: 'air_f.musicxml',
              storedRelativePath: 'scores/v2.musicxml',
              importedAtMs: 200,
            ),
          ],
        ),
      );

      expect(
        (await repo.queryPieces(const CatalogQuery(searchText: 'dvor')))
            .map((p) => p.id),
        ['p1'],
      );
      expect(
        (await repo.queryPieces(const CatalogQuery(searchText: 'etud')))
            .map((p) => p.id),
        ['p1'],
      );
      expect(
        (await repo.queryPieces(const CatalogQuery(searchText: 'F♯')))
            .map((p) => p.id),
        ['p1'],
      );

      await repo.attachVariant(
        pieceId: 'p1',
        variant: ScoreVariant(
          id: 'v1b',
          pieceId: 'p1',
          difficultyTier: DifficultyTier.original,
          label: 'Original',
          fileName: 'sonata_k545.mxl',
          storedRelativePath: 'scores/v1b.mxl',
          importedAtMs: 300,
        ),
      );
      expect(
        (await repo.queryPieces(const CatalogQuery(searchText: 'k545')))
            .map((p) => p.id),
        ['p1'],
      );

      final afterVariantDelete = await repo.deleteVariant(
        pieceId: 'p1',
        variantId: 'v1b',
      );
      expect(afterVariantDelete?.variants.map((v) => v.id), ['v1']);
      expect(
        await repo.queryPieces(const CatalogQuery(searchText: 'k545')),
        isEmpty,
      );
      expect(
        (await repo.queryPieces(const CatalogQuery(searchText: 'etud')))
            .map((p) => p.id),
        ['p1'],
      );

      expect(await repo.deleteVariant(pieceId: 'p2', variantId: 'v2'), isNull);
      expect(await repo.getPieceById('p2'), isNull);
      expect(
        await repo.queryPieces(const CatalogQuery(searchText: 'air')),
        isEmpty,
      );

      await repo.deletePiece('p1');
      expect(await repo.queryPieces(), isEmpty);
      await repo.close();

      final rawDb = await databaseFactoryFfi.openDatabase(dbPath);
      addTearDown(rawDb.close);
      final variantRows = await rawDb.rawQuery(
        'SELECT COUNT(*) AS cnt FROM score_variants',
      );
      final ftsRows = await rawDb.rawQuery(
        'SELECT COUNT(*) AS cnt FROM pieces_fts',
      );
      expect(variantRows.single['cnt'], 0);
      expect(ftsRows.single['cnt'], 0);
    });

    test(
      'handles adversarial FTS strings without SQLite syntax errors',
      () async {
        await repo.createPiece(
          Piece(
            id: 'p1',
            title: 'And Near Or Not',
            artist: 'Dvořák',
            scale: Scale.fromKeySignature(KeySignature.cMajor),
            variants: <ScoreVariant>[
              ScoreVariant(
                id: 'v1',
                pieceId: 'p1',
                difficultyTier: DifficultyTier.beginner,
                label: 'Beginner',
                fileName: 'and_near.mxl',
                storedRelativePath: 'scores/v1.mxl',
                importedAtMs: 1,
              ),
            ],
          ),
        );

        final adversarialQueries = <String>[
          '"dvorak"* : - NEAR AND OR NOT ()',
          "'''",
          '***',
          'a\x00b',
          '""" * : - ()',
        ];
        for (final input in adversarialQueries) {
          final results = await repo.queryPieces(
            CatalogQuery(searchText: input),
          );
          expect(results, isA<List<Piece>>());
        }
        final matched = await repo.queryPieces(
          const CatalogQuery(searchText: '"dvorak"* : - NEAR AND OR NOT ()'),
        );
        expect(matched.map((p) => p.id), ['p1']);
      },
    );

    test('supports combined filters, listAvailableScales, and >450-piece variant batching', () async {
      final cMajor = Scale.fromKeySignature(KeySignature.cMajor);
      final gMajor = Scale.fromKeySignature(const KeySignature(1));

      await repo.createPiece(
        Piece(
          id: 'a_piece',
          title: 'alpha',
          artist: 'Composer A',
          scale: gMajor,
          variants: <ScoreVariant>[
            ScoreVariant(
              id: 'va',
              pieceId: 'a_piece',
              difficultyTier: DifficultyTier.advanced,
              label: 'Advanced',
              fileName: 'alpha.mxl',
              storedRelativePath: 'scores/va.mxl',
              importedAtMs: 10,
            ),
          ],
        ),
      );
      for (var i = 0; i < 460; i += 1) {
        final id = 'batch_${i.toString().padLeft(3, '0')}';
        await repo.createPiece(
          Piece(
            id: id,
            title: 'Zebra Study $i',
            artist: 'Etude',
            scale: cMajor,
            variants: <ScoreVariant>[
              ScoreVariant(
                id: 'v_$id',
                pieceId: id,
                difficultyTier: DifficultyTier.beginner,
                label: 'Beginner',
                fileName: '$id.mxl',
                storedRelativePath: 'scores/v_$id.mxl',
                importedAtMs: i,
              ),
            ],
          ),
        );
      }

      final allPieces = await repo.queryPieces();
      expect(allPieces, hasLength(461));
      expect(await repo.countPieces(), 461);
      expect(allPieces.first.id, 'a_piece');

      expect(await repo.listAvailableScales(), [cMajor, gMajor]);

      final filtered = await repo.queryPieces(
        CatalogQuery(
          searchText: 'alpha',
          difficultyFilter: DifficultyTier.advanced,
          scaleFilter: gMajor,
        ),
      );
      expect(filtered.map((p) => p.id), ['a_piece']);
    });
  });

  group('Android FTS4 fallback contract', () {
    test('falls back to fts4 when fts5 module is missing and rethrows other errors', () async {
      final fts4Db = _FakeSchemaDatabase(
        fts5Error: _FakeDatabaseException('no such module: fts5'),
      );
      await createCatalogSchema(fts4Db);
      expect(
        fts4Db.executedSql.last,
        'CREATE VIRTUAL TABLE IF NOT EXISTS pieces_fts '
        'USING fts4(piece_id, search_text, notindexed=piece_id);',
      );

      final failingDb = _FakeSchemaDatabase(
        fts5Error: _FakeDatabaseException('disk I/O error'),
      );
      await expectLater(
        () => createCatalogSchema(failingDb),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('detectFtsDialect reads fts4 vs fts5 from sqlite_master', () async {
      final fts4Db = _FakeSchemaDatabase(
        masterRows: const <Map<String, Object?>>[
          <String, Object?>{
            'sql': 'CREATE VIRTUAL TABLE pieces_fts USING fts4(piece_id, search_text, notindexed=piece_id)',
          },
        ],
      );
      expect(await detectFtsDialect(fts4Db), FtsDialect.fts4);

      final fts5Db = _FakeSchemaDatabase(
        masterRows: const <Map<String, Object?>>[
          <String, Object?>{
            'sql': 'CREATE VIRTUAL TABLE pieces_fts USING fts5(piece_id UNINDEXED, search_text)',
          },
        ],
      );
      expect(await detectFtsDialect(fts5Db), FtsDialect.fts5);
    });

    test('buildCatalogWhereClause emits dialect-specific MATCH query args', () {
      const query = CatalogQuery(searchText: 'Dvoř');

      final fts4Where = buildCatalogWhereClause(query, FtsDialect.fts4);
      expect(
        fts4Where.whereSql,
        'WHERE p.id IN (SELECT piece_id FROM pieces_fts WHERE search_text MATCH ?)',
      );
      expect(fts4Where.args, ['"dvor*"']);

      final fts5Where = buildCatalogWhereClause(query, FtsDialect.fts5);
      expect(fts5Where.whereSql, fts4Where.whereSql);
      expect(fts5Where.args, ['"dvor"*']);
    });
  });
}
