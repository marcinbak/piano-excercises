import 'dart:typed_data';

import 'package:archive/archive.dart';
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
    if (bytes.length < 4 ||
        bytes.length > maxUncompressedBytes ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4B ||
        bytes[2] != 0x03 ||
        bytes[3] != 0x04) {
      throw const ScoreParseException(
        'Input is not a valid bounded .mxl ZIP archive.',
      );
    }

    final directory = _readDirectory(bytes);
    if (directory.fileHeaders.isEmpty ||
        directory.fileHeaders.length > maxEntries ||
        directory.totalCentralDirectoryEntries <= 0 ||
        directory.totalCentralDirectoryEntries > maxEntries) {
      throw ScoreParseException(
        'Archive entry count must be between 1 and $maxEntries.',
      );
    }

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
    final containerBytes = _decompressEntry(containerHeader, budget);
    final containerDoc = containerXmlLoader.parseBytes(containerBytes);
    final rootPath = _resolveRootfilePath(containerDoc);
    final targetHeader = headersByPath[rootPath];
    if (targetHeader == null) {
      throw const ScoreParseException(
        'MusicXML rootfile declared in container.xml is missing from archive.',
      );
    }
    return _decompressEntry(targetHeader, budget);
  }

  ZipDirectory _readDirectory(Uint8List bytes) {
    try {
      return ZipDirectory.read(InputStream(bytes));
    } on ArchiveException catch (error) {
      throw ScoreParseException('Invalid .mxl archive: ${error.message}');
    } on Object {
      throw const ScoreParseException('Invalid .mxl archive structure.');
    }
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

  Uint8List _decompressEntry(ZipFileHeader header, DecodeBudget budget) {
    final file = header.file!;
    final raw = file.rawContent!;
    final hasDescriptor = (file.flags & 0x08) != 0;
    final expectedCrc = hasDescriptor
        ? file.crc32
        : (header.crc32 ?? file.crc32);
    final expectedSize = hasDescriptor
        ? file.uncompressedSize!
        : header.uncompressedSize!;
    if (expectedCrc == null) {
      throw const ScoreParseException('Missing CRC-32 checksum in .mxl.');
    }

    final Uint8List out;
    if (header.compressionMethod == ZipFile.zipCompressionStore) {
      budget.consume(raw.length);
      out = Uint8List.fromList(raw.toUint8List());
    } else {
      final output = BoundedZipOutputStream(budget);
      try {
        Inflate.stream(InputStream(raw.toUint8List()), output);
      } on ScoreParseException {
        rethrow;
      } on Object {
        throw const ScoreParseException('Corrupt deflate stream in .mxl.');
      }
      out = output.takeBytes();
    }

    if (out.length != expectedSize) {
      throw const ScoreParseException(
        'Decompressed .mxl entry size does not match header.',
      );
    }
    if (getCrc32(out) != expectedCrc) {
      throw const ScoreParseException('CRC-32 mismatch in .mxl archive.');
    }
    return out;
  }
}
