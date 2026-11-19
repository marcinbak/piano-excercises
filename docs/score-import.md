# Score Import

## Runtime Policy (`D1`)

- Bundle zero `.mxl` or `.musicxml` score assets in the app binary (`pubspec.yaml` excludes score files).
- Import single `.mxl`/`.musicxml` files, multi-file picks, and `.zip` bundles at runtime via [FilePickerScoreImporter](../lib/features/catalog/data/file_picker_score_importer.dart), [ZipBundleScoreExtractor](../lib/features/catalog/data/zip_bundle_score_extractor.dart), and [ScoreParser](../lib/features/catalog/domain/score_parser.dart).
- Reject all network fetches, external DTD resolution, custom entities, ZIP64, encrypted entries, and ZIP symlinks during parsing.

## Offline PDF Conversion Pipeline

Convert printed sheet music offline before importing into the app:

`PDF -> Audiveris or homr -> MuseScore 4 cleanup -> .mxl export`

1. Run optical music recognition (`Audiveris` or `homr`) on clean PDF pages.
2. Open the recognized MusicXML in `MuseScore 4` to fix clefs, key signatures, voices, and ties.
3. Export as compressed MusicXML (`.mxl`) for runtime import.

## Multi-Difficulty `ScoreVariant` Authoring

Author each arrangement (`DifficultyTier` `1..5`) in `MuseScore 4` with identical top-level identification metadata:

| Tier | Label | Arrangement Scope |
|---|---|---|
| `1` | `Beginner` | Single-line melody or landmark bass notes with sparse rhythms |
| `2` | `Elementary` | Simple two-hand patterns in narrow positions |
| `3` | `Intermediate` | Standard accompaniment patterns and simple chords |
| `4` | `Advanced` | Multi-voice counterpoint and denser chords |
| `5` | `Original` | Unabridged score faithful to the published edition |

- Set identical `<work-title>` across every variant of the same piece.
- Set `<creator type="composer">` consistently so catalog grouping matches variants to one work.
- Set `<key><fifths>` and `<key><mode>` (`major` or `minor`) in measure 1.
- Include tier keywords (`beginner`/`easy`/`tier1`, `elementary`/`tier2`, `intermediate`/`tier3`, `advanced`/`tier4`, `original`/`tier5`) in folders, filenames, or titles for auto-detection in [inferDifficultyTier](../lib/features/catalog/domain/difficulty_tier_inference.dart).

## Parser & Bundle Limits

| Constraint | Limit | Enforced By |
|---|---|---|
| Single score byte cap | `10 MB` (`10,485,760` bytes) | [HardenedXmlLoader](../lib/features/catalog/data/hardened_xml_loader.dart), [MxlArchiveExtractor](../lib/features/catalog/data/mxl_archive_extractor.dart), [ZipBundleScoreExtractor](../lib/features/catalog/data/zip_bundle_score_extractor.dart) |
| `.mxl` container entries | `1..32` entries; `STORE` (`0`) or `DEFLATE` (`8`) only | [MxlArchiveExtractor](../lib/features/catalog/data/mxl_archive_extractor.dart), [MxlEocdrValidator](../lib/features/catalog/data/mxl_eocdr_validator.dart), [MxlEntryValidator](../lib/features/catalog/data/mxl_entry_validator.dart) |
| `.zip` bundle / multi-select cap | `50 MB` (`52,428,800` bytes) total/decompressed; `<= 500` entries/scores | [FilePickerScoreImporter](../lib/features/catalog/data/file_picker_score_importer.dart), [ZipBundleScoreExtractor](../lib/features/catalog/data/zip_bundle_score_extractor.dart), [BoundedZipOutputStream](../lib/features/catalog/data/bounded_zip_stream.dart) |
| XML elements | `50,000` elements max; `32` attributes/element max | [HardenedXmlLoader](../lib/features/catalog/data/hardened_xml_loader.dart) |
| XML nesting depth | `64` levels max (iterative parser stack) | [HardenedXmlLoader](../lib/features/catalog/data/hardened_xml_loader.dart) |
| Score layout | `<score-partwise>` only; `1..2` parts; staves `1..2`; `1..2000` bars | [MusicXmlScoreParser](../lib/features/catalog/data/musicxml_score_parser.dart) |
| Pitch alterations | Integer `<alter>` `-2..+2` (`doubleFlat..doubleSharp`); no microtones | [musicxml_pitch_tie_parser.dart](../lib/features/catalog/data/musicxml_pitch_tie_parser.dart) |

## Bulk `.zip` Bundle & Batch Behavior

- **OS metadata:** [ZipBundleScoreExtractor](../lib/features/catalog/data/zip_bundle_score_extractor.dart) skips directories, `__MACOSX`, `.DS_Store`, `Thumbs.db`, `desktop.ini`, `.*`, and `._*`.
- **Companion files:** Non-score entries increment `ignoredNonScoreCount` without decompression.
- **Per-entry isolation:** Nested `.zip` archives and malformed scores record per-entry failures without aborting valid scores.
- **Planning & deduplication:** [CatalogBatchImportPlanner](../lib/features/catalog/domain/catalog_batch_import_planner.dart) groups by normalized `(title, artist)`, skips duplicate bytes (FNV-1a), and disambiguates colliding names.
- **Atomic commit:** [CatalogImportCoordinator](../lib/features/catalog/domain/catalog_import_coordinator.dart) and [CatalogRepository.applyBatch](../lib/features/catalog/domain/catalog_repository.dart) commit in one transaction and unlink files on error.
