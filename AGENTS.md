# Agent guidelines for piano_exercises

`piano_exercises` is a Flutter (Dart + `flutter_riverpod`) mobile app for iOS and Android that delivers MusoPhone-style piano sight-reading drills over BLE-MIDI.

## Quick reference

| Topic | File |
|---|---|
| Product specification | [docs/project-spec.md](docs/project-spec.md) |
| Architecture rules | [docs/architecture.md](docs/architecture.md) — read before adding a module or growing a file past budget |
| Development workflow | [docs/dev-workflow.md](docs/dev-workflow.md) |
| Known pitfalls | [docs/pitfalls/](docs/pitfalls/README.md) |

## Commands

| Task | Command |
|---|---|
| install | `flutter pub get` |
| format | `dart format .` |
| format check | `dart format --output=none --set-exit-if-changed .` |
| lint & typecheck | `flutter analyze --fatal-infos` |
| size gate | `python3 scripts/hotspots.py --repo . --check` |
| test | `flutter test test packages/smufl_notation/test` |
| build (Android) | `flutter build apk --debug` |
| build (iOS) | `flutter build ios --no-codesign` |

Before calling work done: format check, lint & typecheck, size gate, and test pass.

## Key conventions

- **Imports:** Always use `package:piano_exercises/...`; import other features only through `lib/features/<name>/<name>.dart`.
- **State & DI:** Use manual `flutter_riverpod` providers in `state/` with `ProviderScope` overrides in `app/`; no `riverpod_generator` codegen.
- **Naming:** `snake_case.dart` files, `UpperCamelCase` types, `lowerCamelCase` symbols.
- **Comments:** Document only the non-obvious *why* (invariants, hardware/OS constraints); never narrate *what* the code does.
- **Tests:** Mirror `lib/` under `test/`; unit-test `domain/` without Flutter or plugin mocks; test `state/` with provider overrides.

## Agent instructions

1. Challenge suggestions — verify assumptions against code and specs before implementing.
2. Ask before choosing when multiple viable designs exist.
3. Keep code, comments, docs, and PR text concise.

## Common pitfalls

One line per pitfall, grouped by area; full write-ups live in `docs/pitfalls/<area>.md`. Read the relevant file before working in that area.

- **BLE-MIDI:** Call `stopScanningForBluetoothDevices()` on Bluetooth power-off and timeout `waitUntilBluetoothIsInitialized()` — see [docs/pitfalls/ble-midi.md](docs/pitfalls/ble-midi.md).
- **iOS:** Physical device deployment requires Xcode signing beyond `--no-codesign` and `--profile`/`--release` AOT builds for untethered launches — see [docs/pitfalls/ios.md](docs/pitfalls/ios.md).
- **Riverpod:** Subscribe directly to `MidiRepository.noteEventsStream` in `Notifier.build()` and defer `state` updates in `dispose()` — see [docs/pitfalls/riverpod.md](docs/pitfalls/riverpod.md).
- **UI & SMuFL:** Align `Bravura` `TextPainter` glyphs via alphabetic baseline, call `dispose()`, set `ChoiceChip.showCheckmark: false`, use `widgets.dart` (`WidgetsApp`) in standalone packages, and clamp `visibleRect.top` on score shrink — see [docs/pitfalls/ui.md](docs/pitfalls/ui.md).

## Continuous documentation

Update docs before finishing a task, in the same commit as the change:

- New pitfall or workaround → `docs/pitfalls/<area>.md` + one-line entry above.
- Convention change → this file.
- Architecture rule change → `docs/architecture.md`.
- Feature scope or progression change → `docs/project-spec.md`.
