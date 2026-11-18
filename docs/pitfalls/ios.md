# iOS Pitfalls

## Physical device deployment requires signing

- **Symptom:** `flutter build ios --no-codesign` passes, but installing onto a physical iPhone fails without signing credentials.
- **Root cause:** `--no-codesign` skips code signing; physical iOS devices require an Xcode Apple Developer team and provisioning profile.
- **Fix:** Configure signing in Xcode (`Signing & Capabilities`) before running on a physical device; keep Bluetooth usage descriptions in [Info.plist](../../ios/Runner/Info.plist).

## Untethered physical device launches require AOT builds

- **Symptom:** App installs via `flutter run` in debug mode and crashes immediately when launched untethered from the home screen.
- **Root cause:** iOS `--debug` builds use a JIT VM that requires an attached Xcode or `lldb` debugger; iOS terminates untethered JIT processes.
- **Fix:** Use `flutter run --profile` or `flutter run --release` (AOT-compiled) for untethered physical device testing.
