import 'package:flutter_test/flutter_test.dart';
import 'package:smufl_notation/smufl_notation.dart';
import 'package:smufl_notation/src/layout/chord_collision_solver.dart';

NotationNote _note(
  int step, {
  SmuflClef clef = SmuflClef.treble,
  SmuflAccidental? acc,
  bool show = false,
}) => NotationNote(
  staffStep: step,
  clef: clef,
  accidental: acc,
  showAccidental: show,
);

void main() {
  group('ChordCollisionSolver stem direction', () {
    test('uses middle line step 4 as stem pivot', () {
      expect(ChordCollisionSolver.computeStemUp([_note(0)]), isTrue);
      expect(ChordCollisionSolver.computeStemUp([_note(3)]), isTrue);
      expect(ChordCollisionSolver.computeStemUp([_note(4)]), isFalse);
      expect(ChordCollisionSolver.computeStemUp([_note(5)]), isFalse);
    });

    test('resolves chord stem direction by outer extremity distance', () {
      final lowChord = [_note(0), _note(2), _note(6)];
      final highChord = [_note(2), _note(5), _note(7)];
      expect(ChordCollisionSolver.computeStemUp(lowChord), isTrue);
      expect(ChordCollisionSolver.computeStemUp(highChord), isFalse);
    });
  });

  group('ChordCollisionSolver adjacent seconds', () {
    test('shifts upper note right on up-stem seconds (E4+F4)', () {
      final chord = NotationChord(
        notes: [_note(1), _note(0)],
        clef: SmuflClef.treble,
        duration: DurationKind.quarter,
      );
      final solved = ChordCollisionSolver.solveChord(chord);
      expect(solved.stemUp, isTrue);
      expect(solved.placements[0].note.staffStep, 0);
      expect(solved.placements[0].horizontalShiftSpaces, 0.0);
      expect(solved.placements[1].note.staffStep, 1);
      expect(
        solved.placements[1].horizontalShiftSpaces,
        closeTo(SmuflGlyphs.secondShiftSpaces, 1e-6),
      );
    });

    test('alternates three-note cluster C4+D4+E4 cleanly', () {
      final chord = NotationChord(
        notes: [_note(-2), _note(-1), _note(0)],
        clef: SmuflClef.treble,
        duration: DurationKind.quarter,
      );
      final solved = ChordCollisionSolver.solveChord(chord);
      expect(solved.stemUp, isTrue);
      expect(solved.placements.map((p) => p.horizontalShiftSpaces).toList(), [
        0.0,
        SmuflGlyphs.secondShiftSpaces,
        0.0,
      ]);
    });

    test('shifts lower note left on down-stem seconds (B4+C5)', () {
      final chord = NotationChord(
        notes: [_note(4), _note(5)],
        clef: SmuflClef.treble,
        duration: DurationKind.quarter,
      );
      final solved = ChordCollisionSolver.solveChord(chord);
      expect(solved.stemUp, isFalse);
      expect(solved.hasLeftShiftedHead, isTrue);
      expect(
        solved.placements[0].horizontalShiftSpaces,
        closeTo(-SmuflGlyphs.secondShiftSpaces, 1e-6),
      );
      expect(solved.placements[1].horizontalShiftSpaces, 0.0);
    });
  });

  group('ChordCollisionSolver accidental columns', () {
    test('assigns distinct columns 0..2 for close stacked accidentals', () {
      final chord = NotationChord(
        notes: [
          _note(1, acc: SmuflAccidental.sharp, show: true),
          _note(3, acc: SmuflAccidental.sharp, show: true),
          _note(5, acc: SmuflAccidental.sharp, show: true),
        ],
        clef: SmuflClef.treble,
        duration: DurationKind.quarter,
      );
      final solved = ChordCollisionSolver.solveChord(chord);
      expect(solved.accidentalColumnCount, 3);
      expect(solved.placements.map((p) => p.accidentalColumn).toSet(), {
        0,
        1,
        2,
      });
    });

    test('reuses column 0 when accidentals are >= 6 steps apart', () {
      final chord = NotationChord(
        notes: [
          _note(1, acc: SmuflAccidental.flat, show: true),
          _note(8, acc: SmuflAccidental.flat, show: true),
        ],
        clef: SmuflClef.treble,
        duration: DurationKind.quarter,
      );
      final solved = ChordCollisionSolver.solveChord(chord);
      expect(solved.accidentalColumnCount, 1);
      expect(solved.placements.map((p) => p.accidentalColumn).toList(), [0, 0]);
    });

    test(
      'skips key-signature-implied accidentals when showAccidental is false',
      () {
        final chord = NotationChord(
          notes: [_note(8, acc: SmuflAccidental.sharp)],
          clef: SmuflClef.treble,
          duration: DurationKind.quarter,
        );
        final solved = ChordCollisionSolver.solveChord(chord);
        expect(solved.accidentalColumnCount, 0);
        expect(solved.placements.single.accidentalColumn, isNull);
      },
    );
  });
}
