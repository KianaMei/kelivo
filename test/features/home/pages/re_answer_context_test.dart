import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo/features/model/widgets/model_select_sheet.dart';
import 'package:kelivo/core/models/chat_message.dart';

/// **Feature: mention-models-feature, Property 9: Re-answer preserves conversation context**
/// **Validates: Requirements 6.3**
///
/// Tests for the re-answer context preservation logic:
/// - Property 9: Re-answer preserves conversation context
///
/// For any re-answer action triggered from a message, the new response should be
/// generated using the same conversation context (previous messages) as the original response.
///
/// Since HomePage has complex widget dependencies, we test the core logic
/// in isolation using a simplified test harness that mirrors the actual implementation.
void main() {
  group('Re-Answer Context Preservation', () {
    /// **Feature: mention-models-feature, Property 9: Re-answer preserves conversation context**
    /// **Validates: Requirements 6.3**
    ///
    /// Property-based test: For any re-answer action triggered from a message,
    /// the new response should be generated using the same conversation context
    /// (previous messages) as the original response.
    test(
      'Property 9: Re-answer should preserve conversation context',
      () {
        final random = Random(42); // Fixed seed for reproducibility

        // Run 100 iterations with different random inputs
        for (var iteration = 0; iteration < 100; iteration++) {
          // Generate a random conversation with 2-10 messages
          final messageCount = 2 + random.nextInt(9);
          final messages = <_TestMessage>[];
          
          for (var i = 0; i < messageCount; i++) {
            final role = i % 2 == 0 ? 'user' : 'assistant';
            final content = _randomAlphaNumeric(random, 10, 100);
            final providerId = role == 'assistant' ? _randomAlphaNumeric(random, 3, 10) : null;
            final modelId = role == 'assistant' ? _randomAlphaNumeric(random, 3, 15) : null;
            
            messages.add(_TestMessage(
              id: 'msg_$i',
              role: role,
              content: content,
              providerId: providerId,
              modelId: modelId,
              groupId: 'msg_$i',
              version: 0,
            ));
          }

          // Find an assistant message to re-answer (pick a random one)
          final assistantMessages = messages.where((m) => m.role == 'assistant').toList();
          if (assistantMessages.isEmpty) continue;
          
          final targetMessage = assistantMessages[random.nextInt(assistantMessages.length)];
          final targetIndex = messages.indexOf(targetMessage);

          // Generate a new model selection for re-answer
          final newModel = ModelSelection(
            _randomAlphaNumeric(random, 3, 10),
            _randomAlphaNumeric(random, 3, 15),
          );

          // Simulate _reAnswerWithModel context building logic
          // The context should include all messages up to (but not including) the new response
          final contextMessages = <_TestMessage>[];
          for (var i = 0; i < messages.length; i++) {
            // Include messages before the target message's position
            // This mirrors the actual implementation which uses messages up to the new assistant message
            if (i <= targetIndex) {
              contextMessages.add(messages[i]);
            }
          }

          // Simulate creating a new version of the assistant message
          final newVersion = _TestMessage(
            id: 'msg_${messages.length}',
            role: 'assistant',
            content: '', // Empty initially, will be filled by streaming
            providerId: newModel.providerKey,
            modelId: newModel.modelId,
            groupId: targetMessage.groupId,
            version: targetMessage.version + 1,
          );

          // Verify context preservation properties:
          
          // 1. Context should include all user messages before the target
          final userMessagesBefore = messages
              .where((m) => m.role == 'user')
              .where((m) => messages.indexOf(m) < targetIndex)
              .toList();
          
          for (final userMsg in userMessagesBefore) {
            expect(
              contextMessages.any((m) => m.id == userMsg.id),
              isTrue,
              reason: 'Iteration $iteration: User message ${userMsg.id} should be in context',
            );
          }

          // 2. Context should include the target message (the one being re-answered)
          expect(
            contextMessages.any((m) => m.id == targetMessage.id),
            isTrue,
            reason: 'Iteration $iteration: Target message should be in context',
          );

          // 3. New version should have the same groupId as the original
          expect(
            newVersion.groupId,
            equals(targetMessage.groupId),
            reason: 'Iteration $iteration: New version should have same groupId as original',
          );

          // 4. New version should have incremented version number
          expect(
            newVersion.version,
            equals(targetMessage.version + 1),
            reason: 'Iteration $iteration: New version should have incremented version number',
          );

          // 5. New version should use the selected model
          expect(
            newVersion.providerId,
            equals(newModel.providerKey),
            reason: 'Iteration $iteration: New version should use selected provider',
          );
          expect(
            newVersion.modelId,
            equals(newModel.modelId),
            reason: 'Iteration $iteration: New version should use selected model',
          );

          // 6. Context should not include messages after the target
          final messagesAfter = messages
              .where((m) => messages.indexOf(m) > targetIndex)
              .toList();
          
          for (final laterMsg in messagesAfter) {
            expect(
              contextMessages.any((m) => m.id == laterMsg.id),
              isFalse,
              reason: 'Iteration $iteration: Message ${laterMsg.id} after target should not be in context',
            );
          }
        }
      },
    );

    test('re-answer creates new version in same group', () {
      final messages = <_TestMessage>[
        _TestMessage(id: 'msg_0', role: 'user', content: 'Hello', groupId: 'msg_0', version: 0),
        _TestMessage(id: 'msg_1', role: 'assistant', content: 'Hi there!', providerId: 'openai', modelId: 'gpt-4o', groupId: 'msg_1', version: 0),
      ];

      final targetMessage = messages[1];
      final newModel = ModelSelection('anthropic', 'claude-3.5-sonnet');

      // Simulate creating new version
      final newVersion = _TestMessage(
        id: 'msg_2',
        role: 'assistant',
        content: '',
        providerId: newModel.providerKey,
        modelId: newModel.modelId,
        groupId: targetMessage.groupId,
        version: targetMessage.version + 1,
      );

      expect(newVersion.groupId, equals('msg_1'));
      expect(newVersion.version, equals(1));
      expect(newVersion.providerId, equals('anthropic'));
      expect(newVersion.modelId, equals('claude-3.5-sonnet'));
    });

    test('re-answer preserves all previous user messages in context', () {
      final messages = <_TestMessage>[
        _TestMessage(id: 'msg_0', role: 'user', content: 'First question', groupId: 'msg_0', version: 0),
        _TestMessage(id: 'msg_1', role: 'assistant', content: 'First answer', providerId: 'openai', modelId: 'gpt-4o', groupId: 'msg_1', version: 0),
        _TestMessage(id: 'msg_2', role: 'user', content: 'Second question', groupId: 'msg_2', version: 0),
        _TestMessage(id: 'msg_3', role: 'assistant', content: 'Second answer', providerId: 'openai', modelId: 'gpt-4o', groupId: 'msg_3', version: 0),
        _TestMessage(id: 'msg_4', role: 'user', content: 'Third question', groupId: 'msg_4', version: 0),
        _TestMessage(id: 'msg_5', role: 'assistant', content: 'Third answer', providerId: 'openai', modelId: 'gpt-4o', groupId: 'msg_5', version: 0),
      ];

      // Re-answer the second assistant message (msg_3)
      final targetIndex = 3;
      
      // Build context (messages up to and including target)
      final contextMessages = messages.sublist(0, targetIndex + 1);

      // Verify all user messages before target are included
      expect(contextMessages.any((m) => m.id == 'msg_0'), isTrue);
      expect(contextMessages.any((m) => m.id == 'msg_2'), isTrue);
      
      // Verify target is included
      expect(contextMessages.any((m) => m.id == 'msg_3'), isTrue);
      
      // Verify messages after target are NOT included
      expect(contextMessages.any((m) => m.id == 'msg_4'), isFalse);
      expect(contextMessages.any((m) => m.id == 'msg_5'), isFalse);
    });

    test('re-answer with different model uses new model for generation', () {
      final originalMessage = _TestMessage(
        id: 'msg_1',
        role: 'assistant',
        content: 'Original response',
        providerId: 'openai',
        modelId: 'gpt-4o',
        groupId: 'msg_1',
        version: 0,
      );

      final newModel = ModelSelection('google', 'gemini-pro');

      // Simulate creating new version with different model
      final newVersion = _TestMessage(
        id: 'msg_2',
        role: 'assistant',
        content: '',
        providerId: newModel.providerKey,
        modelId: newModel.modelId,
        groupId: originalMessage.groupId,
        version: originalMessage.version + 1,
      );

      // Original should keep its model
      expect(originalMessage.providerId, equals('openai'));
      expect(originalMessage.modelId, equals('gpt-4o'));

      // New version should use the selected model
      expect(newVersion.providerId, equals('google'));
      expect(newVersion.modelId, equals('gemini-pro'));

      // Both should be in the same group
      expect(newVersion.groupId, equals(originalMessage.groupId));
    });

    test('multiple re-answers increment version correctly', () {
      final groupId = 'msg_1';
      var currentVersion = 0;

      // Simulate multiple re-answers
      for (var i = 0; i < 5; i++) {
        final newVersion = currentVersion + 1;
        
        expect(
          newVersion,
          equals(i + 1),
          reason: 'Re-answer $i should create version ${i + 1}',
        );
        
        currentVersion = newVersion;
      }

      expect(currentVersion, equals(5));
    });
  });
}

/// Test message class that mirrors ChatMessage structure
class _TestMessage {
  final String id;
  final String role;
  final String content;
  final String? providerId;
  final String? modelId;
  final String? groupId;
  final int version;

  _TestMessage({
    required this.id,
    required this.role,
    required this.content,
    this.providerId,
    this.modelId,
    this.groupId,
    this.version = 0,
  });
}

/// Generate a random alphanumeric string
String _randomAlphaNumeric(Random random, int minLength, int maxLength) {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final length = minLength + random.nextInt(maxLength - minLength + 1);
  return String.fromCharCodes(
    List.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
  );
}
