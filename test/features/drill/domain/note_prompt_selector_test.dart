import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/drill/domain/note_prompt_selector.dart';
import 'package:piano_exercises/features/progression/progression.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  group('NotePromptSelector', () {
    test('throws ArgumentError when pool is empty', () {
      final selector = NotePromptSelector(nextInt: (_) => 0);
      expect(
        () => selector.selectFromPool(const <StaffNote>[]),
        throwsArgumentError,
      );
    });

    test('returns sole note when pool length is 1', () {
      const only = StaffNote(
        note: DiatonicNote.c,
        octave: 4,
        clef: Clef.treble,
      );
      final selector = NotePromptSelector(nextInt: (_) => 0);

      expect(selector.selectFromPool(<StaffNote>[only]), only);
      expect(selector.selectFromPool(<StaffNote>[only], previous: only), only);
    });

    test(
      'never repeats previous StaffNote back-to-back across Stages 1..5',
      () {
        final random = math.Random(42);
        final selector = NotePromptSelector(nextInt: random.nextInt);

        for (final stage in ProgressionCatalog.stages) {
          StaffNote? previous;
          for (var i = 0; i < 100; i += 1) {
            final next = selector.selectFromStage(stage, previous: previous);
            expect(stage.containsNote(next), isTrue);
            if (previous != null) {
              expect(
                next,
                isNot(previous),
                reason:
                    'Stage ${stage.id.number} repeated $previous at step $i',
              );
            }
            previous = next;
          }
        }
      },
    );
  });
}
