import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:piano_exercises/features/catalog/data/sqlite_catalog_codec.dart';
import 'package:piano_exercises/features/catalog/data/sqlite_catalog_schema.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_query.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_search_normalizer.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// SQLite-backed [CatalogRepository] with FTS5/FTS4 prefix search and cascades.
final class SqliteCatalogRepository implements CatalogRepository {
  SqliteCatalogRepository._(this._db, this._dialect);

  final sqflite.Database _db;
  final FtsDialect _dialect;

  @visibleForTesting
  FtsDialect get ftsDialect => _dialect;

  /// Opens (or initializes) the SQLite catalog database.
  static Future<SqliteCatalogRepository> open({
    sqflite.DatabaseFactory? databaseFactory,
    String? databasePath,
  }) async {
    final factory = databaseFactory ?? sqflite.databaseFactory;
    final path =
        databasePath ??
        p.join(await factory.getDatabasesPath(), catalogDatabaseFileName);
    if (path != sqflite.inMemoryDatabasePath && path.isNotEmpty) {
      final parent = Directory(p.dirname(path));
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
    }
    try {
      final db = await factory.openDatabase(
        path,
        options: sqflite.OpenDatabaseOptions(
          version: catalogSchemaVersion,
          onConfigure: configureCatalogDatabase,
          onCreate: (db, _) => createCatalogSchema(db),
        ),
      );
      final dialect = await detectFtsDialect(db);
      return SqliteCatalogRepository._(db, dialect);
    } on sqflite.DatabaseException catch (error) {
      throw CatalogStorageException('Failed to open catalog DB: $error');
    }
  }

  @visibleForTesting
  Future<bool> debugIsForeignKeysEnabled() async {
    final rows = await _db.rawQuery('PRAGMA foreign_keys');
    return sqflite.Sqflite.firstIntValue(rows) == 1;
  }

  @override
  Future<List<Piece>> queryPieces([
    CatalogQuery query = const CatalogQuery(),
  ]) async {
    try {
      return await _db.transaction(
        (txn) => queryPiecesInTxn(txn, query, _dialect),
      );
    } on sqflite.DatabaseException catch (error) {
      throw CatalogStorageException('Failed to query catalog: $error');
    }
  }

  @override
  Future<int> countPieces() async {
    try {
      final rows = await _db.rawQuery('SELECT COUNT(*) AS cnt FROM pieces');
      return sqflite.Sqflite.firstIntValue(rows) ?? 0;
    } on sqflite.DatabaseException catch (error) {
      throw CatalogStorageException('Failed to count pieces: $error');
    }
  }

  @override
  Future<List<Scale>> listAvailableScales() async {
    try {
      final rows = await _db.rawQuery(
        'SELECT DISTINCT key_fifths, scale_mode FROM pieces '
        'ORDER BY key_fifths ASC, scale_mode ASC',
      );
      return List<Scale>.unmodifiable(<Scale>[
        for (final row in rows)
          scaleFromSqlColumns(
            row['key_fifths']! as int,
            row['scale_mode']! as String,
          ),
      ]);
    } on sqflite.DatabaseException catch (error) {
      throw CatalogStorageException('Failed to list available scales: $error');
    }
  }

  @override
  Future<Piece?> getPieceById(String pieceId) async {
    try {
      return await _db.transaction((txn) async {
        final row = await findPieceRow(txn, pieceId);
        if (row == null) {
          return null;
        }
        final variants = await loadVariantsByPiece(txn, <String>[pieceId]);
        return pieceFromSqlRow(
          row,
          variants[pieceId] ?? const <ScoreVariant>[],
        );
      });
    } on sqflite.DatabaseException catch (error) {
      throw CatalogStorageException('Failed to fetch piece $pieceId: $error');
    }
  }

  @override
  Future<Piece> createPiece(Piece piece) async {
    try {
      return await _db.transaction((txn) async {
        await txn.insert('pieces', <String, Object?>{
          'id': piece.id,
          'title': piece.title,
          'artist': piece.artist,
          'key_fifths': piece.scale.keySignature.fifths,
          'scale_mode': piece.scale.mode.name,
        });
        for (final variant in piece.variants) {
          await insertScoreVariant(txn, variant);
        }
        await syncPieceFts(txn, piece);
        return piece;
      });
    } on sqflite.DatabaseException catch (error) {
      throw CatalogStorageException('Failed to create piece: $error');
    }
  }

  @override
  Future<Piece> attachVariant({
    required String pieceId,
    required ScoreVariant variant,
  }) async {
    if (variant.pieceId != pieceId) {
      throw CatalogStorageException(
        'Variant pieceId ${variant.pieceId} does not match $pieceId.',
      );
    }
    try {
      return await _db.transaction((txn) async {
        final row = await findPieceRow(txn, pieceId);
        if (row == null) {
          throw CatalogStorageException('Piece $pieceId not found.');
        }
        await insertScoreVariant(txn, variant);
        final variants = await loadVariantsByPiece(txn, <String>[pieceId]);
        final updated = pieceFromSqlRow(row, variants[pieceId] ?? const []);
        await syncPieceFts(txn, updated);
        return updated;
      });
    } on sqflite.DatabaseException catch (error) {
      throw CatalogStorageException('Failed to attach variant: $error');
    }
  }

  @override
  Future<Piece?> deleteVariant({
    required String pieceId,
    required String variantId,
  }) async {
    try {
      return await _db.transaction((txn) async {
        final row = await findPieceRow(txn, pieceId);
        if (row == null) {
          return null;
        }
        await txn.delete(
          'score_variants',
          where: 'id = ? AND piece_id = ?',
          whereArgs: <Object?>[variantId, pieceId],
        );
        final variants = await loadVariantsByPiece(txn, <String>[pieceId]);
        final remaining = variants[pieceId] ?? const <ScoreVariant>[];
        if (remaining.isEmpty) {
          await txn.delete('pieces', where: 'id = ?', whereArgs: [pieceId]);
          await txn.delete(
            'pieces_fts',
            where: 'piece_id = ?',
            whereArgs: <Object?>[pieceId],
          );
          return null;
        }
        final updated = pieceFromSqlRow(row, remaining);
        await syncPieceFts(txn, updated);
        return updated;
      });
    } on sqflite.DatabaseException catch (error) {
      throw CatalogStorageException('Failed to delete variant: $error');
    }
  }

  @override
  Future<void> deletePiece(String pieceId) async {
    try {
      await _db.transaction((txn) async {
        await txn.delete('pieces', where: 'id = ?', whereArgs: [pieceId]);
        await txn.delete(
          'pieces_fts',
          where: 'piece_id = ?',
          whereArgs: <Object?>[pieceId],
        );
      });
    } on sqflite.DatabaseException catch (error) {
      throw CatalogStorageException('Failed to delete piece: $error');
    }
  }

  @override
  Future<Set<String>> listStoredRelativePaths() async {
    try {
      final rows = await _db.query(
        'score_variants',
        columns: <String>['stored_relative_path'],
      );
      return Set<String>.unmodifiable(<String>{
        for (final row in rows) row['stored_relative_path']! as String,
      });
    } on sqflite.DatabaseException catch (error) {
      throw CatalogStorageException('Failed to list score paths: $error');
    }
  }

  @override
  Future<void> close() => _db.close();
}
