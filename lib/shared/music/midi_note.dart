import 'package:piano_exercises/shared/music/pitch_class.dart';

/// Immutable MIDI note number (`0..127`) with scientific pitch helpers.
final class MidiNote implements Comparable<MidiNote> {
  const MidiNote(this.number)
    : assert(number >= minNumber && number <= maxNumber);

  /// Creates a [MidiNote] after validating [number] is in `0..127`.
  factory MidiNote.fromNumber(int number) {
    RangeError.checkValueInInterval(number, minNumber, maxNumber, 'number');
    return MidiNote(number);
  }

  /// Creates a [MidiNote] from diatonic spelling and scientific [octave].
  ///
  /// Throws [RangeError] if the resulting MIDI note number falls outside `0..127`.
  factory MidiNote.fromPitch(
    DiatonicNote note, {
    required int octave,
    Accidental accidental = Accidental.natural,
  }) {
    // Reject extreme octaves before multiplying so (octave + 1) * 12 cannot
    // wrap modulo 2^64 into 0..127 (B#-2 is MIDI 0; any octave outside -2..10
    // is guaranteed out of range for any accidental).
    RangeError.checkValueInInterval(octave, -2, 10, 'octave');
    final number =
        ((octave + 1) * 12) + note.semitoneOffset + accidental.semitoneDelta;
    RangeError.checkValueInInterval(number, minNumber, maxNumber, 'number');
    return MidiNote(number);
  }

  static const int minNumber = 0;
  static const int maxNumber = 127;
  static const MidiNote middleC = MidiNote(60);

  final int number;

  /// Non-throwing variant of [MidiNote.fromNumber].
  static MidiNote? tryFromNumber(int number) {
    if (number < minNumber || number > maxNumber) {
      return null;
    }
    return MidiNote(number);
  }

  int get octave => (number ~/ 12) - 1;

  PitchClass get pitchClass => PitchClass.values[number % 12];

  DiatonicNote? get naturalNote => pitchClass.naturalNote;

  bool get isNatural => pitchClass.isNatural;

  String get name => '${pitchClass.label}$octave';

  @override
  int compareTo(MidiNote other) => number.compareTo(other.number);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MidiNote && other.number == number);
  }

  @override
  int get hashCode => number.hashCode;
}
