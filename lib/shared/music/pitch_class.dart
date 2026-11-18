/// Natural diatonic letter names within an octave (`C`..`B`).
enum DiatonicNote {
  c(0, 'C'),
  d(2, 'D'),
  e(4, 'E'),
  f(5, 'F'),
  g(7, 'G'),
  a(9, 'A'),
  b(11, 'B');

  const DiatonicNote(this.semitoneOffset, this.letter);

  final int semitoneOffset;
  final String letter;
}

/// Chromatic alteration relative to a natural [DiatonicNote].
enum Accidental {
  flat(-1, 'b'),
  natural(0, ''),
  sharp(1, '#');

  const Accidental(this.semitoneDelta, this.symbol);

  final int semitoneDelta;
  final String symbol;
}

/// The twelve chromatic pitch classes (`0..11`), named with sharp spellings.
enum PitchClass {
  c(0, 'C', DiatonicNote.c),
  cSharp(1, 'C#'),
  d(2, 'D', DiatonicNote.d),
  dSharp(3, 'D#'),
  e(4, 'E', DiatonicNote.e),
  f(5, 'F', DiatonicNote.f),
  fSharp(6, 'F#'),
  g(7, 'G', DiatonicNote.g),
  gSharp(8, 'G#'),
  a(9, 'A', DiatonicNote.a),
  aSharp(10, 'A#'),
  b(11, 'B', DiatonicNote.b);

  const PitchClass(this.semitone, this.label, [this.naturalNote]);

  final int semitone;
  final String label;
  final DiatonicNote? naturalNote;

  bool get isNatural => naturalNote != null;

  /// Resolves any [semitone] integer modulo 12 into its chromatic [PitchClass].
  static PitchClass fromSemitone(int semitone) => values[semitone % 12];
}
