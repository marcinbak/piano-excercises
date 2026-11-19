# Riverpod Pitfalls

## StreamProvider coalescing of rapid MIDI events

- **Symptom:** Simultaneous or rapid synchronous Note On/Off events drop when watched through `StreamProvider<MidiNoteEvent>`.
- **Root cause:** `StreamProvider` wraps emissions in `AsyncValue` and schedules rebuilds asynchronously, coalescing synchronous bursts into the latest value.
- **Fix:** Subscribe directly to `MidiRepository.noteEventsStream` inside `Notifier.build()` and cancel in `ref.onDispose()` ([drill_providers.dart](../../lib/features/drill/state/drill_providers.dart)).

## Synchronous provider state mutation during widget disposal

- **Symptom:** Updating Riverpod `state` or reading `ref` synchronously inside `State.dispose()` or `ref.onDispose()` throws a lifecycle error.
- **Root cause:** Flutter forbids provider notifications during tree teardown, and `ref.mounted` is false inside `ref.onDispose()`.
- **Fix:** Cache the notifier before `dispose()`, use plain teardown flags, and defer `state` updates via `Future<void>.microtask` with `ref.mounted` ([midi_providers.dart](../../lib/features/midi/state/midi_providers.dart), [midi_connection_screen.dart](../../lib/features/midi/ui/midi_connection_screen.dart)).

## Riverpod 3 automatic retry stalls deterministic file/parse errors

- **Symptom:** `FutureProvider.autoDispose` hangs on `AsyncLoading` for ~25s (and times out `.future` in unit tests) when a local file read or parse throws.
- **Root cause:** Riverpod 3 retries async provider errors with exponential backoff by default unless `retry` returns `null`, and `autoDispose` cancels un-listened `.future` reads with `ProviderDisposedException`.
- **Fix:** Pass `retry: (_, _) => null` on deterministic local `FutureProvider`s and keep an active `container.listen` subscription when testing `.future` errors ([piece_score_providers.dart](../../lib/features/piece_practice/state/piece_score_providers.dart)).
