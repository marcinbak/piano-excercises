import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _modelForbid = <String>[
  'dart:ui',
  'package:flutter',
  'src/layout/',
  'src/painting/',
  'src/widgets/',
];
const _layerRules = <String, List<String>>{
  'lib/src/glyphs/': <String>[..._modelForbid, 'src/model/'],
  'lib/src/model/': _modelForbid,
  'lib/src/layout/': <String>[
    'package:flutter',
    'src/painting/',
    'src/widgets/',
  ],
  'lib/src/painting/': <String>[
    'package:flutter/widgets.dart',
    'package:flutter/material.dart',
    'package:flutter/cupertino.dart',
    'src/widgets/',
  ],
};
const _paintingAllow = <String>{
  'package:flutter/painting.dart',
  'package:flutter/rendering.dart',
  'package:flutter/foundation.dart',
};
const _bannedInternals = <String>[
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

String _stripComments(String src) => src.replaceAllMapped(
  RegExp(r'//[^\n]*|/\*[\s\S]*?\*/'),
  (m) => m.group(0)!.startsWith('//') ? '' : ' ',
);

List<String> _directives(String src, String kind) {
  final re = RegExp(
    '(?:^|;)\\s*$kind\\s+(?:r?\'\'\'([\\s\\S]*?)\'\'\'|r?"""([\\s\\S]*?)"""|r?\'([^\'\\n]*)\'|r?"([^"\\n]*)")',
    multiLine: true,
  );
  return <String>[
    for (final m in re.allMatches(_stripComments(src)))
      m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4)!,
  ];
}

void _checkLayerImports(String rel, List<String> imports) {
  for (final imp in imports) {
    final isPkgOrDart = imp.startsWith('dart:') || imp.startsWith('package:');
    expect(isPkgOrDart, isTrue, reason: '$rel relative import: $imp');
    expect(
      imp,
      isNot('package:smufl_notation/smufl_notation.dart'),
      reason: rel,
    );
    if (rel.startsWith('lib/src/painting/') &&
        imp.startsWith('package:flutter/')) {
      expect(_paintingAllow, contains(imp), reason: '$rel -> $imp');
    }
    for (final entry in _layerRules.entries) {
      if (!rel.startsWith(entry.key)) continue;
      for (final forbid in entry.value) {
        expect(imp, isNot(contains(forbid)), reason: '$rel -> $imp');
      }
    }
  }
}

void main() {
  final pkgRoot = _resolvePackageRoot();
  final libFiles = _dartFilesIn(Directory('${pkgRoot.path}/lib'));
  final partRe = RegExp(
    r'''(?:^|;)\s*part\s+(?:of\b|r?['"])''',
    multiLine: true,
  );

  test('lib/ exposes only smufl_notation.dart and 5 src/ layers', () {
    const layers = <String>{'glyphs', 'model', 'layout', 'painting', 'widgets'};
    for (final file in libFiles) {
      final rel = _rel(pkgRoot, file);
      if (rel == 'lib/smufl_notation.dart') continue;
      expect(rel, startsWith('lib/src/'), reason: rel);
      final parts = rel.substring('lib/src/'.length).split('/');
      expect(parts.length, greaterThan(1), reason: '$rel flat in lib/src/');
      expect(layers, contains(parts.first), reason: rel);
    }
  });

  test('barrel is sole export file, no parts, hides internals', () {
    final barrel = File('${pkgRoot.path}/lib/smufl_notation.dart')
        .readAsStringSync();
    for (final uri in _directives(barrel, 'export')) {
      for (final b in _bannedInternals) {
        expect(uri, isNot(contains(b)), reason: 'Barrel leaks $uri');
      }
    }
    for (final file in libFiles) {
      final rel = _rel(pkgRoot, file);
      final src = file.readAsStringSync();
      expect(partRe.hasMatch(_stripComments(src)), isFalse, reason: rel);
      if (rel.startsWith('lib/src/')) {
        expect(_directives(src, 'export'), isEmpty, reason: rel);
      }
    }
  });

  test('enforces strict layer import boundaries across lib/src/', () {
    for (final file in libFiles) {
      final rel = _rel(pkgRoot, file);
      if (rel.startsWith('lib/src/')) {
        _checkLayerImports(rel, _directives(file.readAsStringSync(), 'import'));
      }
    }
  });

  test('zero app or material_ui imports in packages/smufl_notation/', () {
    for (final sub in const <String>['lib', 'example', 'test']) {
      for (final file in _dartFilesIn(Directory('${pkgRoot.path}/$sub'))) {
        final rel = _rel(pkgRoot, file);
        final src = file.readAsStringSync();
        for (final u in <String>[
          ..._directives(src, 'import'),
          ..._directives(src, 'export'),
        ]) {
          expect(u, isNot(contains('package:piano_exercises')), reason: rel);
          expect(u, isNot(contains('package:material_ui')), reason: rel);
        }
      }
    }
  });
}
