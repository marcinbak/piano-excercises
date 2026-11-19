import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/catalog/ui/score_import_sheet.dart';
import 'package:piano_exercises/shared/music/music.dart';

class _QueuedScoreImportSource implements ScoreImportSource {
  final List<Future<ScoreImportSelection?> Function()> _queue =
      <Future<ScoreImportSelection?> Function()>[];

  void enqueue(Future<ImportedScoreCandidate?> Function() action) {
    _queue.add(() async {
      final candidate = await action();
      return candidate == null ? null : ScoreImportSelection.single(candidate);
    });
  }

  void enqueueSelection(Future<ScoreImportSelection?> Function() action) {
    _queue.add(action);
  }

  @override
  Future<ScoreImportSelection?> pickAndParseScores() {
    if (_queue.isEmpty) {
      return Future<ScoreImportSelection?>.value();
    }
    return _queue.removeAt(0)();
  }
}

ImportedScoreCandidate _syntheticCandidate({
  required String fileName,
  String? archiveEntryPath,
  required String title,
  required String artist,
  required List<int> bytes,
}) {
  final scale = Scale.fromKeySignature(KeySignature.cMajor);
  final score = Score(
    title: title,
    artist: artist,
    scale: scale,
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
        scale: scale,
        timeSignature: TimeSignature.common,
        measureCount: 1,
        sourceFormat: ScoreFormat.mxl,
      ),
    ),
  );
}

ImportedScoreCandidate _fixtureCandidate(
  String fixturePath, {
  required String fileName,
}) {
  final bytes = File(fixturePath).readAsBytesSync();
  final parsed = const MusicXmlScoreParser().parseBytes(
    Uint8List.fromList(bytes),
    fileName: fileName,
  );
  return ImportedScoreCandidate(
    fileName: fileName,
    bytes: Uint8List.fromList(bytes),
    parsedScore: parsed,
  );
}

Widget _buildCatalogTestApp({
  required InMemoryCatalogRepository repo,
  required InMemoryScoreFileStore store,
  required _QueuedScoreImportSource importSource,
}) {
  var nextId = 0;
  return ProviderScope(
    overrides: [
      catalogRepositoryProvider.overrideWith((ref) {
        ref.onDispose(repo.close);
        return repo;
      }),
      scoreFileStoreProvider.overrideWithValue(store),
      scoreImportSourceProvider.overrideWithValue(importSource),
      catalogClockMsProvider.overrideWithValue(() => 1700000000000),
      catalogIdGeneratorProvider.overrideWithValue(() => 'id_${++nextId}'),
    ],
    child: const MaterialApp(home: CatalogScreen()),
  );
}

void main() {
  testWidgets(
    'supports import, attaching variants, search/filter chips, errors, and deletions',
    (tester) async {
      final repo = InMemoryCatalogRepository();
      final store = InMemoryScoreFileStore();
      final importSource = _QueuedScoreImportSource();

      final simpleCandidate = _fixtureCandidate(
        'test/fixtures/simplified_melody_bass.musicxml',
        fileName: 'melody_easy.musicxml',
      );
      final polyCandidate = _fixtureCandidate(
        'test/fixtures/polyphonic_grand_staff.musicxml',
        fileName: 'poly_hard.musicxml',
      );

      await tester.pumpWidget(
        _buildCatalogTestApp(
          repo: repo,
          store: store,
          importSource: importSource,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('catalog-empty-state')),
        findsOneWidget,
      );

      // 1. Error banner when score import fails on invalid .mxl.
      importSource.enqueue(
        () async => throw const ScoreParseException('Invalid ZIP container.'),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-empty-import-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('catalog-error-banner')),
        findsOneWidget,
      );
      expect(find.text('Invalid ZIP container.'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-error-dismiss-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('catalog-error-banner')),
        findsNothing,
      );

      // 2. Import first piece (edit title/artist, select Elementary, custom label).
      importSource.enqueue(() async => simpleCandidate);
      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-import-button')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('import-title-field')),
        'Humoresque',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('import-artist-field')),
        'Antonín Dvořák',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('import-tier-chip-2')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('import-variant-label-field')),
        'Easy Hand',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('import-save-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('import-save-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('piece-card-id_1')),
        findsOneWidget,
      );
      expect(find.text('Humoresque'), findsOneWidget);
      expect(find.text('Antonín Dvořák'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('piece-variant-badge-id_1-id_2')),
        findsOneWidget,
      );

      // 3. Attach second variant directly via card button.
      importSource.enqueue(() async => polyCandidate);
      await tester.tap(
        find.byKey(const ValueKey<String>('piece-attach-variant-button-id_1')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('import-tier-chip-4')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('import-save-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('import-save-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Elementary – Advanced'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('piece-variant-badge-id_1-id_3')),
        findsOneWidget,
      );

      // 4. Import a second piece in general mode (verify attach toggle & target selector work).
      importSource.enqueue(() async => polyCandidate);
      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-import-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('import-mode-attach-piece')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('import-target-piece-selector')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('import-mode-new-piece')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('import-tier-chip-5')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('import-save-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('import-save-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('piece-card-id_4')),
        findsOneWidget,
      );

      // 5. Filter by search, difficulty tier, and scale chips.
      await tester.enterText(
        find.byKey(const ValueKey<String>('catalog-search-field')),
        'dvorak',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('piece-card-id_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('piece-card-id_4')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-tier-chip-5')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('catalog-no-matches-state')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-clear-filters-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('piece-card-id_1')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('piece-card-id_4')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey<String>('catalog-piece-list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('piece-card-id_4')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-scale-chip-Eb Major')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('piece-card-id_1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('piece-card-id_4')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-scale-chip-all')),
      );
      await tester.pumpAndSettle();

      // 6. Delete single variant on id_1 (keeps parent), then delete remaining pieces.
      await tester.tap(
        find.byKey(const ValueKey<String>('variant-delete-button-id_3')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('confirm-delete-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('piece-card-id_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('piece-variant-badge-id_1-id_3')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('piece-delete-button-id_1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('confirm-delete-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('piece-card-id_1')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('variant-delete-button-id_5')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('confirm-delete-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('catalog-empty-state')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ScoreImportSheet falls back safely when initialTargetPiece is missing from existingPieces',
    (tester) async {
      final repo = InMemoryCatalogRepository();
      final store = InMemoryScoreFileStore();
      final importSource = _QueuedScoreImportSource();
      final candidate = _fixtureCandidate(
        'test/fixtures/simplified_melody_bass.musicxml',
        fileName: 'melody.musicxml',
      );
      final missingPiece = Piece(
        id: 'deleted_p1',
        title: 'Deleted Piece',
        artist: 'Composer',
        scale: candidate.parsedScore.metadata.scale,
        variants: <ScoreVariant>[
          ScoreVariant(
            id: 'deleted_v1',
            pieceId: 'deleted_p1',
            difficultyTier: DifficultyTier.beginner,
            label: 'Beginner',
            fileName: 'deleted.mxl',
            storedRelativePath: 'scores/deleted_v1.mxl',
            importedAtMs: 1,
          ),
        ],
      );
      final survivingPiece = Piece(
        id: 'surviving_p2',
        title: 'Surviving Piece',
        artist: 'Composer',
        scale: candidate.parsedScore.metadata.scale,
        variants: <ScoreVariant>[
          ScoreVariant(
            id: 'surviving_v2',
            pieceId: 'surviving_p2',
            difficultyTier: DifficultyTier.beginner,
            label: 'Beginner',
            fileName: 'surviving.mxl',
            storedRelativePath: 'scores/surviving_v2.mxl',
            importedAtMs: 2,
          ),
        ],
      );

      var nextId = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogRepositoryProvider.overrideWith((ref) {
              ref.onDispose(repo.close);
              return repo;
            }),
            scoreFileStoreProvider.overrideWithValue(store),
            scoreImportSourceProvider.overrideWithValue(importSource),
            catalogClockMsProvider.overrideWithValue(() => 1700000000000),
            catalogIdGeneratorProvider.overrideWithValue(
              () => 'id_${++nextId}',
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ScoreImportSheet(
                candidate: candidate,
                existingPieces: <Piece>[survivingPiece],
                initialTargetPiece: missingPiece,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('import-title-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('import-target-piece-selector')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'invokes onSelectVariant when tapping a variant row or the piece card',
    (tester) async {
      final repo = InMemoryCatalogRepository();
      final store = InMemoryScoreFileStore();
      final importSource = _QueuedScoreImportSource();
      final candidate = _fixtureCandidate(
        'test/fixtures/simplified_melody_bass.musicxml',
        fileName: 'melody.musicxml',
      );
      final v1 = ScoreVariant(
        id: 'var_1',
        pieceId: 'piece_1',
        difficultyTier: DifficultyTier.beginner,
        label: 'Easy',
        fileName: 'easy.musicxml',
        storedRelativePath: 'scores/var_1.musicxml',
        importedAtMs: 1,
      );
      final v2 = ScoreVariant(
        id: 'var_2',
        pieceId: 'piece_1',
        difficultyTier: DifficultyTier.advanced,
        label: 'Hard',
        fileName: 'hard.musicxml',
        storedRelativePath: 'scores/var_2.musicxml',
        importedAtMs: 2,
      );
      final piece = Piece(
        id: 'piece_1',
        title: 'Waltz in G',
        artist: 'Composer',
        scale: candidate.parsedScore.metadata.scale,
        variants: <ScoreVariant>[v1, v2],
      );
      await repo.createPiece(piece);

      final selected = <(String pieceId, String variantId)>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogRepositoryProvider.overrideWith((ref) {
              ref.onDispose(repo.close);
              return repo;
            }),
            scoreFileStoreProvider.overrideWithValue(store),
            scoreImportSourceProvider.overrideWithValue(importSource),
          ],
          child: MaterialApp(
            home: CatalogScreen(
              onSelectVariant: (p, v) => selected.add((p.id, v.id)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('open_variant_var_2')),
      );
      await tester.pump();
      expect(selected, <(String, String)>[('piece_1', 'var_2')]);

      await tester.tap(find.text('Waltz in G'));
      await tester.pump();
      expect(selected, <(String, String)>[
        ('piece_1', 'var_2'),
        ('piece_1', 'var_1'),
      ]);
    },
  );

  testWidgets(
    'routes .zip/multi-score picks to BatchScoreImportSheet, supports tier override and idempotent re-import, and keeps card + single-score routing',
    (tester) async {
      final repo = InMemoryCatalogRepository();
      final store = InMemoryScoreFileStore();
      final importSource = _QueuedScoreImportSource();

      final batchCandidates = <ImportedScoreCandidate>[
        _syntheticCandidate(
          fileName: 'mikrokosmos_vol1.mxl',
          archiveEntryPath: 'vol1/mikrokosmos_vol1.mxl',
          title: 'Mikrokosmos No. 1',
          artist: 'Béla Bartók',
          bytes: const <int>[1, 2],
        ),
        _syntheticCandidate(
          fileName: 'etude.mxl',
          archiveEntryPath: 'advanced/etude.mxl',
          title: 'Etude Op. 10',
          artist: 'Chopin',
          bytes: const <int>[3, 4],
        ),
      ];
      final batchSelection = ScoreImportSelection(
        candidates: batchCandidates,
        failures: const <ScoreImportFailure>[
          ScoreImportFailure(
            sourceName: 'corrupt.mxl',
            message: 'Invalid ZIP container.',
          ),
        ],
        ignoredNonScoreCount: 1,
        isBundle: true,
      );

      await tester.pumpWidget(
        _buildCatalogTestApp(
          repo: repo,
          store: store,
          importSource: importSource,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Bundle pick opens BatchScoreImportSheet with summary counts & auto-detected tiers.
      importSource.enqueueSelection(() async => batchSelection);
      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-empty-import-button')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BatchScoreImportSheet), findsOneWidget);
      expect(find.byType(ScoreImportSheet), findsNothing);
      expect(find.text('2 new pieces'), findsOneWidget);
      expect(find.text('1 ignored non-score file'), findsOneWidget);
      expect(find.text('1 failed'), findsOneWidget);
      expect(
        find.textContaining('Tier 1: Beginner (mikrokosmos_vol1.mxl)'),
        findsOneWidget,
      );

      final submitBtn = find.byKey(
        const ValueKey<String>('batch-import-submit-button'),
      );
      expect(find.text('Import 2 Scores'), findsOneWidget);
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.byType(BatchScoreImportSheet), findsNothing);
      expect(find.text('Mikrokosmos No. 1'), findsOneWidget);
      expect(find.text('Etude Op. 10'), findsOneWidget);
      expect(find.text('Tier 1: Beginner'), findsOneWidget);
      expect(find.text('Tier 4: Advanced'), findsOneWidget);

      // 2. Idempotent re-import of the same bundle shows 0 new, 2 duplicates skipped, and Close button.
      importSource.enqueueSelection(() async => batchSelection);
      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-import-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 new pieces'), findsOneWidget);
      expect(find.text('2 duplicates skipped'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('batch-import-submit-button')),
        findsNothing,
      );
      final closeBtn = find.byKey(
        const ValueKey<String>('batch-import-close-button'),
      );
      await tester.ensureVisible(closeBtn);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();
      expect(find.byType(BatchScoreImportSheet), findsNothing);

      // 3. Toggle 'One tier for all' -> select Elementary (tier 2) and submit.
      final overrideSelection = ScoreImportSelection(
        candidates: <ImportedScoreCandidate>[
          _syntheticCandidate(
            fileName: 'sonata.mxl',
            archiveEntryPath: 'tier1/sonata.mxl',
            title: 'Sonata in C',
            artist: 'Mozart',
            bytes: const <int>[10, 11],
          ),
          _syntheticCandidate(
            fileName: 'prelude.mxl',
            archiveEntryPath: 'tier3/prelude.mxl',
            title: 'Prelude in D',
            artist: 'Bach',
            bytes: const <int>[12, 13],
          ),
        ],
        isBundle: true,
      );
      importSource.enqueueSelection(() async => overrideSelection);
      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-import-button')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('batch-tier-mode-override')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('batch-tier-chip-2')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Tier 2: Elementary (sonata.mxl)'),
        findsOneWidget,
      );

      final overrideSubmitBtn = find.byKey(
        const ValueKey<String>('batch-import-submit-button'),
      );
      await tester.ensureVisible(overrideSubmitBtn);
      await tester.tap(overrideSubmitBtn);
      await tester.pumpAndSettle();

      expect(find.byType(BatchScoreImportSheet), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Sonata in C'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey<String>('catalog-piece-list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Sonata in C'), findsOneWidget);
      expect(find.text('Prelude in D'), findsOneWidget);
      expect(find.text('Tier 2: Elementary'), findsNWidgets(2));

      // 4. Single-candidate bundle routed to ScoreImportSheet when launched from card '+' attach button.
      final attachCandidate = _syntheticCandidate(
        fileName: 'attach_hard.mxl',
        archiveEntryPath: 'hard/attach_hard.mxl',
        title: 'Ignored Title',
        artist: 'Ignored',
        bytes: const <int>[99, 100],
      );
      importSource.enqueueSelection(
        () async => ScoreImportSelection(
          candidates: <ImportedScoreCandidate>[attachCandidate],
          isBundle: true,
        ),
      );
      final attachButton = find.byKey(
        const ValueKey<String>('piece-attach-variant-button-id_1'),
      );
      await tester.scrollUntilVisible(
        attachButton,
        -200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey<String>('catalog-piece-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(attachButton);
      await tester.pumpAndSettle();
      await tester.tap(attachButton);
      await tester.pumpAndSettle();
      expect(find.byType(ScoreImportSheet), findsOneWidget);
      expect(find.byType(BatchScoreImportSheet), findsNothing);
    },
  );

  testWidgets(
    'CatalogScreen and BatchScoreImportSheet render with zero overflow at 800x360 @ 1.6x',
    (tester) async {
      final repo = InMemoryCatalogRepository();
      final store = InMemoryScoreFileStore();
      final importSource = _QueuedScoreImportSource();

      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      final largeSelection = ScoreImportSelection(
        candidates: <ImportedScoreCandidate>[
          for (var i = 0; i < 25; i += 1)
            _syntheticCandidate(
              fileName: 'piece_$i.mxl',
              archiveEntryPath: 'vol1/piece_$i.mxl',
              title: 'Long Study Number $i in C Major',
              artist: 'Composer $i',
              bytes: <int>[i + 1],
            ),
        ],
        failures: <ScoreImportFailure>[
          for (var i = 0; i < 7; i += 1)
            ScoreImportFailure(
              sourceName: 'bad_$i.mxl',
              message: 'Corrupt XML structure in entry $i',
            ),
        ],
        ignoredNonScoreCount: 2,
        isBundle: true,
      );

      await tester.pumpWidget(
        _buildCatalogTestApp(
          repo: repo,
          store: store,
          importSource: importSource,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      importSource.enqueueSelection(() async => largeSelection);
      await tester.tap(
        find.byKey(const ValueKey<String>('catalog-import-button')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BatchScoreImportSheet), findsOneWidget);
      expect(find.text('...and 2 more'), findsOneWidget);
      expect(find.text('...and 5 more'), findsOneWidget);
    },
  );
}
