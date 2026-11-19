import 'package:smufl_notation/src/smufl_glyphs.dart';

export 'package:smufl_notation/src/notation_score_model.dart';

/// Staff clef within a piano grand staff.
enum SmuflClef {
  treble(referenceStep: 2),
  bass(referenceStep: 6);

  const SmuflClef({required this.referenceStep});

  final int referenceStep;
}

/// Chromatic alteration glyph and semitone offset (`-2..+2`).
enum SmuflAccidental {
  doubleFlat(semitoneDelta: -2, glyph: SmuflGlyphs.accidentalDoubleFlat),
  flat(semitoneDelta: -1, glyph: SmuflGlyphs.accidentalFlat),
  natural(semitoneDelta: 0, glyph: SmuflGlyphs.accidentalNatural),
  sharp(semitoneDelta: 1, glyph: SmuflGlyphs.accidentalSharp),
  doubleSharp(semitoneDelta: 2, glyph: SmuflGlyphs.accidentalDoubleSharp);

  const SmuflAccidental({required this.semitoneDelta, required this.glyph});

  final int semitoneDelta;
  final String glyph;
}

/// Rhythmic note/rest duration and engraving properties.
enum DurationKind {
  whole(
    quarterBeats: 4.0,
    beamCount: 0,
    isHollow: true,
    hasStem: false,
    noteheadGlyph: SmuflGlyphs.noteheadWhole,
    restGlyph: SmuflGlyphs.restWhole,
  ),
  half(
    quarterBeats: 2.0,
    beamCount: 0,
    isHollow: true,
    hasStem: true,
    noteheadGlyph: SmuflGlyphs.noteheadHalf,
    restGlyph: SmuflGlyphs.restHalf,
  ),
  quarter(
    quarterBeats: 1.0,
    beamCount: 0,
    isHollow: false,
    hasStem: true,
    noteheadGlyph: SmuflGlyphs.noteheadBlack,
    restGlyph: SmuflGlyphs.restQuarter,
  ),
  eighth(
    quarterBeats: 0.5,
    beamCount: 1,
    isHollow: false,
    hasStem: true,
    noteheadGlyph: SmuflGlyphs.noteheadBlack,
    restGlyph: SmuflGlyphs.rest8th,
  ),
  sixteenth(
    quarterBeats: 0.25,
    beamCount: 2,
    isHollow: false,
    hasStem: true,
    noteheadGlyph: SmuflGlyphs.noteheadBlack,
    restGlyph: SmuflGlyphs.rest16th,
  );

  const DurationKind({
    required this.quarterBeats,
    required this.beamCount,
    required this.isHollow,
    required this.hasStem,
    required this.noteheadGlyph,
    required this.restGlyph,
  });

  final double quarterBeats;
  final int beamCount;
  final bool isHollow;
  final bool hasStem;
  final String noteheadGlyph;
  final String restGlyph;

  /// Beat duration scaled by `0..2` augmentation dots.
  double dottedBeats(int dots) {
    RangeError.checkValueInInterval(dots, 0, 2, 'dots');
    return switch (dots) {
      0 => quarterBeats,
      1 => quarterBeats * 1.5,
      _ => quarterBeats * 1.75,
    };
  }
}

/// Tie endpoint status on a [NotationNote].
enum TieFlag { none, start, stop, continueTie }

/// Single pitched note placed at [staffStep] relative to [clef] bottom line.
final class NotationNote {
  NotationNote({
    required this.staffStep,
    required this.clef,
    this.accidental,
    this.showAccidental = false,
    this.tie = TieFlag.none,
    this.noteId,
  }) {
    RangeError.checkValueInInterval(staffStep, -40, 40, 'staffStep');
  }

  final int staffStep;
  final SmuflClef clef;
  final SmuflAccidental? accidental;
  final bool showAccidental;
  final TieFlag tie;
  final String? noteId;

  SmuflAccidental? get displayedAccidental =>
      showAccidental ? accidental : null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is NotationNote &&
            other.staffStep == staffStep &&
            other.clef == clef &&
            other.accidental == accidental &&
            other.showAccidental == showAccidental &&
            other.tie == tie &&
            other.noteId == noteId);
  }

  @override
  int get hashCode =>
      Object.hash(staffStep, clef, accidental, showAccidental, tie, noteId);
}

/// One or more simultaneous notes sharing a stem/duration on one [clef].
final class NotationChord {
  NotationChord({
    required List<NotationNote> notes,
    required this.clef,
    required this.duration,
    this.dots = 0,
    this.beamGroupId,
  }) : notes = List<NotationNote>.unmodifiable(notes) {
    RangeError.checkValueInInterval(dots, 0, 2, 'dots');
    if (notes.isEmpty) {
      throw ArgumentError.value(notes, 'notes', 'must not be empty');
    }
    if (notes.any((note) => note.clef != clef)) {
      throw ArgumentError.value(
        notes,
        'notes',
        'all notes must match chord clef',
      );
    }
  }

  final List<NotationNote> notes;
  final SmuflClef clef;
  final DurationKind duration;
  final int dots;
  final String? beamGroupId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is NotationChord &&
            _listsEqual(other.notes, notes) &&
            other.clef == clef &&
            other.duration == duration &&
            other.dots == dots &&
            other.beamGroupId == beamGroupId);
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(notes), clef, duration, dots, beamGroupId);
}

/// Rest symbol on one [clef].
final class NotationRest {
  NotationRest({required this.clef, required this.duration, this.dots = 0}) {
    RangeError.checkValueInInterval(dots, 0, 2, 'dots');
  }

  final SmuflClef clef;
  final DurationKind duration;
  final int dots;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is NotationRest &&
            other.clef == clef &&
            other.duration == duration &&
            other.dots == dots);
  }

  @override
  int get hashCode => Object.hash(clef, duration, dots);
}

bool _listsEqual<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
