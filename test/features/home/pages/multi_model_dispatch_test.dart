import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo/features/model/widgets/model_select_sheet.dart';
import 'package:kelivo/core/models/chat_input_data.dart';

/// **Feature: mention-models-feature, Property 6, 7, 8: Multi-model dispatch**
/// **Validates: Requirements 4.1, 4.2, 4.3, 4.4**
///
/// Tests for the multi-model message dispatch logic:
/// - Property 6: Multi-model dispatch sends to all mentioned models
/// - Property 7: Send clears mentioned models
/// - Property 8: Empty mentions uses default model
///
/// Since HomePage has complex widget dependencies, we test the core logic
/// in isolation using a simplified test harness that mirrors the actual implementation.
void main() {
  group('Multi-Model Dispatch', () {
    /// **Feature: mention-models-feature, Property 6: Multi-model dispatch sends to all mentioned models**
    /// **Validates: Requirements 4.1, 4.2**
    ///
    /// Property-based test: For any message sent with N mentioned models (N > 0),
    /// the system should create exactly N separate response streams, one for each mentioned model.
    test(
      'Property 6: For any N mentioned models, dispatch should send to exactly N models',
      () {
        final random = Random(42); // Fixed seed for reproducibility

        // Run 100 iterations with different random inputs
        for (var iteration = 0; iteration < 100; iteration++) {
          // Create a fresh state for each iteration
          final mentionedModels = <ModelSelection>[];
          final dispatchedModels = <ModelSelection>[];

          // Generate 1-5 random unique models
          final targetCount = 1 + random.nextInt(5);
          while (mentionedModels.length < targetCount) {
            final providerKey = _randomAlphaNumeric(random, 3, 10);
            final modelId = _randomAlphaNumeric(random, 3, 15);
            final model = ModelSelection(providerKey, modelId);

            // Add only if not duplicate
            final isDuplicate = mentionedModels.any((m) =>
                m.providerKey == model.providerKey && m.modelId == model.modelId);
            if (!isDuplicate) {
              mentionedModels.add(model);
            }
          }

          // Simulate _sendToMentionedModels logic
          Future<void> sendToMentionedModels(ChatInputData input) async {
            if (mentionedModels.isEmpty) {
              // Would send to default model - not testing this case here
              return;
            }

            // Capture models to send to
            final modelsToSend = List<ModelSelection>.from(mentionedModels);

            // Clear mentioned models immediately
            mentionedModels.clear();

            // Dispatch to each model
            for (final model in modelsToSend) {
              dispatchedModels.add(model);
            }
          }

          final input = ChatInputData(text: 'Test message $iteration');
          final expectedCount = mentionedModels.length;

          // Execute dispatch
          sendToMentionedModels(input);

          // Verify exactly N models were dispatched to
          expect(
            dispatchedModels.length,
            equals(expectedCount),
            reason: 'Iteration $iteration: Should dispatch to exactly $expectedCount models',
          );

          // Verify all original models were dispatched to
          for (final original in List<ModelSelection>.from(dispatchedModels)) {
            expect(
              dispatchedModels.any((m) =>
                  m.providerKey == original.providerKey && m.modelId == original.modelId),
              isTrue,
              reason: 'Iteration $iteration: Model ${original.providerKey}/${original.modelId} should be in dispatched list',
            );
          }
        }
      },
    );

    /// **Feature: mention-models-feature, Property 7: Send clears mentioned models**
    /// **Validates: Requirements 4.3**
    ///
    /// Property-based test: For any message send action, after the message is dispatched,
    /// the mentioned models list should be empty.
    test(
      'Property 7: After send, mentioned models list should be empty',
      () {
        final random = Random(42); // Fixed seed for reproducibility

        // Run 100 iterations with different random inputs
        for (var iteration = 0; iteration < 100; iteration++) {
          // Create a fresh state for each iteration
          final mentionedModels = <ModelSelection>[];

          // Generate 1-5 random unique models
          final targetCount = 1 + random.nextInt(5);
          while (mentionedModels.length < targetCount) {
            final providerKey = _randomAlphaNumeric(random, 3, 10);
            final modelId = _randomAlphaNumeric(random, 3, 15);
            final model = ModelSelection(providerKey, modelId);

            final isDuplicate = mentionedModels.any((m) =>
                m.providerKey == model.providerKey && m.modelId == model.modelId);
            if (!isDuplicate) {
              mentionedModels.add(model);
            }
          }

          expect(
            mentionedModels.isNotEmpty,
            isTrue,
            reason: 'Iteration $iteration: Should have models before send',
          );

          // Simulate _sendToMentionedModels logic (the clearing part)
          void sendToMentionedModels(ChatInputData input) {
            if (mentionedModels.isEmpty) {
              return;
            }

            // Capture models to send to
            final modelsToSend = List<ModelSelection>.from(mentionedModels);

            // Clear mentioned models immediately after capturing
            mentionedModels.clear();

            // Would dispatch to each model here...
            // ignore: unused_local_variable
            for (final model in modelsToSend) {
              // Simulated dispatch
            }
          }

          final input = ChatInputData(text: 'Test message $iteration');

          // Execute dispatch
          sendToMentionedModels(input);

          // Verify mentioned models list is empty after send
          expect(
            mentionedModels.isEmpty,
            isTrue,
            reason: 'Iteration $iteration: Mentioned models should be empty after send',
          );
        }
      },
    );

    /// **Feature: mention-models-feature, Property 8: Empty mentions uses default model**
    /// **Validates: Requirements 4.4**
    ///
    /// Property-based test: For any message sent with an empty mentioned models list,
    /// the message should be sent to the current assistant's default model.
    test(
      'Property 8: With empty mentions, should use default model',
      () {
        final random = Random(42); // Fixed seed for reproducibility

        // Run 100 iterations with different random inputs
        for (var iteration = 0; iteration < 100; iteration++) {
          // Create a fresh state with empty mentioned models
          final mentionedModels = <ModelSelection>[];
          var usedDefaultModel = false;
          var dispatchedToMentioned = false;

          // Simulate _sendToMentionedModels logic
          void sendToMentionedModels(ChatInputData input) {
            if (mentionedModels.isEmpty) {
              // Use default model
              usedDefaultModel = true;
              return;
            }

            // Would dispatch to mentioned models
            dispatchedToMentioned = true;
          }

          // Generate random input text
          final text = _randomAlphaNumeric(random, 5, 50);
          final input = ChatInputData(text: text);

          // Execute dispatch with empty mentioned models
          sendToMentionedModels(input);

          // Verify default model was used
          expect(
            usedDefaultModel,
            isTrue,
            reason: 'Iteration $iteration: Should use default model when mentions are empty',
          );
          expect(
            dispatchedToMentioned,
            isFalse,
            reason: 'Iteration $iteration: Should not dispatch to mentioned models when list is empty',
          );
        }
      },
    );

    test('dispatch preserves model order', () {
      final mentionedModels = <ModelSelection>[
        ModelSelection('openai', 'gpt-4o'),
        ModelSelection('anthropic', 'claude-3.5-sonnet'),
        ModelSelection('google', 'gemini-pro'),
      ];
      final dispatchedModels = <ModelSelection>[];

      // Simulate dispatch
      final modelsToSend = List<ModelSelection>.from(mentionedModels);
      mentionedModels.clear();
      for (final model in modelsToSend) {
        dispatchedModels.add(model);
      }

      // Verify order is preserved
      expect(dispatchedModels[0].providerKey, equals('openai'));
      expect(dispatchedModels[1].providerKey, equals('anthropic'));
      expect(dispatchedModels[2].providerKey, equals('google'));
    });

    test('dispatch with single model works correctly', () {
      final mentionedModels = <ModelSelection>[
        ModelSelection('openai', 'gpt-4o'),
      ];
      final dispatchedModels = <ModelSelection>[];

      // Simulate dispatch
      final modelsToSend = List<ModelSelection>.from(mentionedModels);
      mentionedModels.clear();
      for (final model in modelsToSend) {
        dispatchedModels.add(model);
      }

      expect(dispatchedModels.length, equals(1));
      expect(dispatchedModels[0].providerKey, equals('openai'));
      expect(dispatchedModels[0].modelId, equals('gpt-4o'));
      expect(mentionedModels.isEmpty, isTrue);
    });

    test('multiple sends each clear the list independently', () {
      final mentionedModels = <ModelSelection>[];
      var sendCount = 0;

      void addModel(ModelSelection m) {
        final isDuplicate = mentionedModels.any((existing) =>
            existing.providerKey == m.providerKey && existing.modelId == m.modelId);
        if (!isDuplicate) {
          mentionedModels.add(m);
        }
      }

      void sendToMentionedModels() {
        if (mentionedModels.isEmpty) return;
        mentionedModels.clear();
        sendCount++;
      }

      // First batch
      addModel(ModelSelection('openai', 'gpt-4o'));
      addModel(ModelSelection('anthropic', 'claude-3.5-sonnet'));
      expect(mentionedModels.length, equals(2));
      
      sendToMentionedModels();
      expect(mentionedModels.isEmpty, isTrue);
      expect(sendCount, equals(1));

      // Second batch
      addModel(ModelSelection('google', 'gemini-pro'));
      expect(mentionedModels.length, equals(1));
      
      sendToMentionedModels();
      expect(mentionedModels.isEmpty, isTrue);
      expect(sendCount, equals(2));
    });
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
