import 'dart:typed_data';

import 'package:piano_exercises/features/catalog/data/bounded_zip_stream.dart';
import 'package:piano_exercises/features/catalog/data/hardened_xml_loader.dart';
import 'package:piano_exercises/features/catalog/data/mxl_entry_validator.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:xml/xml.dart';

/// Extracts MusicXML rootfile bytes from compressed `.mxl` ZIP containers.
final class MxlArchiveExtractor {
  const MxlArchiveExtractor({
    this.maxUncompressedBytes = defaultMaxUncompressedBytes,
    this.maxEntries = defaultMaxEntries,
    this.containerXmlLoader = const HardenedXmlLoader(
      allowMusicXmlDoctype: false,
    ),
  });

  static const int defaultMaxUncompressedBytes = 10 * 1024 * 1024;
  static const int defaultMaxEntries = 32;

  static const String _containerPath = 'META-INF/container.xml';
  static const Set<String> _allowedMediaTypes = <String>{
    '',
    'application/vnd.recordare.musicxml+xml',
    'application/vnd.recordare.musicxml',
    'text/xml',
  };

  final int maxUncompressedBytes;
  final int maxEntries;
  final HardenedXmlLoader containerXmlLoader;

  /// Validates archive headers, reads `META-INF/container.xml`, and extracts score XML.
  Uint8List extractMusicXmlBytes(Uint8List bytes) {
    final directory = readBoundedZipDirectory(
      bytes,
      maxArchiveBytes: maxUncompressedBytes,
      maxEntries: maxEntries,
    );
    final headersByPath = MxlEntryValidator.validateAllHeaders(
      bytes,
      directory.fileHeaders,
      maxUncompressedBytes: maxUncompressedBytes,
    );
    final containerHeader = headersByPath[_containerPath];
    if (containerHeader == null) {
      throw const ScoreParseException(
        'Missing META-INF/container.xml in .mxl archive.',
      );
    }

    final budget = DecodeBudget(maxUncompressedBytes);
    final containerBytes = decompressBoundedZipEntry(containerHeader, budget);
    final containerDoc = containerXmlLoader.parseBytes(containerBytes);
    final rootPath = _resolveRootfilePath(containerDoc);
    final targetHeader = headersByPath[rootPath];
    if (targetHeader == null) {
      throw const ScoreParseException(
        'MusicXML rootfile declared in container.xml is missing from archive.',
      );
    }
    return decompressBoundedZipEntry(targetHeader, budget);
  }

  String _resolveRootfilePath(XmlDocument containerDoc) {
    if (containerDoc.rootElement.name.local != 'container') {
      throw const ScoreParseException(
        'Invalid META-INF/container.xml root element.',
      );
    }
    String? candidatePath;
    for (final element in containerDoc.findAllElements('rootfile')) {
      final mediaType = element.getAttribute('media-type')?.trim();
      if (mediaType == 'application/vnd.recordare.musicxml+zip') {
        throw const ScoreParseException(
          'Nested .mxl archive rootfiles are not supported.',
        );
      }
      if (mediaType == null || _allowedMediaTypes.contains(mediaType)) {
        candidatePath = element.getAttribute('full-path');
        break;
      }
    }
    if (candidatePath == null || candidatePath == _containerPath) {
      throw const ScoreParseException(
        'No valid MusicXML rootfile found in META-INF/container.xml.',
      );
    }
    MxlEntryValidator.validateArchivePath(
      candidatePath,
      allowDirectorySlash: false,
    );
    return candidatePath;
  }
}
