import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/progression/progression.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

base class _ControllableMemoryPreferences
    extends InMemorySharedPreferencesAsync {
  _ControllableMemoryPreferences() : super.empty();

  Completer<void>? nextSetStringGate;
  bool failNextSetString = false;
  final List<String> writeLog = <String>[];

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {
    writeLog.add('set:start');
    final gate = nextSetStringGate;
    if (gate != null) {
      nextSetStringGate = null;
      await gate.future;
    }
    if (failNextSetString) {
      failNextSetString = false;
      writeLog.add('set:fail');
      throw StateError('Simulated storage write error');
    }
    final result = await super.setString(key, value, options);
    writeLog.add('set:done');
    return result;
  }

  @override
  Future<bool> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    writeLog.add('clear');
    return super.clear(parameters, options);
  }
}

void main() {
  test('loads synchronously after create, saves, reloads across instances, and clears', () async {
    final snapshot = ProgressionSnapshot(
      activeStageId: StageId.stage3,
      highestUnlockedStageId: StageId.stage2,
      statsByStage: const <StageId, StageAttemptStats>{
        StageId.stage1: StageAttemptStats(
          attempts: 10,
          correctAttempts: 10,
          currentStreak: 10,
          bestStreak: 10,
        ),
      },
    );
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          SharedPreferencesProgressionRepository.storageKey:
              ProgressionCodec.encode(snapshot),
        });

    final repo = await SharedPreferencesProgressionRepository.create();
    expect(repo.load(), snapshot);

    final updated = snapshot.selectStage(StageId.stage4);
    await repo.save(updated);
    expect(repo.load(), updated);

    final secondRepo = await SharedPreferencesProgressionRepository.create();
    expect(secondRepo.load(), updated);

    await repo.clear();
    expect(repo.load(), isNull);
    final thirdRepo = await SharedPreferencesProgressionRepository.create();
    expect(thirdRepo.load(), isNull);
  });

  test('self-heals corrupt JSON and wrong-type values on load', () async {
    // 1) Corrupt JSON payload
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          SharedPreferencesProgressionRepository.storageKey: '{corrupt-json',
        });
    final corruptRepo = await SharedPreferencesProgressionRepository.create();
    expect(corruptRepo.load(), isNull);
    await Future<void>.delayed(Duration.zero);

    final afterCorruptHeal =
        await SharedPreferencesProgressionRepository.create();
    expect(afterCorruptHeal.load(), isNull);
    expect(
      await SharedPreferencesAsyncPlatform.instance!.getKeys(
        const GetPreferencesParameters(
          filter: PreferencesFilters(
            allowList: <String>{
              SharedPreferencesProgressionRepository.storageKey,
            },
          ),
        ),
        const SharedPreferencesOptions(),
      ),
      isEmpty,
    );

    // 2) Wrong-type stored value (int instead of String)
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          SharedPreferencesProgressionRepository.storageKey: 12345,
        });
    final wrongTypeRepo = await SharedPreferencesProgressionRepository.create();
    expect(wrongTypeRepo.load(), isNull);
    await Future<void>.delayed(Duration.zero);

    expect(
      await SharedPreferencesAsyncPlatform.instance!.getKeys(
        const GetPreferencesParameters(
          filter: PreferencesFilters(
            allowList: <String>{
              SharedPreferencesProgressionRepository.storageKey,
            },
          ),
        ),
        const SharedPreferencesOptions(),
      ),
      isEmpty,
    );
  });

  test('serializes rapid save/clear calls in FIFO order and recovers from storage errors', () async {
    final prefs = _ControllableMemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = prefs;
    final repo = await SharedPreferencesProgressionRepository.create();

    final s1 = ProgressionSnapshot.initial().recordAttempt(correct: true);
    final s2 = s1.selectStage(StageId.stage3);

    final gate = Completer<void>();
    prefs.nextSetStringGate = gate;

    // Rapidly enqueue save(s1) -> clear() -> save(s2) without awaiting in between.
    final f1 = repo.save(s1);
    final f2 = repo.clear();
    await Future<void>.delayed(Duration.zero);
    // clear() must not overtake the blocked setString(s1).
    expect(prefs.writeLog, <String>['set:start']);

    gate.complete();
    await Future.wait(<Future<void>>[f1, f2]);
    expect(prefs.writeLog, <String>['set:start', 'set:done', 'clear']);
    expect(repo.load(), isNull);

    // Simulate a platform write error; subsequent save must still succeed.
    prefs.failNextSetString = true;
    await repo.save(s1);
    await repo.save(s2);
    expect(repo.load(), s2);

    final reloaded = await SharedPreferencesProgressionRepository.create();
    expect(reloaded.load(), s2);
  });
}
