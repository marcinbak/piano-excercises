import 'package:piano_exercises/shared/music/music.dart';

/// Practice hand selection filtering which clef requires hits vs dims.
enum HandMode {
  both('Both Hands', 'Both'),
  right('Right Hand', 'Right'),
  left('Left Hand', 'Left');

  const HandMode(this.label, this.shortLabel);

  final String label;
  final String shortLabel;

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
