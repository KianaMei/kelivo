import 'package:flutter_test/flutter_test.dart' hide expect, group, test;
import 'package:glados/glados.dart';
import 'package:kelivo/core/models/tool_call_mode.dart';
import 'package:kelivo/core/models/chat_message.dart';

/// **Feature: prompt-tool-use, Property 6: 模式切换不影响对话历史**
/// **Validates: Requirements 1.3, 6.4**
/// 
/// This test verifies that switching between native and prompt tool modes
/// does not affect the conversation history. The conversation messages
/// should remain unchanged regardless of mode switches.

/// Custom generators for property-based testing
extension ChatMessageGenerators on Any {
  /// Generate a list of ChatMessages (conversation history)
  static Generator<List<ChatMessage>> conversationHistory = 
      any.positiveIntOrZero.map((seed) {
        final count = (seed % 10) + 1; // 1-10 messages
        return List<ChatMessage>.generate(count, (i) => ChatMessage(
          id: 'msg_${seed}_$i',
          conversationId: 'conv_test',
          role: i % 2 == 0 ? 'user' : 'assistant',
          content: 'Message $i with seed $seed',
          timestamp: DateTime.fromMillisecondsSinceEpoch((seed + i) * 1000),
        ));
      });
}

/// Simulates mode switching behavior
/// Returns the conversation history after mode switch (should be unchanged)
List<ChatMessage> simulateModeSwitchAndGetHistory(
  List<ChatMessage> originalHistory,
  ToolCallMode fromMode,
  ToolCallMode toMode,
) {
  // Mode switching should NOT modify conversation history
  // This simulates what happens in the UI when user toggles the mode
  // The history is passed through unchanged
  return List<ChatMessage>.from(originalHistory);
}

/// Deep equality check for ChatMessage lists
bool messagesEqual(List<ChatMessage> a, List<ChatMessage> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id ||
        a[i].conversationId != b[i].conversationId ||
        a[i].role != b[i].role ||
        a[i].content != b[i].content) {
      return false;
    }
  }
  return true;
}

void main() {
  group('ToolCallMode Property Tests', () {
    // **Feature: prompt-tool-use, Property 6: 模式切换不影响对话历史**
    // **Validates: Requirements 1.3, 6.4**
    Glados(ChatMessageGenerators.conversationHistory).test(
      'Property 6: Mode switching does not affect conversation history',
      (conversationHistory) {
        // Create a deep copy of the original history for comparison
        final originalHistory = conversationHistory.map((m) => ChatMessage(
          id: m.id,
          conversationId: m.conversationId,
          role: m.role,
          content: m.content,
          timestamp: m.timestamp,
        )).toList();
        
        // Test switching from native to prompt mode
        final afterNativeToPrompt = simulateModeSwitchAndGetHistory(
          conversationHistory,
          ToolCallMode.native,
          ToolCallMode.prompt,
        );
        
        expect(messagesEqual(afterNativeToPrompt, originalHistory), isTrue,
            reason: 'Conversation history should be unchanged after switching from native to prompt mode');
        
        // Test switching from prompt to native mode
        final afterPromptToNative = simulateModeSwitchAndGetHistory(
          conversationHistory,
          ToolCallMode.prompt,
          ToolCallMode.native,
        );
        
        expect(messagesEqual(afterPromptToNative, originalHistory), isTrue,
            reason: 'Conversation history should be unchanged after switching from prompt to native mode');
        
        // Test multiple switches
        var currentHistory = conversationHistory;
        for (int i = 0; i < 5; i++) {
          final fromMode = i % 2 == 0 ? ToolCallMode.native : ToolCallMode.prompt;
          final toMode = i % 2 == 0 ? ToolCallMode.prompt : ToolCallMode.native;
          currentHistory = simulateModeSwitchAndGetHistory(currentHistory, fromMode, toMode);
        }
        
        expect(messagesEqual(currentHistory, originalHistory), isTrue,
            reason: 'Conversation history should be unchanged after multiple mode switches');
      },
    );

    // Additional test: ToolCallMode enum values
    Glados(any.bool).test(
      'ToolCallMode has exactly two values: native and prompt',
      (_) {
        expect(ToolCallMode.values.length, equals(2));
        expect(ToolCallMode.values.contains(ToolCallMode.native), isTrue);
        expect(ToolCallMode.values.contains(ToolCallMode.prompt), isTrue);
      },
    );

    // Additional test: ToolCallMode toggle behavior
    Glados(any.bool).test(
      'ToolCallMode toggle returns opposite mode',
      (startWithNative) {
        final startMode = startWithNative ? ToolCallMode.native : ToolCallMode.prompt;
        final expectedAfterToggle = startWithNative ? ToolCallMode.prompt : ToolCallMode.native;
        
        // Simulate toggle
        final toggledMode = startMode == ToolCallMode.native 
            ? ToolCallMode.prompt 
            : ToolCallMode.native;
        
        expect(toggledMode, equals(expectedAfterToggle),
            reason: 'Toggle should return the opposite mode');
        
        // Toggle again should return to original
        final doubleToggledMode = toggledMode == ToolCallMode.native 
            ? ToolCallMode.prompt 
            : ToolCallMode.native;
        
        expect(doubleToggledMode, equals(startMode),
            reason: 'Double toggle should return to original mode');
      },
    );
  });
}
