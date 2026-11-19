import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _resolvePackageRoot() {
  for (final dir in const <String>['packages/smufl_notation', '.']) {
    final pub = File('$dir/pubspec.yaml');
    if (Directory('$dir/lib').existsSync() &&
        pub.existsSync() &&
        pub.readAsStringSync().contains('name: smufl_notation')) {
      return Directory(dir);
    }
  }
  throw StateError(
    'Unable to locate packages/smufl_notation from ${Directory.current.path}',
  );
}

List<File> _dartFilesIn(Directory dir) => dir.existsSync()
    ? dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
    : const <File>[];

String _rel(Directory root, File f) {
  final p = f.path.replaceAll('\\', '/');
  return p.startsWith('${root.path}/') ? p.substring(root.path.length + 1) : p;
}

List<String> _directives(String src, String kind) => <String>[
  for (final m in RegExp(
    '^\\s*$kind\\s+[\'"]([^\'"]+)[\'"]',
    multiLine: true,
  ).allMatches(src))
    m.group(1)!,
];

void main() {
  final pkgRoot = _resolvePackageRoot();
  final libFiles = _dartFilesIn(Directory('${pkgRoot.path}/lib'));

  test('lib/src/ has zero flat files and uses only 5 layer folders', () {
    const layers = <String>{'glyphs', 'model', 'layout', 'painting', 'widgets'};
    for (final file in libFiles) {
      final rel = _rel(pkgRoot, file);
      if (!rel.startsWith('lib/src/')) continue;
      final parts = rel.substring('lib/src/'.length).split('/');
      expect(
        parts.length,
        greaterThan(1),
        reason: '$rel sits flat in lib/src/',
      );
      expect(layers, contains(parts.first), reason: 'Unknown layer in $rel');
    }
  });

  test('lib/smufl_notation.dart is sole export file and hides internals', () {
    const banned = <String>[
      'chord_collision_solver',
      'measure_preparer',
      'measure_placer',
      'chord_placer',
      'beam_solver',
      'tie_solver',
      'glyph_painter',
      'backdrop_painter',
      'chord_renderer',
      'ornaments',
      'wrong_note_painter',
    ];
    final barrel = File('${pkgRoot.path}/lib/smufl_notation.dart')
        .readAsStringSync();
    for (final uri in _directives(barrel, 'export')) {
      for (final b in banned) {
        expect(uri, isNot(contains(b)), reason: 'Barrel leaks $uri');
      }
    }
    for (final file in libFiles) {
      final rel = _rel(pkgRoot, file);
      if (rel.startsWith('lib/src/')) {
        expect(
          _directives(file.readAsStringSync(), 'export'),
          isEmpty,
          reason: rel,
        );
      }
    }
  });

  test('enforces strict layer import boundaries across lib/src/', () {
    const pureDart = <String>[
      'dart:ui',
      'package:flutter',
      'src/layout/',
      'src/painting/',
      'src/widgets/',
    ];
    const rules = <String, List<String>>{
      'lib/src/glyphs/': pureDart,
      'lib/src/model/': pureDart,
      'lib/src/layout/': <String>[
        'package:flutter',
        'src/painting/',
        'src/widgets/',
      ],
      'lib/src/painting/': <String>[
        'package:flutter/widgets.dart',
        'src/widgets/',
      ],
    };
    for (final file in libFiles) {
      final rel = _rel(pkgRoot, file);
      final imports = _directives(file.readAsStringSync(), 'import');
      for (final entry in rules.entries) {
        if (!rel.startsWith(entry.key)) continue;
        for (final imp in imports) {
          for (final forbid in entry.value) {
            expect(imp, isNot(contains(forbid)), reason: '$rel imports $imp');
          }
        }
      }
    }
  });

  test('zero app or material_ui imports in packages/smufl_notation/', () {
    for (final sub in const <String>['lib', 'example', 'test']) {
      for (final file in _dartFilesIn(Directory('${pkgRoot.path}/$sub'))) {
        final src = file.readAsStringSync();
        for (final uri in <String>[
          ..._directives(src, 'import'),
          ..._directives(src, 'export'),
        ]) {
          expect(
            uri,
            isNot(contains('package:piano_exercises')),
            reason: _rel(pkgRoot, file),
          );
          expect(
            uri,
            isNot(contains('package:material_ui')),
            reason: _rel(pkgRoot, file),
          );
        }
      }
    }
  });
}
