import 'package:piano_exercises/features/catalog/data/sqlite_catalog_codec.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_search_normalizer.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// Atomically updates parent piece metadata, one [ScoreVariant] row, and FTS in [txn].
Future<Piece> updateVariantInTxn(
  sqflite.Transaction txn,
  CatalogVariantUpdate update,
) async {
  final pieceRow = await findPieceRow(txn, update.pieceId);
  if (pieceRow == null) {
    throw CatalogStorageException('Piece ${update.pieceId} not found.');
  }
  final updatedCount = await txn.update(
    'score_variants',
    <String, Object?>{
      'difficulty_tier': update.difficultyTier.tier,
      'label': update.label,
      'file_name': update.fileName,
      'stored_relative_path': update.storedRelativePath,
      'imported_at_ms': update.importedAtMs,
    },
    where: 'id = ? AND piece_id = ?',
    whereArgs: <Object?>[update.variantId, update.pieceId],
  );
  if (updatedCount == 0) {
    throw CatalogStorageException(
      'ScoreVariant ${update.variantId} not found on ${update.pieceId}.',
    );
  }
  await txn.update(
    'pieces',
    <String, Object?>{
      'title': update.title,
      'artist': update.artist,
      'key_fifths': update.scale.keySignature.fifths,
      'scale_mode': update.scale.mode.name,
    },
    where: 'id = ?',
    whereArgs: <Object?>[update.pieceId],
  );
  final variantsByPiece = await loadVariantsByPiece(txn, <String>[
    update.pieceId,
  ]);
  final updatedPiece = Piece(
    id: update.pieceId,
    title: update.title,
    artist: update.artist,
    scale: update.scale,
    variants: variantsByPiece[update.pieceId] ?? const <ScoreVariant>[],
  );
  await syncPieceFts(txn, updatedPiece);
  return updatedPiece;
}

/// Atomically applies [batch] inserts, target validation, and per-piece FTS sync in [txn].
Future<void> applyBatchInTxn(
  sqflite.Transaction txn,
  CatalogBatchMutation batch, {
  required FtsDialect ftsDialect,
}) async {
  // Both FTS5 and FTS4 share the (piece_id, search_text) insert shape during writes.
  final _ = ftsDialect;
  for (final piece in batch.newPieces) {
    if (piece.variants.isEmpty) {
      throw CatalogStorageException('Piece ${piece.id} has zero variants.');
    }
    await insertPieceRow(txn, piece);
    for (final variant in piece.variants) {
      if (variant.pieceId != piece.id) {
        throw CatalogStorageException(
          'Variant pieceId ${variant.pieceId} does not match ${piece.id}.',
        );
      }
      await insertScoreVariant(txn, variant);
    }
    await syncPieceFts(txn, piece);
  }
  await _applyAttachmentBatchInTxn(txn, batch.attachments);
}

Future<void> _applyAttachmentBatchInTxn(
  sqflite.Transaction txn,
  List<CatalogBatchPieceAttachment> attachments,
) async {
  if (attachments.isEmpty) {
    return;
  }
  final targetIds = _collectValidatedTargetIds(attachments);
  final pieceRowsById = await _loadPieceRowsByIds(txn, targetIds);
  for (final id in targetIds) {
    if (!pieceRowsById.containsKey(id)) {
      throw CatalogStorageException('Piece $id not found.');
    }
  }
  for (final attachment in attachments) {
    for (final variant in attachment.variants) {
      await insertScoreVariant(txn, variant);
    }
  }
  final variantsByPiece = await loadVariantsByPiece(txn, targetIds);
  for (final id in targetIds) {
    final updated = pieceFromSqlRow(
      pieceRowsById[id]!,
      variantsByPiece[id] ?? const <ScoreVariant>[],
    );
    await syncPieceFts(txn, updated);
  }
}

List<String> _collectValidatedTargetIds(
  List<CatalogBatchPieceAttachment> attachments,
) {
  final targetIds = <String>[];
  final seenTargetIds = <String>{};
  for (final attachment in attachments) {
    if (attachment.variants.isEmpty) {
      throw CatalogStorageException(
        'Attachment for ${attachment.pieceId} has zero variants.',
      );
    }
    for (final variant in attachment.variants) {
      if (variant.pieceId != attachment.pieceId) {
        throw CatalogStorageException(
          'Variant pieceId ${variant.pieceId} does not match ${attachment.pieceId}.',
        );
      }
    }
    if (seenTargetIds.add(attachment.pieceId)) {
      targetIds.add(attachment.pieceId);
    }
  }
  return targetIds;
}

Future<Map<String, Map<String, Object?>>> _loadPieceRowsByIds(
  sqflite.DatabaseExecutor db,
  List<String> pieceIds,
) async {
  final byId = <String, Map<String, Object?>>{};
  for (var start = 0; start < pieceIds.length; start += catalogSqlBatchSize) {
    final end = (start + catalogSqlBatchSize).clamp(0, pieceIds.length);
    final chunk = pieceIds.sublist(start, end);
    final placeholders = List<String>.filled(chunk.length, '?').join(', ');
    final rows = await db.query(
      'pieces',
      columns: pieceColumns,
      where: 'id IN ($placeholders)',
      whereArgs: chunk,
    );
    for (final row in rows) {
      byId[row['id']! as String] = row;
    }
  }
  return byId;
}
