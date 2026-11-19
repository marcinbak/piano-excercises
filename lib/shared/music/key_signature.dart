import 'package:piano_exercises/shared/music/pitch_class.dart';

/// Major/minor key signature identified by circle-of-fifths offset (`-7..+7`).
final class KeySignature {
  const KeySignature(this.fifths) : assert(fifths >= -7 && fifths <= 7);

  /// Creates a [KeySignature] after validating [fifths] is in `-7..7`.
  factory KeySignature.validated(int fifths) {
    RangeError.checkValueInInterval(fifths, -7, 7, 'fifths');
    return KeySignature(fifths);
  }

  static const KeySignature cMajor = KeySignature(0);

  static const List<DiatonicNote> sharpOrder = <DiatonicNote>[
    DiatonicNote.f,
    DiatonicNote.c,
    DiatonicNote.g,
    DiatonicNote.d,
    DiatonicNote.a,
    DiatonicNote.e,
    DiatonicNote.b,
  ];

  static const List<DiatonicNote> flatOrder = <DiatonicNote>[
    DiatonicNote.b,
    DiatonicNote.e,
    DiatonicNote.a,
    DiatonicNote.d,
    DiatonicNote.g,
    DiatonicNote.c,
    DiatonicNote.f,
  ];

  final int fifths;

  /// Diatonic steps altered by this key signature in engraving order.
  List<DiatonicNote> get alteredNotes {
    if (fifths == 0) {
      return const <DiatonicNote>[];
    }
    if (fifths > 0) {
      return List<DiatonicNote>.unmodifiable(sharpOrder.take(fifths));
    }
    return List<DiatonicNote>.unmodifiable(flatOrder.take(-fifths));
  }

  /// Key-signature-implied accidental for natural letter [note].
  Accidental defaultAccidentalFor(DiatonicNote note) {
    if (fifths > 0) {
      for (var i = 0; i < fifths; i += 1) {
        if (sharpOrder[i] == note) {
          return Accidental.sharp;
        }
      }
    } else if (fifths < 0) {
      for (var i = 0; i < -fifths; i += 1) {
        if (flatOrder[i] == note) {
          return Accidental.flat;
        }
      }
    }
    return Accidental.natural;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is KeySignature && other.fifths == fifths);
  }

  @override
  int get hashCode => fifths.hashCode;
}

/// Diatonic scale mode supported for score display and key metadata.
enum ScaleMode {
  major('Major'),
  minor('Minor');

  const ScaleMode(this.label);

  final String label;
}

/// Diatonic scale pairing a spelled tonic with a [ScaleMode] and [KeySignature].
final class Scale {
  const Scale({
    required this.tonic,
    this.tonicAccidental = Accidental.natural,
    required this.mode,
    required this.keySignature,
  });

  /// Maps [keySignature] (`-7..+7`) and [mode] to its standard enharmonic tonic.
  factory Scale.fromKeySignature(
    KeySignature keySignature, {
    ScaleMode mode = ScaleMode.major,
  }) {
    final index = keySignature.fifths + 7;
    final (tonic, accidental) = switch (mode) {
      ScaleMode.major => _majorTonics[index],
      ScaleMode.minor => _minorTonics[index],
    };
    return Scale(
      tonic: tonic,
      tonicAccidental: accidental,
      mode: mode,
      keySignature: keySignature,
    );
  }

  static const List<(DiatonicNote, Accidental)> _majorTonics =
      <(DiatonicNote, Accidental)>[
        (DiatonicNote.c, Accidental.flat), // -7: Cb
        (DiatonicNote.g, Accidental.flat), // -6: Gb
        (DiatonicNote.d, Accidental.flat), // -5: Db
        (DiatonicNote.a, Accidental.flat), // -4: Ab
        (DiatonicNote.e, Accidental.flat), // -3: Eb
        (DiatonicNote.b, Accidental.flat), // -2: Bb
        (DiatonicNote.f, Accidental.natural), // -1: F
        (DiatonicNote.c, Accidental.natural), // 0: C
        (DiatonicNote.g, Accidental.natural), // +1: G
        (DiatonicNote.d, Accidental.natural), // +2: D
        (DiatonicNote.a, Accidental.natural), // +3: A
        (DiatonicNote.e, Accidental.natural), // +4: E
        (DiatonicNote.b, Accidental.natural), // +5: B
        (DiatonicNote.f, Accidental.sharp), // +6: F#
        (DiatonicNote.c, Accidental.sharp), // +7: C#
      ];

  static const List<(DiatonicNote, Accidental)> _minorTonics =
      <(DiatonicNote, Accidental)>[
        (DiatonicNote.a, Accidental.flat), // -7: Ab
        (DiatonicNote.e, Accidental.flat), // -6: Eb
        (DiatonicNote.b, Accidental.flat), // -5: Bb
        (DiatonicNote.f, Accidental.natural), // -4: F
        (DiatonicNote.c, Accidental.natural), // -3: C
        (DiatonicNote.g, Accidental.natural), // -2: G
        (DiatonicNote.d, Accidental.natural), // -1: D
        (DiatonicNote.a, Accidental.natural), // 0: A
        (DiatonicNote.e, Accidental.natural), // +1: E
        (DiatonicNote.b, Accidental.natural), // +2: B
        (DiatonicNote.f, Accidental.sharp), // +3: F#
        (DiatonicNote.c, Accidental.sharp), // +4: C#
        (DiatonicNote.g, Accidental.sharp), // +5: G#
        (DiatonicNote.d, Accidental.sharp), // +6: D#
        (DiatonicNote.a, Accidental.sharp), // +7: A#
      ];

  final DiatonicNote tonic;
  final Accidental tonicAccidental;
  final ScaleMode mode;
  final KeySignature keySignature;

  String get label => '${tonic.letter}${tonicAccidental.symbol} ${mode.label}';

  /// Seven diatonic scale degrees rotated from [tonic] with key-signature defaults.
  List<(DiatonicNote, Accidental)> get degreeSpellings {
    const notes = DiatonicNote.values;
    return List<(DiatonicNote, Accidental)>.unmodifiable(
      List<(DiatonicNote, Accidental)>.generate(notes.length, (i) {
        final step = notes[(tonic.index + i) % notes.length];
        return (step, keySignature.defaultAccidentalFor(step));
      }),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Scale &&
            other.tonic == tonic &&
            other.tonicAccidental == tonicAccidental &&
            other.mode == mode &&
            other.keySignature == keySignature);
  }

  @override
  int get hashCode => Object.hash(tonic, tonicAccidental, mode, keySignature);
}
