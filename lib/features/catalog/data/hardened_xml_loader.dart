import 'dart:convert';
import 'dart:typed_data';

import 'package:piano_exercises/features/catalog/data/strict_xml_entity_mapping.dart';
import 'package:piano_exercises/features/catalog/domain/score_parser.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

/// Iterative, bounded XML parser that blocks XXE, custom entities, and DTD bombs.
final class HardenedXmlLoader {
  const HardenedXmlLoader({
    this.maxByteLength = defaultMaxByteLength,
    this.maxElements = defaultMaxElements,
    this.maxDepth = defaultMaxDepth,
    this.maxAttributesPerElement = defaultMaxAttributesPerElement,
    this.allowMusicXmlDoctype = true,
  });

  static const int defaultMaxByteLength = 10 * 1024 * 1024;
  static const int defaultMaxElements = 50000;
  static const int defaultMaxDepth = 64;
  static const int defaultMaxAttributesPerElement = 32;

  static final RegExp _entityDeclPattern = RegExp(
    r'<!entity',
    caseSensitive: false,
  );

  final int maxByteLength;
  final int maxElements;
  final int maxDepth;
  final int maxAttributesPerElement;
  final bool allowMusicXmlDoctype;

  /// Parses UTF-8 [bytes] into an [XmlDocument] under strict structural bounds.
  XmlDocument parseBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const ScoreParseException('XML input is empty.');
    }
    if (bytes.length > maxByteLength) {
      throw ScoreParseException(
        'XML input exceeds maximum size of $maxByteLength bytes.',
      );
    }

    var text = _decodeUtf8(bytes);
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }
    if (text.trim().isEmpty) {
      throw const ScoreParseException('XML input is empty.');
    }
    if (_entityDeclPattern.hasMatch(text)) {
      throw const ScoreParseException(
        'XML ENTITY declarations are not permitted.',
      );
    }

    try {
      return _parseIteratively(text);
    } on ScoreParseException {
      rethrow;
    } on XmlException catch (error) {
      throw ScoreParseException('Malformed XML: ${error.message}');
    }
  }

  static String _decodeUtf8(Uint8List bytes) {
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      throw const ScoreParseException('Invalid UTF-8 encoding in XML input.');
    }
  }

  XmlDocument _parseIteratively(String text) {
    final events = parseEvents(
      text,
      entityMapping: const StrictXmlEntityMapping(),
      validateNesting: true,
      validateDocument: true,
    );
    final topLevelNodes = <XmlNode>[];
    final stack = <XmlElement>[];
    var elementCount = 0;

    for (final event in events) {
      switch (event) {
        case XmlDeclarationEvent():
          topLevelNodes.add(
            XmlDeclaration(_convertAttributes(event.attributes)),
          );
        case XmlDoctypeEvent():
          _validateDoctype(event);
          topLevelNodes.add(
            XmlDoctype(event.name, event.externalId, event.internalSubset),
          );
        case XmlStartElementEvent():
          elementCount += 1;
          _appendStartElement(
            event,
            elementCount: elementCount,
            stack: stack,
            topLevelNodes: topLevelNodes,
          );
        case XmlEndElementEvent():
          if (stack.isEmpty || stack.last.name.qualified != event.name) {
            throw ScoreParseException(
              'Mismatched XML closing tag </${event.name}>.',
            );
          }
          stack.removeLast();
        case XmlTextEvent():
          final decoded = event.value;
          if (stack.isNotEmpty) {
            stack.last.children.add(XmlText(decoded));
          } else if (decoded.trim().isNotEmpty) {
            throw const ScoreParseException(
              'Unexpected text outside XML root element.',
            );
          }
        case XmlCDATAEvent():
          if (stack.isEmpty) {
            throw const ScoreParseException(
              'Unexpected CDATA outside XML root element.',
            );
          }
          stack.last.children.add(XmlCDATA(event.value));
        default:
          break;
      }
    }

    if (stack.isNotEmpty) {
      throw ScoreParseException(
        'Unclosed XML element <${stack.last.name.qualified}>.',
      );
    }
    return XmlDocument(topLevelNodes);
  }

  void _appendStartElement(
    XmlStartElementEvent event, {
    required int elementCount,
    required List<XmlElement> stack,
    required List<XmlNode> topLevelNodes,
  }) {
    if (event.attributes.length > maxAttributesPerElement) {
      throw ScoreParseException(
        'XML element <${event.name}> exceeds $maxAttributesPerElement attributes.',
      );
    }
    if (elementCount > maxElements) {
      throw ScoreParseException(
        'XML document exceeds maximum element count of $maxElements.',
      );
    }
    if (stack.length + 1 > maxDepth) {
      throw ScoreParseException(
        'XML nesting depth exceeds maximum of $maxDepth.',
      );
    }
    final element = XmlElement.tag(
      event.name,
      attributes: _convertAttributes(event.attributes),
      isSelfClosing: event.isSelfClosing,
    );
    if (stack.isEmpty) {
      topLevelNodes.add(element);
    } else {
      stack.last.children.add(element);
    }
    if (!event.isSelfClosing) {
      stack.add(element);
    }
  }

  void _validateDoctype(XmlDoctypeEvent event) {
    if (!allowMusicXmlDoctype) {
      throw const ScoreParseException(
        'XML DOCTYPE declarations are not permitted in this document.',
      );
    }
    if (event.internalSubset != null) {
      throw const ScoreParseException(
        'XML DOCTYPE internal subsets are not permitted.',
      );
    }
    final externalId = event.externalId;
    if (externalId != null) {
      final publicId = externalId.publicId;
      if (publicId == null ||
          !publicId.startsWith('-//Recordare//DTD MusicXML')) {
        throw const ScoreParseException(
          'Unsupported external XML DOCTYPE public identifier.',
        );
      }
      if (!_isSafeDoctypeSystemId(externalId.systemId)) {
        throw const ScoreParseException(
          'Unsafe XML DOCTYPE system identifier.',
        );
      }
    }
  }

  static bool _isSafeDoctypeSystemId(String systemId) {
    if (systemId.isEmpty ||
        systemId.contains('..') ||
        systemId.contains(r'\') ||
        systemId.contains('\u0000') ||
        systemId.startsWith('/')) {
      return false;
    }
    if (systemId.contains(':')) {
      final lower = systemId.toLowerCase();
      if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
        return false;
      }
      final uri = Uri.tryParse(systemId);
      if (uri == null || uri.host.isEmpty) {
        return false;
      }
    }
    return true;
  }

  static List<XmlAttribute> _convertAttributes(
    List<XmlEventAttribute> attributes,
  ) {
    return attributes
        .map(
          (attr) => XmlAttribute(
            XmlName.qualified(attr.name),
            attr.value,
            attr.attributeType,
          ),
        )
        .toList(growable: false);
  }
}
