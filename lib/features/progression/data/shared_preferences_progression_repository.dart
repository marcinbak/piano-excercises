import 'dart:async';

import 'package:piano_exercises/features/progression/data/progression_codec.dart';
import 'package:piano_exercises/features/progression/domain/progression_repository.dart';
import 'package:piano_exercises/features/progression/domain/progression_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists progression snapshots locally via [SharedPreferencesWithCache].
final class SharedPreferencesProgressionRepository
    implements ProgressionRepository {
  SharedPreferencesProgressionRepository(SharedPreferencesWithCache cache)
    : _cache = cache;

  static const String storageKey = 'piano_exercises.progression.v1';

  final SharedPreferencesWithCache _cache;
  Future<void> _writeChain = Future<void>.value();

  static Future<SharedPreferencesProgressionRepository> create() async {
    final cache = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: <String>{storageKey},
      ),
    );
    return SharedPreferencesProgressionRepository(cache);
  }

  @override
  ProgressionSnapshot? load({
    StageMasteryCriteria criteria = StageMasteryCriteria.standard,
  }) {
    final String? rawJson;
    try {
      rawJson = _cache.getString(storageKey);
    } catch (_) {
      unawaited(clear());
      return null;
    }
    if (rawJson == null) {
      return null;
    }
    final snapshot = ProgressionCodec.tryDecode(rawJson, criteria: criteria);
    if (snapshot == null) {
      unawaited(clear());
      return null;
    }
    return snapshot;
  }

  @override
  Future<void> save(ProgressionSnapshot snapshot) {
    final encoded = ProgressionCodec.encode(snapshot);
    return _enqueueWrite(() => _cache.setString(storageKey, encoded));
  }

  @override
  Future<void> clear() {
    return _enqueueWrite(() => _cache.remove(storageKey));
  }

  // Chain writes sequentially and absorb storage failures so one error never wedges future saves.
  Future<void> _enqueueWrite(Future<void> Function() writeOperation) {
    final next = _writeChain
        .then((_) => writeOperation())
        .catchError((Object _) {});
    _writeChain = next;
    return next;
  }
}
