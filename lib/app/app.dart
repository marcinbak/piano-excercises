import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/drill/drill.dart';
import 'package:piano_exercises/features/midi/midi.dart';

/// Root widget configuring dependency overrides for the application.
class PianoExercisesRoot extends StatelessWidget {
  const PianoExercisesRoot({super.key});

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
