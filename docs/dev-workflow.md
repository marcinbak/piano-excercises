# Dev workflow manifest

Project facts for the `dev-workflow` skill. The skill owns the process; this file owns the facts. Conventions and pitfalls stay in [AGENTS.md](../AGENTS.md) and [docs/pitfalls/](pitfalls/README.md).

## Tracker

| Key | Value |
|---|---|
| tracker | ackbar |
| project_node | `Personal/Piano` (initial task `task_1794864111216060000`) |
| jira_base_url | none (personal repo) |
| ready_statuses | `NEW` |
| in_progress_status | `IN_PROGRESS` |
| pr_open_status | `REVIEW` |

## Naming

| Key | Pattern |
|---|---|
| branch_pattern | `<type>/<slug>` (`feat/`, `fix/`, `chore/`) |
| pr_title_pattern | `<type>(<scope>): <summary>` |
| commit_pattern | `<type>(<scope>): <summary>` |

## Commands

`ci` values: `✅ <workflow>` (hard gate), `⚠️ warning-only`, `❌ not gated`, or `—` (not run in CI).

| Capability | Command | T0 | CI | Notes |
|---|---|---|---|---|
| install | `flutter pub get` | | ✅ PR checks | Run after checkout/worktree creation |
| format | `dart format --output=none --set-exit-if-changed .` | x | ✅ PR checks | Fix locally with `dart format .` |
| lint | `flutter analyze --fatal-infos` | x | ✅ PR checks | Also runs `scripts/hotspots.py --check` separately |
| typecheck | `flutter analyze --fatal-infos` | x | ✅ PR checks | Strict mode enabled (`strict-casts`, `strict-inference`, `strict-raw-types`) |
| size gate | `python3 scripts/hotspots.py --repo . --check` | x | ✅ PR checks | Errors on tracked source files >500 non-blank lines |
| unit test | `flutter test test packages/smufl_notation/test` | x | ✅ PR checks | Runs root and workspace package Dart/Flutter tests |
| compile/bundle gate | `flutter build apk --debug` | | ✅ PR checks | Catches broken Android/Dart imports and packaging |
| build artifact (iOS) | `flutter build ios --no-codesign` | | ✅ PR checks | Runs on `macos-latest` (`ios-build` job) |
| install to device | `flutter run --profile` (or `--release`) | | — | Physical iOS BLE-MIDI verified; untethered launches require AOT builds |
| e2e | none — no E2E suite configured yet | | — | Revisit once drill UI and BLE-MIDI adapter exist |

T0 set: `dart format --output=none --set-exit-if-changed .`, `flutter analyze --fatal-infos`, `python3 scripts/hotspots.py --repo . --check`, `flutter test test packages/smufl_notation/test`.

## Runtime

| Key | Value |
|---|---|
| worktree_location | `.worktrees/<branch-slug>` |
| dependency_install_rule | Run `flutter pub get` in each new worktree before `T0` |
| device_acquisition | Manual physical iOS/Android device with BLE-MIDI keyboard (simulators lack BLE) |
| build_flags | `--no-codesign` for un-signed iOS compile checks |
| install_caveats | iOS requires `NSBluetoothAlwaysUsageDescription` and `--profile`/`--release` for untethered runs; Android 12+ requires `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` |
| device_automation | none — no automation harness configured yet |
| design_tool | none — no external design tool linked |
| design_link_location | none — UI scope defined in [docs/project-spec.md](project-spec.md) |

### E2E flows

| Flow | Surface | Notes |
|---|---|---|
| none | none | No E2E flows configured yet |

Excluded flows and why: none.

## Ship

| Key | Value |
|---|---|
| merge_policy | auto |
| announce_channel | none (personal repo) |
| cc_resolution | none |
| doc_update_targets | `README.md`, `AGENTS.md`, `docs/architecture.md`, `docs/project-spec.md`, `docs/pitfalls/` |

## Skip rules

N9 (on-device) is skipped when the change matches:

- Only `docs/**`, `AGENTS.md`, `CLAUDE.md`, `.github/**`, `.claude/**`, `analysis_options.yaml`, `scripts/**`, or `test/**` changed, with zero edits to `lib/`, `ios/`, `android/`, or `pubspec.*`.

## Security addendum

Project-specific risks for the N6 security reviewer, beyond generic review:

- Validate bounds and lengths when parsing raw BLE-MIDI packet bytes; never trust malformed incoming MIDI frames.
- Keep Android `BLUETOOTH_SCAN` scoped with `neverForLocation` and declare accurate iOS Bluetooth purpose strings.
- Never commit Apple signing certificates, provisioning profiles, or Android keystores.

## Model overrides

- None — use the `dev-workflow` default routing rubric.
