import 'dart:convert';
import '../../models/tool_call_mode.dart';

/// XML tag extractor for streaming tool use detection
/// 
/// Extracts `<tool_use>` tags from streaming model output, handling
/// cases where tags may span multiple chunks.
class XmlTagExtractor {
  static const String openingTag = '<tool_use>';
  static const String closingTag = '</tool_use>';
  
  /// Internal buffer for accumulating partial content
  String _buffer = '';
  
  /// Whether we're currently inside a tool_use tag
  bool _insideTag = false;
  
  /// Process a streaming text chunk and return extraction results
  /// 
  /// Returns a list of [TagExtractionResult] objects, each containing
  /// either regular content or tool_use tag content.
  List<TagExtractionResult> processChunk(String chunk) {
    final results = <TagExtractionResult>[];
    _buffer += chunk;
    
    while (_buffer.isNotEmpty) {
      if (_insideTag) {
        // Look for closing tag
        final closeIndex = _buffer.indexOf(closingTag);
        if (closeIndex != -1) {
          // Found closing tag - extract content
          final tagContent = _buffer.substring(0, closeIndex);
          results.add(TagExtractionResult(
            content: tagContent,
            isTagContent: true,
          ));
          _buffer = _buffer.substring(closeIndex + closingTag.length);
          _insideTag = false;
        } else {
          // Check if buffer might contain partial closing tag
          if (_mightContainPartialTag(_buffer, closingTag)) {
            // Wait for more data
            break;
          } else {
            // No closing tag yet, but buffer is safe to keep
            break;
          }
        }
      } else {
        // Look for opening tag
        final openIndex = _buffer.indexOf(openingTag);
        if (openIndex != -1) {
          // Found opening tag
          if (openIndex > 0) {
            // Emit content before the tag
            results.add(TagExtractionResult(
              content: _buffer.substring(0, openIndex),
              isTagContent: false,
            ));
          }
          _buffer = _buffer.substring(openIndex + openingTag.length);
          _insideTag = true;
        } else {
          // Check if buffer might contain partial opening tag
          final partialIndex = _findPartialTagStart(_buffer, openingTag);
          if (partialIndex != -1) {
            // Emit content before potential partial tag
            if (partialIndex > 0) {
              results.add(TagExtractionResult(
                content: _buffer.substring(0, partialIndex),
                isTagContent: false,
              ));
              _buffer = _buffer.substring(partialIndex);
            }
            // Wait for more data
            break;
          } else {
            // No tag found, emit all content
            results.add(TagExtractionResult(
              content: _buffer,
              isTagContent: false,
            ));
            _buffer = '';
          }
        }
      }
    }
    
    return results;
  }
  
  /// Reset the extractor state
  void reset() {
    _buffer = '';
    _insideTag = false;
  }
  
  /// Check if buffer might contain a partial tag at the end
  bool _mightContainPartialTag(String buffer, String tag) {
    for (var i = 1; i < tag.length && i <= buffer.length; i++) {
      if (buffer.endsWith(tag.substring(0, i))) {
        return true;
      }
    }
    return false;
  }
  
  /// Find the start index of a potential partial tag at the end of buffer
  int _findPartialTagStart(String buffer, String tag) {
    for (var i = 1; i < tag.length && i <= buffer.length; i++) {
      final suffix = buffer.substring(buffer.length - i);
      if (tag.startsWith(suffix)) {
        return buffer.length - i;
      }
    }
    return -1;
  }
  
  /// Parse tool use XML content into a ParsedToolUse object
  /// 
  /// Expected format:
  /// ```xml
  /// <name>tool_name</name>
  /// <arguments>{"key": "value"}</arguments>
  /// ```
  static ParsedToolUse? parseToolUse(String xmlContent) {
    try {
      // Extract name
      final nameMatch = RegExp(r'<name>\s*(.*?)\s*</name>', dotAll: true)
          .firstMatch(xmlContent);
      if (nameMatch == null) return null;
      final name = nameMatch.group(1)?.trim() ?? '';
      if (name.isEmpty) return null;
      
      // Extract arguments
      final argsMatch = RegExp(r'<arguments>\s*(.*?)\s*</arguments>', dotAll: true)
          .firstMatch(xmlContent);
      
      Map<String, dynamic> arguments = {};
      if (argsMatch != null) {
        final argsStr = argsMatch.group(1)?.trim() ?? '{}';
        try {
          final decoded = jsonDecode(argsStr);
          if (decoded is Map<String, dynamic>) {
            arguments = decoded;
          }
        } catch (_) {
          // Invalid JSON, use empty map per requirement 3.5
          arguments = {};
        }
      }
      
      return ParsedToolUse.create(name: name, arguments: arguments);
    } catch (_) {
      return null;
    }
  }
}
