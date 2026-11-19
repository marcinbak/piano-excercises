import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:xml/xml.dart';

/// Strict XML entity decoder allowing only built-in entities and scalar refs.
final class StrictXmlEntityMapping extends XmlEntityMapping {
  const StrictXmlEntityMapping();

  static const XmlEntityMapping _encoder = XmlDefaultEntityMapping.xml();

  @override
  String? decodeEntity(String input) {
    if (input.isEmpty) {
      throw const ScoreParseException('Empty XML entity reference.');
    }
    if (input.codeUnitAt(0) == 0x23) {
      return _decodeNumericRef(input);
    }
    return switch (input) {
      'lt' => '<',
      'gt' => '>',
      'amp' => '&',
      'apos' => "'",
      'quot' => '"',
      _ => throw ScoreParseException('Unknown XML entity reference: &$input;'),
    };
  }

  static String _decodeNumericRef(String input) {
    final isHex =
        input.length > 1 &&
        (input.codeUnitAt(1) == 0x78 || input.codeUnitAt(1) == 0x58);
    final digits = isHex ? input.substring(2) : input.substring(1);
    final validDigits = isHex
        ? _isAsciiHexDigits(digits)
        : _isAsciiDigits(digits);
    final value = validDigits
        ? int.tryParse(digits, radix: isHex ? 16 : 10)
        : null;
    if (value == null ||
        value <= 0 ||
        value > 0x10FFFF ||
        (value >= 0xD800 && value <= 0xDFFF)) {
      throw ScoreParseException(
        'Invalid numeric XML character reference: &$input;',
      );
    }
    return String.fromCharCode(value);
  }

  static bool _isAsciiDigits(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (var i = 0; i < value.length; i += 1) {
      final unit = value.codeUnitAt(i);
      if (unit < 0x30 || unit > 0x39) {
        return false;
      }
    }
    return true;
  }

  static bool _isAsciiHexDigits(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (var i = 0; i < value.length; i += 1) {
      final unit = value.codeUnitAt(i);
      final isDigit = unit >= 0x30 && unit <= 0x39;
      final isUpper = unit >= 0x41 && unit <= 0x46;
      final isLower = unit >= 0x61 && unit <= 0x66;
      if (!isDigit && !isUpper && !isLower) {
        return false;
      }
    }
    return true;
  }

  @override
  String encodeText(String input) => _encoder.encodeText(input);

  @override
  String encodeAttributeValue(String input, XmlAttributeType type) =>
      _encoder.encodeAttributeValue(input, type);
}
