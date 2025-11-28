import 'dart:convert';

/// Provider-specific tool schema sanitization.
///
/// Different LLM providers have varying levels of JSON Schema support.
/// This module normalizes tool schemas to each provider's accepted subset,
/// preventing API errors from unsupported schema features.
///
/// **Supported Providers**:
/// - **Google/Gemini**: Strict validation, requires `items` for arrays
/// - **OpenAI**: Standard JSON Schema with minor restrictions
/// - **Claude**: Similar to OpenAI but with additional constraints
///
/// **Common Transformations**:
/// - Remove `$schema`, `examples`, `additionalProperties`
/// - Flatten `anyOf`/`oneOf`/`allOf` to first branch
/// - Normalize `type` arrays to single value
/// - Convert `const` to `enum`
/// - Ensure arrays have `items` field (Gemini requirement)
class ToolSchemaSanitizer {
  ToolSchemaSanitizer._();

  /// Sanitizes a tool parameter schema for a specific provider.
  ///
  /// **Example**:
  /// ```dart
  /// final schema = {
  ///   'type': ['string', 'null'],  // Will become 'string'
  ///   'anyOf': [{'type': 'string'}, {'type': 'number'}],  // Will flatten to first
  ///   r'$schema': 'http://json-schema.org/draft-07/schema#',  // Will be removed
  /// };
  ///
  /// final sanitized = ToolSchemaSanitizer.sanitizeForProvider(
  ///   schema,
  ///   ProviderKind.google,
  /// );
  /// // => {'type': 'string'}
  /// ```
  static Map<String, dynamic> sanitizeForProvider(
    Map<String, dynamic> schema,
    ProviderKind kind,
  ) {
    // Deep clone to avoid mutating input
    Map<String, dynamic> clone = _deepClone(schema);
    clone = _sanitizeNode(clone, kind) as Map<String, dynamic>;
    return clone;
  }

  /// Cleans OpenAI-format tool definitions for strict backends (like Gemini via NewAPI).
  ///
  /// This is specifically for the OpenAI tool format:
  /// ```json
  /// {
  ///   "type": "function",
  ///   "function": {
  ///     "name": "get_weather",
  ///     "parameters": { ... }
  ///   }
  /// }
  /// ```
  ///
  /// **Example**:
  /// ```dart
  /// final tools = [
  ///   {
  ///     'type': 'function',
  ///     'function': {
  ///       'name': 'search',
  ///       'parameters': {
  ///         'type': 'object',
  ///         'properties': {
  ///           'query': {'type': 'array'}  // Missing 'items'!
  ///         }
  ///       }
  ///     }
  ///   }
  /// ];
  ///
  /// final cleaned = ToolSchemaSanitizer.cleanToolsForGemini(tools);
  /// // 'items': {'type': 'string'} will be added automatically
  /// ```
  static List<Map<String, dynamic>> cleanToolsForGemini(
    List<Map<String, dynamic>> tools,
  ) {
    return tools.map((tool) {
      final result = Map<String, dynamic>.from(tool);
      final fn = result['function'];
      if (fn is Map) {
        final fnMap = Map<String, dynamic>.from(fn as Map);
        final params = fnMap['parameters'];
        if (params is Map) {
          fnMap['parameters'] =
              _cleanSchemaForGemini(params as Map<String, dynamic>);
        }
        result['function'] = fnMap;
      }
      return result;
    }).toList();
  }

  // ========== Private Helpers ==========

  /// Recursively sanitizes a schema node based on provider requirements.
  static dynamic _sanitizeNode(dynamic node, ProviderKind kind) {
    if (node is List) {
      return node.map((e) => _sanitizeNode(e, kind)).toList();
    }
    if (node is! Map) return node;

    final m = Map<String, dynamic>.from(node as Map);

    // Remove unsupported fields
    m.remove(r'$schema');
    m.remove('examples');

    // Convert 'const' to 'enum' (more widely supported)
    if (m.containsKey('const')) {
      final v = m['const'];
      if (v is String || v is num || v is bool) {
        m['enum'] = [v];
      }
      m.remove('const');
    }

    // Flatten composition keywords (anyOf/oneOf/allOf)
    // Take the first branch as a simplification
    for (final key in [
      'anyOf',
      'oneOf',
      'allOf',
      'any_of',
      'one_of',
      'all_of'
    ]) {
      if (m[key] is List && (m[key] as List).isNotEmpty) {
        final first = (m[key] as List).first;
        final flattened = _sanitizeNode(first, kind);
        m.remove(key);
        if (flattened is Map<String, dynamic>) {
          // Merge flattened properties into current node
          m
            ..remove('type')
            ..remove('properties')
            ..remove('items');
          m.addAll(flattened);
        }
      }
    }

    // Normalize 'type' to single value (not array)
    final t = m['type'];
    if (t is List && t.isNotEmpty) {
      m['type'] = t.first.toString();
    }

    // Normalize 'items' to single schema (not array)
    final items = m['items'];
    if (items is List && items.isNotEmpty) {
      m['items'] = items.first;
    }

    // Recursively sanitize nested schemas
    if (m['items'] is Map) {
      m['items'] = _sanitizeNode(m['items'], kind);
    }

    if (m['properties'] is Map) {
      final props = Map<String, dynamic>.from(m['properties']);
      final normalized = <String, dynamic>{};
      props.forEach((k, v) {
        normalized[k] = _sanitizeNode(v, kind);
      });
      m['properties'] = normalized;
    }

    // Remove fields not in provider's allowlist
    final Set<String> allowed;
    switch (kind) {
      case ProviderKind.google:
        allowed = {
          'type',
          'description',
          'properties',
          'required',
          'items',
          'enum'
        };
        break;
      case ProviderKind.openai:
      case ProviderKind.claude:
        allowed = {
          'type',
          'description',
          'properties',
          'required',
          'items',
          'enum'
        };
        break;
    }
    m.removeWhere((k, v) => !allowed.contains(k));

    return m;
  }

  /// Gemini-specific schema cleaning: ensures arrays have 'items' field.
  static Map<String, dynamic> _cleanSchemaForGemini(
    Map<String, dynamic> schema,
  ) {
    final result = Map<String, dynamic>.from(schema);

    // Recursively fix 'properties' if present
    if (result['properties'] is Map) {
      final props = Map<String, dynamic>.from(result['properties'] as Map);
      props.forEach((key, value) {
        if (value is Map) {
          final propMap = Map<String, dynamic>.from(value as Map);

          // Gemini requires array types to have 'items' field
          if (propMap['type'] == 'array' && !propMap.containsKey('items')) {
            propMap['items'] = {'type': 'string'}; // Default to string array
          }

          // Recursively clean nested objects
          if (propMap['type'] == 'object' &&
              propMap.containsKey('properties')) {
            propMap['properties'] = _cleanSchemaForGemini(
                {'properties': propMap['properties']})['properties'];
          }

          props[key] = propMap;
        }
      });
      result['properties'] = props;
    }

    // Handle array items recursively
    if (result['items'] is Map) {
      result['items'] =
          _cleanSchemaForGemini(result['items'] as Map<String, dynamic>);
    }

    return result;
  }

  /// Deep clones a map using JSON serialization.
  static Map<String, dynamic> _deepClone(Map<String, dynamic> input) {
    return jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
  }
}

/// Provider classification for schema sanitization rules.
enum ProviderKind {
  openai,
  claude,
  google,
}
