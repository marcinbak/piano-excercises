import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Pre-decompression validator for `.mxl` ZIP headers and archive paths.
abstract final class MxlEntryValidator {
  /// Bounds-checks the raw ZIP EOCDR before [ZipDirectory.read] parses entries.
  static void validateCentralDirectoryBounds(
    Uint8List bytes, {
    required int maxEntries,
  }) {
    if (bytes.length < 22) {
      throw const ScoreParseException('Truncated .mxl ZIP archive.');
    }
    final minOffset = math.max(0, bytes.length - 65557);
    var eocdrPos = -1;
    for (var pos = bytes.length - 22; pos >= minOffset; pos -= 1) {
      if (bytes[pos] == 0x50 &&
          bytes[pos + 1] == 0x4B &&
          bytes[pos + 2] == 0x05 &&
          bytes[pos + 3] == 0x06) {
        final commentLen = _readUint16Le(bytes, pos + 20);
        if (commentLen == bytes.length - (pos + 22)) {
          eocdrPos = pos;
          break;
        }
      }
    }
    if (eocdrPos < 0) {
      throw const ScoreParseException(
        'Missing ZIP End of Central Directory Record.',
      );
    }
    if (eocdrPos >= 20 &&
        bytes[eocdrPos - 20] == 0x50 &&
        bytes[eocdrPos - 19] == 0x4B &&
        bytes[eocdrPos - 18] == 0x06 &&
        bytes[eocdrPos - 17] == 0x07) {
      throw const ScoreParseException('ZIP64 archives are not supported.');
    }
    final diskNum = _readUint16Le(bytes, eocdrPos + 4);
    final cdStartDisk = _readUint16Le(bytes, eocdrPos + 6);
    final diskEntries = _readUint16Le(bytes, eocdrPos + 8);
    final totalEntries = _readUint16Le(bytes, eocdrPos + 10);
    final cdSize = _readUint32Le(bytes, eocdrPos + 12);
    final cdOffset = _readUint32Le(bytes, eocdrPos + 16);
    if (diskNum == 0xFFFF ||
        cdStartDisk == 0xFFFF ||
        diskEntries == 0xFFFF ||
        totalEntries == 0xFFFF ||
        cdSize == 0xFFFFFFFF ||
        cdOffset == 0xFFFFFFFF) {
      throw const ScoreParseException('ZIP64 archives are not supported.');
    }
    if (diskNum != 0 ||
        cdStartDisk != 0 ||
        totalEntries < 1 ||
        totalEntries > maxEntries ||
        diskEntries != totalEntries) {
      throw ScoreParseException(
        'Archive entry count must be between 1 and $maxEntries.',
      );
    }
    if (cdSize > maxEntries * 1024 || cdOffset + cdSize > eocdrPos) {
      throw const ScoreParseException(
        'ZIP central directory size exceeds bounded archive limits.',
      );
    }
  }

  static int _readUint16Le(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _readUint32Le(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  /// Validates every central and local ZIP header prior to decompression.
  static Map<String, ZipFileHeader> validateAllHeaders(
    Uint8List bytes,
    List<ZipFileHeader> headers, {
    required int maxUncompressedBytes,
  }) {
    final headersByPath = <String, ZipFileHeader>{};
    var cumulativeDeclaredUncompressed = 0;

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
        maxUncompressedBytes: maxUncompressedBytes,
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
    required int maxUncompressedBytes,
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
        hComp > maxUncompressedBytes ||
        hUncomp > maxUncompressedBytes ||
        fComp > maxUncompressedBytes ||
        fUncomp > maxUncompressedBytes ||
        raw == null ||
        raw.length != fComp) {
      throw const ScoreParseException(
        'Invalid or oversized entry bounds in .mxl archive.',
      );
    }
  }
}
