# Score Import

## Runtime Policy (`D1`)

- Bundle zero `.mxl` or `.musicxml` score assets in the app binary (`pubspec.yaml` excludes score files).
- Import user-selected `.mxl` and `.musicxml` files at runtime through [ScoreParser](../lib/features/catalog/domain/score_parser.dart).
- Reject all network fetches, external DTD resolution, custom entities, and ZIP symlinks during parsing.

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
| `2` | `Easy` | Simple two-hand patterns in narrow positions |
| `3` | `Intermediate` | Standard accompaniment patterns and simple chords |
| `4` | `Advanced` | Multi-voice counterpoint and denser chords |
| `5` | `Original` | Unabridged score faithful to the published edition |

- Set identical `<work-title>` across every variant of the same piece.
- Set `<creator type="composer">` consistently so catalog grouping matches variants to one work.
- Set `<key><fifths>` and `<key><mode>` (`major` or `minor`) in measure 1.

## Parser Limits & Support

| Constraint | Limit | Enforced By |
|---|---|---|
| Uncompressed byte cap | `10 MB` (`10,485,760` bytes) | [HardenedXmlLoader](../lib/features/catalog/data/hardened_xml_loader.dart), [MxlArchiveExtractor](../lib/features/catalog/data/mxl_archive_extractor.dart) |
| ZIP archive entries | `1..32` entries; `STORE` (`0`) or `DEFLATE` (`8`) only | [MxlArchiveExtractor](../lib/features/catalog/data/mxl_archive_extractor.dart) |
| XML elements | `50,000` elements max; `32` attributes/element max | [HardenedXmlLoader](../lib/features/catalog/data/hardened_xml_loader.dart) |
| XML nesting depth | `64` levels max (iterative parser stack) | [HardenedXmlLoader](../lib/features/catalog/data/hardened_xml_loader.dart) |
| Score layout | `<score-partwise>` only; `1..2` parts; staves `1..2`; `1..2000` bars | [MusicXmlScoreParser](../lib/features/catalog/data/musicxml_score_parser.dart) |
| Pitch alterations | Integer `<alter>` `-2..+2` (`doubleFlat..doubleSharp`); no microtones | [musicxml_pitch_tie_parser.dart](../lib/features/catalog/data/musicxml_pitch_tie_parser.dart) |
