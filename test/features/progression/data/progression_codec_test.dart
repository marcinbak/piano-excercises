import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/progression/progression.dart';

void main() {
  group('ProgressionCodec', () {
    test(
      'round-trips initial, multi-stage stats, and free-practice snapshots',
      () {
        final initial = ProgressionSnapshot.initial();
        expect(
          ProgressionCodec.tryDecode(ProgressionCodec.encode(initial)),
          initial,
        );

        const customCriteria = StageMasteryCriteria(
          minAttempts: 3,
          minAccuracy: 0.8,
          minStreak: 2,
        );
        final freePractice = ProgressionSnapshot(
          activeStageId: StageId.stage4,
          highestUnlockedStageId: StageId.stage2,
          statsByStage: const <StageId, StageAttemptStats>{
            StageId.stage1: StageAttemptStats(
              attempts: 12,
              correctAttempts: 11,
              currentStreak: 4,
              bestStreak: 8,
            ),
            StageId.stage4: StageAttemptStats(
              attempts: 3,
              correctAttempts: 2,
              currentStreak: 0,
              bestStreak: 2,
            ),
          },
          criteria: customCriteria,
        );

        final encoded = ProgressionCodec.encode(freePractice);
        final decoded = ProgressionCodec.tryDecode(
          encoded,
          criteria: customCriteria,
        );
        expect(decoded, freePractice);
      },
    );

    test('rejects malformed JSON and invalid top-level payloads', () {
      const invalidPayloads = <String>[
        '',
        '{not-json',
        'null',
        '[]',
        '42',
        '"string"',
        '{}',
        '{"version": 2, "activeStage": 1, "highestUnlockedStage": 1, "statsByStage": {}}',
        '{"version": "1", "activeStage": 1, "highestUnlockedStage": 1, "statsByStage": {}}',
        '{"version": 1.5, "activeStage": 1, "highestUnlockedStage": 1, "statsByStage": {}}',
        '{"version": 1, "activeStage": 0, "highestUnlockedStage": 1, "statsByStage": {}}',
        '{"version": 1, "activeStage": 5, "highestUnlockedStage": 1, "statsByStage": {}}',
        '{"version": 1, "activeStage": -1, "highestUnlockedStage": 1, "statsByStage": {}}',
        '{"version": 1, "activeStage": "1", "highestUnlockedStage": 1, "statsByStage": {}}',
        '{"version": 1, "activeStage": 1, "highestUnlockedStage": 0, "statsByStage": {}}',
        '{"version": 1, "activeStage": 1, "highestUnlockedStage": 5, "statsByStage": {}}',
        '{"version": 1, "activeStage": 1, "highestUnlockedStage": 1, "statsByStage": []}',
      ];

      for (final raw in invalidPayloads) {
        expect(
          ProgressionCodec.tryDecode(raw),
          isNull,
          reason: 'Payload: $raw',
        );
      }
    });

    test('rejects non-canonical stage keys and broken stat invariants', () {
      String withStats(Map<String, Object?> statsByStage) {
        return jsonEncode(<String, Object?>{
          'version': 1,
          'activeStage': 1,
          'highestUnlockedStage': 1,
          'statsByStage': statsByStage,
        });
      }

      const validStats = <String, Object?>{
        'attempts': 4,
        'correctAttempts': 3,
        'currentStreak': 1,
        'bestStreak': 2,
      };

      for (final badKey in const <String>[
        '0',
        '5',
        '-1',
        '01',
        '+1',
        ' 1',
        '1 ',
        'stage1',
      ]) {
        expect(
          ProgressionCodec.tryDecode(
            withStats(<String, Object?>{badKey: validStats}),
          ),
          isNull,
          reason: 'Key: "$badKey"',
        );
      }

      final badStatsList = <Object?>[
        null,
        'invalid',
        <Object?>[],
        <String, Object?>{
          'attempts': 1,
          'correctAttempts': 1,
          'currentStreak': 1,
        },
        <String, Object?>{
          'attempts': '4',
          'correctAttempts': 3,
          'currentStreak': 1,
          'bestStreak': 2,
        },
        <String, Object?>{
          'attempts': -1,
          'correctAttempts': 0,
          'currentStreak': 0,
          'bestStreak': 0,
        },
        <String, Object?>{
          'attempts': 2,
          'correctAttempts': -1,
          'currentStreak': 0,
          'bestStreak': 0,
        },
        <String, Object?>{
          'attempts': 2,
          'correctAttempts': 3,
          'currentStreak': 0,
          'bestStreak': 0,
        },
        <String, Object?>{
          'attempts': 4,
          'correctAttempts': 2,
          'currentStreak': 0,
          'bestStreak': -1,
        },
        <String, Object?>{
          'attempts': 4,
          'correctAttempts': 2,
          'currentStreak': 2,
          'bestStreak': 3,
        },
        <String, Object?>{
          'attempts': 4,
          'correctAttempts': 2,
          'currentStreak': -1,
          'bestStreak': 2,
        },
        <String, Object?>{
          'attempts': 4,
          'correctAttempts': 3,
          'currentStreak': 3,
          'bestStreak': 2,
        },
      ];

      for (final badStats in badStatsList) {
        expect(
          ProgressionCodec.tryDecode(
            withStats(<String, Object?>{'1': badStats}),
          ),
          isNull,
          reason: 'Stats: $badStats',
        );
      }
    });
  });
}
