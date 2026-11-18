import 'package:piano_exercises/shared/music/music.dart';

/// Ordered identifier for the four curriculum progression stages.
enum StageId {
  stage1(1),
  stage2(2),
  stage3(3),
  stage4(4);

  const StageId(this.number);

  final int number;

  StageId? get next => index + 1 < values.length ? values[index + 1] : null;

  StageId? get previous => index > 0 ? values[index - 1] : null;

  /// Resolves a 1-based stage [number] (`1..4`), throwing [RangeError] otherwise.
  static StageId fromNumber(int number) {
    RangeError.checkValueInInterval(number, 1, values.length, 'number');
    return values[number - 1];
  }
}

/// Immutable curriculum stage describing newly introduced and cumulative notes.
final class ProgressionStage {
  ProgressionStage({
    required this.id,
    required this.title,
    required this.description,
    required List<StaffNote> introducedNotes,
    required List<StaffNote> cumulativeNotes,
  }) : introducedNotes = List<StaffNote>.unmodifiable(introducedNotes),
       cumulativeNotes = List<StaffNote>.unmodifiable(cumulativeNotes);

  const ProgressionStage._({
    required this.id,
    required this.title,
    required this.description,
    required this.introducedNotes,
    required this.cumulativeNotes,
  });

  final StageId id;
  final String title;
  final String description;
  final List<StaffNote> introducedNotes;
  final List<StaffNote> cumulativeNotes;

  bool containsNote(StaffNote target) => cumulativeNotes.contains(target);

  Set<MidiNote> get distinctMidiNotes =>
      Set<MidiNote>.unmodifiable(cumulativeNotes.map((note) => note.midiNote));
}

/// Canonical grand-staff sight-reading stages covering `C2..C6`.
abstract final class ProgressionCatalog {
  static const List<StaffNote> _stage1Introduced = <StaffNote>[
    StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble),
    StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.bass),
    StaffNote(note: DiatonicNote.c, octave: 3, clef: Clef.bass),
    StaffNote(note: DiatonicNote.c, octave: 5, clef: Clef.treble),
  ];

  static const List<StaffNote> _stage2Introduced = <StaffNote>[
    StaffNote(note: DiatonicNote.c, octave: 2, clef: Clef.bass),
    StaffNote(note: DiatonicNote.c, octave: 6, clef: Clef.treble),
  ];

  static const List<StaffNote> _stage3Introduced = <StaffNote>[
    StaffNote(note: DiatonicNote.f, octave: 3, clef: Clef.bass),
    StaffNote(note: DiatonicNote.g, octave: 4, clef: Clef.treble),
  ];

  static const List<StaffNote> _stage4Introduced = <StaffNote>[
    StaffNote(note: DiatonicNote.d, octave: 2, clef: Clef.bass),
    StaffNote(note: DiatonicNote.e, octave: 2, clef: Clef.bass),
    StaffNote(note: DiatonicNote.f, octave: 2, clef: Clef.bass),
    StaffNote(note: DiatonicNote.g, octave: 2, clef: Clef.bass),
    StaffNote(note: DiatonicNote.a, octave: 2, clef: Clef.bass),
    StaffNote(note: DiatonicNote.b, octave: 2, clef: Clef.bass),
    StaffNote(note: DiatonicNote.d, octave: 3, clef: Clef.bass),
    StaffNote(note: DiatonicNote.e, octave: 3, clef: Clef.bass),
    StaffNote(note: DiatonicNote.g, octave: 3, clef: Clef.bass),
    StaffNote(note: DiatonicNote.a, octave: 3, clef: Clef.bass),
    StaffNote(note: DiatonicNote.b, octave: 3, clef: Clef.bass),
    StaffNote(note: DiatonicNote.d, octave: 4, clef: Clef.treble),
    StaffNote(note: DiatonicNote.e, octave: 4, clef: Clef.treble),
    StaffNote(note: DiatonicNote.f, octave: 4, clef: Clef.treble),
    StaffNote(note: DiatonicNote.a, octave: 4, clef: Clef.treble),
    StaffNote(note: DiatonicNote.b, octave: 4, clef: Clef.treble),
    StaffNote(note: DiatonicNote.d, octave: 5, clef: Clef.treble),
    StaffNote(note: DiatonicNote.e, octave: 5, clef: Clef.treble),
    StaffNote(note: DiatonicNote.f, octave: 5, clef: Clef.treble),
    StaffNote(note: DiatonicNote.g, octave: 5, clef: Clef.treble),
    StaffNote(note: DiatonicNote.a, octave: 5, clef: Clef.treble),
    StaffNote(note: DiatonicNote.b, octave: 5, clef: Clef.treble),
  ];

  static const List<StaffNote> _stage2Cumulative = <StaffNote>[
    ..._stage1Introduced,
    ..._stage2Introduced,
  ];

  static const List<StaffNote> _stage3Cumulative = <StaffNote>[
    ..._stage2Cumulative,
    ..._stage3Introduced,
  ];

  static const List<StaffNote> _stage4Cumulative = <StaffNote>[
    ..._stage3Cumulative,
    ..._stage4Introduced,
  ];

  static const List<ProgressionStage> stages = <ProgressionStage>[
    ProgressionStage._(
      id: StageId.stage1,
      title: 'Core Cs',
      description: 'Identify Middle C (C4) on both clefs plus octave anchors C3 (bass) and C5 (treble).',
      introducedNotes: _stage1Introduced,
      cumulativeNotes: _stage1Introduced,
    ),
    ProgressionStage._(
      id: StageId.stage2,
      title: 'All Treble & Bass Cs',
      description: 'Complete C anchors with two-ledger C2 and C6.',
      introducedNotes: _stage2Introduced,
      cumulativeNotes: _stage2Cumulative,
    ),
    ProgressionStage._(
      id: StageId.stage3,
      title: 'Base Landmark Notes',
      description: 'Add clef reference landmarks F3 (bass) and G4 (treble).',
      introducedNotes: _stage3Introduced,
      cumulativeNotes: _stage3Cumulative,
    ),
    ProgressionStage._(
      id: StageId.stage4,
      title: 'All Natural Notes',
      description:
          'Practice all remaining natural notes across C2..C6 (max 2 ledgers).',
      introducedNotes: _stage4Introduced,
      cumulativeNotes: _stage4Cumulative,
    ),
  ];

  static ProgressionStage byId(StageId id) => stages[id.index];
}
