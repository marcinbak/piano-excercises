import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/catalog/ui/score_import_sheet.dart';

class _QueuedScoreImportSource implements ScoreImportSource {
  final List<Future<ImportedScoreCandidate?> Function()> _queue =
      <Future<ImportedScoreCandidate?> Function()>[];

  void enqueue(Future<ImportedScoreCandidate?> Function() action) {
    _queue.add(action);
  }

  @override
  Future<ImportedScoreCandidate?> pickAndParseScore() {
    if (_queue.isEmpty) {
      return Future<ImportedScoreCandidate?>.value();
    }
    return _queue.removeAt(0)();
  }
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
}
