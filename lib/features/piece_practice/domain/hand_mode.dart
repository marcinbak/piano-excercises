import 'package:piano_exercises/shared/music/music.dart';

/// Practice hand selection filtering which clef requires hits vs dims.
enum HandMode {
  both('Both Hands'),
  right('Right Hand'),
  left('Left Hand');

  const HandMode(this.label);

  final String label;

  bool includesClef(Clef clef) => switch (this) {
    HandMode.both => true,
    HandMode.right => clef == Clef.treble,
    HandMode.left => clef == Clef.bass,
  };

  Clef? get dimmedClef => switch (this) {
    HandMode.both => null,
    HandMode.right => Clef.bass,
    HandMode.left => Clef.treble,
  };
}
