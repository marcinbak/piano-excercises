import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/app/app_navigation_shell.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/progression/progression.dart';
import 'package:piano_exercises/features/score_playback/score_playback.dart';

/// Initializes persistence before first frame and returns the configured app root.
Future<PianoExercisesRoot> bootstrapPianoExercisesRoot({
  Future<ProgressionRepository> Function()? createProgressionRepository,
  Future<CatalogRepository> Function()? createCatalogRepository,
  Future<ScoreFileStore> Function()? createScoreFileStore,
  ScoreImportSource? scoreImportSource,
  Widget? home,
}) async {
  ProgressionRepository progressionRepository;
  try {
    progressionRepository =
        await (createProgressionRepository ??
            SharedPreferencesProgressionRepository.create)();
  } catch (_) {
    progressionRepository = InMemoryProgressionRepository();
  }

  CatalogRepository catalogRepository;
  var catalogOpenedCleanly = false;
  try {
    catalogRepository =
        await (createCatalogRepository ?? SqliteCatalogRepository.open)();
    catalogOpenedCleanly = true;
  } catch (_) {
    catalogRepository = InMemoryCatalogRepository();
  }

  ScoreFileStore scoreFileStore;
  var scoreStoreOpenedCleanly = false;
  try {
    scoreFileStore = await (createScoreFileStore ?? AppDocsScoreStore.create)();
    scoreStoreOpenedCleanly = true;
  } catch (_) {
    scoreFileStore = InMemoryScoreFileStore();
  }

  if (catalogOpenedCleanly && scoreStoreOpenedCleanly) {
    try {
      final activePaths = await catalogRepository.listStoredRelativePaths();
      await scoreFileStore.purgeOrphans(activePaths);
    } catch (_) {
      // Best-effort orphan cleanup must never block startup.
    }
  }

  return PianoExercisesRoot(
    progressionRepository: progressionRepository,
    catalogRepository: catalogRepository,
    scoreFileStore: scoreFileStore,
    scoreImportSource: scoreImportSource,
    home: home,
  );
}

/// Root widget configuring dependency overrides for the application.
class PianoExercisesRoot extends StatelessWidget {
  const PianoExercisesRoot({
    super.key,
    this.progressionRepository,
    this.catalogRepository,
    this.scoreFileStore,
    this.scoreImportSource,
    this.home,
  });

  final ProgressionRepository? progressionRepository;
  final CatalogRepository? catalogRepository;
  final ScoreFileStore? scoreFileStore;
  final ScoreImportSource? scoreImportSource;
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        midiRepositoryProvider.overrideWith((ref) {
          final repository = FlutterMidiRepository();
          ref.onDispose(() {
            unawaited(repository.dispose());
          });
          return repository;
        }),
        midiOutputSinkProvider.overrideWith((ref) {
          final sink = FlutterMidiOutputSink();
          ref.onDispose(() {
            unawaited(sink.sendAllNotesOff());
          });
          return sink;
        }),
        pcmAudioOutputProvider.overrideWith((ref) {
          final output = MethodChannelPcmAudioOutput();
          ref.onDispose(() {
            unawaited(output.dispose());
          });
          return output;
        }),
        scoreParserProvider.overrideWithValue(const MusicXmlScoreParser()),
        scoreSerializerProvider.overrideWithValue(
          const MusicXmlScoreSerializer(),
        ),
        scoreImportSourceProvider.overrideWith(
          (ref) =>
              scoreImportSource ??
              FilePickerScoreImporter(parser: ref.watch(scoreParserProvider)),
        ),
        if (progressionRepository != null)
          progressionRepositoryProvider.overrideWithValue(
            progressionRepository!,
          ),
        if (catalogRepository != null)
          catalogRepositoryProvider.overrideWith((ref) {
            ref.onDispose(() {
              unawaited(catalogRepository!.close());
            });
            return catalogRepository!;
          }),
        if (scoreFileStore != null)
          scoreFileStoreProvider.overrideWithValue(scoreFileStore!),
      ],
      child: PianoExercisesApp(home: home),
    );
  }
}

/// Top-level [MaterialApp] entry point; tests can wrap it with custom [ProviderScope] overrides.
class PianoExercisesApp extends StatelessWidget {
  const PianoExercisesApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Piano Exercises',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: home ?? const AppNavigationShell(),
    );
  }
}
