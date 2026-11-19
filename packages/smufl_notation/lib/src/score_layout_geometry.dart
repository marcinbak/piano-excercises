import 'package:flutter/painting.dart';
import 'package:smufl_notation/src/notation_model.dart';

/// Visual styling and spacing metrics for engraving and painting a grand staff.
final class ScoreStyle {
  const ScoreStyle({
    this.staffSpace = 9.0,
    this.systemGap = 44.0,
    this.trebleToBassGapSpaces = 6.0,
    this.inkColor = const Color(0xFF1A1C1E),
    this.staffLineColor = const Color(0xFF5C6470),
    this.cursorColor = const Color(0x241E64D8),
    this.errorColor = const Color(0xFFD32F2F),
    this.dimmedOpacity = 0.28,
    this.fontFamily = 'Bravura',
    this.fontPackage,
  });

  final double staffSpace;
  final double systemGap;
  final double trebleToBassGapSpaces;
  final Color inkColor;
  final Color staffLineColor;
  final Color cursorColor;
  final Color errorColor;
  final double dimmedOpacity;
  final String fontFamily;
  final String? fontPackage;

  double get fontSize => staffSpace * 4.0;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScoreStyle &&
            other.staffSpace == staffSpace &&
            other.systemGap == systemGap &&
            other.trebleToBassGapSpaces == trebleToBassGapSpaces &&
            other.inkColor == inkColor &&
            other.staffLineColor == staffLineColor &&
            other.cursorColor == cursorColor &&
            other.errorColor == errorColor &&
            other.dimmedOpacity == dimmedOpacity &&
            other.fontFamily == fontFamily &&
            other.fontPackage == fontPackage);
  }

  @override
  int get hashCode => Object.hash(
    staffSpace,
    systemGap,
    trebleToBassGapSpaces,
    inkColor,
    staffLineColor,
    cursorColor,
    errorColor,
    dimmedOpacity,
    fontFamily,
    fontPackage,
  );
}

/// Engraved notehead coordinates and optional augmentation dot.
final class PlacedNotehead {
  const PlacedNotehead({
    required this.note,
    required this.centerX,
    required this.centerY,
    required this.glyph,
    required this.dots,
    required this.ledgerSteps,
    this.dotStartX,
    this.dotY,
  });

  final NotationNote note;
  final double centerX;
  final double centerY;
  final String glyph;
  final int dots;
  final List<int> ledgerSteps;
  final double? dotStartX;
  final double? dotY;
}

/// Engraved accidental glyph placement (key signature or inline).
final class PlacedAccidental {
  const PlacedAccidental({
    required this.accidental,
    required this.clef,
    required this.centerX,
    required this.centerY,
    required this.glyph,
  });

  final SmuflAccidental accidental;
  final SmuflClef clef;
  final double centerX;
  final double centerY;
  final String glyph;
}

/// Engraved chord geometry with solved stem and accidental coordinates.
final class PlacedChord {
  const PlacedChord({
    required this.clef,
    required this.noteheads,
    required this.accidentals,
    required this.stemUp,
    required this.flagCount,
    this.stemX,
    this.stemStartY,
    this.stemEndY,
    this.beamGroupId,
  });

  final SmuflClef clef;
  final List<PlacedNotehead> noteheads;
  final List<PlacedAccidental> accidentals;
  final bool stemUp;
  final int flagCount;
  final double? stemX;
  final double? stemStartY;
  final double? stemEndY;
  final String? beamGroupId;
}

/// Engraved rest symbol placement.
final class PlacedRest {
  const PlacedRest({
    required this.clef,
    required this.centerX,
    required this.anchorY,
    required this.glyph,
    required this.dots,
    this.dotStartX,
    this.dotY,
  });

  final SmuflClef clef;
  final double centerX;
  final double anchorY;
  final String glyph;
  final int dots;
  final double? dotStartX;
  final double? dotY;
}

/// Chord endpoint inside a [PlacedBeamGroup].
final class PlacedBeamChord {
  const PlacedBeamChord({
    required this.stemX,
    required this.stemTipY,
    required this.beamCount,
  });

  final double stemX;
  final double stemTipY;
  final int beamCount;
}

/// Consecutive beamed 8th/16th chords sharing a unified beam slant.
final class PlacedBeamGroup {
  const PlacedBeamGroup({
    required this.clef,
    required this.stemUp,
    required this.chords,
  });

  final SmuflClef clef;
  final bool stemUp;
  final List<PlacedBeamChord> chords;
}

/// Cubic/quadratic tie curve spanning two noteheads or a system boundary.
final class PlacedTieArc {
  const PlacedTieArc({
    required this.clef,
    required this.startX,
    required this.endX,
    required this.y,
    required this.curveUp,
  });

  final SmuflClef clef;
  final double startX;
  final double endX;
  final double y;
  final bool curveUp;
}
