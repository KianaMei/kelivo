import 'package:flutter_test/flutter_test.dart' hide expect, group;
import 'package:glados/glados.dart';
import 'package:kelivo/core/services/prompt_tool_use/prompt_tool_use_service.dart';

/// Custom generators for property-based testing
extension PromptToolUseAny on Any {
  /// Generate valid tool names (alphanumeric with underscores, non-empty)
  static Generator<String> toolName = any.letterOrDigits
      .map((s) => s.isEmpty ? 'tool' : s.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), 'x'));

  /// Generate safe string values (no special chars that break parsing)
  static Generator<String> safeString = any.letterOrDigits;

  /// Generate tool descriptions
  static Generator<String> toolDescription = any.letterOrDigits
      .map((s) => s.isEmpty ? 'A tool description' : s);
}

/// Helper function to create a tool definition from generated values
Map<String, dynamic> createToolDefinition(String name, String description, int paramSeed) {
  final toolNameValue = name.isEmpty ? 'test_tool' : name;
  final descValue = description.isEmpty ? 'A test tool' : description;

  return {
    'type': 'function',
    'function': {
      'name': toolNameValue,
      'description': descValue,
      'parameters': {
        'type': 'object',
        'properties': {
          'param_${paramSeed % 10}': {
            'type': 'integer',
            'description': 'A parameter',
          },
        },
        'required': ['param_${paramSeed % 10}'],
      },
    },
  };
}

void main() {
  group('PromptToolUseService Property Tests', () {
    // **Feature: prompt-tool-use, Property 4: 系统提示词包含必要元素**
    // **Validates: Requirements 2.1, 2.2**
    Glados3(
      PromptToolUseAny.toolName,
      PromptToolUseAny.toolDescription,
      any.positiveIntOrZero,
    ).test(
      'Property 4: System prompt contains necessary elements for each tool',
      (toolName, toolDescription, paramSeed) {
        final tool = createToolDefinition(toolName, toolDescription, paramSeed);
        final tools = [tool];
        final function = tool['function'] as Map<String, dynamic>;
        final name = function['name'] as String;
        final description = function['description'] as String;
        final parameters = function['parameters'] as Map<String, dynamic>;
        final properties = parameters['properties'] as Map<String, dynamic>;

        // Build system prompt with empty user prompt
        final systemPrompt = PromptToolUseService.buildSystemPrompt(
          userSystemPrompt: '',
          tools: tools,
        );

        // Verify tool name is present
        expect(
          systemPrompt.contains(name),
          isTrue,
          reason: 'System prompt should contain tool name: $name',
        );

        // Verify tool description is present
        expect(
          systemPrompt.contains(description),
          isTrue,
          reason: 'System prompt should contain tool description: $description',
        );

        // Verify each parameter name is present
        for (final paramName in properties.keys) {
          expect(
            systemPrompt.contains(paramName),
            isTrue,
            reason: 'System prompt should contain parameter name: $paramName',
          );
        }
      },
    );

    // **Feature: prompt-tool-use, Property 5: 用户系统提示词保留**
    // **Validates: Requirements 2.3**
    Glados3(
      PromptToolUseAny.safeString,
      PromptToolUseAny.toolName,
      any.positiveIntOrZero,
    ).test(
      'Property 5: User system prompt is preserved in enhanced prompt',
      (userPrompt, toolName, paramSeed) {
        // Skip empty user prompts as they are a special case
        if (userPrompt.isEmpty) return;

        final tool = createToolDefinition(toolName, 'A test tool', paramSeed);
        final tools = [tool];

        // Build system prompt with user prompt
        final systemPrompt = PromptToolUseService.buildSystemPrompt(
          userSystemPrompt: userPrompt,
          tools: tools,
        );

        // Verify user prompt content is preserved
        expect(
          systemPrompt.contains(userPrompt),
          isTrue,
          reason: 'Enhanced system prompt should contain user prompt: $userPrompt',
        );

        // Verify the user instructions section header is present
        expect(
          systemPrompt.contains('用户指令'),
          isTrue,
          reason: 'Enhanced system prompt should contain user instructions section',
        );
      },
    );

    // Additional test: Empty tools list returns original user prompt
    Glados(PromptToolUseAny.safeString).test(
      'Empty tools list returns original user prompt',
      (userPrompt) {
        final systemPrompt = PromptToolUseService.buildSystemPrompt(
          userSystemPrompt: userPrompt,
          tools: [],
        );

        expect(
          systemPrompt,
          equals(userPrompt),
          reason: 'With empty tools, should return original user prompt',
        );
      },
    );
  });
}
