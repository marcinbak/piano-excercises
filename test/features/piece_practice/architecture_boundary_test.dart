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

  group('PiecePractice architecture boundaries', () {
    test('domain/ is pure Dart with zero UI, Riverpod, catalog, midi, or smufl imports', () {
      final files = dartFilesIn('lib/features/piece_practice/domain');
      expect(files, isNotEmpty);

      const forbiddenPrefixes = <String>[
        'package:flutter/',
        'package:material_ui/',
        'package:flutter_riverpod/',
        'package:smufl_notation/',
        'package:piano_exercises/features/catalog/',
        'package:piano_exercises/features/midi/',
        'package:piano_exercises/features/piece_practice/state/',
        'package:piano_exercises/features/piece_practice/ui/',
        'package:piano_exercises/features/piece_practice/data/',
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
    });

    test('state/ imports zero ui/data/material_ui and uses catalog & midi barrels only', () {
      final files = dartFilesIn('lib/features/piece_practice/state');
      expect(files, isNotEmpty);

      for (final file in files) {
        final content = file.readAsStringSync();
        for (final match in importPattern.allMatches(content)) {
          final uri = match.group(1)!;
          expect(
            uri.contains('/features/piece_practice/ui/') ||
                uri.contains('/features/piece_practice/data/') ||
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

    test('ui/ uses package:material_ui, barrel-only cross-feature imports, and no catalog cycle', () {
      final uiFiles = dartFilesIn('lib/features/piece_practice/ui');
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

      for (final catalogFile in dartFilesIn('lib/features/catalog')) {
        final content = catalogFile.readAsStringSync();
        expect(
          content.contains('piece_practice'),
          isFalse,
          reason: '${catalogFile.path} must never import piece_practice.',
        );
        expect(
          content.contains('/features/midi/'),
          isFalse,
          reason: '${catalogFile.path} must never import midi.',
        );
      }
    });
  });
}
