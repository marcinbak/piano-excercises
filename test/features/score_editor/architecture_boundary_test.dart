import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final importPattern = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  List<File> dartFilesIn(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      return const <File>[];
    }
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList(growable: false);
  }

  group('ScoreEditor architecture boundaries', () {
    test(
      'domain/ is pure Dart with zero Flutter, Riverpod, UI, or other features',
      () {
        final files = dartFilesIn('lib/features/score_editor/domain');
        expect(files, isNotEmpty);

        const forbiddenPrefixes = <String>[
          'package:flutter/',
          'package:material_ui/',
          'package:flutter_riverpod/',
          'package:smufl_notation/',
          'package:piano_exercises/features/catalog/',
          'package:piano_exercises/features/midi/',
          'package:piano_exercises/features/piece_practice/',
          'package:piano_exercises/features/score_editor/state/',
          'package:piano_exercises/features/score_editor/ui/',
          'package:piano_exercises/features/score_editor/data/',
          'dart:io',
          'dart:ui',
        ];

        for (final file in files) {
          final content = file.readAsStringSync();
          for (final match in importPattern.allMatches(content)) {
            final uri = match.group(1)!;
            for (final forbidden in forbiddenPrefixes) {
              expect(
                uri.startsWith(forbidden),
                isFalse,
                reason: '${file.path} has forbidden directive "$uri".',
              );
            }
          }
        }
      },
    );

    test('state/ imports zero ui/data/material_ui and uses catalog & midi barrels only', () {
      final files = dartFilesIn('lib/features/score_editor/state');
      expect(files, isNotEmpty);

      for (final file in files) {
        final content = file.readAsStringSync();
        for (final match in importPattern.allMatches(content)) {
          final uri = match.group(1)!;
          expect(
            uri.contains('/features/score_editor/ui/') ||
                uri.contains('/features/score_editor/data/') ||
                uri.startsWith('package:material_ui/') ||
                uri.startsWith('package:flutter/'),
            isFalse,
            reason: '${file.path} has forbidden directive "$uri".',
          );
          if (uri.contains('/features/catalog/')) {
            expect(
              uri,
              'package:piano_exercises/features/catalog/catalog.dart',
              reason: '${file.path} must import catalog barrel only.',
            );
          }
          if (uri.contains('/features/midi/')) {
            expect(
              uri,
              'package:piano_exercises/features/midi/midi.dart',
              reason: '${file.path} must import midi barrel only.',
            );
          }
        }
      }
    });

    test('shared/ never imports features/ or app/ and lower features never import score_editor', () {
      for (final file in dartFilesIn('lib/shared')) {
        final content = file.readAsStringSync();
        for (final match in importPattern.allMatches(content)) {
          final uri = match.group(1)!;
          expect(
            uri.contains('/features/') || uri.contains('/app/'),
            isFalse,
            reason: '${file.path} must not import features/ or app/ ($uri).',
          );
        }
      }
      for (final dir in const <String>[
        'lib/features/catalog',
        'lib/features/midi',
        'lib/features/piece_practice',
      ]) {
        for (final file in dartFilesIn(dir)) {
          expect(
            file.readAsStringSync().contains('score_editor'),
            isFalse,
            reason: '${file.path} must never import score_editor.',
          );
        }
      }
    });
  });
}
