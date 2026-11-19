import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _bravuraLoaded = false;

/// Loads `Bravura.otf` into Flutter's test font registry from repo or package cwd.
Future<void> loadBravuraTestFont() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_bravuraLoaded) {
    return;
  }
  const candidates = <String>[
    'assets/fonts/Bravura.otf',
    '../../assets/fonts/Bravura.otf',
  ];
  File? fontFile;
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      fontFile = file;
      break;
    }
  }
  if (fontFile == null) {
    throw StateError(
      'Unable to locate Bravura.otf from ${Directory.current.path}',
    );
  }
  final bytes = fontFile.readAsBytesSync();
  final data = ByteData.view(bytes.buffer);
  final loader = FontLoader('Bravura')..addFont(Future<ByteData>.value(data));
  await loader.load();
  _bravuraLoaded = true;
}
