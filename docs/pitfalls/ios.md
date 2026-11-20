# iOS Pitfalls

## Physical device deployment requires signing

- **Symptom:** `flutter build ios --no-codesign` passes, but installing onto a physical iPhone fails without signing credentials.
- **Root cause:** `--no-codesign` skips code signing; physical iOS devices require an Xcode Apple Developer team and provisioning profile.
- **Fix:** Configure signing in Xcode (`Signing & Capabilities`) before running on a physical device; keep Bluetooth usage descriptions in [Info.plist](../../ios/Runner/Info.plist).

## Untethered physical device launches require AOT builds

- **Symptom:** App installs via `flutter run` in debug mode and crashes immediately when launched untethered from the home screen.
- **Root cause:** iOS `--debug` builds use a JIT VM that requires an attached Xcode or `lldb` debugger; iOS terminates untethered JIT processes.
- **Fix:** Use `flutter run --profile` or `flutter run --release` (AOT-compiled) for untethered physical device testing.

## In-app 90-degree fullscreen rotation across iPhone Portrait Lock and iPadOS multitasking

- **Symptom:** `SystemChrome.setPreferredOrientations` is ignored on iPadOS 16+ without `UIRequiresFullScreen` (which disables Split View and Stage Manager) and rejects `portraitDown` (`180°`) on Face ID iPhones.
- **Root cause:** iPadOS windowing decouples scene geometry from app orientation requests, and UIKit blocks upside-down portrait on notched/Dynamic Island iPhones.
- **Fix:** Wrap fullscreen score content in `SafeArea` -> `RotatedBox(quarterTurns: 0..3)` paired with `SystemUiMode.immersiveSticky` ([piece_score_fullscreen_view.dart](../../lib/features/piece_practice/ui/piece_score_fullscreen_view.dart)).
