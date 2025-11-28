import '../providers/model_provider.dart';
import '../providers/settings_provider.dart';

/// Centralized model capability detection to eliminate scattered if/else logic.
///
/// This module provides a single source of truth for determining what features
/// a model supports (tools, reasoning, images, streaming, etc.). All logic is
/// extracted from existing implementations to maintain byte-for-byte compatibility.
///
/// **Design Principles**:
/// - Conservative defaults (assume unsupported unless proven otherwise)
/// - Per-model overrides via `ProviderConfig.modelOverrides`
/// - Provider-level allow/deny lists
/// - Special handling for known model families (Grok, Gemini, etc.)
class ModelCapabilities {
  ModelCapabilities._();

  /// Checks if a model supports tool/function calling.
  ///
  /// **Logic**:
  /// 1. Check `modelOverrides[modelId].abilities` for explicit 'tool' capability
  /// 2. Fall back to `ModelRegistry.infer()` pattern matching
  ///
  /// **Example**:
  /// ```dart
  /// final cfg = settings.getProviderConfig('openai');
  /// if (ModelCapabilities.supportsTools(cfg, 'gpt-4o')) {
  ///   // Enable tool calling UI
  /// }
  /// ```
  static bool supportsTools(ProviderConfig config, String modelId) {
    try {
      final ov = config.modelOverrides[modelId];
      if (ov is Map<String, dynamic>) {
        final abilities = (ov['abilities'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            const [];
        if (abilities.contains('tool')) return true;
      }
    } catch (_) {}

    // Fallback to ModelRegistry inference
    final inferred = ModelRegistry.infer(
      ModelInfo(id: modelId, displayName: modelId),
    );
    return inferred.abilities.contains(ModelAbility.tool);
  }

  /// Checks if a model supports reasoning/thinking modes.
  ///
  /// **Special Cases**:
  /// - **Grok models**: Only Grok-3-Mini supports reasoning controls.
  ///   Grok-4 and other Grok models are reasoning models but don't support
  ///   the `reasoning_effort` parameter, so we return `false` to hide controls.
  ///
  /// **Logic**:
  /// 1. Check for Grok models with special handling
  /// 2. Check `modelOverrides[modelId].abilities` for 'reasoning'
  /// 3. Fall back to `ModelRegistry.infer()`
  ///
  /// **Example**:
  /// ```dart
  /// if (ModelCapabilities.supportsReasoning(cfg, 'o1-preview')) {
  ///   // Show reasoning budget controls
  /// }
  /// ```
  static bool supportsReasoning(ProviderConfig config, String modelId) {
    final modelLower = modelId.toLowerCase();

    // Special handling for Grok models
    // Grok 3 Mini series supports reasoning controls
    if (modelLower.contains('grok')) {
      if (modelLower.contains('grok-3-mini')) {
        return true;
      }
      // Grok 4 and other Grok models don't support reasoning_effort parameter
      // Return false to hide reasoning controls
      return false;
    }

    try {
      final ov = config.modelOverrides[modelId];
      if (ov is Map<String, dynamic>) {
        final abilities = (ov['abilities'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            const [];
        if (abilities.contains('reasoning')) return true;
      }
    } catch (_) {}

    // Fallback to ModelRegistry inference
    final inferred = ModelRegistry.infer(
      ModelInfo(id: modelId, displayName: modelId),
    );
    return inferred.abilities.contains(ModelAbility.reasoning);
  }

  /// Checks if a model supports image input (vision capability).
  ///
  /// **Logic**:
  /// 1. Check `modelOverrides[modelId].input` for 'image' modality
  /// 2. Fall back to `ModelRegistry.infer()`
  ///
  /// **Example**:
  /// ```dart
  /// if (ModelCapabilities.supportsImages(cfg, 'gpt-4o')) {
  ///   // Allow image attachments
  /// }
  /// ```
  static bool supportsImages(ProviderConfig config, String modelId) {
    try {
      final ov = config.modelOverrides[modelId];
      if (ov is Map<String, dynamic>) {
        final input = (ov['input'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            const [];
        if (input.contains('image')) return true;
      }
    } catch (_) {}

    // Fallback to ModelRegistry inference
    final inferred = ModelRegistry.infer(
      ModelInfo(id: modelId, displayName: modelId),
    );
    return inferred.input.contains(Modality.image);
  }

  /// Returns the set of built-in tools configured for a model.
  ///
  /// Built-in tools are provider-native features like web search that don't
  /// require external tool definitions. Examples:
  /// - Gemini: `google_search`, `code_execution`
  /// - Grok: `search`
  /// - Claude: `search` (web search)
  ///
  /// **Configuration**:
  /// Stored under `ProviderConfig.modelOverrides[modelId].builtInTools` as a list.
  ///
  /// **Example**:
  /// ```dart
  /// final tools = ModelCapabilities.builtInTools(cfg, 'gemini-2.0-flash-exp');
  /// if (tools.contains('search')) {
  ///   // Enable built-in search UI
  /// }
  /// ```
  static Set<String> builtInTools(ProviderConfig config, String modelId) {
    try {
      final ov = config.modelOverrides[modelId];
      if (ov is Map<String, dynamic>) {
        final raw = ov['builtInTools'];
        if (raw is List) {
          return raw
              .map((e) => e.toString().trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toSet();
        }
      }
    } catch (_) {}
    return const <String>{};
  }

  /// Checks if a model is a Grok model (xAI).
  ///
  /// **Detection**:
  /// - Checks both the logical `modelId` and the upstream `apiModelId` (if overridden)
  /// - Matches patterns: `grok`, `xai-`
  ///
  /// **Example**:
  /// ```dart
  /// if (ModelCapabilities.isGrokModel(cfg, 'grok-4')) {
  ///   // Apply Grok-specific API parameters
  /// }
  /// ```
  static bool isGrokModel(ProviderConfig config, String modelId) {
    final apiModel = _apiModelId(config, modelId).toLowerCase();
    final logicalModel = modelId.toLowerCase();

    // Check common Grok model name patterns
    final grokPatterns = ['grok', 'xai-'];
    for (final pattern in grokPatterns) {
      if (apiModel.contains(pattern) || logicalModel.contains(pattern)) {
        return true;
      }
    }

    return false;
  }

  /// Checks if a model is a Gemini model (Google).
  ///
  /// **Detection**:
  /// - Matches pattern: `gemini`
  ///
  /// **Example**:
  /// ```dart
  /// if (ModelCapabilities.isGeminiModel(cfg, 'gemini-2.0-flash-exp')) {
  ///   // Use Gemini-specific API format
  /// }
  /// ```
  static bool isGeminiModel(ProviderConfig config, String modelId) {
    final apiModel = _apiModelId(config, modelId).toLowerCase();
    final logicalModel = modelId.toLowerCase();
    return apiModel.contains('gemini') || logicalModel.contains('gemini');
  }

  /// Resolves the upstream/vendor model ID for API requests.
  ///
  /// When `ProviderConfig.modelOverrides[modelId].apiModelId` is set, that value
  /// is used for outbound HTTP requests. Otherwise, the logical `modelId` is used.
  ///
  /// **Example**:
  /// ```dart
  /// // User sees "GPT-4o" in UI, but API uses "gpt-4o-2024-11-20"
  /// final apiId = ModelCapabilities.getApiModelId(cfg, 'GPT-4o');
  /// // => "gpt-4o-2024-11-20"
  /// ```
  static String getApiModelId(ProviderConfig config, String modelId) {
    return _apiModelId(config, modelId);
  }

  /// Determines the provider kind (OpenAI, Anthropic, Google, xAI, etc.).
  ///
  /// **Logic**:
  /// 1. Check explicit `providerType` field
  /// 2. Infer from `baseUrl` hostname patterns
  ///
  /// **Example**:
  /// ```dart
  /// final kind = ModelCapabilities.getProviderKind(cfg);
  /// if (kind == 'anthropic') {
  ///   // Use Claude-specific message format
  /// }
  /// ```
  static String getProviderKind(ProviderConfig config) {
    // Priority 1: Explicit provider type
    final explicit = config.providerType?.trim().toLowerCase();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    // Priority 2: Infer from baseUrl
    try {
      final host = Uri.parse(config.baseUrl).host.toLowerCase();
      if (host.contains('anthropic')) return 'anthropic';
      if (host.contains('openai')) return 'openai';
      if (host.contains('google') || host.contains('generativelanguage')) {
        return 'google';
      }
      if (host.contains('xai')) return 'xai';
      if (host.contains('cohere')) return 'cohere';
    } catch (_) {}

    return 'unknown';
  }

  // ========== Private Helpers ==========

  /// Resolves the upstream API model ID from overrides.
  static String _apiModelId(ProviderConfig config, String modelId) {
    try {
      final ov = config.modelOverrides[modelId];
      if (ov is Map<String, dynamic>) {
        final raw =
            (ov['apiModelId'] ?? ov['api_model_id'])?.toString().trim();
        if (raw != null && raw.isNotEmpty) return raw;
      }
    } catch (_) {}
    return modelId;
  }
}
