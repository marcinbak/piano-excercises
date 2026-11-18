import 'package:piano_exercises/shared/music/clef.dart';
import 'package:piano_exercises/shared/music/midi_note.dart';
import 'package:piano_exercises/shared/music/pitch_class.dart';
import 'package:piano_exercises/shared/music/staff_position.dart';

/// Spelled musical note assigned to a specific [Clef] and [octave].
final class StaffNote {
  const StaffNote({
    required this.note,
    required this.octave,
    required this.clef,
    this.accidental = Accidental.natural,
  }) : // Dart const evaluation disallows reading enum fields (semitoneOffset /
       // semitoneDelta), so compute MIDI bounds via enum identity.
       assert(
         (((octave + 1) * 12) +
                 (note == DiatonicNote.c
                     ? 0
                     : note == DiatonicNote.d
                     ? 2
                     : note == DiatonicNote.e
                     ? 4
                     : note == DiatonicNote.f
                     ? 5
                     : note == DiatonicNote.g
                     ? 7
                     : note == DiatonicNote.a
                     ? 9
                     : 11) +
                 (accidental == Accidental.flat
                     ? -1
                     : accidental == Accidental.sharp
                     ? 1
                     : 0)) >=
             MidiNote.minNumber,
       ),
       assert(
         (((octave + 1) * 12) +
                 (note == DiatonicNote.c
                     ? 0
                     : note == DiatonicNote.d
                     ? 2
                     : note == DiatonicNote.e
                     ? 4
                     : note == DiatonicNote.f
                     ? 5
                     : note == DiatonicNote.g
                     ? 7
                     : note == DiatonicNote.a
                     ? 9
                     : 11) +
                 (accidental == Accidental.flat
                     ? -1
                     : accidental == Accidental.sharp
                     ? 1
                     : 0)) <=
             MidiNote.maxNumber,
       );

  /// Creates a [StaffNote] while throwing [RangeError] if outside MIDI `0..127`.
  factory StaffNote.validated({
    required DiatonicNote note,
    required int octave,
    required Clef clef,
    Accidental accidental = Accidental.natural,
  }) {
    MidiNote.fromPitch(note, octave: octave, accidental: accidental);
    return StaffNote(
      note: note,
      octave: octave,
      clef: clef,
      accidental: accidental,
    );
  }

  final DiatonicNote note;
  final int octave;
  final Clef clef;
  final Accidental accidental;

  int get diatonicStep => (octave * 7) + note.index;

  MidiNote get midiNote =>
      MidiNote.fromPitch(note, octave: octave, accidental: accidental);

  StaffPosition get staffPosition =>
      StaffPosition.forDiatonicStep(clef: clef, diatonicStep: diatonicStep);

  String get pitchName => '${note.letter}${accidental.symbol}$octave';

  bool matchesMidi(MidiNote played) => midiNote == played;

  bool matchesNoteNumber(int noteNumber) => midiNote.number == noteNumber;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is StaffNote &&
            other.note == note &&
            other.octave == octave &&
            other.clef == clef &&
            other.accidental == accidental);
  }

  @override
  int get hashCode => Object.hash(note, octave, clef, accidental);
}
