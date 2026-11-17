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
| 1 | Middle C (`C4`) only | Verify MIDI connection and basic response |
| 2 | Additional C notes | Expand octave recognition from Middle C |
| 3 | All treble and bass C notes | Anchor C positions across the grand staff |
| 4 | Base landmark notes | Establish primary reference notes on both clefs |
| 5 | Remaining natural notes | Fill gaps between landmark notes step by step |
| 6+ | Accidentals, intervals, speed drills | Planned future expansion after core loop |

## 4. Platform & Connectivity Requirements

| Requirement | Details |
| --- | --- |
| Operating systems | iOS and Android |
| MIDI transport | Bluetooth Low Energy MIDI (BLE-MIDI, UUID `03B80E5A-EDE8-4B33-A751-6CE34EC4C700`) |
| Latency target | Real-time Note On detection with minimal UI delay |
| Offline operation | Drills and staff rendering run locally on device |

## 5. Open Decisions

- **Creator Permission:** Contact Benedict Westenra (`musophone.com`) regarding permission to adapt the Read Music Fast exercise flow.
- **BLE-MIDI & Staff Packages:** Verify `flutter_midi_command` + `flutter_midi_command_ble` and SMuFL staff rendering approach on physical hardware.
- **Fallback Input:** Decide whether to include an on-screen piano or microphone pitch detection when no MIDI keyboard is connected.
- **USB-MIDI:** Decide whether to support wired USB-MIDI alongside BLE-MIDI.
