import 'dart:typed_data';

import 'package:piano_exercises/features/catalog/domain/catalog_repository.dart';
import 'package:piano_exercises/features/catalog/domain/catalog_save_helpers.dart';
import 'package:piano_exercises/features/catalog/domain/difficulty_tier.dart';
import 'package:piano_exercises/features/catalog/domain/piece.dart';
import 'package:piano_exercises/features/catalog/domain/score_file_store.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:piano_exercises/features/catalog/domain/score_serializer.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Metadata payload applied when persisting an edited or newly composed [Score].
final class CatalogScoreSaveDetails {
  const CatalogScoreSaveDetails({
    required this.title,
    this.artist = '',
    required this.difficultyTier,
    this.variantLabel,
  });

  final String title;
  final String artist;
  final DifficultyTier difficultyTier;
  final String? variantLabel;
}

/// Coordinates score serialization, atomic file writes, and catalog persistence.
final class CatalogScoreSaveCoordinator {
  const CatalogScoreSaveCoordinator({
    required this.catalogRepository,
    required this.scoreFileStore,
    required this.scoreSerializer,
    required this.clockMs,
    required this.generateId,
  });

  final CatalogRepository catalogRepository;
  final ScoreFileStore scoreFileStore;
  final ScoreSerializer scoreSerializer;
  final int Function() clockMs;
  final String Function() generateId;

  Future<Piece> saveAsNewPiece({
    required Score score,
    required CatalogScoreSaveDetails details,
  }) async {
    final trimmedTitle = requireCatalogSaveTitle(details.title);
    final trimmedArtist = details.artist.trim();
    final effectiveLabel = resolveCatalogVariantLabel(
      details.variantLabel,
      details.difficultyTier,
    );
    final pieceId = _nextSafeId('piece');
    final variantId = _nextSafeId('variant');
    final serialized = _serializeWithMetadata(
      score,
      title: trimmedTitle,
      artist: trimmedArtist,
    );

    final storedRelativePath = await scoreFileStore.saveScoreBytes(
      variantId: variantId,
      format: ScoreFormat.musicXml,
      bytes: serialized,
    );
    try {
      final variant = ScoreVariant(
        id: variantId,
        pieceId: pieceId,
        difficultyTier: details.difficultyTier,
        label: effectiveLabel,
        fileName: buildMusicXmlFileName(trimmedTitle, fallbackId: variantId),
        storedRelativePath: storedRelativePath,
        importedAtMs: clockMs(),
      );
      return await catalogRepository.createPiece(
        Piece(
          id: pieceId,
          title: trimmedTitle,
          artist: trimmedArtist,
          scale: score.scale,
          variants: <ScoreVariant>[variant],
        ),
      );
    } catch (_) {
      await _rollbackFile(storedRelativePath);
      rethrow;
    }
  }

  Future<Piece> saveAsAttachedVariant({
    required String pieceId,
    required Score score,
    required DifficultyTier difficultyTier,
    String? variantLabel,
  }) async {
    final existing = await catalogRepository.getPieceById(pieceId);
    if (existing == null) {
      throw CatalogStorageException('Piece $pieceId not found.');
    }
    final effectiveLabel = resolveCatalogVariantLabel(
      variantLabel,
      difficultyTier,
    );
    final variantId = _nextSafeId('variant');
    final serialized = _serializeWithMetadata(
      score,
      title: existing.title,
      artist: existing.artist,
    );

    final storedRelativePath = await scoreFileStore.saveScoreBytes(
      variantId: variantId,
      format: ScoreFormat.musicXml,
      bytes: serialized,
    );
    try {
      final variant = ScoreVariant(
        id: variantId,
        pieceId: pieceId,
        difficultyTier: difficultyTier,
        label: effectiveLabel,
        fileName: buildMusicXmlFileName(
          '${existing.title}_$effectiveLabel',
          fallbackId: variantId,
        ),
        storedRelativePath: storedRelativePath,
        importedAtMs: clockMs(),
      );
      return await catalogRepository.attachVariant(
        pieceId: pieceId,
        variant: variant,
      );
    } catch (_) {
      await _rollbackFile(storedRelativePath);
      rethrow;
    }
  }

  Future<Piece> updateVariantInPlace({
    required ScoreVariant existingVariant,
    required Score score,
    required CatalogScoreSaveDetails details,
  }) async {
    final trimmedTitle = requireCatalogSaveTitle(details.title);
    final trimmedArtist = details.artist.trim();
    final effectiveLabel = resolveCatalogVariantLabel(
      details.variantLabel,
      details.difficultyTier,
    );
    final existingPiece = await catalogRepository.getPieceById(
      existingVariant.pieceId,
    );
    if (existingPiece == null) {
      throw CatalogStorageException(
        'Piece ${existingVariant.pieceId} not found.',
      );
    }
    if (!existingPiece.variants.any((v) => v.id == existingVariant.id)) {
      throw CatalogStorageException(
        'ScoreVariant ${existingVariant.id} not found on ${existingVariant.pieceId}.',
      );
    }

    final serialized = _serializeWithMetadata(
      score,
      title: trimmedTitle,
      artist: trimmedArtist,
    );
    final expectedPath = 'scores/${existingVariant.id}.musicxml';
    final overwritesSamePath =
        existingVariant.storedRelativePath == expectedPath;
    final Uint8List? priorBytes = overwritesSamePath
        ? await scoreFileStore.readScoreBytes(
            existingVariant.storedRelativePath,
          )
        : null;

    final newRelativePath = await scoreFileStore.saveScoreBytes(
      variantId: existingVariant.id,
      format: ScoreFormat.musicXml,
      bytes: serialized,
    );
    final Piece updatedPiece;
    try {
      updatedPiece = await catalogRepository.updateVariant(
        CatalogVariantUpdate(
          pieceId: existingVariant.pieceId,
          variantId: existingVariant.id,
          title: trimmedTitle,
          artist: trimmedArtist,
          scale: score.scale,
          difficultyTier: details.difficultyTier,
          label: effectiveLabel,
          fileName: toMusicXmlVariantFileName(
            existingVariant.fileName,
            fallbackTitle: trimmedTitle,
            fallbackId: existingVariant.id,
          ),
          storedRelativePath: newRelativePath,
          importedAtMs: clockMs(),
        ),
      );
    } catch (_) {
      if (overwritesSamePath && priorBytes != null) {
        await _restorePriorBytes(existingVariant.id, priorBytes);
      } else {
        await _rollbackFile(newRelativePath);
      }
      rethrow;
    }

    if (!overwritesSamePath) {
      await _rollbackFile(existingVariant.storedRelativePath);
    }
    return updatedPiece;
  }

  Uint8List _serializeWithMetadata(
    Score score, {
    required String title,
    required String artist,
  }) {
    final normalized = Score(
      title: title,
      artist: artist,
      scale: score.scale,
      timeSignature: score.timeSignature,
      initialTempo: score.initialTempo,
      measures: score.measures,
    );
    return scoreSerializer.serialize(normalized);
  }

  String _nextSafeId(String kind) {
    final id = generateId();
    if (!ScoreFileStore.isValidVariantId(id)) {
      throw CatalogStorageException('Generated invalid $kind id: $id');
    }
    return id;
  }

  Future<void> _restorePriorBytes(String variantId, Uint8List bytes) async {
    try {
      await scoreFileStore.saveScoreBytes(
        variantId: variantId,
        format: ScoreFormat.musicXml,
        bytes: bytes,
      );
    } catch (_) {}
  }

  Future<void> _rollbackFile(String storedRelativePath) async {
    try {
      await scoreFileStore.deleteScoreFile(storedRelativePath);
    } catch (_) {}
  }
}
