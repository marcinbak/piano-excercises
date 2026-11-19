import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:piano_exercises/features/catalog/data/mxl_eocdr_validator.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Shared remaining-byte allowance enforced across all decompressed ZIP entries.
final class DecodeBudget {
  DecodeBudget(
    this.remainingBytes, {
    this.errorMessage =
        'Decompressed .mxl content exceeds maximum uncompressed byte limit.',
  });

  int remainingBytes;
  final String errorMessage;
  bool exceeded = false;

  void consume(int byteCount) {
    if (byteCount < 0) {
      throw ScoreParseException(errorMessage);
    }
    if (byteCount > remainingBytes) {
      exceeded = true;
      throw ScoreParseException(errorMessage);
    }
    remainingBytes -= byteCount;
  }
}

/// Validates ZIP outer signature, EOCDR bounds, and entry count before reading central directory.
ZipDirectory readBoundedZipDirectory(
  Uint8List bytes, {
  required int maxArchiveBytes,
  required int maxEntries,
}) {
  if (bytes.length < 4 ||
      bytes.length > maxArchiveBytes ||
      bytes[0] != 0x50 ||
      bytes[1] != 0x4B ||
      bytes[2] != 0x03 ||
      bytes[3] != 0x04) {
    throw const ScoreParseException(
      'Input is not a valid bounded .mxl ZIP archive.',
    );
  }
  MxlEocdrValidator.validate(bytes, maxEntries: maxEntries);
  final ZipDirectory directory;
  try {
    directory = ZipDirectory.read(InputStream(bytes));
  } on ArchiveException catch (error) {
    throw ScoreParseException('Invalid ZIP archive: ${error.message}');
  } on Object {
    throw const ScoreParseException('Invalid ZIP archive structure.');
  }
  if (directory.fileHeaders.isEmpty ||
      directory.fileHeaders.length > maxEntries ||
      directory.totalCentralDirectoryEntries <= 0 ||
      directory.totalCentralDirectoryEntries > maxEntries) {
    throw ScoreParseException(
      'Archive entry count must be between 1 and $maxEntries.',
    );
  }
  return directory;
}

/// Decompresses a single validated ZIP entry within [budget] and optional [maxEntryBytes] and verifies CRC-32.
Uint8List decompressBoundedZipEntry(
  ZipFileHeader header,
  DecodeBudget budget, {
  int? maxEntryBytes,
}) {
  final file = header.file;
  final raw = file?.rawContent;
  if (file == null || raw == null) {
    throw const ScoreParseException('Missing ZIP entry payload.');
  }
  final hasDescriptor = (file.flags & 0x08) != 0;
  final expectedCrc = hasDescriptor ? file.crc32 : (header.crc32 ?? file.crc32);
  final expectedSize = hasDescriptor
      ? file.uncompressedSize
      : header.uncompressedSize;
  if (expectedCrc == null || expectedSize == null) {
    throw const ScoreParseException('Missing CRC-32 checksum in ZIP entry.');
  }
  if (maxEntryBytes != null && expectedSize > maxEntryBytes) {
    throw const ScoreParseException(
      'ZIP entry declared size exceeds single-entry byte limit.',
    );
  }

  final out = _decodeEntryPayload(
    header: header,
    raw: raw,
    budget: budget,
    maxEntryBytes: maxEntryBytes,
  );
  if (out.length != expectedSize) {
    throw const ScoreParseException(
      'Decompressed ZIP entry size does not match header.',
    );
  }
  if (getCrc32(out) != expectedCrc) {
    throw const ScoreParseException('CRC-32 mismatch in ZIP archive.');
  }
  return out;
}

Uint8List _decodeEntryPayload({
  required ZipFileHeader header,
  required InputStreamBase raw,
  required DecodeBudget budget,
  required int? maxEntryBytes,
}) {
  if (header.compressionMethod == ZipFile.zipCompressionStore) {
    if (maxEntryBytes != null && raw.length > maxEntryBytes) {
      throw const ScoreParseException(
        'ZIP entry exceeds single-entry byte limit.',
      );
    }
    budget.consume(raw.length);
    return Uint8List.fromList(raw.toUint8List());
  }
  final output = BoundedZipOutputStream(budget, maxEntryBytes: maxEntryBytes);
  try {
    Inflate.stream(InputStream(raw.toUint8List()), output);
  } on ScoreParseException {
    rethrow;
  } on Object {
    throw const ScoreParseException('Corrupt deflate stream in ZIP entry.');
  }
  return output.takeBytes();
}

/// Bounded [OutputStreamBase] that checks [DecodeBudget] and optional per-entry limit before every growth.
final class BoundedZipOutputStream extends OutputStreamBase {
  BoundedZipOutputStream(this._budget, {this.maxEntryBytes});

  final DecodeBudget _budget;
  final int? maxEntryBytes;
  Uint8List _buffer = Uint8List(0);
  int _length = 0;

  @override
  int get length => _length;

  @override
  void flush() {}

  Uint8List takeBytes() => Uint8List.sublistView(_buffer, 0, _length);

  List<int> subset(int start, [int? end]) {
    final s = start < 0 ? _length + start : start;
    final e = end == null ? _length : (end < 0 ? _length + end : end);
    if (s < 0 || e < s || e > _length) {
      throw const ScoreParseException(
        'Corrupt deflate back-reference in ZIP entry.',
      );
    }
    return Uint8List.view(_buffer.buffer, _buffer.offsetInBytes + s, e - s);
  }

  @override
  void writeByte(int value) {
    _ensureCapacity(1);
    _buffer[_length++] = value & 0xFF;
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    final count = len ?? bytes.length;
    if (count <= 0) {
      return;
    }
    _ensureCapacity(count);
    for (var i = 0; i < count; i += 1) {
      _buffer[_length + i] = bytes[i];
    }
    _length += count;
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    final count = stream.length;
    if (count <= 0) {
      return;
    }
    _ensureCapacity(count);
    final data = stream.toUint8List();
    _buffer.setRange(_length, _length + count, data, 0);
    _length += count;
  }

  void _ensureCapacity(int additional) {
    if (additional < 0) {
      throw const ScoreParseException('Invalid negative ZIP write size.');
    }
    if (maxEntryBytes != null && _length + additional > maxEntryBytes!) {
      throw const ScoreParseException(
        'Decompressed ZIP entry exceeds maximum single-entry byte limit.',
      );
    }
    _budget.consume(additional);
    final required = _length + additional;
    if (required <= _buffer.length) {
      return;
    }
    var nextCapacity = _buffer.isEmpty ? 4096 : _buffer.length * 2;
    if (nextCapacity < required) {
      nextCapacity = required;
    }
    var maxAllowed = _length + additional + _budget.remainingBytes;
    if (maxEntryBytes != null && maxEntryBytes! < maxAllowed) {
      maxAllowed = maxEntryBytes!;
    }
    if (nextCapacity > maxAllowed) {
      nextCapacity = maxAllowed;
    }
    final nextBuffer = Uint8List(nextCapacity);
    if (_length > 0) {
      nextBuffer.setRange(0, _length, _buffer, 0);
    }
    _buffer = nextBuffer;
  }

  @override
  void writeUint16(int value) => throw UnsupportedError('writeUint16');

  @override
  void writeUint32(int value) => throw UnsupportedError('writeUint32');

  @override
  void writeUint64(int value) => throw UnsupportedError('writeUint64');
}
