import 'dart:math';
import 'package:flutter/material.dart';
// Import statements for service implementations
import 'providers/bing_search_service.dart';
import 'providers/tavily_search_service.dart';
import 'providers/exa_search_service.dart';
import 'providers/zhipu_search_service.dart';
import 'providers/searxng_search_service.dart';
import 'providers/linkup_search_service.dart';
import 'providers/brave_search_service.dart';
import 'providers/metaso_search_service.dart';
import 'providers/ollama_search_service.dart';
import 'providers/jina_search_service.dart';
import 'providers/bocha_search_service.dart';
import 'providers/perplexity_search_service.dart';
// Import existing ApiKeyConfig and LoadBalanceStrategy
import '../../models/api_keys.dart';

// Base interface for all search services
abstract class SearchService<T extends SearchServiceOptions> {
  String get name;
  
  Widget description(BuildContext context);
  
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required T serviceOptions,
  });
  
  // Factory method to get service instance based on options type
  static SearchService getService(SearchServiceOptions options) {
    switch (options.runtimeType) {
      case BingLocalOptions:
        return BingSearchService() as SearchService;
      case TavilyOptions:
        return TavilySearchService() as SearchService;
      case ExaOptions:
        return ExaSearchService() as SearchService;
      case ZhipuOptions:
        return ZhipuSearchService() as SearchService;
      case SearXNGOptions:
        return SearXNGSearchService() as SearchService;
      case LinkUpOptions:
        return LinkUpSearchService() as SearchService;
      case BraveOptions:
        return BraveSearchService() as SearchService;
      case MetasoOptions:
        return MetasoSearchService() as SearchService;
      case OllamaOptions:
        return OllamaSearchService() as SearchService;
      case JinaOptions:
        return JinaSearchService() as SearchService;
      case BochaOptions:
        return BochaSearchService() as SearchService;
      case PerplexityOptions:
        return PerplexitySearchService() as SearchService;
      default:
        return BingSearchService() as SearchService;
    }
  }
}

// Search result data structure
class SearchResult {
  final String? answer;
  final List<SearchResultItem> items;
  
  SearchResult({
    this.answer,
    required this.items,
  });
  
  Map<String, dynamic> toJson() => {
    if (answer != null) 'answer': answer,
    'items': items.map((e) => e.toJson()).toList(),
  };
  
  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    answer: json['answer'],
    items: (json['items'] as List).map((e) => SearchResultItem.fromJson(e)).toList(),
  );
}

class SearchResultItem {
  final String title;
  final String url;
  final String text;
  String? id;
  int? index;
  
  SearchResultItem({
    required this.title,
    required this.url,
    required this.text,
    this.id,
    this.index,
  });
  
  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'text': text,
    if (id != null) 'id': id,
    if (index != null) 'index': index,
  };
  
  factory SearchResultItem.fromJson(Map<String, dynamic> json) => SearchResultItem(
    title: json['title'],
    url: json['url'],
    text: json['text'],
    id: json['id'],
    index: json['index'],
  );
}

// Common search options
class SearchCommonOptions {
  final int resultSize;
  final int timeout;
  
  const SearchCommonOptions({
    this.resultSize = 10,
    this.timeout = 5000,
  });
  
  Map<String, dynamic> toJson() => {
    'resultSize': resultSize,
    'timeout': timeout,
  };
  
  factory SearchCommonOptions.fromJson(Map<String, dynamic> json) => SearchCommonOptions(
    resultSize: json['resultSize'] ?? 10,
    timeout: json['timeout'] ?? 5000,
  );
}

// Base class for service-specific options
abstract class SearchServiceOptions {
  final String id;
  
  const SearchServiceOptions({required this.id});
  
  Map<String, dynamic> toJson();
  
  static SearchServiceOptions fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'bing_local':
        return BingLocalOptions.fromJson(json);
      case 'tavily':
        return TavilyOptions.fromJson(json);
      case 'exa':
        return ExaOptions.fromJson(json);
      case 'zhipu':
        return ZhipuOptions.fromJson(json);
      case 'searxng':
        return SearXNGOptions.fromJson(json);
      case 'linkup':
        return LinkUpOptions.fromJson(json);
      case 'brave':
        return BraveOptions.fromJson(json);
      case 'metaso':
        return MetasoOptions.fromJson(json);
      case 'ollama':
        return OllamaOptions.fromJson(json);
      case 'jina':
        return JinaOptions.fromJson(json);
      case 'bocha':
        return BochaOptions.fromJson(json);
      case 'perplexity':
        return PerplexityOptions.fromJson(json);
      default:
        return BingLocalOptions(id: json['id']);
    }
  }
  
  static final SearchServiceOptions defaultOption = BingLocalOptions(
    id: 'default',
  );
}

// Service-specific option classes
class BingLocalOptions extends SearchServiceOptions {
  final String acceptLanguage;
  
  BingLocalOptions({
    required String id,
    this.acceptLanguage = 'en-US,en;q=0.9',
  }) : super(id: id);
  
  @override
  Map<String, dynamic> toJson() => {
    'type': 'bing_local',
    'id': id,
    'acceptLanguage': acceptLanguage,
  };
  
  factory BingLocalOptions.fromJson(Map<String, dynamic> json) => BingLocalOptions(
    id: json['id'],
    acceptLanguage: json['acceptLanguage'] ?? 'en-US,en;q=0.9',
  );
}

class TavilyOptions extends SearchServiceOptions {
  final List<ApiKeyConfig> apiKeys;
  final LoadBalanceStrategy strategy;
  int _currentIndex = 0;  // For round-robin strategy
  static const int _cooldownMinutes = 5;
  static const int _maxFailuresBeforeError = 3;
  
  TavilyOptions({
    required String id,
    required this.apiKeys,
    this.strategy = LoadBalanceStrategy.roundRobin,
  }) : super(id: id) {
    if (apiKeys.isEmpty) {
      throw ArgumentError('At least one API key is required');
    }
  }
  
  // Backward compatibility: single key constructor
  factory TavilyOptions.single({
    required String id,
    required String apiKey,
  }) {
    return TavilyOptions(
      id: id,
      apiKeys: [ApiKeyConfig.create(apiKey)],
    );
  }
  
  ApiKeyConfig? getNextAvailableKey({Set<String> excludeIds = const {}}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cooldownMs = _cooldownMinutes * 60 * 1000;

    bool isTemporarilyBlocked(ApiKeyConfig k) {
      if (!k.isEnabled) return true;
      if (excludeIds.contains(k.id)) return true;
      if (k.status == ApiKeyStatus.rateLimited || k.status == ApiKeyStatus.error) {
        final since = now - k.updatedAt;
        if (since < cooldownMs) return true;
      }
      if (k.maxRequestsPerMinute != null && k.usage.lastUsed != null && k.maxRequestsPerMinute! > 0) {
        final minInterval = (60000 / k.maxRequestsPerMinute!).floor();
        if ((now - (k.usage.lastUsed!)) < minInterval) return true;
      }
      return false;
    }

    List<ApiKeyConfig> candidates = List<ApiKeyConfig>.from(apiKeys);
    for (int i = 0; i < candidates.length; i++) {
      final k = candidates[i];
      if ((k.status == ApiKeyStatus.rateLimited || k.status == ApiKeyStatus.error) && (now - k.updatedAt) >= cooldownMs) {
        final idx = apiKeys.indexWhere((e) => e.id == k.id);
        if (idx >= 0) {
          apiKeys[idx] = k.copyWith(status: ApiKeyStatus.active, updatedAt: now);
        }
      }
    }

    candidates = candidates.where((k) => !isTemporarilyBlocked(k)).toList();
    if (candidates.isEmpty) return null;

    switch (strategy) {
      case LoadBalanceStrategy.roundRobin:
        final active = candidates;
        _currentIndex = (_currentIndex + 1) % active.length;
        return active[_currentIndex];
      case LoadBalanceStrategy.random:
        final random = Random();
        return candidates[random.nextInt(candidates.length)];
      case LoadBalanceStrategy.leastUsed:
        candidates.sort((a, b) => a.usage.totalRequests.compareTo(b.usage.totalRequests));
        return candidates.first;
      case LoadBalanceStrategy.priority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first;
    }
  }
  
  // Mark key as used
  void markKeyAsUsed(String keyId) {
    final index = apiKeys.indexWhere((k) => k.id == keyId);
    if (index != -1) {
      final oldConfig = apiKeys[index];
      final newUsage = oldConfig.usage.copyWith(
        totalRequests: oldConfig.usage.totalRequests + 1,
        successfulRequests: oldConfig.usage.successfulRequests + 1,
        lastUsed: DateTime.now().millisecondsSinceEpoch,
        consecutiveFailures: 0,
      );
      apiKeys[index] = oldConfig.copyWith(
        usage: newUsage,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        status: ApiKeyStatus.active,
        lastError: null,
      );
    }
  }

  void markKeyRateLimited(String keyId, {String? error}) {
    final i = apiKeys.indexWhere((k) => k.id == keyId);
    if (i >= 0) {
      final k = apiKeys[i];
      final now = DateTime.now().millisecondsSinceEpoch;
      final u = k.usage.copyWith(
        totalRequests: k.usage.totalRequests + 1,
        failedRequests: k.usage.failedRequests + 1,
        consecutiveFailures: k.usage.consecutiveFailures + 1,
        lastUsed: now,
      );
      apiKeys[i] = k.copyWith(
        usage: u,
        status: ApiKeyStatus.rateLimited,
        lastError: error ?? 'rate_limited',
        updatedAt: now,
      );
    }
  }

  void markKeyFailure(String keyId, {String? error}) {
    final i = apiKeys.indexWhere((k) => k.id == keyId);
    if (i >= 0) {
      final k = apiKeys[i];
      final now = DateTime.now().millisecondsSinceEpoch;
      final nextFails = k.usage.consecutiveFailures + 1;
      final u = k.usage.copyWith(
        totalRequests: k.usage.totalRequests + 1,
        failedRequests: k.usage.failedRequests + 1,
        consecutiveFailures: nextFails,
        lastUsed: now,
      );
      final st = nextFails >= _maxFailuresBeforeError ? ApiKeyStatus.error : k.status;
      apiKeys[i] = k.copyWith(
        usage: u,
        status: st,
        lastError: error ?? 'request_failed',
        updatedAt: now,
      );
    }
  }
  
  // Update a key configuration
  void updateKey(int index, ApiKeyConfig newConfig) {
    if (index >= 0 && index < apiKeys.length) {
      apiKeys[index] = newConfig;
    }
  }
  
  // Add a new key
  void addKey(ApiKeyConfig config) {
    apiKeys.add(config);
  }
  
  // Remove a key
  void removeKey(int index) {
    if (apiKeys.length > 1 && index >= 0 && index < apiKeys.length) {
      apiKeys.removeAt(index);
    }
  }
  
  @override
  Map<String, dynamic> toJson() => {
    'type': 'tavily',
    'id': id,
    'apiKeys': apiKeys.map((k) => k.toJson()).toList(),
    'strategy': strategy.name,
  };
  
  factory TavilyOptions.fromJson(Map<String, dynamic> json) {
    // Backward compatibility: support old single apiKey format
    if (json.containsKey('apiKey') && json['apiKey'] is String) {
      return TavilyOptions.single(
        id: json['id'],
        apiKey: json['apiKey'],
      );
    }
    
    return TavilyOptions(
      id: json['id'],
      apiKeys: (json['apiKeys'] as List)
          .map((k) => ApiKeyConfig.fromJson(k as Map<String, dynamic>))
          .toList(),
      strategy: LoadBalanceStrategy.values.firstWhere(
        (s) => s.name == json['strategy'],
        orElse: () => LoadBalanceStrategy.roundRobin,
      ),
    );
  }
}

class ExaOptions extends SearchServiceOptions {
  final String apiKey;
  
  ExaOptions({
    required String id,
    required this.apiKey,
  }) : super(id: id);
  
  @override
  Map<String, dynamic> toJson() => {
    'type': 'exa',
    'id': id,
    'apiKey': apiKey,
  };
  
  factory ExaOptions.fromJson(Map<String, dynamic> json) => ExaOptions(
    id: json['id'],
    apiKey: json['apiKey'],
  );
}

class ZhipuOptions extends SearchServiceOptions {
  final String apiKey;
  
  ZhipuOptions({
    required String id,
    required this.apiKey,
  }) : super(id: id);
  
  @override
  Map<String, dynamic> toJson() => {
    'type': 'zhipu',
    'id': id,
    'apiKey': apiKey,
  };
  
  factory ZhipuOptions.fromJson(Map<String, dynamic> json) => ZhipuOptions(
    id: json['id'],
    apiKey: json['apiKey'],
  );
}

class SearXNGOptions extends SearchServiceOptions {
  final String url;
  final String engines;
  final String language;
  final String username;
  final String password;
  
  SearXNGOptions({
    required String id,
    required this.url,
    this.engines = '',
    this.language = '',
    this.username = '',
    this.password = '',
  }) : super(id: id);
  
  @override
  Map<String, dynamic> toJson() => {
    'type': 'searxng',
    'id': id,
    'url': url,
    'engines': engines,
    'language': language,
    'username': username,
    'password': password,
  };
  
  factory SearXNGOptions.fromJson(Map<String, dynamic> json) => SearXNGOptions(
    id: json['id'],
    url: json['url'],
    engines: json['engines'] ?? '',
    language: json['language'] ?? '',
    username: json['username'] ?? '',
    password: json['password'] ?? '',
  );
}

class LinkUpOptions extends SearchServiceOptions {
  final String apiKey;
  
  LinkUpOptions({
    required String id,
    required this.apiKey,
  }) : super(id: id);
  
  @override
  Map<String, dynamic> toJson() => {
    'type': 'linkup',
    'id': id,
    'apiKey': apiKey,
  };
  
  factory LinkUpOptions.fromJson(Map<String, dynamic> json) => LinkUpOptions(
    id: json['id'],
    apiKey: json['apiKey'],
  );
}

class BraveOptions extends SearchServiceOptions {
  final String apiKey;
  
  BraveOptions({
    required String id,
    required this.apiKey,
  }) : super(id: id);
  
  @override
  Map<String, dynamic> toJson() => {
    'type': 'brave',
    'id': id,
    'apiKey': apiKey,
  };
  
  factory BraveOptions.fromJson(Map<String, dynamic> json) => BraveOptions(
    id: json['id'],
    apiKey: json['apiKey'],
  );
}

class MetasoOptions extends SearchServiceOptions {
  final String apiKey;
  
  MetasoOptions({
    required String id,
    required this.apiKey,
  }) : super(id: id);
  
  @override
  Map<String, dynamic> toJson() => {
    'type': 'metaso',
    'id': id,
    'apiKey': apiKey,
  };
  
  factory MetasoOptions.fromJson(Map<String, dynamic> json) => MetasoOptions(
    id: json['id'],
    apiKey: json['apiKey'],
  );
}

class OllamaOptions extends SearchServiceOptions {
  final String apiKey;

  OllamaOptions({
    required String id,
    required this.apiKey,
  }) : super(id: id);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ollama',
    'id': id,
    'apiKey': apiKey,
  };

  factory OllamaOptions.fromJson(Map<String, dynamic> json) => OllamaOptions(
    id: json['id'],
    apiKey: json['apiKey'],
  );
}

class JinaOptions extends SearchServiceOptions {
  final String apiKey;

  JinaOptions({
    required String id,
    required this.apiKey,
  }) : super(id: id);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'jina',
        'id': id,
        'apiKey': apiKey,
      };

  factory JinaOptions.fromJson(Map<String, dynamic> json) => JinaOptions(
        id: json['id'],
        apiKey: json['apiKey'],
      );
}

class PerplexityOptions extends SearchServiceOptions {
  final String apiKey;
  final String? country; // ISO 3166-1 alpha-2
  final List<String>? searchDomainFilter; // domains/URLs
  final int? maxTokensPerPage; // default 1024

  PerplexityOptions({
    required String id,
    required this.apiKey,
    this.country,
    this.searchDomainFilter,
    this.maxTokensPerPage,
  }) : super(id: id);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'perplexity',
        'id': id,
        'apiKey': apiKey,
        if (country != null) 'country': country,
        if (searchDomainFilter != null) 'searchDomainFilter': searchDomainFilter,
        if (maxTokensPerPage != null) 'maxTokensPerPage': maxTokensPerPage,
      };

  factory PerplexityOptions.fromJson(Map<String, dynamic> json) => PerplexityOptions(
        id: json['id'],
        apiKey: json['apiKey'],
        country: json['country'],
        searchDomainFilter: (json['searchDomainFilter'] as List?)?.map((e) => e.toString()).toList(),
        maxTokensPerPage: json['maxTokensPerPage'],
      );
}

class BochaOptions extends SearchServiceOptions {
  final String apiKey;
  // Optional parameters supported by Bocha API
  final String? freshness; // e.g., 'noLimit', 'week', 'month', etc.
  final bool summary; // whether to include textual summary
  final String? include; // e.g., 'qq.com|m.163.com'
  final String? exclude; // e.g., 'qq.com|m.163.com'

  BochaOptions({
    required String id,
    required this.apiKey,
    this.freshness,
    this.summary = true,
    this.include,
    this.exclude,
  }) : super(id: id);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'bocha',
        'id': id,
        'apiKey': apiKey,
        if (freshness != null) 'freshness': freshness,
        'summary': summary,
        if (include != null) 'include': include,
        if (exclude != null) 'exclude': exclude,
      };

  factory BochaOptions.fromJson(Map<String, dynamic> json) => BochaOptions(
        id: json['id'],
        apiKey: json['apiKey'],
        freshness: json['freshness'],
        summary: (json['summary'] ?? true) as bool,
        include: json['include'],
        exclude: json['exclude'],
      );
}
