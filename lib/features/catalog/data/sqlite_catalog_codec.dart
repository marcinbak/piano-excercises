import 'package:piano_exercises/features/catalog/domain/catalog_query.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_search_normalizer.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

const int _variantBatchSize = 400;

const List<String> pieceColumns = <String>[
  'id',
  'title',
  'artist',
  'key_fifths',
  'scale_mode',
];

const List<String> variantColumns = <String>[
  'id',
  'piece_id',
  'difficulty_tier',
  'label',
  'file_name',
  'stored_relative_path',
  'imported_at_ms',
];

/// Builds parameterized `WHERE` SQL and positional arguments for [query].
({String whereSql, List<Object?> args}) buildCatalogWhereClause(
  CatalogQuery query,
  FtsDialect dialect,
) {
  final clauses = <String>[];
  final args = <Object?>[];
  final matchQuery = CatalogSearchNormalizer.buildFtsMatchQuery(
    query.searchText,
    dialect: dialect,
  );
  if (matchQuery != null) {
    clauses.add(
      'p.id IN (SELECT piece_id FROM pieces_fts WHERE search_text MATCH ?)',
    );
    args.add(matchQuery);
  }
  if (query.difficultyFilter != null) {
    clauses.add(
      'EXISTS (SELECT 1 FROM score_variants sv '
      'WHERE sv.piece_id = p.id AND sv.difficulty_tier = ?)',
    );
    args.add(query.difficultyFilter!.tier);
  }
  if (query.scaleFilter != null) {
    clauses.add('p.key_fifths = ? AND p.scale_mode = ?');
    args.add(query.scaleFilter!.keySignature.fifths);
    args.add(query.scaleFilter!.mode.name);
  }
  final whereSql = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
  return (whereSql: whereSql, args: args);
}

/// Inserts a [ScoreVariant] row inside an active SQLite transaction.
Future<void> insertScoreVariant(sqflite.Transaction txn, ScoreVariant variant) {
  return txn.insert('score_variants', <String, Object?>{
    'id': variant.id,
    'piece_id': variant.pieceId,
    'difficulty_tier': variant.difficultyTier.tier,
    'label': variant.label,
    'file_name': variant.fileName,
    'stored_relative_path': variant.storedRelativePath,
    'imported_at_ms': variant.importedAtMs,
  });
}

/// Replaces the `pieces_fts` row for [piece] from its metadata and variant file names.
Future<void> syncPieceFts(sqflite.Transaction txn, Piece piece) async {
  final searchText = CatalogSearchNormalizer.buildDocumentIndex(
    title: piece.title,
    artist: piece.artist,
    scale: piece.scale,
    fileNames: piece.variants.map((v) => v.fileName),
  );
  await txn.delete(
    'pieces_fts',
    where: 'piece_id = ?',
    whereArgs: <Object?>[piece.id],
  );
  await txn.insert('pieces_fts', <String, Object?>{
    'piece_id': piece.id,
    'search_text': searchText,
  });
}

/// Batch-loads `score_variants` grouped by `piece_id` under SQLite's placeholder limit.
Future<Map<String, List<ScoreVariant>>> loadVariantsByPiece(
  sqflite.DatabaseExecutor db,
  List<String> pieceIds,
) async {
  final grouped = <String, List<ScoreVariant>>{};
  for (var start = 0; start < pieceIds.length; start += _variantBatchSize) {
    final end = (start + _variantBatchSize).clamp(0, pieceIds.length);
    final chunk = pieceIds.sublist(start, end);
    final placeholders = List<String>.filled(chunk.length, '?').join(', ');
    final rows = await db.query(
      'score_variants',
      columns: variantColumns,
      where: 'piece_id IN ($placeholders)',
      whereArgs: chunk,
      orderBy: 'difficulty_tier ASC, imported_at_ms ASC, id ASC',
    );
    for (final row in rows) {
      final variant = _variantFromRow(row);
      grouped.putIfAbsent(variant.pieceId, () => <ScoreVariant>[]).add(variant);
    }
  }
  return grouped;
}

/// Maps a `pieces` row paired with [variants] into a domain [Piece].
Piece pieceFromSqlRow(Map<String, Object?> row, List<ScoreVariant> variants) {
  if (variants.isEmpty) {
    throw CatalogStorageException(
      'Piece ${row['id']} has zero stored variants.',
    );
  }
  return Piece(
    id: row['id']! as String,
    title: row['title']! as String,
    artist: row['artist']! as String,
    scale: scaleFromSqlColumns(
      row['key_fifths']! as int,
      row['scale_mode']! as String,
    ),
    variants: variants,
  );
}

/// Reconstructs a [Scale] from stored circle-of-fifths and mode columns.
Scale scaleFromSqlColumns(int fifths, String modeName) {
  try {
    final key = KeySignature.validated(fifths);
    final mode = ScaleMode.values.byName(modeName);
    return Scale.fromKeySignature(key, mode: mode);
  } on RangeError catch (error) {
    throw CatalogStorageException('Corrupt key fifths ($fifths): $error');
  } on ArgumentError catch (error) {
    throw CatalogStorageException(
      'Corrupt scale metadata ($fifths, $modeName): $error',
    );
  }
}

/// Loads a single `pieces` row by [pieceId], or `null` when absent.
Future<Map<String, Object?>?> findPieceRow(
  sqflite.DatabaseExecutor db,
  String pieceId,
) async {
  final rows = await db.query(
    'pieces',
    columns: pieceColumns,
    where: 'id = ?',
    whereArgs: <Object?>[pieceId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

/// Queries matching `pieces` and batch-loads child variants within one [txn].
Future<List<Piece>> queryPiecesInTxn(
  sqflite.DatabaseExecutor txn,
  CatalogQuery query,
  FtsDialect dialect,
) async {
  final where = buildCatalogWhereClause(query, dialect);
  final pieceRows = await txn.rawQuery(
    'SELECT p.id, p.title, p.artist, p.key_fifths, p.scale_mode '
    'FROM pieces p ${where.whereSql} '
    'ORDER BY p.title COLLATE NOCASE ASC, p.id ASC',
    where.args,
  );
  if (pieceRows.isEmpty) {
    return const <Piece>[];
  }
  final pieceIds = pieceRows
      .map((row) => row['id']! as String)
      .toList(growable: false);
  final variantsByPiece = await loadVariantsByPiece(txn, pieceIds);
  return List<Piece>.unmodifiable(<Piece>[
    for (final row in pieceRows)
      pieceFromSqlRow(
        row,
        variantsByPiece[row['id']! as String] ?? const <ScoreVariant>[],
      ),
  ]);
}

ScoreVariant _variantFromRow(Map<String, Object?> row) {
  return ScoreVariant(
    id: row['id']! as String,
    pieceId: row['piece_id']! as String,
    difficultyTier: DifficultyTier.fromTier(row['difficulty_tier']! as int),
    label: row['label']! as String,
    fileName: row['file_name']! as String,
    storedRelativePath: row['stored_relative_path']! as String,
    importedAtMs: row['imported_at_ms']! as int,
  );
}
