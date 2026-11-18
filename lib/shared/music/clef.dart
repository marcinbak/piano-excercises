/// Musical staff clef anchored by absolute diatonic steps (`octave * 7 + step`).
enum Clef {
  // Bottom line E4 = 4 * 7 + 2 = 30; top line F5 = 38; G4 reference = +2.
  treble(
    bottomLineDiatonicStep: 30,
    topLineDiatonicStep: 38,
    referenceLineOffset: 2,
  ),
  // Bottom line G2 = 2 * 7 + 4 = 18; top line A3 = 26; F3 reference = +6.
  bass(
    bottomLineDiatonicStep: 18,
    topLineDiatonicStep: 26,
    referenceLineOffset: 6,
  );

  const Clef({
    required this.bottomLineDiatonicStep,
    required this.topLineDiatonicStep,
    required this.referenceLineOffset,
  });

  final int bottomLineDiatonicStep;
  final int topLineDiatonicStep;
  final int referenceLineOffset;

  int get referenceDiatonicStep => bottomLineDiatonicStep + referenceLineOffset;
}
