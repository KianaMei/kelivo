import 'dart:convert';

/// Service for building prompt-based tool use system prompts and messages
///
/// This service handles the construction of enhanced system prompts that
/// include tool definitions in XML format, allowing models without native
/// function calling to use tools through prompt engineering.
class PromptToolUseService {
  /// System prompt template for prompt-based tool use
  static const String systemPromptTemplate = '''
# 工具使用说明

你可以使用以下工具来完成任务。当你需要使用工具时，请使用 XML 格式输出工具调用。

## 可用工具

{available_tools}

## 工具调用格式

当你需要调用工具时，请使用以下 XML 格式：

```xml
<tool_use>
  <name>工具名称</name>
  <arguments>{"参数名": "参数值"}</arguments>
</tool_use>
```

## 重要规则

1. **一次只调用一个工具**：每次回复中最多包含一个 `<tool_use>` 标签
2. **等待结果**：发出工具调用后，等待工具结果返回再继续
3. **参数格式**：arguments 必须是有效的 JSON 格式
4. **正常回复**：如果不需要使用工具，直接正常回复即可

## 工具结果格式

工具执行后，你会收到以下格式的结果：

```xml
<tool_use_result>
  <name>工具名称</name>
  <result>{"结果字段": "结果值"}</result>
</tool_use_result>
```

{user_instructions}
''';

  /// Build XML representation of available tools
  ///
  /// Takes a list of tool definitions (in OpenAI function calling format)
  /// and converts them to XML format for inclusion in the system prompt.
  static String buildAvailableToolsXml(List<Map<String, dynamic>> tools) {
    if (tools.isEmpty) return '';

    final buffer = StringBuffer();
    for (final tool in tools) {
      final function = tool['function'] as Map<String, dynamic>?;
      if (function == null) continue;

      final name = function['name'] as String? ?? '';
      final description = function['description'] as String? ?? '';
      final parameters = function['parameters'] as Map<String, dynamic>?;

      buffer.writeln('### $name');
      buffer.writeln();
      buffer.writeln('**描述**: $description');
      buffer.writeln();

      if (parameters != null) {
        buffer.writeln('**参数**:');
        final properties =
            parameters['properties'] as Map<String, dynamic>? ?? {};
        final required =
            (parameters['required'] as List<dynamic>?)?.cast<String>() ?? [];

        for (final entry in properties.entries) {
          final paramName = entry.key;
          final paramDef = entry.value as Map<String, dynamic>;
          final paramType = paramDef['type'] as String? ?? 'any';
          final paramDesc = paramDef['description'] as String? ?? '';
          final isRequired = required.contains(paramName);

          buffer.writeln(
            '- `$paramName` ($paramType${isRequired ? ', 必填' : ', 可选'}): $paramDesc',
          );
        }
        buffer.writeln();
      }

      buffer.writeln('**调用示例**:');
      buffer.writeln('```xml');
      buffer.writeln('<tool_use>');
      buffer.writeln('  <name>$name</name>');
      buffer.writeln('  <arguments>${_buildExampleArguments(parameters)}</arguments>');
      buffer.writeln('</tool_use>');
      buffer.writeln('```');
      buffer.writeln();
    }

    return buffer.toString().trim();
  }

  /// Build the complete system prompt with tool definitions
  ///
  /// Combines the system prompt template with available tools and
  /// preserves the user's original system prompt.
  static String buildSystemPrompt({
    required String userSystemPrompt,
    required List<Map<String, dynamic>> tools,
  }) {
    if (tools.isEmpty) {
      return userSystemPrompt;
    }

    final availableToolsXml = buildAvailableToolsXml(tools);

    String userInstructions = '';
    if (userSystemPrompt.isNotEmpty) {
      userInstructions = '''
## 用户指令

$userSystemPrompt
''';
    }

    return systemPromptTemplate
        .replaceAll('{available_tools}', availableToolsXml)
        .replaceAll('{user_instructions}', userInstructions)
        .trim();
  }

  /// Build a tool result message in XML format
  ///
  /// Formats the tool execution result for sending back to the model.
  static String buildToolResultMessage({
    required String toolName,
    required String result,
    bool isError = false,
  }) {
    if (isError) {
      return '''<tool_use_result>
  <name>$toolName</name>
  <error>$result</error>
</tool_use_result>''';
    }

    return '''<tool_use_result>
  <name>$toolName</name>
  <result>$result</result>
</tool_use_result>''';
  }

  /// Build example arguments JSON for a tool
  static String _buildExampleArguments(Map<String, dynamic>? parameters) {
    if (parameters == null) return '{}';

    final properties =
        parameters['properties'] as Map<String, dynamic>? ?? {};
    if (properties.isEmpty) return '{}';

    final example = <String, dynamic>{};
    for (final entry in properties.entries) {
      final paramDef = entry.value as Map<String, dynamic>;
      final paramType = paramDef['type'] as String? ?? 'string';

      switch (paramType) {
        case 'integer':
          example[entry.key] = paramDef['minimum'] ?? 0;
          break;
        case 'number':
          example[entry.key] = paramDef['minimum'] ?? 0.0;
          break;
        case 'boolean':
          example[entry.key] = true;
          break;
        case 'string':
        default:
          example[entry.key] = 'example_value';
          break;
      }
    }

    return jsonEncode(example);
  }
}
