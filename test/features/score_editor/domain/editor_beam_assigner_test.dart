import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/score_editor/domain/editor_beam_assigner.dart';
import 'package:piano_exercises/shared/music/music.dart';

NoteTimelineInput _note(
  Clef clef,
  RationalBeats offset,
  NoteBaseDuration base, {
  int voice = 1,
}) {
  return NoteTimelineInput(
    clef: clef,
    diatonicNote: DiatonicNote.c,
    octave: clef == Clef.treble ? 4 : 3,
    beatOffset: offset,
    duration: DurationValue(base: base),
    voice: voice,
  );
}

void main() {
  group('EditorBeamAssigner', () {
    test('beams runs of >=2 contiguous same-beat notes and leaves singles/cross-beat un-beamed', () {
      final assigned = EditorBeamAssigner.assign(
        measureNumber: 2,
        timeSignature: TimeSignature.common,
        notes: <NoteTimelineInput>[
          // Beat 0: two eighths -> beamed together
          _note(
            Clef.treble,
            const RationalBeats.zero(),
            NoteBaseDuration.eighth,
          ),
          _note(Clef.treble, RationalBeats(1, 2), NoteBaseDuration.eighth),
          // Beat 1..2: isolated eighth at 1, quarter at 3/2, isolated eighth at 5/2
          _note(Clef.treble, RationalBeats(1), NoteBaseDuration.eighth),
          _note(Clef.treble, RationalBeats(3, 2), NoteBaseDuration.quarter),
          _note(Clef.treble, RationalBeats(5, 2), NoteBaseDuration.eighth),
          // Beat 3: two 16ths -> new beam group on treble
          _note(Clef.treble, RationalBeats(3), NoteBaseDuration.sixteenth),
          _note(Clef.treble, RationalBeats(13, 4), NoteBaseDuration.sixteenth),
          // Bass beat 0: two eighths -> separate beam id per clef/stream
          _note(Clef.bass, const RationalBeats.zero(), NoteBaseDuration.eighth),
          _note(Clef.bass, RationalBeats(1, 2), NoteBaseDuration.eighth),
        ],
      );

      expect(assigned[0].beamGroupId, 'm2-p0-v1-b0');
      expect(assigned[1].beamGroupId, 'm2-p0-v1-b0');
      expect(assigned[2].beamGroupId, isNull);
      expect(assigned[3].beamGroupId, isNull);
      expect(assigned[4].beamGroupId, isNull);
      expect(assigned[5].beamGroupId, 'm2-p0-v1-b1');
      expect(assigned[6].beamGroupId, 'm2-p0-v1-b1');
      expect(assigned[7].beamGroupId, 'm2-p0-v1-b2');
      expect(assigned[8].beamGroupId, 'm2-p0-v1-b2');
    });

    test(
      'groups three eighths per dotted-quarter beat in 6/8 compound meter',
      () {
        final assigned = EditorBeamAssigner.assign(
          measureNumber: 1,
          timeSignature: TimeSignature(6, 8),
          notes: <NoteTimelineInput>[
            _note(
              Clef.treble,
              const RationalBeats.zero(),
              NoteBaseDuration.eighth,
            ),
            _note(Clef.treble, RationalBeats(1, 2), NoteBaseDuration.eighth),
            _note(Clef.treble, RationalBeats(1), NoteBaseDuration.eighth),
            _note(Clef.treble, RationalBeats(3, 2), NoteBaseDuration.eighth),
            _note(Clef.treble, RationalBeats(2), NoteBaseDuration.eighth),
          ],
        );
        expect(assigned[0].beamGroupId, 'm1-p0-v1-b0');
        expect(assigned[1].beamGroupId, 'm1-p0-v1-b0');
        expect(assigned[2].beamGroupId, 'm1-p0-v1-b0');
        expect(assigned[3].beamGroupId, 'm1-p0-v1-b1');
        expect(assigned[4].beamGroupId, 'm1-p0-v1-b1');
      },
    );
  });
}
