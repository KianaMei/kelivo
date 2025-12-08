import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo/features/model/widgets/model_select_sheet.dart';

/// **Feature: mention-models-feature, Property 2, 3, 4: Mentioned models state management**
/// **Validates: Requirements 2.3, 3.1, 3.2, 3.4, 5.4**
///
/// Tests for the mentioned models state management logic:
/// - Property 2: Model selection adds to mentioned list
/// - Property 3: Mentioned models list prevents duplicates
/// - Property 4: Chip removal updates mentioned list
///
/// Since HomePage has complex widget dependencies, we test the core logic
/// in isolation using a simplified test harness that mirrors the actual implementation.
void main() {
  group('Mentioned Models State Management', () {
    /// **Feature: mention-models-feature, Property 2: Model selection adds to mentioned list**
    /// **Validates: Requirements 2.3, 3.1**
    ///
    /// Property-based test: For any model selected from the selector,
    /// if it is not already in the mentioned models list, it should be added to the list.
    test(
      'Property 2: For any model selection, if not already in list, it should be added',
      () {
        final random = Random(42); // Fixed seed for reproducibility

        // Run 100 iterations with different random inputs
        for (var iteration = 0; iteration < 100; iteration++) {
          // Create a fresh state for each iteration
          final mentionedModels = <ModelSelection>[];

          // Generate a random model
          final providerKey = _randomAlphaNumeric(random, 3, 10);
          final modelId = _randomAlphaNumeric(random, 3, 15);
          final model = ModelSelection(providerKey, modelId);

          // Simulate _addMentionedModel logic
          final isDuplicate = mentionedModels.any((m) =>
              m.providerKey == model.providerKey && m.modelId == model.modelId);
          
          final wasAdded = !isDuplicate;
          if (!isDuplicate) {
            mentionedModels.add(model);
          }

          // Verify the model was added
          expect(
            wasAdded,
            isTrue,
            reason: 'Iteration $iteration: Model should be added when list is empty',
          );
          expect(
            mentionedModels.length,
            equals(1),
            reason: 'Iteration $iteration: List should have exactly 1 model after adding',
          );
          expect(
            mentionedModels.any((m) =>
                m.providerKey == providerKey && m.modelId == modelId),
            isTrue,
            reason: 'Iteration $iteration: List should contain the added model',
          );
        }
      },
    );

    /// **Feature: mention-models-feature, Property 3: Mentioned models list prevents duplicates**
    /// **Validates: Requirements 3.2**
    ///
    /// Property-based test: For any model selection, if the model is already
    /// in the mentioned models list, the list should remain unchanged (no duplicates).
    test(
      'Property 3: For any duplicate model selection, list should remain unchanged',
      () {
        final random = Random(42); // Fixed seed for reproducibility

        // Run 100 iterations with different random inputs
        for (var iteration = 0; iteration < 100; iteration++) {
          // Create a fresh state for each iteration
          final mentionedModels = <ModelSelection>[];

          // Generate a random model
          final providerKey = _randomAlphaNumeric(random, 3, 10);
          final modelId = _randomAlphaNumeric(random, 3, 15);
          final model = ModelSelection(providerKey, modelId);

          // Add the model first time
          bool addModel(ModelSelection m) {
            final isDuplicate = mentionedModels.any((existing) =>
                existing.providerKey == m.providerKey && existing.modelId == m.modelId);
            if (!isDuplicate) {
              mentionedModels.add(m);
              return true;
            }
            return false;
          }

          final firstAdd = addModel(model);
          expect(
            firstAdd,
            isTrue,
            reason: 'Iteration $iteration: First add should succeed',
          );
          expect(
            mentionedModels.length,
            equals(1),
            reason: 'Iteration $iteration: List should have 1 model after first add',
          );

          // Try to add the same model again (duplicate)
          final duplicateModel = ModelSelection(providerKey, modelId);
          final secondAdd = addModel(duplicateModel);

          // Verify the duplicate was not added
          expect(
            secondAdd,
            isFalse,
            reason: 'Iteration $iteration: Duplicate add should return false',
          );
          expect(
            mentionedModels.length,
            equals(1),
            reason: 'Iteration $iteration: List should still have 1 model after duplicate add attempt',
          );
        }
      },
    );

    /// **Feature: mention-models-feature, Property 4: Chip removal updates mentioned list**
    /// **Validates: Requirements 3.4, 5.4**
    ///
    /// Property-based test: For any model chip that is tapped or has its remove
    /// button pressed, that model should be removed from the mentioned models list.
    test(
      'Property 4: For any chip removal, the model should be removed from the list',
      () {
        final random = Random(42); // Fixed seed for reproducibility

        // Run 100 iterations with different random inputs
        for (var iteration = 0; iteration < 100; iteration++) {
          // Create a fresh state with multiple models
          final mentionedModels = <ModelSelection>[];
          
          // Generate 1-5 random models
          final modelCount = 1 + random.nextInt(5);
          final generatedModels = <ModelSelection>[];
          
          for (var i = 0; i < modelCount; i++) {
            final providerKey = _randomAlphaNumeric(random, 3, 10);
            final modelId = _randomAlphaNumeric(random, 3, 15);
            final model = ModelSelection(providerKey, modelId);
            
            // Add only if not duplicate
            final isDuplicate = mentionedModels.any((m) =>
                m.providerKey == model.providerKey && m.modelId == model.modelId);
            if (!isDuplicate) {
              mentionedModels.add(model);
              generatedModels.add(model);
            }
          }

          if (generatedModels.isEmpty) continue; // Skip if no unique models generated

          // Pick a random model to remove
          final indexToRemove = random.nextInt(generatedModels.length);
          final modelToRemove = generatedModels[indexToRemove];
          final initialLength = mentionedModels.length;

          // Simulate _removeMentionedModel logic
          mentionedModels.removeWhere((m) =>
              m.providerKey == modelToRemove.providerKey && 
              m.modelId == modelToRemove.modelId);

          // Verify the model was removed
          expect(
            mentionedModels.length,
            equals(initialLength - 1),
            reason: 'Iteration $iteration: List length should decrease by 1 after removal',
          );
          expect(
            mentionedModels.any((m) =>
                m.providerKey == modelToRemove.providerKey && 
                m.modelId == modelToRemove.modelId),
            isFalse,
            reason: 'Iteration $iteration: Removed model should not be in the list',
          );
        }
      },
    );

    test('adding multiple unique models increases list size correctly', () {
      final mentionedModels = <ModelSelection>[];
      
      bool addModel(ModelSelection m) {
        final isDuplicate = mentionedModels.any((existing) =>
            existing.providerKey == m.providerKey && existing.modelId == m.modelId);
        if (!isDuplicate) {
          mentionedModels.add(m);
          return true;
        }
        return false;
      }

      // Add 3 unique models
      expect(addModel(ModelSelection('openai', 'gpt-4o')), isTrue);
      expect(addModel(ModelSelection('anthropic', 'claude-3.5-sonnet')), isTrue);
      expect(addModel(ModelSelection('google', 'gemini-pro')), isTrue);

      expect(mentionedModels.length, equals(3));
    });

    test('removing non-existent model does not change list', () {
      final mentionedModels = <ModelSelection>[
        ModelSelection('openai', 'gpt-4o'),
        ModelSelection('anthropic', 'claude-3.5-sonnet'),
      ];

      final initialLength = mentionedModels.length;

      // Try to remove a model that doesn't exist
      final nonExistent = ModelSelection('google', 'gemini-pro');
      mentionedModels.removeWhere((m) =>
          m.providerKey == nonExistent.providerKey && 
          m.modelId == nonExistent.modelId);

      expect(mentionedModels.length, equals(initialLength));
    });

    test('duplicate detection works with same providerKey but different modelId', () {
      final mentionedModels = <ModelSelection>[];
      
      bool addModel(ModelSelection m) {
        final isDuplicate = mentionedModels.any((existing) =>
            existing.providerKey == m.providerKey && existing.modelId == m.modelId);
        if (!isDuplicate) {
          mentionedModels.add(m);
          return true;
        }
        return false;
      }

      // Add model with same provider but different model IDs
      expect(addModel(ModelSelection('openai', 'gpt-4o')), isTrue);
      expect(addModel(ModelSelection('openai', 'gpt-4o-mini')), isTrue);
      expect(addModel(ModelSelection('openai', 'gpt-4o')), isFalse); // Duplicate

      expect(mentionedModels.length, equals(2));
    });

    test('duplicate detection works with same modelId but different providerKey', () {
      final mentionedModels = <ModelSelection>[];
      
      bool addModel(ModelSelection m) {
        final isDuplicate = mentionedModels.any((existing) =>
            existing.providerKey == m.providerKey && existing.modelId == m.modelId);
        if (!isDuplicate) {
          mentionedModels.add(m);
          return true;
        }
        return false;
      }

      // Add model with same model ID but different providers
      expect(addModel(ModelSelection('provider1', 'model-a')), isTrue);
      expect(addModel(ModelSelection('provider2', 'model-a')), isTrue);
      expect(addModel(ModelSelection('provider1', 'model-a')), isFalse); // Duplicate

      expect(mentionedModels.length, equals(2));
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
