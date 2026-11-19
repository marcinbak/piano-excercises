# UI & SMuFL Pitfalls

## SMuFL glyph alignment and TextPainter disposal

- **Symptom:** `Bravura` glyphs shift off staff lines or leak native layout resources across repaints.
- **Root cause:** SMuFL anchors glyph origins to the alphabetic baseline, and `TextPainter` holds native state until disposed.
- **Fix:** Set `fontSize = 4 * staffSpace`, align via `computeDistanceToActualBaseline(TextBaseline.alphabetic)`, and call `painter.dispose()` ([grand_staff_layout.dart](../../lib/features/drill/ui/grand_staff_layout.dart)).

## Material 3 ChoiceChip checkmark overlaps avatar icons

- **Symptom:** Selected `ChoiceChip` widgets draw a checkmark on top of the leading `avatar` icon.
- **Root cause:** Material 3 `ChoiceChip` defaults `showCheckmark` to `true`, which renders over `avatar` when selected.
- **Fix:** Set `showCheckmark: false` on `ChoiceChip` when using a leading `avatar` icon ([drill_header_bar.dart](../../lib/features/drill/ui/drill_header_bar.dart)).

## Flutter 3.50 deprecates `package:flutter/material.dart`

- **Symptom:** Importing `package:flutter/material.dart` fails `flutter analyze --fatal-infos` with `deprecated_member_use` on Flutter `3.50.0`.
- **Root cause:** Flutter `3.50.0` deprecated `material.dart` in favor of `package:material_ui` or `package:flutter/widgets.dart`.
- **Fix:** Build standalone packages and harnesses on `package:flutter/widgets.dart` (`WidgetsApp`) without `material_ui` ([main.dart](../../packages/smufl_notation/example/main.dart)).

## Scrollable CustomPainter culling after score shrink

- **Symptom:** Culled systems stay blank after replacing a tall score with a shorter score while scrolled down.
- **Root cause:** `ScrollPosition.correctPixels` clamps scroll offset during layout without notifying `ScrollController` listeners.
- **Fix:** Resynchronize and clamp `visibleRect.top` against `maxScrollExtent` on `score`, `style`, and `controller` updates ([grand_staff_score_view.dart](../../packages/smufl_notation/lib/src/widgets/grand_staff_score_view.dart)).

## Unbounded outer scroll containers cull CustomPainter past fallback height

- **Symptom:** Systems below `480px` disappear when wrapping `GrandStaffScoreView` inside an unbounded vertical scroll container.
- **Root cause:** `constraints.maxHeight` is infinite inside unbounded scroll views, so fixed fallback viewport heights or zero-height rects cull lower systems.
- **Fix:** Pass `visibleRect: constraints.maxHeight.isFinite ? effectiveRect : null` to disable culling when height is unbounded ([grand_staff_score_view.dart](../../packages/smufl_notation/lib/src/widgets/grand_staff_score_view.dart)).
