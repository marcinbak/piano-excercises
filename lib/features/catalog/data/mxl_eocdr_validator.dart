import 'dart:math' as math;
import 'dart:typed_data';

import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Bounds-checks raw ZIP EOCDR headers before `ZipDirectory.read` runs.
abstract final class MxlEocdrValidator {
  /// Validates EOCDR signature, ZIP64 absence, and entry/directory bounds.
  static void validate(
    Uint8List bytes, {
    required int maxEntries,
    void Function(String message)? onEntryLimitExceeded,
  }) {
    if (bytes.length < 22) {
      throw const ScoreParseException('Truncated .mxl ZIP archive.');
    }
    final eocdrPos = _findLastEocdrSignature(bytes);
    _rejectZip64Sentinels(bytes, eocdrPos);
    _validateEntryAndDirectoryBounds(
      bytes,
      eocdrPos,
      maxEntries: maxEntries,
      onEntryLimitExceeded: onEntryLimitExceeded,
    );
  }

  static int _findLastEocdrSignature(Uint8List bytes) {
    final minOffset = math.max(0, bytes.length - 65557);
    for (var pos = bytes.length - 22; pos >= minOffset; pos -= 1) {
      if (bytes[pos] == 0x50 &&
          bytes[pos + 1] == 0x4B &&
          bytes[pos + 2] == 0x05 &&
          bytes[pos + 3] == 0x06) {
        final commentLen = _readUint16Le(bytes, pos + 20);
        if (commentLen != bytes.length - (pos + 22)) {
          throw const ScoreParseException(
            'Invalid ZIP EOCDR comment length or trailing signature.',
          );
        }
        return pos;
      }
    }
    throw const ScoreParseException(
      'Missing ZIP End of Central Directory Record.',
    );
  }

  static void _rejectZip64Sentinels(Uint8List bytes, int eocdrPos) {
    if (eocdrPos >= 20 &&
        bytes[eocdrPos - 20] == 0x50 &&
        bytes[eocdrPos - 19] == 0x4B &&
        bytes[eocdrPos - 18] == 0x06 &&
        bytes[eocdrPos - 17] == 0x07) {
      throw const ScoreParseException('ZIP64 archives are not supported.');
    }
    final hasSentinel16 =
        _readUint16Le(bytes, eocdrPos + 4) == 0xFFFF ||
        _readUint16Le(bytes, eocdrPos + 6) == 0xFFFF ||
        _readUint16Le(bytes, eocdrPos + 8) == 0xFFFF ||
        _readUint16Le(bytes, eocdrPos + 10) == 0xFFFF;
    final hasSentinel32 =
        _readUint32Le(bytes, eocdrPos + 12) == 0xFFFFFFFF ||
        _readUint32Le(bytes, eocdrPos + 16) == 0xFFFFFFFF;
    if (hasSentinel16 || hasSentinel32) {
      throw const ScoreParseException('ZIP64 archives are not supported.');
    }
  }

  static void _validateEntryAndDirectoryBounds(
    Uint8List bytes,
    int eocdrPos, {
    required int maxEntries,
    void Function(String message)? onEntryLimitExceeded,
  }) {
    final diskNum = _readUint16Le(bytes, eocdrPos + 4);
    final cdStartDisk = _readUint16Le(bytes, eocdrPos + 6);
    final diskEntries = _readUint16Le(bytes, eocdrPos + 8);
    final totalEntries = _readUint16Le(bytes, eocdrPos + 10);
    final cdSize = _readUint32Le(bytes, eocdrPos + 12);
    final cdOffset = _readUint32Le(bytes, eocdrPos + 16);

    if (diskNum != 0 ||
        cdStartDisk != 0 ||
        totalEntries < 1 ||
        diskEntries != totalEntries) {
      throw ScoreParseException(
        'Archive entry count must be between 1 and $maxEntries.',
      );
    }
    if (totalEntries > maxEntries) {
      final msg = 'Archive entry count must be between 1 and $maxEntries.';
      onEntryLimitExceeded?.call(msg);
      throw ScoreParseException(msg);
    }
    if (cdOffset + cdSize > eocdrPos) {
      throw const ScoreParseException(
        'ZIP central directory size exceeds bounded archive limits.',
      );
    }
    if (cdSize > maxEntries * 1024) {
      const msg = 'ZIP central directory size exceeds bounded archive limits.';
      onEntryLimitExceeded?.call(msg);
      throw const ScoreParseException(msg);
    }
  }

  static int _readUint16Le(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _readUint32Le(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}
