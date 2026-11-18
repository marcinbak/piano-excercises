import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/progression/progression.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('StageId', () {
    test('provides numbers, neighbors, and validated lookup', () {
      expect(StageId.values, hasLength(4));
      expect(StageId.stage1.number, 1);
      expect(StageId.stage1.previous, isNull);
      expect(StageId.stage1.next, StageId.stage2);

      expect(StageId.stage4.number, 4);
      expect(StageId.stage4.previous, StageId.stage3);
      expect(StageId.stage4.next, isNull);

      for (final id in StageId.values) {
        expect(StageId.fromNumber(id.number), id);
      }
      expect(() => StageId.fromNumber(0), throwsRangeError);
      expect(() => StageId.fromNumber(5), throwsRangeError);
    });
  });

  group('ProgressionCatalog', () {
    test(
      'defines exact introduced and cumulative counts across stages 1..4',
      () {
        expect(ProgressionCatalog.stages, hasLength(4));

        final expectedCounts = <StageId, (int introduced, int cumulative)>{
          StageId.stage1: (4, 4),
          StageId.stage2: (2, 6),
          StageId.stage3: (2, 8),
          StageId.stage4: (22, 30),
        };

        for (final stageId in StageId.values) {
          final stage = ProgressionCatalog.byId(stageId);
          final expected = expectedCounts[stageId]!;
          expect(stage.id, stageId);
          expect(stage.introducedNotes, hasLength(expected.$1));
          expect(stage.cumulativeNotes, hasLength(expected.$2));
        }
      },
    );

    test('matches exact grand-staff landmark pools for stages 1..3', () {
      expect(
        ProgressionCatalog.byId(StageId.stage1).introducedNotes,
        const <StaffNote>[
          StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble),
          StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.bass),
          StaffNote(note: DiatonicNote.c, octave: 3, clef: Clef.bass),
          StaffNote(note: DiatonicNote.c, octave: 5, clef: Clef.treble),
        ],
      );
      expect(
        ProgressionCatalog.byId(StageId.stage1).distinctMidiNotes,
        <MidiNote>{const MidiNote(48), MidiNote.middleC, const MidiNote(72)},
      );

      expect(
        ProgressionCatalog.byId(StageId.stage2).introducedNotes,
        const <StaffNote>[
          StaffNote(note: DiatonicNote.c, octave: 2, clef: Clef.bass),
          StaffNote(note: DiatonicNote.c, octave: 6, clef: Clef.treble),
        ],
      );
      expect(
        ProgressionCatalog.byId(StageId.stage3).introducedNotes,
        const <StaffNote>[
          StaffNote(note: DiatonicNote.f, octave: 3, clef: Clef.bass),
          StaffNote(note: DiatonicNote.g, octave: 4, clef: Clef.treble),
        ],
      );
    });

    test('maintains strict subset monotonicity without duplicates', () {
      for (var i = 0; i < ProgressionCatalog.stages.length; i++) {
        final current = ProgressionCatalog.stages[i];
        expect(
          current.cumulativeNotes.toSet(),
          hasLength(current.cumulativeNotes.length),
        );
        expect(
          current.introducedNotes.toSet(),
          hasLength(current.introducedNotes.length),
        );

        if (i > 0) {
          final previous = ProgressionCatalog.stages[i - 1];
          for (final note in previous.cumulativeNotes) {
            expect(current.containsNote(note), isTrue);
          }
          for (final introduced in current.introducedNotes) {
            expect(previous.containsNote(introduced), isFalse);
            expect(current.containsNote(introduced), isTrue);
          }
          expect(
            current.cumulativeNotes.toSet(),
            previous.cumulativeNotes.toSet().union(
              current.introducedNotes.toSet(),
            ),
          );
        }
      }
    });

    test('covers all 29 natural notes in C2..C6 with at most 2 ledger lines in stage 4', () {
      final stage4 = ProgressionCatalog.byId(StageId.stage4);
      final bassNotes = stage4.cumulativeNotes
          .where((note) => note.clef == Clef.bass)
          .toList();
      final trebleNotes = stage4.cumulativeNotes
          .where((note) => note.clef == Clef.treble)
          .toList();

      expect(bassNotes, hasLength(15));
      expect(trebleNotes, hasLength(15));
      expect(stage4.distinctMidiNotes, hasLength(29));

      for (final staffNote in stage4.cumulativeNotes) {
        expect(staffNote.accidental, Accidental.natural);
        expect(staffNote.midiNote.isNatural, isTrue);
        expect(staffNote.midiNote.number, inInclusiveRange(36, 84));
        expect(staffNote.staffPosition.ledgerLineCount, lessThanOrEqualTo(2));
      }

      expect(
        () => stage4.cumulativeNotes.add(
          const StaffNote(note: DiatonicNote.c, octave: 4, clef: Clef.treble),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => stage4.distinctMidiNotes.add(MidiNote.middleC),
        throwsUnsupportedError,
      );
    });

    test(
      'defensively copies and freezes caller lists in public constructor',
      () {
        const trebleC4 = StaffNote(
          note: DiatonicNote.c,
          octave: 4,
          clef: Clef.treble,
        );
        const bassC4 = StaffNote(
          note: DiatonicNote.c,
          octave: 4,
          clef: Clef.bass,
        );
        final introduced = <StaffNote>[trebleC4];
        final cumulative = <StaffNote>[trebleC4];

        final stage = ProgressionStage(
          id: StageId.stage1,
          title: 'Custom',
          description: 'Mutable source test',
          introducedNotes: introduced,
          cumulativeNotes: cumulative,
        );

        introduced.add(bassC4);
        cumulative.add(bassC4);

        expect(stage.introducedNotes, const <StaffNote>[trebleC4]);
        expect(stage.cumulativeNotes, const <StaffNote>[trebleC4]);
        expect(() => stage.introducedNotes.add(bassC4), throwsUnsupportedError);
        expect(() => stage.cumulativeNotes.add(bassC4), throwsUnsupportedError);
      },
    );
  });
}
