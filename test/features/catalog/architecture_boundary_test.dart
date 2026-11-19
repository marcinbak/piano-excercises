import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Catalog architecture boundaries', () {
    test('lib/features/catalog/domain/ imports zero UI, state, plugin, or dart:io libraries', () {
      final domainDir = Directory('lib/features/catalog/domain');
      expect(domainDir.existsSync(), isTrue);

      final forbiddenPrefixes = <String>[
        'package:flutter/',
        'package:material_ui/',
        'package:flutter_riverpod/',
        'package:sqflite',
        'package:path_provider',
        'package:file_picker',
        'dart:io',
      ];
      final importPattern = RegExp(
        r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
        multiLine: true,
      );

      final dartFiles = domainDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList(growable: false);
      expect(dartFiles, isNotEmpty);

      for (final file in dartFiles) {
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

    test('lib/features/catalog/ui/ uses package:material_ui and never package:flutter/material.dart', () {
      final uiDir = Directory('lib/features/catalog/ui');
      final dartFiles = uiDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList(growable: false);
      expect(dartFiles, isNotEmpty);

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        expect(
          content.contains('package:flutter/material.dart'),
          isFalse,
          reason:
              '${file.path} must import package:material_ui/material_ui.dart.',
        );
      }
    });

    test('lib/features/catalog/state/ imports zero data or ui files', () {
      final stateDir = Directory('lib/features/catalog/state');
      final importPattern = RegExp(
        r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
        multiLine: true,
      );
      final dartFiles = stateDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList(growable: false);
      expect(dartFiles, isNotEmpty);

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        for (final match in importPattern.allMatches(content)) {
          final uri = match.group(1)!;
          expect(
            uri.contains('/features/catalog/data/') ||
                uri.contains('/features/catalog/ui/') ||
                uri.startsWith('package:material_ui/'),
            isFalse,
            reason: '${file.path} has forbidden directive "$uri".',
          );
        }
      }
    });

    test('pubspec.yaml bundles zero .mxl or .musicxml assets', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('.mxl'), isFalse);
      expect(pubspec.contains('.musicxml'), isFalse);
      expect(pubspec.contains('assets/fonts/Bravura-OFL.txt'), isTrue);
    });
  });
}
