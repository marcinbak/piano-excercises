# iOS Pitfalls

## Physical device deployment requires signing

- **Symptom:** `flutter build ios --no-codesign` passes, but installing onto a physical iPhone fails without signing credentials.
- **Root cause:** `--no-codesign` skips code signing; physical iOS devices require an Xcode Apple Developer team and provisioning profile.
- **Fix:** Configure signing in Xcode (`Signing & Capabilities`) before running on a physical device; keep Bluetooth usage descriptions in [Info.plist](../../ios/Runner/Info.plist).
