import 'package:piano_exercises/features/catalog/domain/catalog_search_normalizer.dart';
import 'package:sqflite/sqflite.dart';

const int catalogSchemaVersion = 1;
const String catalogDatabaseFileName = 'piano_catalog.db';

/// Enables SQLite foreign-key enforcement on every connection open.
Future<void> configureCatalogDatabase(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON;');
}

/// Creates catalog tables, indexes, and FTS5 (or FTS4 fallback) virtual table.
Future<void> createCatalogSchema(Database db) async {
  await db.execute('''
CREATE TABLE IF NOT EXISTS pieces (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  key_fifths INTEGER NOT NULL,
  scale_mode TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE IF NOT EXISTS score_variants (
  id TEXT PRIMARY KEY,
  piece_id TEXT NOT NULL REFERENCES pieces(id) ON DELETE CASCADE,
  difficulty_tier INTEGER NOT NULL,
  label TEXT NOT NULL,
  file_name TEXT NOT NULL,
  stored_relative_path TEXT NOT NULL,
  imported_at_ms INTEGER NOT NULL
)
''');
  await db.execute('''
CREATE INDEX IF NOT EXISTS idx_score_variants_piece_tier
  ON score_variants(piece_id, difficulty_tier)
''');

  try {
    await db.execute(
      'CREATE VIRTUAL TABLE IF NOT EXISTS pieces_fts '
      'USING fts5(piece_id UNINDEXED, search_text);',
    );
    return;
  } on DatabaseException catch (error) {
    if (!_isMissingFts5Error(error)) {
      rethrow;
    }
  }
  await db.execute(
    'CREATE VIRTUAL TABLE IF NOT EXISTS pieces_fts '
    'USING fts4(piece_id, search_text, notindexed=piece_id);',
  );
}

/// Inspects `sqlite_master` so reopened DBs match the virtual table's FTS syntax.
Future<FtsDialect> detectFtsDialect(DatabaseExecutor db) async {
  final rows = await db.query(
    'sqlite_master',
    columns: <String>['sql'],
    where: 'type = ? AND name = ?',
    whereArgs: <Object?>['table', 'pieces_fts'],
    limit: 1,
  );
  if (rows.isEmpty) {
    return FtsDialect.fts5;
  }
  final sql = (rows.first['sql'] as String? ?? '').toLowerCase();
  return sql.contains('fts4') ? FtsDialect.fts4 : FtsDialect.fts5;
}

bool _isMissingFts5Error(DatabaseException error) =>
    error.toString().toLowerCase().contains('no such module: fts5');
