import '../core/providers/model_provider.dart';

/// Utility for grouping models by vendor/family for display purposes.
class ModelGrouping {
  /// Returns a human-readable group name for the given model.
  static String groupFor(
    ModelInfo m, {
    required String embeddingsLabel,
    required String otherLabel,
  }) {
    final id = m.id.toLowerCase();

    // Check for embedding models first
    if (m.type == ModelType.embedding ||
        id.contains('embedding') ||
        id.contains('embed')) {
      return embeddingsLabel;
    }

    // OpenAI GPT models
    if (id.contains('gpt') || RegExp(r'(^|[^a-z])o[134]').hasMatch(id)) {
      return 'GPT';
    }

    // Google Gemini models
    if (id.contains('gemini-3')) return 'Gemini 3';
    if (id.contains('gemini-2.5')) return 'Gemini 2.5';
    if (id.contains('gemini')) return 'Gemini';

    // Anthropic Claude models
    if (id.contains('claude-4')) return 'Claude 4';
    if (id.contains('claude-sonnet')) return 'Claude Sonnet';
    if (id.contains('claude-opus')) return 'Claude Opus';
    if (id.contains('claude-haiku')) return 'Claude Haiku';
    if (id.contains('claude-3.5')) return 'Claude 3.5';
    if (id.contains('claude-3')) return 'Claude 3';

    // Chinese providers
    if (id.contains('deepseek')) return 'DeepSeek';
    if (id.contains('kimi')) return 'Kimi';
    if (RegExp(r'qwen|qwq|qvq|dashscope').hasMatch(id)) return 'Qwen';
    if (RegExp(r'doubao|ark|volc').hasMatch(id)) return 'Doubao';
    if (id.contains('glm') || id.contains('zhipu')) return 'GLM';
    if (id.contains('minimax')) return 'MiniMax';

    // Other providers
    if (id.contains('mistral')) return 'Mistral';
    if (id.contains('grok') || id.contains('xai')) return 'Grok';
    if (id.contains('kat')) return 'KAT';

    return otherLabel;
  }
}
