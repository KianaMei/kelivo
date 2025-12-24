import 'package:uuid/uuid.dart';
import '../../../core/services/search/search_service.dart';
import '../../../core/models/api_keys.dart';

/// Factory for creating SearchServiceOptions instances
class SearchServiceFactory {
  SearchServiceFactory._();

  static SearchServiceOptions create({
    required String type,
    String? apiKey,
    String? url,
    String? engines,
    String? language,
    String? username,
    String? password,
    String? region,
  }) {
    final id = const Uuid().v4().substring(0, 8);

    switch (type) {
      case 'bing_local':
        return BingLocalOptions(id: id);
      case 'tavily':
        return TavilyOptions.single(id: id, apiKey: apiKey ?? '');
      case 'exa':
        return ExaOptions.single(id: id, apiKey: apiKey ?? '');
      case 'zhipu':
        return ZhipuOptions.single(id: id, apiKey: apiKey ?? '');
      case 'searxng':
        return SearXNGOptions(
          id: id,
          url: url ?? '',
          engines: engines ?? '',
          language: language ?? '',
          username: username ?? '',
          password: password ?? '',
        );
      case 'linkup':
        return LinkUpOptions.single(id: id, apiKey: apiKey ?? '');
      case 'brave':
        return BraveOptions.single(id: id, apiKey: apiKey ?? '');
      case 'metaso':
        return MetasoOptions.single(id: id, apiKey: apiKey ?? '');
      case 'jina':
        return JinaOptions.single(id: id, apiKey: apiKey ?? '');
      case 'ollama':
        return OllamaOptions.single(id: id, apiKey: apiKey ?? '');
      case 'perplexity':
        return PerplexityOptions.single(id: id, apiKey: apiKey ?? '');
      case 'bocha':
        return BochaOptions.single(id: id, apiKey: apiKey ?? '');
      case 'duckduckgo':
        return DuckDuckGoOptions(id: id, region: region ?? 'wt-wt');
      default:
        return BingLocalOptions(id: id);
    }
  }

  /// All supported service types in display order
  static const allTypes = [
    'bing_local', 'tavily', 'exa', 'zhipu', 'searxng', 'linkup',
    'brave', 'metaso', 'jina', 'ollama', 'perplexity', 'bocha', 'duckduckgo'
  ];

  /// Service types that only need an API key
  static const apiKeyOnlyTypes = [
    'tavily', 'exa', 'zhipu', 'linkup', 'brave',
    'metaso', 'jina', 'ollama', 'perplexity', 'bocha'
  ];

  /// Service types that need no configuration
  static const noConfigTypes = ['bing_local'];

  /// Check if type needs only API key
  static bool needsApiKeyOnly(String type) => apiKeyOnlyTypes.contains(type);

  /// Check if type needs no config
  static bool needsNoConfig(String type) => noConfigTypes.contains(type);

  /// Check if service supports multi-key
  static bool supportsMultiKey(SearchServiceOptions s) =>
      s is TavilyOptions || s is ExaOptions || s is ZhipuOptions ||
      s is LinkUpOptions || s is BraveOptions || s is MetasoOptions ||
      s is OllamaOptions || s is JinaOptions || s is PerplexityOptions || s is BochaOptions;

  /// Extract apiKeys from a multi-key service
  static List<ApiKeyConfig> getApiKeys(SearchServiceOptions s) {
    if (s is TavilyOptions) return s.apiKeys;
    if (s is ExaOptions) return s.apiKeys;
    if (s is ZhipuOptions) return s.apiKeys;
    if (s is LinkUpOptions) return s.apiKeys;
    if (s is BraveOptions) return s.apiKeys;
    if (s is MetasoOptions) return s.apiKeys;
    if (s is OllamaOptions) return s.apiKeys;
    if (s is JinaOptions) return s.apiKeys;
    if (s is PerplexityOptions) return s.apiKeys;
    if (s is BochaOptions) return s.apiKeys;
    return [];
  }

  /// Extract strategy from a multi-key service
  static LoadBalanceStrategy getStrategy(SearchServiceOptions s) {
    if (s is TavilyOptions) return s.strategy;
    if (s is ExaOptions) return s.strategy;
    if (s is ZhipuOptions) return s.strategy;
    if (s is LinkUpOptions) return s.strategy;
    if (s is BraveOptions) return s.strategy;
    if (s is MetasoOptions) return s.strategy;
    if (s is OllamaOptions) return s.strategy;
    if (s is JinaOptions) return s.strategy;
    if (s is PerplexityOptions) return s.strategy;
    if (s is BochaOptions) return s.strategy;
    return LoadBalanceStrategy.roundRobin;
  }

  /// Update a multi-key service with new keys and strategy
  static SearchServiceOptions updateMultiKey(
    SearchServiceOptions s,
    List<ApiKeyConfig> keys,
    LoadBalanceStrategy strategy, {
    String? baseUrl,
  }) {
    if (s is TavilyOptions) return TavilyOptions(id: s.id, apiKeys: keys, strategy: strategy);
    if (s is ExaOptions) return ExaOptions(id: s.id, apiKeys: keys, strategy: strategy, baseUrl: baseUrl ?? s.baseUrl);
    if (s is ZhipuOptions) return ZhipuOptions(id: s.id, apiKeys: keys, strategy: strategy);
    if (s is LinkUpOptions) return LinkUpOptions(id: s.id, apiKeys: keys, strategy: strategy);
    if (s is BraveOptions) return BraveOptions(id: s.id, apiKeys: keys, strategy: strategy);
    if (s is MetasoOptions) return MetasoOptions(id: s.id, apiKeys: keys, strategy: strategy);
    if (s is OllamaOptions) return OllamaOptions(id: s.id, apiKeys: keys, strategy: strategy);
    if (s is JinaOptions) return JinaOptions(id: s.id, apiKeys: keys, strategy: strategy);
    if (s is PerplexityOptions) return PerplexityOptions(
      id: s.id, apiKeys: keys, strategy: strategy,
      country: s.country, searchDomainFilter: s.searchDomainFilter, maxTokensPerPage: s.maxTokensPerPage,
    );
    if (s is BochaOptions) return BochaOptions(
      id: s.id, apiKeys: keys, strategy: strategy,
      freshness: s.freshness, summary: s.summary, include: s.include, exclude: s.exclude,
    );
    return s;
  }

  /// Get baseUrl for Exa service (returns null for other services)
  static String? getBaseUrl(SearchServiceOptions s) {
    if (s is ExaOptions) return s.baseUrl;
    return null;
  }

  /// Check if service supports custom base URL
  static bool supportsBaseUrl(SearchServiceOptions s) => s is ExaOptions;
}
