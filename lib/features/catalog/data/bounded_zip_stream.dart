import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';

/// Shared remaining-byte allowance enforced across all decompressed `.mxl` entries.
final class DecodeBudget {
  DecodeBudget(this.remainingBytes);

  int remainingBytes;

  void consume(int byteCount) {
    if (byteCount < 0 || byteCount > remainingBytes) {
      throw const ScoreParseException(
        'Decompressed .mxl content exceeds maximum uncompressed byte limit.',
      );
    }
    remainingBytes -= byteCount;
  }
}

/// Bounded [OutputStreamBase] that checks [DecodeBudget] before every growth.
final class BoundedZipOutputStream extends OutputStreamBase {
  BoundedZipOutputStream(this._budget);

  final DecodeBudget _budget;
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
        'Corrupt deflate back-reference in .mxl.',
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
    _budget.consume(additional);
    final required = _length + additional;
    if (required <= _buffer.length) {
      return;
    }
    var nextCapacity = _buffer.isEmpty ? 4096 : _buffer.length * 2;
    if (nextCapacity < required) {
      nextCapacity = required;
    }
    final maxAllowed = _length + additional + _budget.remainingBytes;
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
