import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/drill/drill.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/progression/progression.dart';

/// Initializes persistence before first frame and returns the configured app root.
Future<PianoExercisesRoot> bootstrapPianoExercisesRoot({
  Future<ProgressionRepository> Function()? createProgressionRepository,
}) async {
  ProgressionRepository repository;
  try {
    repository =
        await (createProgressionRepository ??
            SharedPreferencesProgressionRepository.create)();
  } catch (_) {
    repository = InMemoryProgressionRepository();
  }
  return PianoExercisesRoot(progressionRepository: repository);
}

/// Root widget configuring dependency overrides for the application.
class PianoExercisesRoot extends StatelessWidget {
  const PianoExercisesRoot({super.key, this.progressionRepository});

  final ProgressionRepository? progressionRepository;

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
        if (progressionRepository != null)
          progressionRepositoryProvider.overrideWithValue(
            progressionRepository!,
          ),
      ],
      child: const PianoExercisesApp(),
    );
  }
}

/// Top-level [MaterialApp] entry point; tests can wrap it with custom [ProviderScope] overrides.
class PianoExercisesApp extends StatelessWidget {
  const PianoExercisesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Piano Exercises',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const DrillScreen(),
    );
  }
}
