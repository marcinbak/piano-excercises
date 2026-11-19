# smufl_notation

Pure-Flutter SMuFL grand-staff music notation layout and `CustomPainter` engine.

## Features

| Component | Purpose |
|---|---|
| `NotationScore` / `NotationMeasure` / `NotationSlice` | Immutable grand-staff score model |
| `ChordCollisionSolver` | Stem direction, adjacent-second shifts, accidental columns |
| `ScoreLayoutEngine` | Multi-system wrapping, justification, beams, ties, `O(1)` slice geometry |
| `GrandStaffScorePainter` | Viewport-culled `CustomPainter` with dimming and wrong-note overlays |
| `GrandStaffScoreView` | Scrollable responsive widget with cached layout and auto-scroll |

## Internal Layers

Dependency flow: `widgets/ -> painting/ -> layout/ -> model/ <- glyphs/`.

| Layer (`lib/src/...`) | Responsibility | Import Constraints |
|---|---|---|
| `glyphs/` | SMuFL codepoints and staff-space metrics | Pure Dart (zero `dart:ui` or `flutter`) |
| `model/` | Immutable grand-staff score and note models | Pure Dart; depends only on `glyphs/` |
| `layout/` | Collision, beam, tie, and multi-system geometry engine | Uses `dart:ui` primitives only; zero `package:flutter` |
| `painting/` | `CustomPainter` renderers and glyph baseline helper | Uses `painting`/`rendering`; zero `widgets.dart` |
| `widgets/` | Scrollable responsive `GrandStaffScoreView` widget | Composes `painting/`, `layout/`, and `model/` |

## Font Setup

Register a SMuFL-compliant font (such as `Bravura`) in your app `pubspec.yaml`:

```yaml
flutter:
  fonts:
    - family: Bravura
      fonts:
        - asset: assets/fonts/Bravura.otf
```

## Example

Run the standalone benchmark and fixture harness from the workspace root:

```sh
flutter run -t packages/smufl_notation/example/main.dart
```
