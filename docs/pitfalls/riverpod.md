# Riverpod Pitfalls

## StreamProvider coalescing of rapid MIDI events

- **Symptom:** Simultaneous or rapid synchronous Note On/Off events drop when watched through `StreamProvider<MidiNoteEvent>`.
- **Root cause:** `StreamProvider` wraps emissions in `AsyncValue` and schedules rebuilds asynchronously, coalescing synchronous bursts into the latest value.
- **Fix:** Subscribe directly to `MidiRepository.noteEventsStream` inside `Notifier.build()` and cancel in `ref.onDispose()` ([drill_providers.dart](../../lib/features/drill/state/drill_providers.dart)).

## Synchronous provider state mutation during widget disposal

- **Symptom:** Updating Riverpod `state` or reading `ref` synchronously inside `State.dispose()` or `ref.onDispose()` throws a lifecycle error.
- **Root cause:** Flutter forbids provider notifications during tree teardown, and `ref.mounted` is false inside `ref.onDispose()`.
- **Fix:** Cache the notifier before `dispose()`, use plain teardown flags, and defer `state` updates via `Future<void>.microtask` with `ref.mounted` ([midi_providers.dart](../../lib/features/midi/state/midi_providers.dart), [midi_connection_screen.dart](../../lib/features/midi/ui/midi_connection_screen.dart)).
