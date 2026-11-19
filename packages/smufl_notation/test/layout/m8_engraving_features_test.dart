import 'package:flutter_test/flutter_test.dart';
import 'package:smufl_notation/smufl_notation.dart';
import 'package:smufl_notation/src/layout/chord_collision_solver.dart';

NotationNote _note(
  int step, {
  SmuflClef clef = SmuflClef.treble,
  SmuflAccidental? acc,
  bool show = false,
  TieFlag tie = TieFlag.none,
  String? noteId,
  DurationKind? noteheadDuration,
}) => NotationNote(
  staffStep: step,
  clef: clef,
  accidental: acc,
  showAccidental: show,
  tie: tie,
  noteId: noteId,
  noteheadDuration: noteheadDuration,
);

void main() {
  group('32nd and 64th durations, pickup bars, and extreme steps', () {
    test('supports 32nd/64th glyphs, stem extension, and beam clearance', () {
      expect(DurationKind.thirtySecond.beamCount, 3);
      expect(DurationKind.thirtySecond.restGlyph, SmuflGlyphs.rest32nd);
      expect(DurationKind.sixtyFourth.beamCount, 4);
      expect(DurationKind.sixtyFourth.restGlyph, SmuflGlyphs.rest64th);

      final sixteenth = NotationChord(
        notes: [_note(2)],
        clef: SmuflClef.treble,
        duration: DurationKind.sixteenth,
      );
      final thirtySecond = NotationChord(
        notes: [_note(2)],
        clef: SmuflClef.treble,
        duration: DurationKind.thirtySecond,
      );
      final sixtyFourth = NotationChord(
        notes: [_note(2)],
        clef: SmuflClef.treble,
        duration: DurationKind.sixtyFourth,
      );
      final s16 = ChordCollisionSolver.solveChord(sixteenth);
      final s32 = ChordCollisionSolver.solveChord(thirtySecond);
      final s64 = ChordCollisionSolver.solveChord(sixtyFourth);
      expect(s32.stemTipStep, greaterThan(s16.stemTipStep));
      expect(s64.stemTipStep, greaterThan(s32.stemTipStep));

      final score = NotationScore(
        title: 'Beamed 64ths',
        measures: [
          NotationMeasure(
            measureNumber: 1,
            slices: [
              NotationSlice(
                sliceIndex: 0,
                beatDuration: 0.0625,
                trebleChord: NotationChord(
                  notes: [_note(2)],
                  clef: SmuflClef.treble,
                  duration: DurationKind.sixtyFourth,
                  beamGroupId: 'b64',
                ),
              ),
              NotationSlice(
                sliceIndex: 1,
                beatDuration: 0.0625,
                trebleChord: NotationChord(
                  notes: [_note(4)],
                  clef: SmuflClef.treble,
                  duration: DurationKind.sixtyFourth,
                  beamGroupId: 'b64',
                ),
              ),
            ],
          ),
        ],
      );
      final layout = ScoreLayoutEngine.layout(
        score: score,
        availableWidth: 420,
      );
      final m = layout.systems.single.measures.single;
      final group = m.beamGroups.single;
      expect(group.chords.map((c) => c.beamCount), [4, 4]);
      final c1 = m.slices[1].trebleChord!;
      final clearance = (c1.noteheads.first.centerY - c1.stemEndY!).abs();
      expect(clearance, greaterThanOrEqualTo(4.2 * layout.style.staffSpace));
    });

    test('allows pickup measureNumber 0 and extreme -60..60 staff steps', () {
      expect(
        () => NotationMeasure(measureNumber: -1, slices: []),
        throwsRangeError,
      );
      expect(() => _note(-61), throwsRangeError);
      expect(() => _note(61), throwsRangeError);

      final extreme = _note(49, clef: SmuflClef.bass);
      expect(ScoreLayoutEngine.ledgerStepsFor(49), hasLength(8));

      final score = NotationScore(
        title: 'Pickup & Extreme',
        measures: [
          NotationMeasure(
            measureNumber: 0,
            beats: 4,
            beatType: 4,
            slices: [
              NotationSlice(
                sliceIndex: 0,
                beatDuration: 1.0,
                bassChord: NotationChord(
                  notes: [extreme],
                  clef: SmuflClef.bass,
                  duration: DurationKind.quarter,
                ),
              ),
            ],
          ),
        ],
      );
      final layout = ScoreLayoutEngine.layout(
        score: score,
        availableWidth: 420,
      );
      expect(layout.systems.single.measures.single.measureNumber, 0);
      expect(
        layout
            .systems
            .single
            .measures
            .single
            .slices
            .single
            .bassChord!
            .noteheads
            .single
            .ledgerSteps,
        hasLength(8),
      );
    });

    test('places per-note noteheadDuration glyph in mixed-voice chords', () {
      final score = NotationScore(
        title: 'Mixed Voice',
        measures: [
          NotationMeasure(
            measureNumber: 1,
            slices: [
              NotationSlice(
                sliceIndex: 0,
                beatDuration: 0.5,
                trebleChord: NotationChord(
                  notes: [
                    _note(2),
                    _note(6, noteheadDuration: DurationKind.half),
                  ],
                  clef: SmuflClef.treble,
                  duration: DurationKind.eighth,
                ),
              ),
            ],
          ),
        ],
      );
      final heads = ScoreLayoutEngine.layout(
        score: score,
        availableWidth: 420,
      ).systems.single.measures.single.slices.single.trebleChord!.noteheads;
      expect(heads[0].glyph, SmuflGlyphs.noteheadBlack);
      expect(heads[1].glyph, SmuflGlyphs.noteheadHalf);
    });
  });

  group('Key cancellation, centered whole rests, and ties', () {
    test(
      'places cancellation naturals when modulating mid-score to fifths == 0',
      () {
        final score = NotationScore(
          title: 'Modulation',
          measures: [
            NotationMeasure(
              measureNumber: 1,
              keyFifths: -3,
              beats: 4,
              beatType: 4,
              slices: [
                NotationSlice(
                  sliceIndex: 0,
                  beatDuration: 4.0,
                  trebleRest: NotationRest(
                    clef: SmuflClef.treble,
                    duration: DurationKind.whole,
                  ),
                  bassRest: NotationRest(
                    clef: SmuflClef.bass,
                    duration: DurationKind.whole,
                  ),
                ),
              ],
            ),
            NotationMeasure(
              measureNumber: 2,
              keyFifths: 0,
              slices: [
                NotationSlice(
                  sliceIndex: 1,
                  beatDuration: 4.0,
                  trebleChord: NotationChord(
                    notes: [_note(2)],
                    clef: SmuflClef.treble,
                    duration: DurationKind.whole,
                  ),
                ),
              ],
            ),
            NotationMeasure(
              measureNumber: 3,
              slices: [
                NotationSlice(
                  sliceIndex: 2,
                  beatDuration: 4.0,
                  trebleChord: NotationChord(
                    notes: [_note(4)],
                    clef: SmuflClef.treble,
                    duration: DurationKind.whole,
                  ),
                ),
              ],
            ),
          ],
        );
        final layout = ScoreLayoutEngine.layout(
          score: score,
          availableWidth: 800,
        );
        final m2 = layout.systems.single.measures[1];
        expect(m2.showKeySignature, isTrue);
        expect(m2.keyAccidentals, hasLength(6));
        expect(
          m2.keyAccidentals.every(
            (a) => a.accidental == SmuflAccidental.natural,
          ),
          isTrue,
        );
        expect(
          m2.slices.single.cursorRect.left,
          greaterThan(m2.keyAccidentals.last.centerX),
        );

        final m3 = layout.systems.single.measures[2];
        expect(m3.showKeySignature, isFalse);
        expect(m3.keyAccidentals, isEmpty);
      },
    );

    test('centers whole-measure rests horizontally in measure body', () {
      final score = NotationScore(
        title: 'Centered Rests',
        measures: [
          NotationMeasure(
            measureNumber: 1,
            beats: 4,
            beatType: 4,
            slices: [
              NotationSlice(
                sliceIndex: 0,
                beatDuration: 4.0,
                trebleRest: NotationRest(
                  clef: SmuflClef.treble,
                  duration: DurationKind.whole,
                ),
                bassRest: NotationRest(
                  clef: SmuflClef.bass,
                  duration: DurationKind.whole,
                ),
              ),
            ],
          ),
          NotationMeasure(
            measureNumber: 2,
            slices: [
              NotationSlice(
                sliceIndex: 1,
                beatDuration: 2.0,
                trebleChord: NotationChord(
                  notes: [_note(2)],
                  clef: SmuflClef.treble,
                  duration: DurationKind.half,
                ),
                bassRest: NotationRest(
                  clef: SmuflClef.bass,
                  duration: DurationKind.whole,
                ),
              ),
              NotationSlice(
                sliceIndex: 2,
                beatDuration: 2.0,
                trebleChord: NotationChord(
                  notes: [_note(4)],
                  clef: SmuflClef.treble,
                  duration: DurationKind.half,
                ),
              ),
            ],
          ),
        ],
      );
      final measures = ScoreLayoutEngine.layout(
        score: score,
        availableWidth: 700,
      ).systems.single.measures;
      final m1 = measures[0];
      final m1Mid = (m1.slices.single.cursorRect.left + m1.rightX) * 0.5;
      expect(m1.slices.single.trebleRest!.centerX, closeTo(m1Mid, 1e-6));
      expect(m1.slices.single.bassRest!.centerX, closeTo(m1Mid, 1e-6));

      final m2 = measures[1];
      final m2BodyStart = m2.slices.first.cursorRect.left;
      final m2Mid = (m2BodyStart + m2.rightX) * 0.5;
      expect(m2.slices.first.bassRest!.centerX, closeTo(m2Mid, 1e-6));
    });

    test(
      'keys ties by measure ordinal index across duplicate measureNumbers',
      () {
        final score = NotationScore(
          title: 'Duplicate measureNumber',
          measures: [
            NotationMeasure(
              measureNumber: 1,
              slices: [
                NotationSlice(
                  sliceIndex: 0,
                  beatDuration: 2.0,
                  trebleChord: NotationChord(
                    notes: [_note(2, tie: TieFlag.start, noteId: 'c1')],
                    clef: SmuflClef.treble,
                    duration: DurationKind.half,
                  ),
                ),
                NotationSlice(
                  sliceIndex: 1,
                  beatDuration: 2.0,
                  trebleChord: NotationChord(
                    notes: [_note(2, tie: TieFlag.stop, noteId: 'c1')],
                    clef: SmuflClef.treble,
                    duration: DurationKind.half,
                  ),
                ),
              ],
            ),
            NotationMeasure(
              measureNumber: 1,
              slices: [
                NotationSlice(
                  sliceIndex: 2,
                  beatDuration: 2.0,
                  trebleChord: NotationChord(
                    notes: [_note(4, tie: TieFlag.start, noteId: 'c2')],
                    clef: SmuflClef.treble,
                    duration: DurationKind.half,
                  ),
                ),
                NotationSlice(
                  sliceIndex: 3,
                  beatDuration: 2.0,
                  trebleChord: NotationChord(
                    notes: [_note(4, tie: TieFlag.stop, noteId: 'c2')],
                    clef: SmuflClef.treble,
                    duration: DurationKind.half,
                  ),
                ),
              ],
            ),
          ],
        );
        final measures = ScoreLayoutEngine.layout(
          score: score,
          availableWidth: 700,
        ).systems.single.measures;
        expect(measures[0].tieArcs, hasLength(1));
        expect(measures[1].tieArcs, hasLength(1));
      },
    );

    test('curves multi-note chord ties outward and places cross-system half-ties after header', () {
      final score = NotationScore(
        title: 'Chord & System Ties',
        measures: [
          for (var i = 0; i < 4; i += 1)
            NotationMeasure(
              measureNumber: i + 1,
              keyFifths: i == 0 ? 3 : null,
              beats: i == 0 ? 4 : null,
              beatType: i == 0 ? 4 : null,
              slices: [
                NotationSlice(
                  sliceIndex: i * 2,
                  beatDuration: 2.0,
                  trebleChord: NotationChord(
                    notes: [
                      _note(
                        0,
                        tie: i == 0 ? TieFlag.start : TieFlag.stop,
                        noteId: 'n0',
                      ),
                      _note(
                        2,
                        tie: i == 0 ? TieFlag.start : TieFlag.stop,
                        noteId: 'n2',
                      ),
                      _note(
                        4,
                        tie: i == 0 ? TieFlag.start : TieFlag.stop,
                        noteId: 'n4',
                      ),
                    ],
                    clef: SmuflClef.treble,
                    duration: DurationKind.half,
                  ),
                ),
                NotationSlice(
                  sliceIndex: (i * 2) + 1,
                  beatDuration: 2.0,
                  trebleChord: NotationChord(
                    notes: [
                      _note(
                        0,
                        tie: i == 3 ? TieFlag.none : TieFlag.start,
                        noteId: 'n0',
                      ),
                      _note(
                        2,
                        tie: i == 3 ? TieFlag.none : TieFlag.start,
                        noteId: 'n2',
                      ),
                      _note(
                        4,
                        tie: i == 3 ? TieFlag.none : TieFlag.start,
                        noteId: 'n4',
                      ),
                    ],
                    clef: SmuflClef.treble,
                    duration: DurationKind.half,
                  ),
                ),
              ],
            ),
        ],
      );
      final layout = ScoreLayoutEngine.layout(
        score: score,
        availableWidth: 280,
      );
      expect(layout.systems.length, greaterThan(1));

      final m0Arcs = layout.systems.first.measures.first.tieArcs;
      expect(m0Arcs, hasLength(3));
      expect(m0Arcs[0].curveUp, isFalse);
      expect(m0Arcs[2].curveUp, isTrue);

      final secondSysFirstMeasure = layout.systems[1].measures.first;
      expect(secondSysFirstMeasure.tieArcs, isNotEmpty);
      final firstBodyLeft = secondSysFirstMeasure.slices.first.cursorRect.left;
      for (final arc in secondSysFirstMeasure.tieArcs.take(3)) {
        expect(arc.startX, greaterThanOrEqualTo(firstBodyLeft));
      }
    });
  });
}
