# Architecture

Rules for where code goes and what may depend on what. Enforced by `flutter analyze --fatal-infos`, `dart format --output=none --set-exit-if-changed .`, and `python3 scripts/hotspots.py --repo . --check`; everything else by the review checklist. Change a rule here first, then the code.

## Modules

| Module | Owns | Public API |
|---|---|---|
| `lib/app/` | Composition root: `MaterialApp`, `ProviderScope`, routing, theme, DI overrides | `lib/app/app.dart` |
| `lib/features/drill/` | Sight-reading loop: staff display, target note, pitch validation, feedback | `lib/features/drill/drill.dart` |
| `lib/features/progression/` | Difficulty stages, unlocked note pools (Core Cs → all Cs → landmarks → all naturals), and local persistence | `lib/features/progression/progression.dart` |
| `lib/features/midi/` | BLE-MIDI discovery, connection lifecycle, Note On/Off stream | `lib/features/midi/midi.dart` |
| `lib/shared/` | Music theory primitives, shared UI widgets, theme tokens used by ≥2 features | per-folder `<area>.dart` |

## Layers and dependency direction

`ui/ → state/ → domain/ ← data/` inside each feature.

- `domain/` is pure Dart: imports nothing from `package:flutter`, `package:material_ui`, `flutter_riverpod`, `ui/`, `state/`, or `data/`.
- `shared/` never imports `features/` or `app/`.
- Feature → feature imports use only the target feature's barrel file (`lib/features/<name>/<name>.dart`); no cycles.
- Cross-feature barrels exporting `state/`, `ui/`, or `data/` break `domain/` purity; pass `shared/` primitives into `domain/` instead.
- Invert dependencies (an abstract interface in `domain/`, implemented in `data/`) only at real I/O boundaries (BLE-MIDI plugin, local storage, clock/randomness).

## Placement

| Kind of code | Goes in |
|---|---|
| Widget, screen, `CustomPainter` | `lib/features/<feature>/ui/` |
| Riverpod `Notifier`, `Provider`, UI state | `lib/features/<feature>/state/` |
| Pure rule, entity, calculation, boundary interface | `lib/features/<feature>/domain/` |
| BLE-MIDI plugin adapter, storage, mapper | `lib/features/<feature>/data/` |
| Shared across ≥2 features | `lib/shared/` (move on second real use) |
| App wiring, `ProviderScope`, navigation, theme | `lib/app/` |

## Budgets

Non-blank lines; `test/` and generated files excluded.

| Unit | Warn | Error | Gate |
|---|---|---|---|
| File lines | 300 | 500 | `python3 scripts/hotspots.py --repo . --check` |
| Function / method lines | 40 | 80 | Review checklist |
| `build()` method / widget body | 150 | 250 | Review checklist |
| Cyclomatic complexity | 10 | 15 | Review checklist |
| Parameters / nesting depth | 5 / 3 | 7 / 4 | Review checklist |
| Static types & lints | 0 | 0 | `flutter analyze --fatal-infos` |

## Exemptions

Files allowed over budget today with a refactor ticket. This list only shrinks.

| File | Lines | Ticket |
|---|---|---|

## Decisions

- **Riverpod without codegen:** Use `flutter_riverpod` with manual providers in `state/` and overrides in `app/`; omit `riverpod_generator` and `build_runner` to keep builds fast.
- **Dart barrel convention:** Public APIs use `<feature>.dart` instead of `index.ts`.
- **No Flutter stack appendix:** `scripts/hotspots.py --check` enforces file-line budgets; `analysis_options.yaml` enforces strict types and lints.

## Review checklist

- New code sits in the module and layer defined in Placement.
- No responsibility added to a file that already owns one (I/O, state, UI, pure logic).
- `domain/` has zero `flutter`, `flutter_riverpod`, or I/O imports.
- No deep cross-feature imports outside the feature's barrel file.
- Every `StreamSubscription` and `StreamController` is closed/cancelled cleanly.
- Abstractions have a second real use or a true I/O boundary.
- A file pushed over budget was split in a separate prep commit before the feature commit.
