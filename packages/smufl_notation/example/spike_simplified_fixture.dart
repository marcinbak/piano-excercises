import 'package:smufl_notation/smufl_notation.dart';

/// 8-measure G-major simplified melody + bass fixture for `[M5]`.
NotationScore buildSimplifiedMelodyBassScore() {
  var idx = 0;
  const t = SmuflClef.treble;
  const b = SmuflClef.bass;
  NotationNote n(
    int step,
    SmuflClef clef, {
    SmuflAccidental? acc,
    TieFlag tie = TieFlag.none,
  }) => NotationNote(staffStep: step, clef: clef, accidental: acc, tie: tie);

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
    int dots = 0,
    String? beam,
  }) => NotationChord(
    notes: notes,
    clef: clef,
    duration: d,
    dots: dots,
    beamGroupId: beam,
  );

  return NotationScore(
    title: 'Simplified Melody + Bass',
    subtitle: 'G Major · 3/4 · 8 Measures',
    measures: <NotationMeasure>[
      NotationMeasure(
        measureNumber: 1,
        keyFifths: 1,
        beats: 3,
        beatType: 4,
        slices: <NotationSlice>[
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [n(2, t)]),
            bc: c(b, DurationKind.half, [n(0, b)]),
          ),
          sl(1.0, tc: c(t, DurationKind.quarter, [n(4, t)])),
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [n(6, t)]),
            bc: c(b, DurationKind.quarter, [n(4, b)]),
          ),
        ],
      ),
      NotationMeasure(
        measureNumber: 2,
        slices: <NotationSlice>[
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [n(9, t)]),
            bc: c(b, DurationKind.half, [n(2, b)], dots: 1),
          ),
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [
              n(8, t, acc: SmuflAccidental.sharp),
            ]),
          ),
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [n(7, t, tie: TieFlag.start)]),
          ),
        ],
      ),
      NotationMeasure(
        measureNumber: 3,
        slices: <NotationSlice>[
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [n(7, t, tie: TieFlag.stop)]),
            bc: c(b, DurationKind.half, [n(3, b)]),
          ),
          sl(1.0, tc: c(t, DurationKind.quarter, [n(6, t)])),
          sl(
            1.0,
            tr: NotationRest(clef: t, duration: DurationKind.quarter),
            br: NotationRest(clef: b, duration: DurationKind.quarter),
          ),
        ],
      ),
      NotationMeasure(
        measureNumber: 4,
        slices: <NotationSlice>[
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [n(5, t)]),
            bc: c(b, DurationKind.half, [n(1, b)], dots: 1),
          ),
          sl(0.5, tc: c(t, DurationKind.eighth, [n(4, t)], beam: 'm4')),
          sl(0.5, tc: c(t, DurationKind.eighth, [n(3, t)], beam: 'm4')),
          sl(1.0, tc: c(t, DurationKind.quarter, [n(2, t)])),
        ],
      ),
      NotationMeasure(
        measureNumber: 5,
        slices: <NotationSlice>[
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [n(3, t)]),
            bc: c(b, DurationKind.half, [n(4, b)]),
          ),
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [
              n(1, t, acc: SmuflAccidental.sharp),
            ]),
          ),
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [n(-1, t)]),
            bc: c(b, DurationKind.quarter, [
              n(6, b, acc: SmuflAccidental.sharp),
            ]),
          ),
        ],
      ),
      NotationMeasure(
        measureNumber: 6,
        slices: <NotationSlice>[
          sl(
            2.0,
            tc: c(t, DurationKind.half, [n(4, t)]),
            bc: c(b, DurationKind.half, [n(0, b)]),
          ),
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [n(6, t, tie: TieFlag.start)]),
            bc: c(b, DurationKind.quarter, [n(4, b)]),
          ),
        ],
      ),
      NotationMeasure(
        measureNumber: 7,
        slices: <NotationSlice>[
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [n(6, t, tie: TieFlag.stop)]),
            bc: c(b, DurationKind.half, [n(4, b)]),
          ),
          sl(1.0, tc: c(t, DurationKind.quarter, [n(5, t)])),
          sl(
            1.0,
            tc: c(t, DurationKind.quarter, [n(3, t)]),
            bc: c(b, DurationKind.quarter, [
              n(6, b, acc: SmuflAccidental.sharp),
            ]),
          ),
        ],
      ),
      NotationMeasure(
        measureNumber: 8,
        slices: <NotationSlice>[
          sl(
            3.0,
            tc: c(t, DurationKind.half, [n(2, t)], dots: 1),
            bc: c(b, DurationKind.half, [n(0, b)], dots: 1),
          ),
        ],
      ),
    ],
  );
}
