/// Tool call mode definitions for Kelivo
/// 
/// This file defines the tool call mode enum and related types for
/// the prompt tool use feature.

/// Tool call mode enumeration
/// 
/// Defines how tools are invoked when interacting with LLM models.
enum ToolCallMode {
  /// Use API native Function Calling
  native,
  
  /// Use prompt engineering to simulate tool calls
  prompt,
}

/// Result of XML tag extraction from streaming output
class TagExtractionResult {
  /// The extracted content
  final String content;
  
  /// Whether this content is from inside a tool_use tag
  final bool isTagContent;
  
  const TagExtractionResult({
    required this.content,
    required this.isTagContent,
  });
  
  @override
  String toString() => 'TagExtractionResult(content: $content, isTagContent: $isTagContent)';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagExtractionResult &&
          runtimeType == other.runtimeType &&
          content == other.content &&
          isTagContent == other.isTagContent;
  
  @override
  int get hashCode => content.hashCode ^ isTagContent.hashCode;
}

/// Parsed tool use call extracted from model output
class ParsedToolUse {
  /// Unique identifier for this tool call (includes timestamp)
  final String id;
  
  /// Name of the tool being called
  final String name;
  
  /// Arguments passed to the tool
  final Map<String, dynamic> arguments;
  
  ParsedToolUse({
    required this.id,
    required this.name,
    required this.arguments,
  });
  
  /// Creates a ParsedToolUse with an auto-generated ID
  factory ParsedToolUse.create({
    required String name,
    required Map<String, dynamic> arguments,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return ParsedToolUse(
      id: 'tool_${name}_$timestamp',
      name: name,
      arguments: arguments,
    );
  }
  
  /// Convert to XML string for round-trip testing
  String toXml() {
    final argsJson = _encodeArguments(arguments);
    return '''<tool_use>
  <name>$name</name>
  <arguments>$argsJson</arguments>
</tool_use>''';
  }
  
  /// Encode arguments to JSON string
  String _encodeArguments(Map<String, dynamic> args) {
    if (args.isEmpty) return '{}';
    
    final buffer = StringBuffer('{');
    var first = true;
    for (final entry in args.entries) {
      if (!first) buffer.write(', ');
      first = false;
      buffer.write('"${entry.key}": ');
      if (entry.value is String) {
        buffer.write('"${entry.value}"');
      } else if (entry.value is num || entry.value is bool) {
        buffer.write(entry.value);
      } else if (entry.value == null) {
        buffer.write('null');
      } else {
        // For complex types, convert to string representation
        buffer.write('"${entry.value}"');
      }
    }
    buffer.write('}');
    return buffer.toString();
  }
  
  @override
  String toString() => 'ParsedToolUse(id: $id, name: $name, arguments: $arguments)';
  
  /// Check equality (excluding id since it contains timestamp)
  bool equalsIgnoringId(ParsedToolUse other) =>
      name == other.name && _mapsEqual(arguments, other.arguments);
  
  bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (a[key] != b[key]) return false;
    }
    return true;
  }
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedToolUse &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          _mapsEqual(arguments, other.arguments);
  
  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ arguments.hashCode;
}
