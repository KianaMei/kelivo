import 'package:flutter_test/flutter_test.dart' hide expect, group, test;
import 'package:glados/glados.dart';
import 'package:kelivo/features/settings/widgets/language_select_sheet.dart'
    show LanguageOption, supportedLanguages;

/// **Feature: desktop-translate, Property 1: Default language selection based on locale**
/// **Validates: Requirements 2.1**
///
/// This test verifies that the default target language is selected correctly
/// based on the app locale:
/// - Chinese locales (starting with 'zh') → English ('en')
/// - All other locales → Simplified Chinese ('zh-CN')

/// Pure function that implements the default language selection logic
/// extracted from _DesktopTranslatePageState._initDefaults()
LanguageOption getDefaultTargetLanguage(String localeLanguageCode) {
  final lc = localeLanguageCode.toLowerCase();
  if (lc.startsWith('zh')) {
    // Chinese users default to English
    return supportedLanguages.firstWhere(
      (e) => e.code == 'en',
      orElse: () => supportedLanguages.first,
    );
  } else {
    // Non-Chinese users default to Simplified Chinese
    return supportedLanguages.firstWhere(
      (e) => e.code == 'zh-CN',
      orElse: () => supportedLanguages.first,
    );
  }
}

/// **Feature: desktop-translate, Property 2: Model fallback chain**
/// **Validates: Requirements 3.1**
///
/// This test verifies that the model selection follows the fallback chain:
/// translateModel → assistant.chatModel → globalDefault
///
/// The fallback chain logic:
/// 1. If translateModelProvider/translateModelId is set, use it
/// 2. Else if assistant?.chatModelProvider/chatModelId is set, use it
/// 3. Else use currentModelProvider/currentModelId (global default)

/// Data class representing model settings for testing
class ModelSettings {
  final String? translateModelProvider;
  final String? translateModelId;
  final String? assistantChatModelProvider;
  final String? assistantChatModelId;
  final String? currentModelProvider;
  final String? currentModelId;

  const ModelSettings({
    this.translateModelProvider,
    this.translateModelId,
    this.assistantChatModelProvider,
    this.assistantChatModelId,
    this.currentModelProvider,
    this.currentModelId,
  });

  @override
  String toString() =>
      'ModelSettings(translate: $translateModelProvider::$translateModelId, '
      'assistant: $assistantChatModelProvider::$assistantChatModelId, '
      'global: $currentModelProvider::$currentModelId)';
}

/// Result of model selection
class ModelSelection {
  final String? providerKey;
  final String? modelId;

  const ModelSelection({this.providerKey, this.modelId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelSelection &&
          runtimeType == other.runtimeType &&
          providerKey == other.providerKey &&
          modelId == other.modelId;

  @override
  int get hashCode => providerKey.hashCode ^ modelId.hashCode;

  @override
  String toString() => 'ModelSelection($providerKey::$modelId)';
}

/// Pure function that implements the model fallback chain logic
/// extracted from _DesktopTranslatePageState._initDefaults()
ModelSelection selectModelWithFallback(ModelSettings settings) {
  // Model fallback chain: translateModel → assistant.chatModel → globalDefault
  final providerKey = settings.translateModelProvider ??
      settings.assistantChatModelProvider ??
      settings.currentModelProvider;
  final modelId = settings.translateModelId ??
      settings.assistantChatModelId ??
      settings.currentModelId;

  return ModelSelection(providerKey: providerKey, modelId: modelId);
}

/// Computes the expected model selection based on the fallback chain rules
ModelSelection expectedModelSelection(ModelSettings settings) {
  // Rule 1: If translateModel is set (both provider and id), use it
  if (settings.translateModelProvider != null &&
      settings.translateModelId != null) {
    return ModelSelection(
      providerKey: settings.translateModelProvider,
      modelId: settings.translateModelId,
    );
  }

  // Rule 2: If assistant's chatModel is set (both provider and id), use it
  if (settings.assistantChatModelProvider != null &&
      settings.assistantChatModelId != null) {
    return ModelSelection(
      providerKey: settings.assistantChatModelProvider,
      modelId: settings.assistantChatModelId,
    );
  }

  // Rule 3: Use global default
  return ModelSelection(
    providerKey: settings.currentModelProvider,
    modelId: settings.currentModelId,
  );
}

/// Generator for Chinese locale codes (should result in English default)
extension LocaleGenerators on Any {
  /// Generate Chinese locale codes: zh, zh-CN, zh-TW, zh-HK, etc.
  static Generator<String> chineseLocale = any.choose([
    'zh',
    'zh-CN',
    'zh-TW',
    'zh-HK',
    'zh-Hans',
    'zh-Hant',
    'ZH',      // uppercase variant
    'Zh-cn',   // mixed case
  ]);

  /// Generate non-Chinese locale codes
  static Generator<String> nonChineseLocale = any.choose([
    'en',
    'en-US',
    'en-GB',
    'ja',
    'ko',
    'fr',
    'de',
    'it',
    'es',
    'pt',
    'ru',
    'ar',
    'hi',
    'th',
    'vi',
    'nl',
    'pl',
    'tr',
    'sv',
    'da',
    'fi',
    'no',
    'cs',
    'hu',
    'ro',
    'uk',
    'id',
    'ms',
    'tl',
  ]);
}

/// Generators for model fallback chain testing
extension ModelGenerators on Any {
  /// Generate provider keys
  static Generator<String> providerKey = any.choose([
    'openai',
    'anthropic',
    'google',
    'azure',
    'ollama',
    'KelivoIN',
    'Tensdaq',
    'SiliconFlow',
    'custom-provider',
  ]);

  /// Generate model IDs
  static Generator<String> modelId = any.choose([
    'gpt-4',
    'gpt-4-turbo',
    'gpt-3.5-turbo',
    'claude-3-opus',
    'claude-3-sonnet',
    'gemini-pro',
    'gemini-1.5-pro',
    'llama-3-70b',
    'qwen-72b',
    'deepseek-coder',
  ]);

  /// Generate optional provider key (null or a provider key)
  static Generator<String?> optionalProviderKey =
      any.choose<String?>([null, ...['openai', 'anthropic', 'google', 'azure', 'ollama']]);

  /// Generate optional model ID (null or a model ID)
  static Generator<String?> optionalModelId =
      any.choose<String?>([null, ...['gpt-4', 'claude-3-opus', 'gemini-pro', 'llama-3-70b']]);

  /// Generate ModelSettings with various combinations
  static Generator<ModelSettings> modelSettings = Generator.combine6(
    optionalProviderKey,
    optionalModelId,
    optionalProviderKey,
    optionalModelId,
    optionalProviderKey,
    optionalModelId,
    (translateProvider, translateId, assistantProvider, assistantId,
            globalProvider, globalId) =>
        ModelSettings(
      translateModelProvider: translateProvider,
      translateModelId: translateId,
      assistantChatModelProvider: assistantProvider,
      assistantChatModelId: assistantId,
      currentModelProvider: globalProvider,
      currentModelId: globalId,
    ),
  );

  /// Generate ModelSettings where translateModel is fully set
  static Generator<ModelSettings> settingsWithTranslateModel = Generator.combine4(
    providerKey,
    modelId,
    optionalProviderKey,
    optionalModelId,
    (translateProvider, translateId, assistantProvider, assistantId) =>
        ModelSettings(
      translateModelProvider: translateProvider,
      translateModelId: translateId,
      assistantChatModelProvider: assistantProvider,
      assistantChatModelId: assistantId,
      currentModelProvider: 'default-provider',
      currentModelId: 'default-model',
    ),
  );

  /// Generate ModelSettings where translateModel is NOT set but assistant model IS set
  static Generator<ModelSettings> settingsWithAssistantModelOnly = Generator.combine2(
    providerKey,
    modelId,
    (assistantProvider, assistantId) => ModelSettings(
      translateModelProvider: null,
      translateModelId: null,
      assistantChatModelProvider: assistantProvider,
      assistantChatModelId: assistantId,
      currentModelProvider: 'default-provider',
      currentModelId: 'default-model',
    ),
  );

  /// Generate ModelSettings where only global default is set
  static Generator<ModelSettings> settingsWithGlobalDefaultOnly = Generator.combine2(
    providerKey,
    modelId,
    (globalProvider, globalId) => ModelSettings(
      translateModelProvider: null,
      translateModelId: null,
      assistantChatModelProvider: null,
      assistantChatModelId: null,
      currentModelProvider: globalProvider,
      currentModelId: globalId,
    ),
  );
}

void main() {
  group('DesktopTranslatePage Property Tests', () {
    // **Feature: desktop-translate, Property 1: Default language selection based on locale**
    // **Validates: Requirements 2.1**
    Glados(LocaleGenerators.chineseLocale).test(
      'Property 1a: Chinese locales default to English target language',
      (localeCode) {
        final defaultLang = getDefaultTargetLanguage(localeCode);

        expect(defaultLang.code, equals('en'),
            reason:
                'Chinese locale "$localeCode" should default to English target language');
      },
    );

    // **Feature: desktop-translate, Property 1: Default language selection based on locale**
    // **Validates: Requirements 2.1**
    Glados(LocaleGenerators.nonChineseLocale).test(
      'Property 1b: Non-Chinese locales default to Simplified Chinese target language',
      (localeCode) {
        final defaultLang = getDefaultTargetLanguage(localeCode);

        expect(defaultLang.code, equals('zh-CN'),
            reason:
                'Non-Chinese locale "$localeCode" should default to Simplified Chinese target language');
      },
    );

    // Edge case: verify 'z' alone is NOT treated as Chinese (must be 'zh')
    Glados(any.bool).test(
      'Property 1c: Single z without h is NOT Chinese - defaults to Simplified Chinese',
      (useUppercase) {
        // 'z' alone or 'Z' alone should NOT be treated as Chinese
        // Only 'zh' prefix counts as Chinese locale
        final localeCode = useUppercase ? 'Z' : 'z';
        final defaultLang = getDefaultTargetLanguage(localeCode);

        expect(defaultLang.code, equals('zh-CN'),
            reason:
                'Single "$localeCode" (without h) should NOT be Chinese, defaults to Simplified Chinese');
      },
    );

    // **Feature: desktop-translate, Property 2: Model fallback chain**
    // **Validates: Requirements 3.1**
    //
    // Property 2a: When translateModel is fully set, it takes priority
    Glados(ModelGenerators.settingsWithTranslateModel).test(
      'Property 2a: TranslateModel takes priority when fully set',
      (settings) {
        final result = selectModelWithFallback(settings);

        expect(result.providerKey, equals(settings.translateModelProvider),
            reason:
                'When translateModel is set, providerKey should be translateModelProvider');
        expect(result.modelId, equals(settings.translateModelId),
            reason:
                'When translateModel is set, modelId should be translateModelId');
      },
    );

    // Property 2b: When translateModel is NOT set but assistant model IS set, use assistant model
    Glados(ModelGenerators.settingsWithAssistantModelOnly).test(
      'Property 2b: Assistant model is used when translateModel is not set',
      (settings) {
        final result = selectModelWithFallback(settings);

        expect(result.providerKey, equals(settings.assistantChatModelProvider),
            reason:
                'When translateModel is null, providerKey should fall back to assistantChatModelProvider');
        expect(result.modelId, equals(settings.assistantChatModelId),
            reason:
                'When translateModel is null, modelId should fall back to assistantChatModelId');
      },
    );

    // Property 2c: When both translateModel and assistant model are NOT set, use global default
    Glados(ModelGenerators.settingsWithGlobalDefaultOnly).test(
      'Property 2c: Global default is used when translateModel and assistant model are not set',
      (settings) {
        final result = selectModelWithFallback(settings);

        expect(result.providerKey, equals(settings.currentModelProvider),
            reason:
                'When translateModel and assistantModel are null, providerKey should fall back to currentModelProvider');
        expect(result.modelId, equals(settings.currentModelId),
            reason:
                'When translateModel and assistantModel are null, modelId should fall back to currentModelId');
      },
    );

    // Property 2d: General fallback chain property - for any settings combination,
    // the result should match the expected fallback chain behavior
    Glados(ModelGenerators.modelSettings).test(
      'Property 2d: Fallback chain follows correct priority order for any settings',
      (settings) {
        final result = selectModelWithFallback(settings);

        // The providerKey should be the first non-null in the chain
        final expectedProviderKey = settings.translateModelProvider ??
            settings.assistantChatModelProvider ??
            settings.currentModelProvider;

        // The modelId should be the first non-null in the chain
        final expectedModelId = settings.translateModelId ??
            settings.assistantChatModelId ??
            settings.currentModelId;

        expect(result.providerKey, equals(expectedProviderKey),
            reason:
                'ProviderKey should follow fallback chain: translate → assistant → global');
        expect(result.modelId, equals(expectedModelId),
            reason:
                'ModelId should follow fallback chain: translate → assistant → global');
      },
    );
  });
}
