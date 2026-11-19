import 'package:piano_exercises/shared/music/music.dart';

/// SQLite full-text virtual-table dialect supported on the current device.
enum FtsDialect { fts5, fts4 }

/// Diacritic-folding and accidental-aware text normalizer for catalog search.
abstract final class CatalogSearchNormalizer {
  static final RegExp _controlChars = RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]',
  );
  static final RegExp _letterSharp = RegExp(r'([A-Ga-g])#');
  static final RegExp _combiningMarks = RegExp(
    r'[\u0300-\u036F\u1AB0-\u1AFF\u1DC0-\u1DFF\u20D0-\u20FF\uFE20-\uFE2F]',
  );
  static final RegExp _nonAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final RegExp _whitespace = RegExp(r'\s+');

  static const Map<int, String> _latinFoldByRune = <int, String>{
    0x00E0: 'a',
    0x00E1: 'a',
    0x00E2: 'a',
    0x00E3: 'a',
    0x00E4: 'a',
    0x00E5: 'a',
    0x0101: 'a',
    0x0103: 'a',
    0x0105: 'a',
    0x00E6: 'ae',
    0x00E7: 'c',
    0x0107: 'c',
    0x0109: 'c',
    0x010B: 'c',
    0x010D: 'c',
    0x010F: 'd',
    0x0111: 'd',
    0x00F0: 'd',
    0x00E8: 'e',
    0x00E9: 'e',
    0x00EA: 'e',
    0x00EB: 'e',
    0x0113: 'e',
    0x0115: 'e',
    0x0117: 'e',
    0x0119: 'e',
    0x011B: 'e',
    0x011D: 'g',
    0x011F: 'g',
    0x0121: 'g',
    0x0123: 'g',
    0x0125: 'h',
    0x0127: 'h',
    0x00EC: 'i',
    0x00ED: 'i',
    0x00EE: 'i',
    0x00EF: 'i',
    0x0129: 'i',
    0x012B: 'i',
    0x012D: 'i',
    0x012F: 'i',
    0x0131: 'i',
    0x0135: 'j',
    0x0137: 'k',
    0x013A: 'l',
    0x013C: 'l',
    0x013E: 'l',
    0x0140: 'l',
    0x0142: 'l',
    0x00F1: 'n',
    0x0144: 'n',
    0x0146: 'n',
    0x0148: 'n',
    0x00F2: 'o',
    0x00F3: 'o',
    0x00F4: 'o',
    0x00F5: 'o',
    0x00F6: 'o',
    0x00F8: 'o',
    0x014D: 'o',
    0x014F: 'o',
    0x0151: 'o',
    0x0153: 'oe',
    0x0155: 'r',
    0x0157: 'r',
    0x0159: 'r',
    0x015B: 's',
    0x015D: 's',
    0x015F: 's',
    0x0161: 's',
    0x00DF: 'ss',
    0x1E9E: 'ss',
    0x0165: 't',
    0x0167: 't',
    0x00FE: 'th',
    0x00F9: 'u',
    0x00FA: 'u',
    0x00FB: 'u',
    0x00FC: 'u',
    0x0169: 'u',
    0x016B: 'u',
    0x016D: 'u',
    0x016F: 'u',
    0x0171: 'u',
    0x0173: 'u',
    0x0175: 'w',
    0x00FD: 'y',
    0x00FF: 'y',
    0x0177: 'y',
    0x017A: 'z',
    0x017C: 'z',
    0x017E: 'z',
  };

  /// Folds musical accidentals, Latin diacritics, and punctuation to ASCII-friendly tokens.
  static String normalizeText(String input) {
    if (input.isEmpty) {
      return '';
    }
    var text = input.replaceAll(_controlChars, '');
    // Preserve sharp/flat semantics before punctuation stripping turns `#` into a space.
    text = text.replaceAll('\u266F', '#').replaceAll('\u266D', 'b');
    text = text.replaceAllMapped(_letterSharp, (m) => '${m[1]}sharp');
    text = text.replaceAll('#', ' sharp ');
    text = text.toLowerCase().replaceAll(_combiningMarks, '');

    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final folded = _latinFoldByRune[rune];
      if (folded != null) {
        buffer.write(folded);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer
        .toString()
        .replaceAll(_nonAlnum, ' ')
        .replaceAll(_whitespace, ' ')
        .trim();
  }

  /// Splits normalized [input] into up to [maxTokens] non-empty search tokens.
  static List<String> tokenize(String input, {int maxTokens = 16}) {
    if (maxTokens <= 0) {
      return const <String>[];
    }
    final normalized = normalizeText(input);
    if (normalized.isEmpty) {
      return const <String>[];
    }
    final tokens = <String>[];
    for (final part in normalized.split(' ')) {
      if (part.isEmpty) {
        continue;
      }
      tokens.add(part);
      if (tokens.length >= maxTokens) {
        break;
      }
    }
    return List<String>.unmodifiable(tokens);
  }

  /// Builds the normalized FTS document string for a piece and its attached files.
  static String buildDocumentIndex({
    required String title,
    required String artist,
    required Scale scale,
    required Iterable<String> fileNames,
  }) {
    final segments = <String>[title, artist, scale.label];
    for (final fileName in fileNames) {
      segments.add(fileName);
      final dotIndex = fileName.lastIndexOf('.');
      if (dotIndex > 0) {
        segments.add(fileName.substring(0, dotIndex));
      }
    }
    final tokens = <String>{};
    for (final segment in segments) {
      final normalized = normalizeText(segment);
      if (normalized.isEmpty) {
        continue;
      }
      for (final token in normalized.split(' ')) {
        if (token.isNotEmpty) {
          tokens.add(token);
        }
      }
    }
    return tokens.join(' ');
  }

  /// Builds an injection-safe FTS prefix-match query, or `null` if no tokens exist.
  static String? buildFtsMatchQuery(
    String userSearchText, {
    FtsDialect dialect = FtsDialect.fts5,
  }) {
    final tokens = tokenize(userSearchText);
    final sanitized = <String>[];
    for (final token in tokens) {
      final clean = token.replaceAll('"', '').replaceAll('*', '');
      if (clean.isNotEmpty) {
        sanitized.add(clean);
      }
    }
    if (sanitized.isEmpty) {
      return null;
    }
    return switch (dialect) {
      FtsDialect.fts5 => sanitized.map((t) => '"$t"*').join(' '),
      FtsDialect.fts4 => sanitized.map((t) => '"$t*"').join(' '),
    };
  }
}
