# Catalog & SQLite Pitfalls

## Stock Android SQLite omits FTS5 while FFI omits FTS4

- **Symptom:** `CREATE VIRTUAL TABLE ... USING fts5` fails with `no such module: fts5` on stock Android, whereas `sqflite_common_ffi` lacks `fts4`.
- **Root cause:** Stock Android `android.database.sqlite` disables `ENABLE_FTS5`, `sqlite3` `3.9.x` omits `fts4`, and prefix syntax differs (`"tok"*` vs `"tok*"`).
- **Fix:** Create `fts5` first with `fts4` fallback in [sqlite_catalog_schema.dart](../../lib/features/catalog/data/sqlite_catalog_schema.dart) and switch query syntax in [CatalogSearchNormalizer](../../lib/features/catalog/domain/catalog_search_normalizer.dart).

## Per-connection `foreign_keys` reset and fallback orphan purge

- **Symptom:** Deleting a piece leaves orphan `score_variants` rows, or a transient DB open failure wipes stored score files at startup.
- **Root cause:** SQLite resets `PRAGMA foreign_keys` to `OFF` per connection, and `InMemoryCatalogRepository` returns an empty path set.
- **Fix:** Run `PRAGMA foreign_keys = ON;` in `onConfigure` ([sqlite_catalog_schema.dart](../../lib/features/catalog/data/sqlite_catalog_schema.dart)) and skip `purgeOrphans` on fallback ([app.dart](../../lib/app/app.dart)).

## Native file pickers grey out `.mxl` under `FileType.custom`

- **Symptom:** Android and iOS system file pickers disable `.mxl` files when filtered by custom extensions.
- **Root cause:** Android `DocumentsUI` and iOS `UTType` lack built-in `.mxl` MIME mappings; `file_picker` `13.4.0` `pickFiles` returns `List<PlatformFile>` directly without `allowMultiple`.
- **Fix:** Call `FilePicker.pickFiles(type: FileType.any)`, validate `.mxl`/`.musicxml`/`.zip` suffixes, and stream-cap `10 MB` per score / `50 MB` per bundle in [FilePickerScoreImporter](../../lib/features/catalog/data/file_picker_score_importer.dart).

## `Isolate.run` breaks `FakeAsync` tests and non-sendable parser doubles

- **Symptom:** Wrapping batch score extraction or parsing in `Isolate.run` stalls `FakeAsync` widget tests and fails on test doubles.
- **Root cause:** `Isolate.run` leaves the `FakeAsync` zone and rejects closures or non-sendable `ScoreParser` fakes.
- **Fix:** Parse on the main isolate and yield `Future<void>.delayed(Duration.zero)` every `8` entries in [FilePickerScoreImporter](../../lib/features/catalog/data/file_picker_score_importer.dart) and [ZipBundleScoreExtractor](../../lib/features/catalog/data/zip_bundle_score_extractor.dart).
