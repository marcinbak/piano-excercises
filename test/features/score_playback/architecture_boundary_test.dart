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

  group('ScorePlayback architecture boundaries', () {
    test(
      'domain/ is pure Dart with zero Flutter, Riverpod, UI, or other features',
      () {
        final files = dartFilesIn('lib/features/score_playback/domain');
        expect(files, isNotEmpty);

        const forbiddenPrefixes = <String>[
          'package:flutter/',
          'package:material_ui/',
          'package:flutter_riverpod/',
          'package:smufl_notation/',
          'package:piano_exercises/features/catalog/',
          'package:piano_exercises/features/midi/',
          'package:piano_exercises/features/piece_practice/',
          'package:piano_exercises/features/score_editor/',
          'package:piano_exercises/features/score_playback/state/',
          'package:piano_exercises/features/score_playback/ui/',
          'package:piano_exercises/features/score_playback/data/',
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

    test(
      'state/ imports zero ui/data/material_ui and uses midi barrel only',
      () {
        final files = dartFilesIn('lib/features/score_playback/state');
        expect(files, isNotEmpty);

        for (final file in files) {
          final content = file.readAsStringSync();
          for (final match in importPattern.allMatches(content)) {
            final uri = match.group(1)!;
            expect(
              uri.contains('/features/score_playback/ui/') ||
                  uri.contains('/features/score_playback/data/') ||
                  uri.contains('/features/catalog/') ||
                  uri.contains('/features/piece_practice/') ||
                  uri.contains('/features/score_editor/') ||
                  uri.startsWith('package:material_ui/') ||
                  uri.startsWith('package:flutter/'),
              isFalse,
              reason: '${file.path} has forbidden directive "$uri".',
            );
            if (uri.contains('/features/midi/')) {
              expect(
                uri,
                'package:piano_exercises/features/midi/midi.dart',
                reason: '${file.path} must import midi barrel only.',
              );
            }
          }
        }
      },
    );

    test('ui/ uses package:material_ui and barrel-only cross-feature imports', () {
      final uiFiles = dartFilesIn('lib/features/score_playback/ui');
      expect(uiFiles, isNotEmpty);

      for (final file in uiFiles) {
        final content = file.readAsStringSync();
        expect(
          content.contains('package:flutter/material.dart'),
          isFalse,
          reason:
              '${file.path} must import package:material_ui/material_ui.dart.',
        );
        for (final match in importPattern.allMatches(content)) {
          final uri = match.group(1)!;
          if (uri.contains('/features/midi/')) {
            expect(
              uri,
              'package:piano_exercises/features/midi/midi.dart',
              reason: '${file.path} must import midi barrel only.',
            );
          }
          expect(
            uri.contains('/features/catalog/') ||
                uri.contains('/features/piece_practice/') ||
                uri.contains('/features/score_editor/'),
            isFalse,
            reason:
                '${file.path} must not depend on higher-level features ($uri).',
          );
        }
      }
    });
  });
}
