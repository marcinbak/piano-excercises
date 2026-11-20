import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('HandMode', () {
    test('defines labels, clef inclusion, and dimmedClef', () {
      expect(HandMode.both.label, 'Both Hands');
      expect(HandMode.both.shortLabel, 'Both');
      expect(HandMode.both.includesClef(Clef.treble), isTrue);
      expect(HandMode.both.includesClef(Clef.bass), isTrue);
      expect(HandMode.both.dimmedClef, isNull);

      expect(HandMode.right.label, 'Right Hand');
      expect(HandMode.right.shortLabel, 'Right');
      expect(HandMode.right.includesClef(Clef.treble), isTrue);
      expect(HandMode.right.includesClef(Clef.bass), isFalse);
      expect(HandMode.right.dimmedClef, Clef.bass);

      expect(HandMode.left.label, 'Left Hand');
      expect(HandMode.left.shortLabel, 'Left');
      expect(HandMode.left.includesClef(Clef.treble), isFalse);
      expect(HandMode.left.includesClef(Clef.bass), isTrue);
      expect(HandMode.left.dimmedClef, Clef.treble);
    });
  });
}
