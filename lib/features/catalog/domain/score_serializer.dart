import 'dart:typed_data';

import 'package:piano_exercises/shared/music/music.dart';

/// Boundary contract for serializing a domain [Score] into persisted score bytes.
abstract interface class ScoreSerializer {
  Uint8List serialize(Score score);
}
