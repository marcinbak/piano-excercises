import 'package:smufl_notation/smufl_notation.dart';

/// 32-measure Eb-major dense two-hand polyphonic fixture for `[M5]`.
NotationScore buildPolyphonicGrandStaffScore() {
  var idx = 0;
  const t = SmuflClef.treble;
  const b = SmuflClef.bass;
  NotationNote n(
    int step,
    SmuflClef clef, {
    SmuflAccidental? acc,
    bool show = false,
    TieFlag tie = TieFlag.none,
  }) => NotationNote(
    staffStep: step,
    clef: clef,
    accidental: acc,
    showAccidental: show,
    tie: tie,
  );

  NotationSlice sl(
    double beats, {
    NotationChord? tc,
    NotationRest? tr,
    NotationChord? bc,
    NotationRest? br,
  }) => NotationSlice(
    sliceIndex: idx++,
    beatDuration: beats,
    trebleChord: tc,
    trebleRest: tr,
    bassChord: bc,
    bassRest: br,
  );

  NotationChord c(
    SmuflClef clef,
    DurationKind d,
    List<NotationNote> notes, {
    String? beam,
  }) => NotationChord(notes: notes, clef: clef, duration: d, beamGroupId: beam);

  final measures = <NotationMeasure>[];
  for (var m = 1; m <= 32; m += 1) {
    if (m % 4 == 0) {
      measures.add(
        NotationMeasure(
          measureNumber: m,
          slices: <NotationSlice>[
            sl(
              1.0,
              tc: c(t, DurationKind.quarter, [
                n(0, t),
                n(1, t),
                n(2, t),
                n(4, t, tie: m < 32 ? TieFlag.stop : TieFlag.none),
              ]),
              bc: c(b, DurationKind.half, [n(-2, b), n(2, b), n(5, b)]),
            ),
            sl(
              1.0,
              tc: c(t, DurationKind.quarter, [
                n(1, t, acc: SmuflAccidental.sharp, show: true),
                n(3, t, acc: SmuflAccidental.natural, show: true),
                n(6, t),
              ]),
            ),
            sl(
              1.0,
              tc: c(t, DurationKind.quarter, [
                n(0, t),
                n(2, t),
                n(4, t),
                n(7, t),
              ]),
              bc: c(b, DurationKind.quarter, [n(1, b), n(2, b), n(5, b)]),
            ),
            sl(
              1.0,
              tr: NotationRest(clef: t, duration: DurationKind.quarter),
              br: NotationRest(clef: b, duration: DurationKind.quarter),
            ),
          ],
        ),
      );
    } else if (m.isOdd) {
      measures.add(
        NotationMeasure(
          measureNumber: m,
          keyFifths: m == 1 ? -3 : null,
          beats: m == 1 ? 4 : null,
          beatType: m == 1 ? 4 : null,
          slices: <NotationSlice>[
            sl(
              1.0,
              tc: c(t, DurationKind.quarter, [
                n(0, t),
                n(2, t),
                n(4, t),
                n(7, t),
              ]),
              bc: c(b, DurationKind.half, [
                n(-2, b),
                n(2, b),
                n(5, b),
                n(7, b),
              ]),
            ),
            sl(
              0.5,
              tc: c(t, DurationKind.eighth, [n(4, t), n(6, t)], beam: 't1_$m'),
            ),
            sl(
              0.5,
              tc: c(t, DurationKind.eighth, [n(5, t), n(7, t)], beam: 't1_$m'),
            ),
            sl(
              0.5,
              tc: c(t, DurationKind.eighth, [
                n(3, t, acc: SmuflAccidental.natural, show: true),
                n(5, t),
              ], beam: 't2_$m'),
              bc: c(b, DurationKind.eighth, [
                n(1, b),
                n(2, b),
                n(5, b),
              ], beam: 'b2_$m'),
            ),
            sl(
              0.5,
              tc: c(t, DurationKind.eighth, [n(4, t), n(6, t)], beam: 't2_$m'),
              bc: c(b, DurationKind.eighth, [n(2, b), n(4, b)], beam: 'b2_$m'),
            ),
            sl(
              1.0,
              tc: c(t, DurationKind.quarter, [
                n(1, t),
                n(2, t),
                n(4, t, tie: TieFlag.start),
              ]),
              bc: c(b, DurationKind.quarter, [
                n(-1, b),
                n(2, b, acc: SmuflAccidental.natural, show: true),
                n(4, b),
              ]),
            ),
          ],
        ),
      );
    } else {
      measures.add(
        NotationMeasure(
          measureNumber: m,
          slices: <NotationSlice>[
            sl(
              1.0,
              tc: c(t, DurationKind.quarter, [
                n(2, t),
                n(4, t, tie: TieFlag.stop),
                n(6, t),
              ]),
              bc: c(b, DurationKind.quarter, [n(0, b), n(4, b), n(7, b)]),
            ),
            sl(
              0.25,
              tc: c(t, DurationKind.sixteenth, [n(5, t)], beam: 's1_$m'),
              bc: c(b, DurationKind.half, [n(3, b), n(5, b), n(7, b)]),
            ),
            sl(
              0.25,
              tc: c(t, DurationKind.sixteenth, [n(6, t)], beam: 's1_$m'),
            ),
            sl(
              0.25,
              tc: c(t, DurationKind.sixteenth, [n(7, t)], beam: 's1_$m'),
            ),
            sl(
              0.25,
              tc: c(t, DurationKind.sixteenth, [n(8, t)], beam: 's1_$m'),
            ),
            sl(
              1.0,
              tc: c(t, DurationKind.quarter, [
                n(3, t, acc: SmuflAccidental.natural, show: true),
                n(5, t),
                n(7, t),
              ]),
            ),
            sl(
              1.0,
              tc: c(t, DurationKind.quarter, [
                n(1, t),
                n(2, t),
                n(4, t, tie: TieFlag.start),
              ]),
              bc: c(b, DurationKind.quarter, [
                n(2, b),
                n(4, b),
                n(6, b, acc: SmuflAccidental.sharp, show: true),
              ]),
            ),
          ],
        ),
      );
    }
  }
  return NotationScore(
    title: 'Polyphonic Grand Staff — 32m',
    subtitle: 'Eb Major · 4/4 · 32 Measures',
    measures: measures,
  );
}
