import 'package:piano_exercises/shared/music/music.dart';

/// Maps a played [MidiNote] (`0..127`) to a sharp-spelled [StaffNote].
///
/// Middle C (`60`) adopts [referenceClef] so played Middle C renders on the
/// active target clef rather than always jumping to treble or bass.
StaffNote mapMidiNoteToStaffNote(
  MidiNote midiNote, {
  required Clef referenceClef,
}) {
  final (
    DiatonicNote note,
    Accidental accidental,
  ) = switch (midiNote.pitchClass) {
    PitchClass.cSharp => (DiatonicNote.c, Accidental.sharp),
    PitchClass.dSharp => (DiatonicNote.d, Accidental.sharp),
    PitchClass.fSharp => (DiatonicNote.f, Accidental.sharp),
    PitchClass.gSharp => (DiatonicNote.g, Accidental.sharp),
    PitchClass.aSharp => (DiatonicNote.a, Accidental.sharp),
    _ => (midiNote.pitchClass.naturalNote!, Accidental.natural),
  };

  final clef = switch (midiNote.number) {
    > 60 => Clef.treble,
    < 60 => Clef.bass,
    _ => referenceClef,
  };

  return StaffNote(
    note: note,
    octave: midiNote.octave,
    clef: clef,
    accidental: accidental,
  );
}
