import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Pre-decompression validator for `.mxl` ZIP headers and archive paths.
abstract final class MxlEntryValidator {
  /// Validates every central and local ZIP header prior to decompression.
  static Map<String, ZipFileHeader> validateAllHeaders(
    Uint8List bytes,
    List<ZipFileHeader> headers, {
    required int maxUncompressedBytes,
    int? maxSingleEntryBytes,
  }) {
    final headersByPath = <String, ZipFileHeader>{};
    var cumulativeDeclaredUncompressed = 0;
    final singleLimit = maxSingleEntryBytes ?? maxUncompressedBytes;

    for (final header in headers) {
      final file = header.file;
      if (file == null) {
        throw const ScoreParseException('Missing local file header in .mxl.');
      }
      _validateEntryPaths(bytes, header, file);
      if (headersByPath.containsKey(header.filename)) {
        throw ScoreParseException(
          'Duplicate archive entry: ${header.filename}.',
        );
      }
      _validateFlagsAndSizes(
        header,
        file,
        maxCompressedBytes: maxUncompressedBytes,
        maxSingleUncompressedBytes: singleLimit,
      );
      final declared = math.max(
        header.uncompressedSize!,
        file.uncompressedSize!,
      );
      cumulativeDeclaredUncompressed += declared;
      if (cumulativeDeclaredUncompressed > maxUncompressedBytes) {
        throw const ScoreParseException(
          'Archive declared uncompressed size exceeds limit.',
        );
      }
      headersByPath[header.filename] = header;
    }
    return headersByPath;
  }

  /// Validates an archive entry or `container.xml` `full-path` value.
  static void validateArchivePath(
    String path, {
    required bool allowDirectorySlash,
  }) {
    if (path.isEmpty || path.length > 255) {
      throw const ScoreParseException('Invalid archive entry path length.');
    }
    for (var i = 0; i < path.length; i += 1) {
      final code = path.codeUnitAt(i);
      if (code <= 0x1F || code == 0x7F) {
        throw const ScoreParseException('Control character in archive path.');
      }
    }
    if (path.startsWith('/') ||
        path.contains(r'\') ||
        path.contains(':') ||
        path.contains('//')) {
      throw ScoreParseException('Unsafe archive entry path: $path');
    }
    if (!allowDirectorySlash && path.endsWith('/')) {
      throw ScoreParseException('Directory path used as score target: $path');
    }
    final normalized = (allowDirectorySlash && path.endsWith('/'))
        ? path.substring(0, path.length - 1)
        : path;
    if (normalized.isEmpty) {
      throw const ScoreParseException('Empty archive entry path.');
    }
    for (final segment in normalized.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        throw ScoreParseException('Unsafe path segment in archive: $path');
      }
    }
  }

  static void _validateEntryPaths(
    Uint8List bytes,
    ZipFileHeader header,
    ZipFile file,
  ) {
    final allowDir =
        header.filename.endsWith('/') && (header.uncompressedSize ?? 0) == 0;
    validateArchivePath(header.filename, allowDirectorySlash: allowDir);
    validateArchivePath(file.filename, allowDirectorySlash: allowDir);
    if (header.filename != file.filename) {
      throw const ScoreParseException(
        'ZIP local and central directory filenames do not match.',
      );
    }
    final localFilename = _readRawLocalFilename(bytes, header);
    validateArchivePath(localFilename, allowDirectorySlash: allowDir);
    if (localFilename != header.filename) {
      throw const ScoreParseException(
        'ZIP raw local filename does not match central directory.',
      );
    }
  }

  static String _readRawLocalFilename(Uint8List bytes, ZipFileHeader header) {
    final offset = header.localHeaderOffset;
    if (offset == null || offset < 0 || offset + 30 > bytes.length) {
      throw const ScoreParseException('Invalid ZIP local header offset.');
    }
    final fnLen = bytes[offset + 26] | (bytes[offset + 27] << 8);
    if (offset + 30 + fnLen > bytes.length) {
      throw const ScoreParseException('Truncated ZIP local filename.');
    }
    final nameBytes = Uint8List.sublistView(
      bytes,
      offset + 30,
      offset + 30 + fnLen,
    );
    try {
      return utf8.decode(nameBytes);
    } on FormatException {
      return String.fromCharCodes(nameBytes);
    }
  }

  static void _validateFlagsAndSizes(
    ZipFileHeader header,
    ZipFile file, {
    required int maxCompressedBytes,
    required int maxSingleUncompressedBytes,
  }) {
    final externalAttrs = header.externalFileAttributes ?? 0;
    if (((externalAttrs >> 16) & 0xF000) == 0xA000) {
      throw const ScoreParseException(
        'UNIX symlink entries are not permitted in .mxl archives.',
      );
    }
    if ((header.generalPurposeBitFlag & 0x1) != 0 ||
        (file.flags & 0x1) != 0 ||
        header.compressionMethod == ZipFile.zipCompressionAexEncryption ||
        file.compressionMethod == ZipFile.zipCompressionAexEncryption) {
      throw const ScoreParseException(
        'Encrypted entries are not permitted in .mxl archives.',
      );
    }
    final method = header.compressionMethod;
    if ((method != ZipFile.zipCompressionStore &&
            method != ZipFile.zipCompressionDeflate) ||
        file.compressionMethod != method) {
      throw ScoreParseException('Unsupported ZIP compression method: $method.');
    }
    final hComp = header.compressedSize;
    final hUncomp = header.uncompressedSize;
    final fComp = file.compressedSize;
    final fUncomp = file.uncompressedSize;
    final raw = file.rawContent;
    if (hComp == null ||
        hUncomp == null ||
        fComp == null ||
        fUncomp == null ||
        hComp < 0 ||
        hUncomp < 0 ||
        fComp < 0 ||
        fUncomp < 0 ||
        hComp > maxCompressedBytes ||
        hUncomp > maxSingleUncompressedBytes ||
        fComp > maxCompressedBytes ||
        fUncomp > maxSingleUncompressedBytes ||
        raw == null ||
        raw.length != fComp) {
      throw const ScoreParseException(
        'Invalid or oversized entry bounds in .mxl archive.',
      );
    }
  }
}
