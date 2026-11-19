# Pitfalls

Record non-obvious bugs, platform/BLE-MIDI quirks, and workflow workarounds here so agents do not hit them twice.

## Areas

- [BLE-MIDI](ble-midi.md) — Bluetooth power-off scan state and initialization wait timeout.
- [iOS](ios.md) — Physical device code signing and untethered AOT build requirements.
- [Riverpod](riverpod.md) — `StreamProvider` coalescing of rapid MIDI events and `dispose()` state mutation.
- [Score Parser](score-parser.md) — `archive` `3.6.x` ZIP bounds/headers, `xml` `7.x` `O(n^2)` entity decode, omitted `<alter>`, and tie accidentals.
- [UI & SMuFL](ui.md) — `Bravura` baseline alignment, `TextPainter` disposal, `ChoiceChip` checkmarks, `material.dart` deprecation, and `visibleRect` culling.

## How to add a pitfall

1. Create or update `docs/pitfalls/<area>.md` (for example `ble-midi.md`, `ios.md`, `android.md`).
2. State the symptom, root cause, and exact fix in active voice.
3. Add a one-line link under `## Common pitfalls` in [AGENTS.md](../../AGENTS.md) in the same commit.
