# Pitfalls

Record non-obvious bugs, platform/BLE-MIDI quirks, and workflow workarounds here so agents do not hit them twice.

## Areas

- [BLE-MIDI](ble-midi.md) — Bluetooth power-off scan state and initialization wait timeout.
- [iOS](ios.md) — Physical device code signing requirements.
- [Riverpod](riverpod.md) — `StreamProvider` coalescing of rapid MIDI events.
- [UI & SMuFL](ui.md) — `Bravura` baseline alignment and `TextPainter` disposal.

## How to add a pitfall

1. Create or update `docs/pitfalls/<area>.md` (for example `ble-midi.md`, `ios.md`, `android.md`).
2. State the symptom, root cause, and exact fix in active voice.
3. Add a one-line link under `## Common pitfalls` in [AGENTS.md](../../AGENTS.md) in the same commit.
