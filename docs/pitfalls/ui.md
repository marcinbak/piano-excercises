# UI & SMuFL Pitfalls

## SMuFL glyph alignment and TextPainter disposal

- **Symptom:** `Bravura` glyphs shift off staff lines or leak native layout resources across repaints.
- **Root cause:** SMuFL anchors glyph origins to the alphabetic baseline, and `TextPainter` holds native state until disposed.
- **Fix:** Set `fontSize = 4 * staffSpace`, align via `computeDistanceToActualBaseline(TextBaseline.alphabetic)`, and call `painter.dispose()` ([grand_staff_layout.dart](../../lib/features/drill/ui/grand_staff_layout.dart)).

## Material 3 ChoiceChip checkmark overlaps avatar icons

- **Symptom:** Selected `ChoiceChip` widgets draw a checkmark on top of the leading `avatar` icon.
- **Root cause:** Material 3 `ChoiceChip` defaults `showCheckmark` to `true`, which renders over `avatar` when selected.
- **Fix:** Set `showCheckmark: false` on `ChoiceChip` when using a leading `avatar` icon ([drill_header_bar.dart](../../lib/features/drill/ui/drill_header_bar.dart)).
