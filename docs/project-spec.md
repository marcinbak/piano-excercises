# Project Specification

## 1. Goal

Replicate the core note-reading drill loop from [MusoPhone Exercise 7](https://musophone.com/tests-new/?exercise=7) as a mobile app for iOS and Android.

## 2. Core Drill Loop

1. App renders a target note on the `Bravura` grand staff in [DrillScreen](../lib/features/drill/ui/drill_screen.dart).
2. User plays a key on a Bluetooth LE MIDI piano.
3. App coalesces simultaneous Note On events (`35ms`) and checks single-note pitch and octave against the target.
4. Clean hits advance the prompt and increment streak; mistakes reset streak, hold the target, and draw red wrong notes.
5. Clearing a missed prompt advances to the next note without incrementing streak.

## 3. Difficulty Progression

| Stage | Scope | Purpose |
| --- | --- | --- |
| 1 | `C4` (treble and bass), `C3` (bass), `C5` (treble) | Establish Core Cs and octave anchors across both clefs |
| 2 | `+ C2` (bass), `C6` (treble) | Complete `C2..C6` anchors across the grand staff |
| 3 | `+ F3` (bass), `G4` (treble) | Establish primary clef landmark notes |
| 4 | `+` remaining naturals across bass `C2..B3` and treble `D4..C6` | Fill gaps between landmarks (max 2 ledger lines) |
| 5+ | Accidentals, intervals, speed drills | Planned future expansion after core loop |

Stage pools live in [progression_stage.dart](../lib/features/progression/domain/progression_stage.dart), default mastery criteria (`10` attempts, `90%` accuracy, `5` streak) live in [progression_rules.dart](../lib/features/progression/domain/progression_rules.dart), and local progression state persists via `SharedPreferencesWithCache` in [shared_preferences_progression_repository.dart](../lib/features/progression/data/shared_preferences_progression_repository.dart).

## 4. Platform & Connectivity Requirements

| Requirement | Details |
| --- | --- |
| Operating systems | iOS and Android |
| MIDI transport | Bluetooth Low Energy MIDI (BLE-MIDI, UUID `03B80E5A-EDE8-4B33-A751-6CE34EC4C700`) |
| Latency target | Real-time Note On detection with minimal UI delay |
| Offline operation | Drills and staff rendering run locally on device |

## 5. Open Decisions

- **BLE-MIDI & Staff Packages:** Integrated `flutter_midi_command` + `flutter_midi_command_ble` in [MidiConnectionScreen](../lib/features/midi/ui/midi_connection_screen.dart) and bundled `Bravura` SMuFL rendering in [DrillScreen](../lib/features/drill/ui/drill_screen.dart); physical iOS BLE-MIDI discovery, connection, and real-time Note On/Off input are verified.
- **Runtime Score Import (`D1`):** Import `.mxl`/`.musicxml` files, multi-file picks, and `.zip` bundles at runtime with zero bundled scores ([score-import.md](score-import.md)); [catalog.dart](../lib/features/catalog/catalog.dart) provides `SqliteCatalogRepository`, `AppDocsScoreStore`, `CatalogScreen`, and `BatchScoreImportSheet`, and [app_navigation_shell.dart](../lib/app/app_navigation_shell.dart) wires `Drill`/`Catalog` navigation.
- **SMuFL Engraving Engine (`D2`):** `[M8]` completed production engraving in [smufl_notation.dart](../packages/smufl_notation/lib/smufl_notation.dart) and score rendering in [piece_practice.dart](../lib/features/piece_practice/piece_practice.dart); `[M9]` completed polyphonic Wait-Mode evaluation and measure loops, deferring Tempo & Metronome Mode to `[M10]`.
- **Fallback Input:** Decide whether to include an on-screen piano or microphone pitch detection when no MIDI keyboard is connected.
- **USB-MIDI:** Decide whether to support wired USB-MIDI alongside BLE-MIDI.
- **Pre-Release Permission Check (Deferred):** Confirm permission with the creators/owners of [MusoPhone](https://musophone.com/tests-new/?exercise=7) before any public release; all credits go to them.
