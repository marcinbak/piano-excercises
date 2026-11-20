import 'package:piano_exercises/shared/music/clef.dart';
import 'package:piano_exercises/shared/music/key_signature.dart';
import 'package:piano_exercises/shared/music/midi_note.dart';
import 'package:piano_exercises/shared/music/pitch_class.dart';
import 'package:piano_exercises/shared/music/staff_note.dart';

/// Key-signature-aware MIDI spelling and diatonic pitch-editing utilities.
abstract final class KeyPitchSpeller {
  /// Spells [midi] on [clef] favoring diatonic degrees in [keySignature].
  ///
  /// Matches key-signature degrees first (including `Cb`, `Fb`, `E#`, `B#` in
  /// `-7..+7`), then natural letters, then chromatic flats (`fifths < 0`) or sharps.
  static StaffNote spellMidiNote(
    MidiNote midi, {
    required Clef clef,
    required KeySignature keySignature,
  }) {
    final diatonicMatch = _spellDiatonicInKey(midi, clef, keySignature);
    if (diatonicMatch != null) {
      return diatonicMatch;
    }

    if (midi.isNatural) {
      return StaffNote(
        note: midi.naturalNote!,
        octave: midi.octave,
        clef: clef,
        accidental: Accidental.natural,
      );
    }

    final (DiatonicNote note, Accidental accidental) = _spellBlackKey(
      midi.pitchClass,
      preferFlats: keySignature.fifths < 0,
    );
    return StaffNote(
      note: note,
      octave: midi.octave,
      clef: clef,
      accidental: accidental,
    );
  }

  /// Steps [current] by [deltaSteps] diatonic letters using [keySignature] defaults.
  ///
  /// Returns [current] unchanged if the stepped pitch falls outside MIDI `0..127`.
  static StaffNote stepDiatonic(
    StaffNote current, {
    required int deltaSteps,
    required KeySignature keySignature,
  }) {
    if (deltaSteps == 0) {
      return current;
    }
    final targetStep = current.diatonicStep + deltaSteps;
    final nextNoteIndex = targetStep % DiatonicNote.values.length;
    final nextOctave =
        (targetStep - nextNoteIndex) ~/ DiatonicNote.values.length;
    if (nextOctave < -2 || nextOctave > 10) {
      return current;
    }
    final nextNote = DiatonicNote.values[nextNoteIndex];
    final nextAccidental = keySignature.defaultAccidentalFor(nextNote);
    final midiNumber =
        ((nextOctave + 1) * 12) +
        nextNote.semitoneOffset +
        nextAccidental.semitoneDelta;
    if (midiNumber < MidiNote.minNumber || midiNumber > MidiNote.maxNumber) {
      return current;
    }
    return StaffNote.validated(
      note: nextNote,
      octave: nextOctave,
      clef: current.clef,
      accidental: nextAccidental,
    );
  }

  /// Applies [accidental] to [current] if the resulting pitch stays in MIDI `0..127`.
  static StaffNote withAccidental(StaffNote current, Accidental accidental) {
    final midiNumber =
        ((current.octave + 1) * 12) +
        current.note.semitoneOffset +
        accidental.semitoneDelta;
    if (midiNumber < MidiNote.minNumber || midiNumber > MidiNote.maxNumber) {
      return current;
    }
    return StaffNote.validated(
      note: current.note,
      octave: current.octave,
      clef: current.clef,
      accidental: accidental,
    );
  }

  static StaffNote? _spellDiatonicInKey(
    MidiNote midi,
    Clef clef,
    KeySignature keySignature,
  ) {
    final baseOctave = midi.octave;
    // Search +/- 1 octave to catch enharmonic boundary spellings (Cb, Fb, E#, B#).
    for (var oct = baseOctave - 1; oct <= baseOctave + 1; oct += 1) {
      if (oct < -2 || oct > 10) {
        continue;
      }
      for (final note in DiatonicNote.values) {
        final accidental = keySignature.defaultAccidentalFor(note);
        final number =
            ((oct + 1) * 12) + note.semitoneOffset + accidental.semitoneDelta;
        if (number == midi.number) {
          return StaffNote(
            note: note,
            octave: oct,
            clef: clef,
            accidental: accidental,
          );
        }
      }
    }
    return null;
  }

  static (DiatonicNote, Accidental) _spellBlackKey(
    PitchClass pitchClass, {
    required bool preferFlats,
  }) {
    if (preferFlats) {
      return switch (pitchClass) {
        PitchClass.cSharp => (DiatonicNote.d, Accidental.flat),
        PitchClass.dSharp => (DiatonicNote.e, Accidental.flat),
        PitchClass.fSharp => (DiatonicNote.g, Accidental.flat),
        PitchClass.gSharp => (DiatonicNote.a, Accidental.flat),
        PitchClass.aSharp => (DiatonicNote.b, Accidental.flat),
        _ => (pitchClass.naturalNote!, Accidental.natural),
      };
    }
    return switch (pitchClass) {
      PitchClass.cSharp => (DiatonicNote.c, Accidental.sharp),
      PitchClass.dSharp => (DiatonicNote.d, Accidental.sharp),
      PitchClass.fSharp => (DiatonicNote.f, Accidental.sharp),
      PitchClass.gSharp => (DiatonicNote.g, Accidental.sharp),
      PitchClass.aSharp => (DiatonicNote.a, Accidental.sharp),
      _ => (pitchClass.naturalNote!, Accidental.natural),
    };
  }
}
