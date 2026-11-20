# Score Parser Pitfalls

## `package:archive` `3.6.x` ZIP bounds and header traps

- **Symptom:** `ZipDecoder.decodeBytes` inflates ZIP bombs or symlinks without bounds and misses trailing EOCDR bytes or mismatched entry paths.
- **Root cause:** `ArchiveFile` rewrites `\`, `ZipFile.filename` reads central-directory `header.filename`, and `ZipDirectory._findEocdrSignature` ignores `commentLen`.
- **Fix:** Validate raw EOCDR ([MxlEocdrValidator](../../lib/features/catalog/data/mxl_eocdr_validator.dart)) and raw local filenames ([MxlEntryValidator](../../lib/features/catalog/data/mxl_entry_validator.dart)), then stream `Inflate.stream` into [BoundedZipOutputStream](../../lib/features/catalog/data/bounded_zip_stream.dart).

## `package:xml` `7.x` quadratic entity decode

- **Symptom:** Text nodes containing many unclosed `&` characters stall `XmlEntityMapping.decode`.
- **Root cause:** The default `XmlEntityMapping.decode` scans forward for `;` from each `&` in `O(n^2)` time.
- **Fix:** Override `decode` with single-pass bounded scanning in `O(n)` time ([StrictXmlEntityMapping](../../lib/features/catalog/data/strict_xml_entity_mapping.dart)).

## MusicXML 4.0 omitted `<alter>` defaults to natural

- **Symptom:** Notes without `<pitch><alter>` in non-C keys play the key-signature accidental instead of a natural.
- **Root cause:** MusicXML 4.0 defines omitted `<alter>` as `0` semitones (natural), independent of key signature.
- **Fix:** Default omitted `<alter>` to `writtenAccidental?.semitoneDelta ?? 0` ([musicxml_note_parser.dart](../../lib/features/catalog/data/musicxml_note_parser.dart)) and emit explicit `<alter>` when serializing ([musicxml_note_serializer.dart](../../lib/features/catalog/data/musicxml_note_serializer.dart)).

## Cross-barline tie continuations and intra-measure accidentals

- **Symptom:** A tied continuation across a barline alters later un-accidentaled notes at that pitch in the new measure.
- **Root cause:** Overwriting `activeAlterations` on every note applies tied-over pitches without a new attack or cautionary accidental.
- **Fix:** Update `activeAlterations` only when `tie.requiresAttack` is true or `writtenAccidental != null` ([ScoreTimelineReducer](../../lib/shared/music/score_timeline_reducer.dart)).
