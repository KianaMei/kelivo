import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo/features/model/widgets/model_select_sheet.dart';
import 'package:kelivo/features/home/widgets/mentioned_models_chips.dart';

/// **Feature: mention-models-feature, Property 10: Chips display model information**
/// **Validates: Requirements 5.1**
///
/// *For any* model in the mentioned models list, the corresponding chip should
/// display the model name and provider name.
void main() {
  group('MentionedModelsChips', () {
    /// **Feature: mention-models-feature, Property 10: Chips display model information**
    /// **Validates: Requirements 5.1**
    ///
    /// Property-based test: For any randomly generated list of models,
    /// each chip should display the model name and provider name.
    testWidgets(
      'Property 10: For any model in the mentioned models list, the chip displays model name and provider name',
      (tester) async {
        final random = Random(42); // Fixed seed for reproducibility
        
        // Run 100 iterations with different random inputs
        for (var iteration = 0; iteration < 100; iteration++) {
          // Generate 1 model per iteration to ensure it's visible
          // (ListView is lazy and only renders visible items)
          final providerKey = _randomAlphaNumeric(random, 3, 10);
          final modelId = _randomAlphaNumeric(random, 3, 15);
          final model = ModelSelection(providerKey, modelId);

          final providerDisplayName = 'Provider_$providerKey';
          final modelDisplayName = 'Model_$modelId';

          // Build the widget with a single model
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MentionedModelsChips(
                  mentionedModels: [model],
                  providerNames: {providerKey: providerDisplayName},
                  modelDisplayNames: {'$providerKey::$modelId': modelDisplayName},
                  onRemove: (_) {},
                ),
              ),
            ),
          );

          // Verify the model's information is displayed
          // Find Text widgets that contain the expected text
          final modelTextFinder = find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == modelDisplayName,
          );
          final providerTextFinder = find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == providerDisplayName,
          );

          expect(
            modelTextFinder,
            findsOneWidget,
            reason: 'Iteration $iteration: Chip should have Text widget with model name: $modelDisplayName',
          );
          expect(
            providerTextFinder,
            findsOneWidget,
            reason: 'Iteration $iteration: Chip should have Text widget with provider name: $providerDisplayName',
          );
        }
      },
    );

    testWidgets('renders empty when no models provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MentionedModelsChips(
              mentionedModels: const [],
              onRemove: (_) {},
            ),
          ),
        ),
      );

      // Should render SizedBox.shrink() - no visible content
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('calls onRemove when remove button is tapped', (tester) async {
      final model = ModelSelection('openai', 'gpt-4o');
      ModelSelection? removedModel;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MentionedModelsChips(
              mentionedModels: [model],
              providerNames: const {'openai': 'OpenAI'},
              modelDisplayNames: const {'openai::gpt-4o': 'GPT-4o'},
              onRemove: (m) => removedModel = m,
            ),
          ),
        ),
      );

      // Find and tap the remove button (X icon container)
      final removeButton = find.byWidgetPredicate(
        (widget) => widget is GestureDetector && 
                    widget.child is Container &&
                    (widget.child as Container).child is Icon,
      );
      
      expect(removeButton, findsOneWidget);
      await tester.tap(removeButton);
      await tester.pump();

      // Verify onRemove was called with the correct model
      expect(removedModel, isNotNull);
      expect(removedModel!.providerKey, equals('openai'));
      expect(removedModel!.modelId, equals('gpt-4o'));
    });

    testWidgets('displays fallback names when display names not provided', (tester) async {
      final model = ModelSelection('test-provider', 'test-model');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MentionedModelsChips(
              mentionedModels: [model],
              onRemove: (_) {},
            ),
          ),
        ),
      );

      // Should fall back to providerKey and modelId
      expect(find.text('test-model'), findsOneWidget);
      expect(find.text('test-provider'), findsOneWidget);
    });

    testWidgets('supports horizontal scrolling with multiple chips', (tester) async {
      // Create many models to test scrolling
      final models = List.generate(10, (i) => ModelSelection('provider$i', 'model$i'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MentionedModelsChips(
              mentionedModels: models,
              onRemove: (_) {},
            ),
          ),
        ),
      );

      // Should have a horizontal ListView
      final listView = find.byType(ListView);
      expect(listView, findsOneWidget);
      
      final listViewWidget = tester.widget<ListView>(listView);
      expect(listViewWidget.scrollDirection, equals(Axis.horizontal));
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
