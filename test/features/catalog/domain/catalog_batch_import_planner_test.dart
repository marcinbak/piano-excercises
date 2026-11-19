import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/shared/music/music.dart';

ImportedScoreCandidate _candidate({
  required String fileName,
  String? archiveEntryPath,
  required String title,
  required String artist,
  Scale? scale,
  List<int> bytes = const <int>[1, 2, 3],
  ScoreFormat format = ScoreFormat.mxl,
}) {
  final effectiveScale = scale ?? Scale.fromKeySignature(KeySignature.cMajor);
  final score = Score(
    title: title,
    artist: artist,
    scale: effectiveScale,
    timeSignature: TimeSignature.common,
    measures: const <ScoreMeasure>[],
  );
  return ImportedScoreCandidate(
    fileName: fileName,
    archiveEntryPath: archiveEntryPath,
    bytes: Uint8List.fromList(bytes),
    parsedScore: ParsedScore(
      score: score,
      metadata: ScoreMetadata(
        title: title,
        artist: artist,
        scale: effectiveScale,
        timeSignature: TimeSignature.common,
        measureCount: 1,
        sourceFormat: format,
      ),
    ),
  );
}

void main() {
  group('inferDifficultyTier', () {
    test('infers tiers from path/filename first, then title tokens', () {
      expect(
        inferDifficultyTier(
          archiveEntryPath: 'scores/mikrokosmos_vol1/sz_01.mxl',
          fileName: 'sz_01.mxl',
          title: 'Sz. 107 No. 1',
        ),
        DifficultyTier.beginner,
      );
      expect(
        inferDifficultyTier(
          fileName: 'bartok_mikrokosmos_vol_2_40.mxl',
          title: 'Mikrokosmos',
        ),
        DifficultyTier.elementary,
      );
      expect(
        inferDifficultyTier(
          fileName: 'mikrokosmos_vol3.mxl',
          title: 'Mikrokosmos',
        ),
        DifficultyTier.intermediate,
      );
      expect(
        inferDifficultyTier(
          fileName: 'mikrokosmos_vol6.mxl',
          title: 'Mikrokosmos',
        ),
        DifficultyTier.advanced,
      );
      expect(
        inferDifficultyTier(
          fileName: 'sonata_intermediate.mxl',
          title: 'Sonata',
        ),
        DifficultyTier.intermediate,
      );
      expect(
        inferDifficultyTier(
          fileName: 'sonata_tier-4.mxl',
          title: 'Sonata (Beginner)',
        ),
        DifficultyTier.advanced,
      );
      expect(
        inferDifficultyTier(
          fileName: 'piece_01.mxl',
          title: 'Minuet in G (Beginner)',
        ),
        DifficultyTier.beginner,
      );
      expect(
        inferDifficultyTier(fileName: 'etude_urtext.mxl', title: 'Etude'),
        DifficultyTier.original,
      );
      expect(
        inferDifficultyTier(fileName: 'tier_2_waltz.mxl', title: 'Waltz'),
        DifficultyTier.elementary,
      );
      expect(
        inferDifficultyTier(
          fileName: 'plain_score.mxl',
          title: 'Untitled Study',
        ),
        isNull,
      );
    });
  });

  group('CatalogBatchImportPlanner', () {
    test('groups diacritic/case-folded (title, artist) and keeps punctuation-only titles distinct', () {
      final cMajor = Scale.fromKeySignature(KeySignature.cMajor);
      final gMajor = Scale.fromKeySignature(const KeySignature(1));

      final plan = CatalogBatchImportPlanner.plan(
        existingPieces: const <Piece>[],
        candidates: <ImportedScoreCandidate>[
          _candidate(
            fileName: 'etude_hard.mxl',
            title: 'Étude Op. 10',
            artist: 'Antonín Dvořák',
            scale: gMajor,
            bytes: const <int>[1],
          ),
          _candidate(
            fileName: 'etude_easy.mxl',
            title: 'etude op 10',
            artist: 'antonin dvorak',
            scale: cMajor,
            bytes: const <int>[2],
          ),
          _candidate(
            fileName: 'q1.mxl',
            title: '!!!',
            artist: 'Anon',
            bytes: const <int>[3],
          ),
          _candidate(
            fileName: 'q2.mxl',
            title: '???',
            artist: 'Anon',
            bytes: const <int>[4],
          ),
        ],
      );

      expect(plan.newPieces, hasLength(3));
      expect(plan.attachments, isEmpty);
      expect(plan.skippedDuplicates, isEmpty);

      final etude = plan.newPieces.first;
      expect(etude.variants, hasLength(2));
      expect(etude.variants[0].difficultyTier, DifficultyTier.advanced);
      expect(etude.variants[1].difficultyTier, DifficultyTier.beginner);
      // Lowest-tier variant's scale is selected for the new piece.
      expect(etude.scale, cMajor);
    });

    test('attaches to existingPieces, skips existing/intra-batch duplicates, and disambiguates colliding basenames', () {
      final cMajor = Scale.fromKeySignature(KeySignature.cMajor);
      final existing = Piece(
        id: 'p_existing',
        title: 'Humoresque',
        artist: 'Dvořák',
        scale: cMajor,
        variants: <ScoreVariant>[
          ScoreVariant(
            id: 'v1',
            pieceId: 'p_existing',
            difficultyTier: DifficultyTier.beginner,
            label: 'Beginner',
            fileName: 'humoresque_easy.mxl',
            storedRelativePath: 'scores/v1.mxl',
            importedAtMs: 10,
          ),
          ScoreVariant(
            id: 'v2',
            pieceId: 'p_existing',
            difficultyTier: DifficultyTier.advanced,
            label: 'Advanced',
            fileName: 'tier4/humoresque.mxl',
            storedRelativePath: 'scores/v2.mxl',
            importedAtMs: 20,
          ),
        ],
      );

      final plan = CatalogBatchImportPlanner.plan(
        existingPieces: <Piece>[existing],
        candidates: <ImportedScoreCandidate>[
          // Matches existing fileName (case-folded).
          _candidate(
            fileName: 'HUMORESQUE_EASY.MXL',
            archiveEntryPath: 'easy/HUMORESQUE_EASY.MXL',
            title: 'Humoresque',
            artist: 'Dvorak',
            bytes: const <int>[10],
          ),
          // Matches existing archive path stored as fileName.
          _candidate(
            fileName: 'humoresque.mxl',
            archiveEntryPath: 'tier4/humoresque.mxl',
            title: 'Humoresque',
            artist: 'Dvorak',
            bytes: const <int>[11],
          ),
          // New valid attachment for existing piece.
          _candidate(
            fileName: 'humoresque_medium.mxl',
            title: 'Humoresque',
            artist: 'Dvorak',
            bytes: const <int>[12],
          ),
          // Byte-identical duplicate of humoresque_medium.mxl.
          _candidate(
            fileName: 'copy.mxl',
            title: 'Humoresque',
            artist: 'Dvorak',
            bytes: const <int>[12],
          ),
          // New piece with colliding basenames across folders & differing bytes.
          _candidate(
            fileName: 'sonata.mxl',
            archiveEntryPath: 'beginner/sonata.mxl',
            title: 'Sonata K.545',
            artist: 'Mozart',
            bytes: const <int>[20],
          ),
          _candidate(
            fileName: 'sonata.mxl',
            archiveEntryPath: 'original/sonata.mxl',
            title: 'Sonata K.545',
            artist: 'Mozart',
            bytes: const <int>[21],
          ),
          // Byte-identical duplicate in another folder does NOT trigger disambiguation on a solo entry.
          _candidate(
            fileName: 'minuet.mxl',
            archiveEntryPath: 'a/minuet.mxl',
            title: 'Minuet',
            artist: 'Bach',
            bytes: const <int>[30],
          ),
          _candidate(
            fileName: 'minuet.mxl',
            archiveEntryPath: 'b/minuet.mxl',
            title: 'Minuet',
            artist: 'Bach',
            bytes: const <int>[30],
          ),
          // Duplicate loose filename (no archiveEntryPath) with differing bytes is skipped.
          _candidate(
            fileName: 'prelude.mxl',
            title: 'Prelude',
            artist: 'Bach',
            bytes: const <int>[40],
          ),
          _candidate(
            fileName: 'PRELUDE.MXL',
            title: 'Prelude',
            artist: 'Bach',
            bytes: const <int>[41],
          ),
        ],
      );

      expect(plan.attachments, hasLength(1));
      expect(plan.attachments.single.targetPiece.id, 'p_existing');
      expect(
        plan.attachments.single.variants.map((v) => v.effectiveFileName),
        <String>['humoresque_medium.mxl'],
      );
      expect(
        plan.attachments.single.variants.single.difficultyTier,
        DifficultyTier.intermediate,
      );

      expect(plan.newPieces, hasLength(3));
      final sonata = plan.newPieces.firstWhere(
        (p) => p.title == 'Sonata K.545',
      );
      expect(sonata.variants.map((v) => v.effectiveFileName), <String>[
        'beginner/sonata.mxl',
        'original/sonata.mxl',
      ]);
      expect(sonata.variants[0].difficultyTier, DifficultyTier.beginner);
      expect(sonata.variants[1].difficultyTier, DifficultyTier.original);

      final minuet = plan.newPieces.firstWhere((p) => p.title == 'Minuet');
      expect(minuet.variants.single.effectiveFileName, 'minuet.mxl');

      final prelude = plan.newPieces.firstWhere((p) => p.title == 'Prelude');
      expect(prelude.variants.single.effectiveFileName, 'prelude.mxl');

      expect(plan.skippedDuplicates, hasLength(5));
      expect(plan.totalVariantsToImport, 5);
      expect(plan.hasImports, isTrue);
    });

    test('respects defaultTier and overrideInferredTiers toggle', () {
      final candidates = <ImportedScoreCandidate>[
        _candidate(
          fileName: 'easy_piece.mxl',
          title: 'Easy Piece',
          artist: 'Anon',
          bytes: const <int>[1],
        ),
        _candidate(
          fileName: 'unlabeled.mxl',
          title: 'Study',
          artist: 'Anon',
          bytes: const <int>[2],
        ),
      ];

      final autoPlan = CatalogBatchImportPlanner.plan(
        candidates: candidates,
        existingPieces: const <Piece>[],
        defaultTier: DifficultyTier.elementary,
      );
      expect(
        autoPlan.newPieces[0].variants.single.difficultyTier,
        DifficultyTier.beginner,
      );
      expect(
        autoPlan.newPieces[1].variants.single.difficultyTier,
        DifficultyTier.elementary,
      );

      final overridePlan = CatalogBatchImportPlanner.plan(
        candidates: candidates,
        existingPieces: const <Piece>[],
        defaultTier: DifficultyTier.advanced,
        overrideInferredTiers: true,
      );
      expect(
        overridePlan.newPieces[0].variants.single.difficultyTier,
        DifficultyTier.advanced,
      );
      expect(
        overridePlan.newPieces[1].variants.single.difficultyTier,
        DifficultyTier.advanced,
      );
    });
  });
}
