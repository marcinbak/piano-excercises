# Riverpod Pitfalls

## StreamProvider coalescing of rapid MIDI events

- **Symptom:** Simultaneous or rapid synchronous Note On/Off events drop when watched through `StreamProvider<MidiNoteEvent>`.
- **Root cause:** `StreamProvider` wraps emissions in `AsyncValue` and schedules rebuilds asynchronously, coalescing synchronous bursts into the latest value.
- **Fix:** Subscribe directly to `MidiRepository.noteEventsStream` inside `Notifier.build()` and cancel in `ref.onDispose()` ([drill_providers.dart](../../lib/features/drill/state/drill_providers.dart)).
