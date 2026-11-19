/// SMuFL (`Bravura`) glyph codepoints and engraving metrics in staff spaces.
abstract final class SmuflGlyphs {
  static const String gClef = '\uE050';
  static const String fClef = '\uE062';

  static const List<String> timeSigDigits = <String>[
    '\uE080',
    '\uE081',
    '\uE082',
    '\uE083',
    '\uE084',
    '\uE085',
    '\uE086',
    '\uE087',
    '\uE088',
    '\uE089',
  ];

  static const String noteheadWhole = '\uE0A2';
  static const String noteheadHalf = '\uE0A3';
  static const String noteheadBlack = '\uE0A4';

  static const String accidentalFlat = '\uE260';
  static const String accidentalNatural = '\uE261';
  static const String accidentalSharp = '\uE262';
  static const String accidentalDoubleSharp = '\uE263';
  static const String accidentalDoubleFlat = '\uE264';

  static const String augmentationDot = '\uE1E7';

  static const String flag8thUp = '\uE240';
  static const String flag8thDown = '\uE241';
  static const String flag16thUp = '\uE242';
  static const String flag16thDown = '\uE243';
  static const String flag32ndUp = '\uE244';
  static const String flag32ndDown = '\uE245';
  static const String flag64thUp = '\uE246';
  static const String flag64thDown = '\uE247';

  static const String restWhole = '\uE4E3';
  static const String restHalf = '\uE4E4';
  static const String restQuarter = '\uE4E5';
  static const String rest8th = '\uE4E6';
  static const String rest16th = '\uE4E7';
  static const String rest32nd = '\uE4E8';
  static const String rest64th = '\uE4E9';

  static const double noteheadWidthSpaces = 1.18;
  static const double wholeNoteheadWidthSpaces = 1.69;
  static const double stemThicknessSpaces = 0.12;
  static const double stemUpXOffsetSpaces =
      (noteheadWidthSpaces - stemThicknessSpaces) / 2;
  static const double stemDownXOffsetSpaces = -stemUpXOffsetSpaces;
  static const double secondShiftSpaces =
      noteheadWidthSpaces - stemThicknessSpaces;
  static const double stemUpYOffsetSpaces = 0.16;
  static const double stemDownYOffsetSpaces = -0.16;
  static const double defaultStemLengthSpaces = 3.5;
  static const double beamThicknessSpaces = 0.48;
  static const double beamSpacingSpaces = 0.24;
  static const double accidentalColumnSpacingSpaces = 1.12;

  /// Returns the SMuFL digit glyph for [digit] in `0..9`.
  static String timeSigDigit(int digit) {
    RangeError.checkValueInInterval(digit, 0, 9, 'digit');
    return timeSigDigits[digit];
  }
}
