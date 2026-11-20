import 'package:piano_exercises/shared/music/music.dart';
import 'package:smufl_notation/smufl_notation.dart';

/// Translates domain [Score] timelines and [StaffNote]s into SMuFL notation models.
abstract final class ScoreNotationMapper {
  /// Maps a domain [Score] into an engravable [NotationScore].
  static NotationScore mapScore(Score score) {
    final measures = <NotationMeasure>[];
    for (var i = 0; i < score.measures.length; i += 1) {
      final measure = score.measures[i];
      final timeSig = i == 0
          ? (measure.timeSignature ?? score.timeSignature)
          : measure.timeSignature;
      final keyFifths = i == 0
          ? (measure.keySignature ?? score.scale.keySignature).fifths
          : measure.keySignature?.fifths;
      measures.add(
        NotationMeasure(
          measureNumber: measure.measureNumber >= 0 ? measure.measureNumber : 0,
          keyFifths: keyFifths,
          beats: timeSig?.beats,
          beatType: timeSig?.beatType,
          slices: <NotationSlice>[
            for (final slice in measure.slices) _mapSlice(slice),
          ],
        ),
      );
    }
    return NotationScore(
      title: score.title,
      subtitle: score.artist,
      measures: measures,
    );
  }

  /// Maps wrong played [StaffNote]s into a key-aware [WrongNoteOverlay].
  static WrongNoteOverlay mapWrongNotes({
    required int sliceIndex,
    required SmuflClef clef,
    required List<StaffNote> wrongNotes,
    required KeySignature activeKeySignature,
  }) {
    final musicClef = clef == SmuflClef.treble ? Clef.treble : Clef.bass;
    final mapped = <NotationNote>[
      for (final staffNote in wrongNotes)
        _mapWrongNote(
          staffNote: staffNote,
          targetClef: clef,
          musicClef: musicClef,
          activeKeySignature: activeKeySignature,
        ),
    ]..sort((a, b) => a.staffStep.compareTo(b.staffStep));
    return WrongNoteOverlay(sliceIndex: sliceIndex, notes: mapped);
  }

  /// Maps wrong played [StaffNote]s into non-empty clef-grouped overlays.
  static List<WrongNoteOverlay> mapWrongNoteOverlays({
    required int sliceIndex,
    required List<StaffNote> wrongNotes,
    required KeySignature activeKeySignature,
  }) {
    if (wrongNotes.isEmpty) {
      return const <WrongNoteOverlay>[];
    }
    final trebleNotes = <StaffNote>[];
    final bassNotes = <StaffNote>[];
    for (final note in wrongNotes) {
      if (note.clef == Clef.treble) {
        trebleNotes.add(note);
      } else {
        bassNotes.add(note);
      }
    }
    return List<WrongNoteOverlay>.unmodifiable(<WrongNoteOverlay>[
      if (trebleNotes.isNotEmpty)
        mapWrongNotes(
          sliceIndex: sliceIndex,
          clef: SmuflClef.treble,
          wrongNotes: trebleNotes,
          activeKeySignature: activeKeySignature,
        ),
      if (bassNotes.isNotEmpty)
        mapWrongNotes(
          sliceIndex: sliceIndex,
          clef: SmuflClef.bass,
          wrongNotes: bassNotes,
          activeKeySignature: activeKeySignature,
        ),
    ]);
  }

  /// Resolves the active [KeySignature] at chronological [sliceIndex].
  static KeySignature activeKeySignatureAtSlice(Score score, int sliceIndex) {
    var activeKey = score.scale.keySignature;
    for (final measure in score.measures) {
      if (measure.keySignature != null) {
        activeKey = measure.keySignature!;
      }
      if (measure.slices.any((slice) => slice.sliceIndex == sliceIndex)) {
        return activeKey;
      }
    }
    return activeKey;
  }

  static NotationNote _mapWrongNote({
    required StaffNote staffNote,
    required SmuflClef targetClef,
    required Clef musicClef,
    required KeySignature activeKeySignature,
  }) {
    final pos = StaffPosition.forDiatonicStep(
      clef: musicClef,
      diatonicStep: staffNote.diatonicStep,
    );
    final implied = activeKeySignature.defaultAccidentalFor(staffNote.note);
    final showAccidental = staffNote.accidental != implied;
    return NotationNote(
      staffStep: pos.stepsFromBottomLine,
      clef: targetClef,
      accidental: showAccidental ? _mapAccidental(staffNote.accidental) : null,
      showAccidental: showAccidental,
    );
  }

  static NotationSlice _mapSlice(ScoreSlice slice) {
    final trebleChord = _mapChord(slice.trebleNotes, SmuflClef.treble);
    final bassChord = _mapChord(slice.bassNotes, SmuflClef.bass);
    return NotationSlice(
      sliceIndex: slice.sliceIndex,
      beatDuration: slice.beatDuration.toDouble,
      trebleChord: trebleChord,
      trebleRest: trebleChord == null
          ? _mapRest(slice.trebleRest, SmuflClef.treble)
          : null,
      bassChord: bassChord,
      bassRest: bassChord == null
          ? _mapRest(slice.bassRest, SmuflClef.bass)
          : null,
    );
  }

  static NotationChord? _mapChord(List<ScoreNote> notes, SmuflClef clef) {
    if (notes.isEmpty) {
      return null;
    }
    var shortest = notes.first;
    for (final note in notes.skip(1)) {
      if (note.duration.quarterBeats < shortest.duration.quarterBeats) {
        shortest = note;
      }
    }
    final chordDuration = _mapDuration(shortest.duration.base);
    final mappedNotes = <NotationNote>[
      for (final note in notes)
        NotationNote(
          staffStep: note.staffNote.staffPosition.stepsFromBottomLine,
          clef: clef,
          accidental: note.showAccidental
              ? _mapAccidental(note.staffNote.accidental)
              : null,
          showAccidental: note.showAccidental,
          tie: _mapTie(note.tie),
          noteId: '${clef.name}_${note.midiNote.number}',
          noteheadDuration: _noteheadOverride(note, chordDuration),
        ),
    ]..sort((a, b) => a.staffStep.compareTo(b.staffStep));

    return NotationChord(
      notes: mappedNotes,
      clef: clef,
      duration: chordDuration,
      dots: shortest.duration.dots,
      beamGroupId: _resolveBeamGroupId(notes, chordDuration),
    );
  }

  static DurationKind? _noteheadOverride(
    ScoreNote note,
    DurationKind chordDuration,
  ) {
    final baseKind = _mapDuration(note.duration.base);
    return baseKind == chordDuration ? null : baseKind;
  }

  static String? _resolveBeamGroupId(
    List<ScoreNote> notes,
    DurationKind chordDuration,
  ) {
    final beamIds = <String>{};
    final voicesWithBeam = <int>{};
    final voicesAtChordDuration = <int>{};
    for (final note in notes) {
      if (_mapDuration(note.duration.base) == chordDuration) {
        voicesAtChordDuration.add(note.voice);
      }
      final id = note.beamGroupId;
      if (id != null) {
        beamIds.add(id);
        voicesWithBeam.add(note.voice);
      }
    }
    if (beamIds.length != 1) {
      return null;
    }
    // Reject mixed voices where another voice at the same beamed duration has no beam.
    for (final voice in voicesAtChordDuration) {
      if (!voicesWithBeam.contains(voice)) {
        return null;
      }
    }
    return beamIds.single;
  }

  static NotationRest? _mapRest(RestEvent? rest, SmuflClef clef) {
    if (rest == null) {
      return null;
    }
    return NotationRest(
      clef: clef,
      duration: _mapDuration(rest.duration.base),
      dots: rest.duration.dots,
    );
  }

  static DurationKind _mapDuration(NoteBaseDuration base) => switch (base) {
    NoteBaseDuration.whole => DurationKind.whole,
    NoteBaseDuration.half => DurationKind.half,
    NoteBaseDuration.quarter => DurationKind.quarter,
    NoteBaseDuration.eighth => DurationKind.eighth,
    NoteBaseDuration.sixteenth => DurationKind.sixteenth,
    NoteBaseDuration.thirtySecond => DurationKind.thirtySecond,
    NoteBaseDuration.sixtyFourth => DurationKind.sixtyFourth,
  };

  static SmuflAccidental _mapAccidental(Accidental acc) => switch (acc) {
    Accidental.doubleFlat => SmuflAccidental.doubleFlat,
    Accidental.flat => SmuflAccidental.flat,
    Accidental.natural => SmuflAccidental.natural,
    Accidental.sharp => SmuflAccidental.sharp,
    Accidental.doubleSharp => SmuflAccidental.doubleSharp,
  };

  static TieFlag _mapTie(TieType tie) => switch (tie) {
    TieType.none => TieFlag.none,
    TieType.start => TieFlag.start,
    TieType.stop => TieFlag.stop,
    TieType.continueTie => TieFlag.continueTie,
  };
}
