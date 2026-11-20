import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:piano_exercises/shared/notation/notation.dart'
    as shared_notation;
import 'package:smufl_notation/smufl_notation.dart';

/// Piece-practice facade over [shared_notation.ScoreNotationMapper] with [mapHandMode].
abstract final class ScoreNotationMapper {
  /// Maps a domain [Score] into an engravable [NotationScore].
  static NotationScore mapScore(Score score) =>
      shared_notation.ScoreNotationMapper.mapScore(score);

  /// Maps a domain [HandMode] to [NotationHandFilter].
  static NotationHandFilter mapHandMode(HandMode mode) => switch (mode) {
    HandMode.both => NotationHandFilter.both,
    HandMode.right => NotationHandFilter.right,
    HandMode.left => NotationHandFilter.left,
  };

  /// Maps wrong played [StaffNote]s into a key-aware [WrongNoteOverlay].
  static WrongNoteOverlay mapWrongNotes({
    required int sliceIndex,
    required SmuflClef clef,
    required List<StaffNote> wrongNotes,
    required KeySignature activeKeySignature,
  }) => shared_notation.ScoreNotationMapper.mapWrongNotes(
    sliceIndex: sliceIndex,
    clef: clef,
    wrongNotes: wrongNotes,
    activeKeySignature: activeKeySignature,
  );

  /// Maps wrong played [StaffNote]s into non-empty clef-grouped overlays.
  static List<WrongNoteOverlay> mapWrongNoteOverlays({
    required int sliceIndex,
    required List<StaffNote> wrongNotes,
    required KeySignature activeKeySignature,
  }) => shared_notation.ScoreNotationMapper.mapWrongNoteOverlays(
    sliceIndex: sliceIndex,
    wrongNotes: wrongNotes,
    activeKeySignature: activeKeySignature,
  );

  /// Resolves the active [KeySignature] at chronological [sliceIndex].
  static KeySignature activeKeySignatureAtSlice(Score score, int sliceIndex) =>
      shared_notation.ScoreNotationMapper.activeKeySignatureAtSlice(
        score,
        sliceIndex,
      );
}
