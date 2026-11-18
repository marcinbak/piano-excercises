# UI & SMuFL Pitfalls

## SMuFL glyph alignment and TextPainter disposal

- **Symptom:** `Bravura` glyphs shift off staff lines or leak native layout resources across repaints.
- **Root cause:** SMuFL anchors glyph origins to the alphabetic baseline, and `TextPainter` holds native state until disposed.
- **Fix:** Set `fontSize = 4 * staffSpace`, align via `computeDistanceToActualBaseline(TextBaseline.alphabetic)`, and call `painter.dispose()` ([grand_staff_layout.dart](../../lib/features/drill/ui/grand_staff_layout.dart)).
