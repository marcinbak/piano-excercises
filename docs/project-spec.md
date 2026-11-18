# Project Specification

## 1. Goal

Replicate the core note-reading drill loop from [MusoPhone Exercise 7](https://musophone.com/tests-new/?exercise=7) as a mobile app for iOS and Android.

## 2. Core Drill Loop

1. App displays a target note on a musical staff (treble, bass, or grand staff).
2. User plays a key on a Bluetooth LE MIDI piano.
3. App reads incoming MIDI Note On events and checks pitch and octave against the target note.
4. App gives immediate right/wrong feedback, records speed/accuracy, and presents the next note.

## 3. Difficulty Progression

| Stage | Scope | Purpose |
| --- | --- | --- |
| 1 | `C4` on treble and bass clefs | Verify MIDI connection and basic response |
| 2 | `+ C3` (bass), `C5` (treble) | Expand octave recognition from Middle C |
| 3 | `+ C2` (bass), `C6` (treble) | Complete `C2..C6` anchors across the grand staff |
| 4 | `+ F3` (bass), `G4` (treble) | Establish primary clef landmark notes |
| 5 | `+` remaining naturals across bass `C2..B3` and treble `D4..C6` | Fill gaps between landmarks (max 2 ledger lines) |
| 6+ | Accidentals, intervals, speed drills | Planned future expansion after core loop |

Stage pools live in [progression_stage.dart](../lib/features/progression/domain/progression_stage.dart); default mastery criteria (`10` attempts, `90%` accuracy, `5` streak) live in [progression_rules.dart](../lib/features/progression/domain/progression_rules.dart).

## 4. Platform & Connectivity Requirements

| Requirement | Details |
| --- | --- |
| Operating systems | iOS and Android |
| MIDI transport | Bluetooth Low Energy MIDI (BLE-MIDI, UUID `03B80E5A-EDE8-4B33-A751-6CE34EC4C700`) |
| Latency target | Real-time Note On detection with minimal UI delay |
| Offline operation | Drills and staff rendering run locally on device |

## 5. Open Decisions

- **BLE-MIDI & Staff Packages:** Integrated `flutter_midi_command` + `flutter_midi_command_ble` in [MidiSpikeScreen](../lib/features/midi/ui/midi_spike_screen.dart) and bundled `Bravura` SMuFL rendering in [DrillScreen](../lib/features/drill/ui/drill_screen.dart); physical BLE-MIDI hardware test remains open.
- **Fallback Input:** Decide whether to include an on-screen piano or microphone pitch detection when no MIDI keyboard is connected.
- **USB-MIDI:** Decide whether to support wired USB-MIDI alongside BLE-MIDI.
- **Pre-Release Permission Check (Deferred):** Confirm permission with the creators/owners of [MusoPhone](https://musophone.com/tests-new/?exercise=7) before any public release; all credits go to them.
