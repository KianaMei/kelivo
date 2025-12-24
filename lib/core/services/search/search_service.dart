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
import 'providers/duckduckgo_search_service.dart';
// Import existing ApiKeyConfig and LoadBalanceStrategy
import '../../models/api_keys.dart';
import '../api_key_manager.dart';

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
      case DuckDuckGoOptions:
        return DuckDuckGoSearchService() as SearchService;
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
      case 'duckduckgo':
        return DuckDuckGoOptions.fromJson(json);
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

  int _sortOrder(ApiKeyConfig k) => k.sortIndex;
  
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

      final state = ApiKeyManager().getKeyState(k.id);
      if (state != null) {
        if (state.status == 'error' || state.status == 'rateLimited') {
          final since = now - state.updatedAt;
          if (since < cooldownMs) return true;
        }
        if (k.maxRequestsPerMinute != null && state.lastUsed != null && k.maxRequestsPerMinute! > 0) {
          final minInterval = (60000 / k.maxRequestsPerMinute!).floor();
          if ((now - state.lastUsed!) < minInterval) return true;
        }
      }
      return false;
    }

    final candidates = apiKeys.where((k) => !isTemporarilyBlocked(k)).toList();
    if (candidates.isEmpty) return null;

    switch (strategy) {
      case LoadBalanceStrategy.roundRobin:
        final active = List<ApiKeyConfig>.from(candidates)
          ..sort((a, b) => _sortOrder(a).compareTo(_sortOrder(b)));
        if (active.isEmpty) return null;
        _currentIndex = (_currentIndex + 1) % active.length;
        return active[_currentIndex];
      case LoadBalanceStrategy.random:
        final random = Random();
        return candidates[random.nextInt(candidates.length)];
      case LoadBalanceStrategy.leastUsed:
        candidates.sort((a, b) {
          final stateA = ApiKeyManager().getKeyState(a.id);
          final stateB = ApiKeyManager().getKeyState(b.id);
          return (stateA?.totalRequests ?? 0).compareTo(stateB?.totalRequests ?? 0);
        });
        return candidates.first;
      case LoadBalanceStrategy.priority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first;
    }
  }

  // Mark key as used
  void markKeyAsUsed(String keyId) {
    ApiKeyManager().updateKeyStatus(keyId, true, maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyRateLimited(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'rate_limited', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyFailure(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'request_failed', maxFailuresBeforeDisable: _maxFailuresBeforeError);
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
  final List<ApiKeyConfig> apiKeys;
  final LoadBalanceStrategy strategy;
  final String? baseUrl;  // Custom base URL for proxy/relay support
  int _currentIndex = 0;  // For round-robin strategy
  static const int _cooldownMinutes = 5;
  static const int _maxFailuresBeforeError = 3;
  static const String defaultBaseUrl = 'https://api.exa.ai';

  ExaOptions({
    required String id,
    required this.apiKeys,
    this.strategy = LoadBalanceStrategy.roundRobin,
    this.baseUrl,
  }) : super(id: id) {
    if (apiKeys.isEmpty) {
      throw ArgumentError('At least one API key is required');
    }
  }

  /// Get the effective base URL (custom or default)
  String get effectiveBaseUrl => (baseUrl?.isNotEmpty == true) ? baseUrl! : defaultBaseUrl;

  // Backward compatibility: single key constructor
  factory ExaOptions.single({
    required String id,
    required String apiKey,
  }) {
    return ExaOptions(
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

      final state = ApiKeyManager().getKeyState(k.id);
      if (state != null) {
        if (state.status == 'error' || state.status == 'rateLimited') {
          final since = now - state.updatedAt;
          if (since < cooldownMs) return true;
        }
        if (k.maxRequestsPerMinute != null && state.lastUsed != null && k.maxRequestsPerMinute! > 0) {
          final minInterval = (60000 / k.maxRequestsPerMinute!).floor();
          if ((now - state.lastUsed!) < minInterval) return true;
        }
      }
      return false;
    }

    final candidates = apiKeys.where((k) => !isTemporarilyBlocked(k)).toList();
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
        candidates.sort((a, b) {
          final stateA = ApiKeyManager().getKeyState(a.id);
          final stateB = ApiKeyManager().getKeyState(b.id);
          return (stateA?.totalRequests ?? 0).compareTo(stateB?.totalRequests ?? 0);
        });
        return candidates.first;
      case LoadBalanceStrategy.priority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first;
    }
  }

  // Mark key as used
  void markKeyAsUsed(String keyId) {
    ApiKeyManager().updateKeyStatus(keyId, true, maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyRateLimited(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'rate_limited', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyFailure(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'request_failed', maxFailuresBeforeDisable: _maxFailuresBeforeError);
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
    'type': 'exa',
    'id': id,
    'apiKeys': apiKeys.map((k) => k.toJson()).toList(),
    'strategy': strategy.name,
    if (baseUrl != null && baseUrl!.isNotEmpty) 'baseUrl': baseUrl,
  };

  factory ExaOptions.fromJson(Map<String, dynamic> json) {
    // Backward compatibility: support old single apiKey format
    if (json.containsKey('apiKey') && json['apiKey'] is String) {
      return ExaOptions.single(
        id: json['id'],
        apiKey: json['apiKey'],
      );
    }

    return ExaOptions(
      id: json['id'],
      apiKeys: (json['apiKeys'] as List)
          .map((k) => ApiKeyConfig.fromJson(k as Map<String, dynamic>))
          .toList(),
      strategy: LoadBalanceStrategy.values.firstWhere(
        (s) => s.name == json['strategy'],
        orElse: () => LoadBalanceStrategy.roundRobin,
      ),
      baseUrl: json['baseUrl'] as String?,
    );
  }

  /// Create a copy with updated baseUrl
  ExaOptions copyWithBaseUrl(String? newBaseUrl) {
    return ExaOptions(
      id: id,
      apiKeys: apiKeys,
      strategy: strategy,
      baseUrl: newBaseUrl,
    );
  }
}

class ZhipuOptions extends SearchServiceOptions {
  final List<ApiKeyConfig> apiKeys;
  final LoadBalanceStrategy strategy;
  int _currentIndex = 0;  // For round-robin strategy
  static const int _cooldownMinutes = 5;
  static const int _maxFailuresBeforeError = 3;

  ZhipuOptions({
    required String id,
    required this.apiKeys,
    this.strategy = LoadBalanceStrategy.roundRobin,
  }) : super(id: id) {
    if (apiKeys.isEmpty) {
      throw ArgumentError('At least one API key is required');
    }
  }

  // Backward compatibility: single key constructor
  factory ZhipuOptions.single({
    required String id,
    required String apiKey,
  }) {
    return ZhipuOptions(
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

      final state = ApiKeyManager().getKeyState(k.id);
      if (state != null) {
        if (state.status == 'error' || state.status == 'rateLimited') {
          final since = now - state.updatedAt;
          if (since < cooldownMs) return true;
        }
        if (k.maxRequestsPerMinute != null && state.lastUsed != null && k.maxRequestsPerMinute! > 0) {
          final minInterval = (60000 / k.maxRequestsPerMinute!).floor();
          if ((now - state.lastUsed!) < minInterval) return true;
        }
      }
      return false;
    }

    final candidates = apiKeys.where((k) => !isTemporarilyBlocked(k)).toList();
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
        candidates.sort((a, b) {
          final stateA = ApiKeyManager().getKeyState(a.id);
          final stateB = ApiKeyManager().getKeyState(b.id);
          return (stateA?.totalRequests ?? 0).compareTo(stateB?.totalRequests ?? 0);
        });
        return candidates.first;
      case LoadBalanceStrategy.priority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first;
    }
  }

  // Mark key as used
  void markKeyAsUsed(String keyId) {
    ApiKeyManager().updateKeyStatus(keyId, true, maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyRateLimited(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'rate_limited', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyFailure(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'request_failed', maxFailuresBeforeDisable: _maxFailuresBeforeError);
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
    'type': 'zhipu',
    'id': id,
    'apiKeys': apiKeys.map((k) => k.toJson()).toList(),
    'strategy': strategy.name,
  };
  
  factory ZhipuOptions.fromJson(Map<String, dynamic> json) {
    // Backward compatibility: support old single apiKey format
    if (json.containsKey('apiKey') && json['apiKey'] is String) {
      return ZhipuOptions.single(
        id: json['id'],
        apiKey: json['apiKey'],
      );
    }
    
    return ZhipuOptions(
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
  final List<ApiKeyConfig> apiKeys;
  final LoadBalanceStrategy strategy;
  int _currentIndex = 0;
  static const int _cooldownMinutes = 5;
  static const int _maxFailuresBeforeError = 3;

  LinkUpOptions({
    required String id,
    required this.apiKeys,
    this.strategy = LoadBalanceStrategy.roundRobin,
  }) : super(id: id) {
    if (apiKeys.isEmpty) {
      throw ArgumentError('At least one API key is required');
    }
  }

  factory LinkUpOptions.single({
    required String id,
    required String apiKey,
  }) {
    return LinkUpOptions(
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

      final state = ApiKeyManager().getKeyState(k.id);
      if (state != null) {
        if (state.status == 'error' || state.status == 'rateLimited') {
          final since = now - state.updatedAt;
          if (since < cooldownMs) return true;
        }
        if (k.maxRequestsPerMinute != null && state.lastUsed != null && k.maxRequestsPerMinute! > 0) {
          final minInterval = (60000 / k.maxRequestsPerMinute!).floor();
          if ((now - state.lastUsed!) < minInterval) return true;
        }
      }
      return false;
    }

    final candidates = apiKeys.where((k) => !isTemporarilyBlocked(k)).toList();
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
        candidates.sort((a, b) {
          final stateA = ApiKeyManager().getKeyState(a.id);
          final stateB = ApiKeyManager().getKeyState(b.id);
          return (stateA?.totalRequests ?? 0).compareTo(stateB?.totalRequests ?? 0);
        });
        return candidates.first;
      case LoadBalanceStrategy.priority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first;
    }
  }

  void markKeyAsUsed(String keyId) {
    ApiKeyManager().updateKeyStatus(keyId, true, maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyRateLimited(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'rate_limited', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyFailure(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'request_failed', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }
  void updateKey(int index, ApiKeyConfig newConfig) {
    if (index >= 0 && index < apiKeys.length) {
      apiKeys[index] = newConfig;
    }
  }
  void addKey(ApiKeyConfig config) {
    apiKeys.add(config);
  }
  void removeKey(int index) {
    if (apiKeys.length > 1 && index >= 0 && index < apiKeys.length) {
      apiKeys.removeAt(index);
    }
  }
  
  @override
  Map<String, dynamic> toJson() => {
    'type': 'linkup',
    'id': id,
    'apiKeys': apiKeys.map((k) => k.toJson()).toList(),
    'strategy': strategy.name,
  };
  
  factory LinkUpOptions.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('apiKey') && json['apiKey'] is String) {
      return LinkUpOptions.single(
        id: json['id'],
        apiKey: json['apiKey'],
      );
    }
    return LinkUpOptions(
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

class BraveOptions extends SearchServiceOptions {
  final List<ApiKeyConfig> apiKeys;
  final LoadBalanceStrategy strategy;
  int _currentIndex = 0;
  static const int _cooldownMinutes = 5;
  static const int _maxFailuresBeforeError = 3;

  BraveOptions({
    required String id,
    required this.apiKeys,
    this.strategy = LoadBalanceStrategy.roundRobin,
  }) : super(id: id) {
    if (apiKeys.isEmpty) {
      throw ArgumentError('At least one API key is required');
    }
  }

  factory BraveOptions.single({
    required String id,
    required String apiKey,
  }) {
    return BraveOptions(
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

      final state = ApiKeyManager().getKeyState(k.id);
      if (state != null) {
        if (state.status == 'error' || state.status == 'rateLimited') {
          final since = now - state.updatedAt;
          if (since < cooldownMs) return true;
        }
        if (k.maxRequestsPerMinute != null && state.lastUsed != null && k.maxRequestsPerMinute! > 0) {
          final minInterval = (60000 / k.maxRequestsPerMinute!).floor();
          if ((now - state.lastUsed!) < minInterval) return true;
        }
      }
      return false;
    }

    final candidates = apiKeys.where((k) => !isTemporarilyBlocked(k)).toList();
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
        candidates.sort((a, b) {
          final stateA = ApiKeyManager().getKeyState(a.id);
          final stateB = ApiKeyManager().getKeyState(b.id);
          return (stateA?.totalRequests ?? 0).compareTo(stateB?.totalRequests ?? 0);
        });
        return candidates.first;
      case LoadBalanceStrategy.priority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first;
    }
  }

  void markKeyAsUsed(String keyId) {
    ApiKeyManager().updateKeyStatus(keyId, true, maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyRateLimited(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'rate_limited', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyFailure(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'request_failed', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }
  void updateKey(int index, ApiKeyConfig newConfig) {
    if (index >= 0 && index < apiKeys.length) {
      apiKeys[index] = newConfig;
    }
  }
  void addKey(ApiKeyConfig config) {
    apiKeys.add(config);
  }
  void removeKey(int index) {
    if (apiKeys.length > 1 && index >= 0 && index < apiKeys.length) {
      apiKeys.removeAt(index);
    }
  }
  
  @override
  Map<String, dynamic> toJson() => {
    'type': 'brave',
    'id': id,
    'apiKeys': apiKeys.map((k) => k.toJson()).toList(),
    'strategy': strategy.name,
  };
  
  factory BraveOptions.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('apiKey') && json['apiKey'] is String) {
      return BraveOptions.single(
        id: json['id'],
        apiKey: json['apiKey'],
      );
    }
    return BraveOptions(
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

class MetasoOptions extends SearchServiceOptions {
  final List<ApiKeyConfig> apiKeys;
  final LoadBalanceStrategy strategy;
  int _currentIndex = 0;
  static const int _cooldownMinutes = 5;
  static const int _maxFailuresBeforeError = 3;

  MetasoOptions({
    required String id,
    required this.apiKeys,
    this.strategy = LoadBalanceStrategy.roundRobin,
  }) : super(id: id) {
    if (apiKeys.isEmpty) {
      throw ArgumentError('At least one API key is required');
    }
  }

  factory MetasoOptions.single({
    required String id,
    required String apiKey,
  }) {
    return MetasoOptions(
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

      final state = ApiKeyManager().getKeyState(k.id);
      if (state != null) {
        if (state.status == 'error' || state.status == 'rateLimited') {
          final since = now - state.updatedAt;
          if (since < cooldownMs) return true;
        }
        if (k.maxRequestsPerMinute != null && state.lastUsed != null && k.maxRequestsPerMinute! > 0) {
          final minInterval = (60000 / k.maxRequestsPerMinute!).floor();
          if ((now - state.lastUsed!) < minInterval) return true;
        }
      }
      return false;
    }

    final candidates = apiKeys.where((k) => !isTemporarilyBlocked(k)).toList();
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
        candidates.sort((a, b) {
          final stateA = ApiKeyManager().getKeyState(a.id);
          final stateB = ApiKeyManager().getKeyState(b.id);
          return (stateA?.totalRequests ?? 0).compareTo(stateB?.totalRequests ?? 0);
        });
        return candidates.first;
      case LoadBalanceStrategy.priority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first;
    }
  }

  void markKeyAsUsed(String keyId) {
    ApiKeyManager().updateKeyStatus(keyId, true, maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyRateLimited(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'rate_limited', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyFailure(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'request_failed', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }
  void updateKey(int index, ApiKeyConfig newConfig) {
    if (index >= 0 && index < apiKeys.length) {
      apiKeys[index] = newConfig;
    }
  }
  void addKey(ApiKeyConfig config) {
    apiKeys.add(config);
  }
  void removeKey(int index) {
    if (apiKeys.length > 1 && index >= 0 && index < apiKeys.length) {
      apiKeys.removeAt(index);
    }
  }
  
  @override
  Map<String, dynamic> toJson() => {
    'type': 'metaso',
    'id': id,
    'apiKeys': apiKeys.map((k) => k.toJson()).toList(),
    'strategy': strategy.name,
  };
  
  factory MetasoOptions.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('apiKey') && json['apiKey'] is String) {
      return MetasoOptions.single(
        id: json['id'],
        apiKey: json['apiKey'],
      );
    }
    return MetasoOptions(
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

class OllamaOptions extends SearchServiceOptions {
  final List<ApiKeyConfig> apiKeys;
  final LoadBalanceStrategy strategy;
  int _currentIndex = 0;
  static const int _cooldownMinutes = 5;
  static const int _maxFailuresBeforeError = 3;

  OllamaOptions({
    required String id,
    required this.apiKeys,
    this.strategy = LoadBalanceStrategy.roundRobin,
  }) : super(id: id) {
    if (apiKeys.isEmpty) {
      throw ArgumentError('At least one API key is required');
    }
  }

  factory OllamaOptions.single({
    required String id,
    required String apiKey,
  }) {
    return OllamaOptions(
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

      final state = ApiKeyManager().getKeyState(k.id);
      if (state != null) {
        if (state.status == 'error' || state.status == 'rateLimited') {
          final since = now - state.updatedAt;
          if (since < cooldownMs) return true;
        }
        if (k.maxRequestsPerMinute != null && state.lastUsed != null && k.maxRequestsPerMinute! > 0) {
          final minInterval = (60000 / k.maxRequestsPerMinute!).floor();
          if ((now - state.lastUsed!) < minInterval) return true;
        }
      }
      return false;
    }

    final candidates = apiKeys.where((k) => !isTemporarilyBlocked(k)).toList();
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
        candidates.sort((a, b) {
          final stateA = ApiKeyManager().getKeyState(a.id);
          final stateB = ApiKeyManager().getKeyState(b.id);
          return (stateA?.totalRequests ?? 0).compareTo(stateB?.totalRequests ?? 0);
        });
        return candidates.first;
      case LoadBalanceStrategy.priority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first;
    }
  }

  void markKeyAsUsed(String keyId) {
    ApiKeyManager().updateKeyStatus(keyId, true, maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyRateLimited(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'rate_limited', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyFailure(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'request_failed', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }
  void updateKey(int index, ApiKeyConfig newConfig) {
    if (index >= 0 && index < apiKeys.length) {
      apiKeys[index] = newConfig;
    }
  }
  void addKey(ApiKeyConfig config) {
    apiKeys.add(config);
  }
  void removeKey(int index) {
    if (apiKeys.length > 1 && index >= 0 && index < apiKeys.length) {
      apiKeys.removeAt(index);
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ollama',
    'id': id,
    'apiKeys': apiKeys.map((k) => k.toJson()).toList(),
    'strategy': strategy.name,
  };

  factory OllamaOptions.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('apiKey') && json['apiKey'] is String) {
      return OllamaOptions.single(
        id: json['id'],
        apiKey: json['apiKey'],
      );
    }
    return OllamaOptions(
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

class JinaOptions extends SearchServiceOptions {
  final List<ApiKeyConfig> apiKeys;
  final LoadBalanceStrategy strategy;
  int _currentIndex = 0;
  static const int _cooldownMinutes = 5;
  static const int _maxFailuresBeforeError = 3;

  JinaOptions({
    required String id,
    required this.apiKeys,
    this.strategy = LoadBalanceStrategy.roundRobin,
  }) : super(id: id) {
    if (apiKeys.isEmpty) {
      throw ArgumentError('At least one API key is required');
    }
  }

  factory JinaOptions.single({
    required String id,
    required String apiKey,
  }) {
    return JinaOptions(
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

      final state = ApiKeyManager().getKeyState(k.id);
      if (state != null) {
        if (state.status == 'error' || state.status == 'rateLimited') {
          final since = now - state.updatedAt;
          if (since < cooldownMs) return true;
        }
        if (k.maxRequestsPerMinute != null && state.lastUsed != null && k.maxRequestsPerMinute! > 0) {
          final minInterval = (60000 / k.maxRequestsPerMinute!).floor();
          if ((now - state.lastUsed!) < minInterval) return true;
        }
      }
      return false;
    }

    final candidates = apiKeys.where((k) => !isTemporarilyBlocked(k)).toList();
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
        candidates.sort((a, b) {
          final stateA = ApiKeyManager().getKeyState(a.id);
          final stateB = ApiKeyManager().getKeyState(b.id);
          return (stateA?.totalRequests ?? 0).compareTo(stateB?.totalRequests ?? 0);
        });
        return candidates.first;
      case LoadBalanceStrategy.priority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first;
    }
  }

  void markKeyAsUsed(String keyId) {
    ApiKeyManager().updateKeyStatus(keyId, true, maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyRateLimited(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'rate_limited', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyFailure(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'request_failed', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }
  void updateKey(int index, ApiKeyConfig newConfig) {
    if (index >= 0 && index < apiKeys.length) {
      apiKeys[index] = newConfig;
    }
  }
  void addKey(ApiKeyConfig config) {
    apiKeys.add(config);
  }
  void removeKey(int index) {
    if (apiKeys.length > 1 && index >= 0 && index < apiKeys.length) {
      apiKeys.removeAt(index);
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'jina',
        'id': id,
        'apiKeys': apiKeys.map((k) => k.toJson()).toList(),
        'strategy': strategy.name,
      };

  factory JinaOptions.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('apiKey') && json['apiKey'] is String) {
      return JinaOptions.single(
        id: json['id'],
        apiKey: json['apiKey'],
      );
    }
    return JinaOptions(
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

class PerplexityOptions extends SearchServiceOptions {
  final List<ApiKeyConfig> apiKeys;
  final LoadBalanceStrategy strategy;
  final String? country; // ISO 3166-1 alpha-2
  final List<String>? searchDomainFilter; // domains/URLs
  final int? maxTokensPerPage; // default 1024
  int _currentIndex = 0;
  static const int _cooldownMinutes = 5;
  static const int _maxFailuresBeforeError = 3;

  PerplexityOptions({
    required String id,
    required this.apiKeys,
    this.strategy = LoadBalanceStrategy.roundRobin,
    this.country,
    this.searchDomainFilter,
    this.maxTokensPerPage,
  }) : super(id: id) {
    if (apiKeys.isEmpty) {
      throw ArgumentError('At least one API key is required');
    }
  }

  factory PerplexityOptions.single({
    required String id,
    required String apiKey,
    String? country,
    List<String>? searchDomainFilter,
    int? maxTokensPerPage,
  }) {
    return PerplexityOptions(
      id: id,
      apiKeys: [ApiKeyConfig.create(apiKey)],
      country: country,
      searchDomainFilter: searchDomainFilter,
      maxTokensPerPage: maxTokensPerPage,
    );
  }

  ApiKeyConfig? getNextAvailableKey({Set<String> excludeIds = const {}}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cooldownMs = _cooldownMinutes * 60 * 1000;

    bool isTemporarilyBlocked(ApiKeyConfig k) {
      if (!k.isEnabled) return true;
      if (excludeIds.contains(k.id)) return true;

      final state = ApiKeyManager().getKeyState(k.id);
      if (state != null) {
        if (state.status == 'error' || state.status == 'rateLimited') {
          final since = now - state.updatedAt;
          if (since < cooldownMs) return true;
        }
        if (k.maxRequestsPerMinute != null && state.lastUsed != null && k.maxRequestsPerMinute! > 0) {
          final minInterval = (60000 / k.maxRequestsPerMinute!).floor();
          if ((now - state.lastUsed!) < minInterval) return true;
        }
      }
      return false;
    }

    final candidates = apiKeys.where((k) => !isTemporarilyBlocked(k)).toList();
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
        candidates.sort((a, b) {
          final stateA = ApiKeyManager().getKeyState(a.id);
          final stateB = ApiKeyManager().getKeyState(b.id);
          return (stateA?.totalRequests ?? 0).compareTo(stateB?.totalRequests ?? 0);
        });
        return candidates.first;
      case LoadBalanceStrategy.priority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first;
    }
  }

  void markKeyAsUsed(String keyId) {
    ApiKeyManager().updateKeyStatus(keyId, true, maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyRateLimited(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'rate_limited', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyFailure(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'request_failed', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }
  void updateKey(int index, ApiKeyConfig newConfig) {
    if (index >= 0 && index < apiKeys.length) {
      apiKeys[index] = newConfig;
    }
  }
  void addKey(ApiKeyConfig config) {
    apiKeys.add(config);
  }
  void removeKey(int index) {
    if (apiKeys.length > 1 && index >= 0 && index < apiKeys.length) {
      apiKeys.removeAt(index);
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'perplexity',
        'id': id,
        'apiKeys': apiKeys.map((k) => k.toJson()).toList(),
        'strategy': strategy.name,
        if (country != null) 'country': country,
        if (searchDomainFilter != null) 'searchDomainFilter': searchDomainFilter,
        if (maxTokensPerPage != null) 'maxTokensPerPage': maxTokensPerPage,
      };

  factory PerplexityOptions.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('apiKey') && json['apiKey'] is String) {
      return PerplexityOptions.single(
        id: json['id'],
        apiKey: json['apiKey'],
        country: json['country'],
        searchDomainFilter: (json['searchDomainFilter'] as List?)?.map((e) => e.toString()).toList(),
        maxTokensPerPage: json['maxTokensPerPage'],
      );
    }
    return PerplexityOptions(
      id: json['id'],
      apiKeys: (json['apiKeys'] as List)
          .map((k) => ApiKeyConfig.fromJson(k as Map<String, dynamic>))
          .toList(),
      strategy: LoadBalanceStrategy.values.firstWhere(
        (s) => s.name == json['strategy'],
        orElse: () => LoadBalanceStrategy.roundRobin,
      ),
      country: json['country'],
      searchDomainFilter: (json['searchDomainFilter'] as List?)?.map((e) => e.toString()).toList(),
      maxTokensPerPage: json['maxTokensPerPage'],
    );
  }
}

class BochaOptions extends SearchServiceOptions {
  final List<ApiKeyConfig> apiKeys;
  final LoadBalanceStrategy strategy;
  // Optional parameters supported by Bocha API
  final String? freshness; // e.g., 'noLimit', 'week', 'month', etc.
  final bool summary; // whether to include textual summary
  final String? include; // e.g., 'qq.com|m.163.com'
  final String? exclude; // e.g., 'qq.com|m.163.com'
  int _currentIndex = 0;
  static const int _cooldownMinutes = 5;
  static const int _maxFailuresBeforeError = 3;

  BochaOptions({
    required String id,
    required this.apiKeys,
    this.strategy = LoadBalanceStrategy.roundRobin,
    this.freshness,
    this.summary = true,
    this.include,
    this.exclude,
  }) : super(id: id) {
    if (apiKeys.isEmpty) {
      throw ArgumentError('At least one API key is required');
    }
  }

  factory BochaOptions.single({
    required String id,
    required String apiKey,
    String? freshness,
    bool summary = true,
    String? include,
    String? exclude,
  }) {
    return BochaOptions(
      id: id,
      apiKeys: [ApiKeyConfig.create(apiKey)],
      freshness: freshness,
      summary: summary,
      include: include,
      exclude: exclude,
    );
  }

  ApiKeyConfig? getNextAvailableKey({Set<String> excludeIds = const {}}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cooldownMs = _cooldownMinutes * 60 * 1000;

    bool isTemporarilyBlocked(ApiKeyConfig k) {
      if (!k.isEnabled) return true;
      if (excludeIds.contains(k.id)) return true;

      final state = ApiKeyManager().getKeyState(k.id);
      if (state != null) {
        if (state.status == 'error' || state.status == 'rateLimited') {
          final since = now - state.updatedAt;
          if (since < cooldownMs) return true;
        }
        if (k.maxRequestsPerMinute != null && state.lastUsed != null && k.maxRequestsPerMinute! > 0) {
          final minInterval = (60000 / k.maxRequestsPerMinute!).floor();
          if ((now - state.lastUsed!) < minInterval) return true;
        }
      }
      return false;
    }

    final candidates = apiKeys.where((k) => !isTemporarilyBlocked(k)).toList();
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
        candidates.sort((a, b) {
          final stateA = ApiKeyManager().getKeyState(a.id);
          final stateB = ApiKeyManager().getKeyState(b.id);
          return (stateA?.totalRequests ?? 0).compareTo(stateB?.totalRequests ?? 0);
        });
        return candidates.first;
      case LoadBalanceStrategy.priority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first;
    }
  }

  void markKeyAsUsed(String keyId) {
    ApiKeyManager().updateKeyStatus(keyId, true, maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyRateLimited(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'rate_limited', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }

  void markKeyFailure(String keyId, {String? error}) {
    ApiKeyManager().updateKeyStatus(keyId, false, error: error ?? 'request_failed', maxFailuresBeforeDisable: _maxFailuresBeforeError);
  }
  void updateKey(int index, ApiKeyConfig newConfig) {
    if (index >= 0 && index < apiKeys.length) {
      apiKeys[index] = newConfig;
    }
  }
  void addKey(ApiKeyConfig config) {
    apiKeys.add(config);
  }
  void removeKey(int index) {
    if (apiKeys.length > 1 && index >= 0 && index < apiKeys.length) {
      apiKeys.removeAt(index);
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'bocha',
        'id': id,
        'apiKeys': apiKeys.map((k) => k.toJson()).toList(),
        'strategy': strategy.name,
        if (freshness != null) 'freshness': freshness,
        'summary': summary,
        if (include != null) 'include': include,
        if (exclude != null) 'exclude': exclude,
      };

  factory BochaOptions.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('apiKey') && json['apiKey'] is String) {
      return BochaOptions.single(
        id: json['id'],
        apiKey: json['apiKey'],
        freshness: json['freshness'],
        summary: (json['summary'] ?? true) as bool,
        include: json['include'],
        exclude: json['exclude'],
      );
    }
    return BochaOptions(
      id: json['id'],
      apiKeys: (json['apiKeys'] as List)
          .map((k) => ApiKeyConfig.fromJson(k as Map<String, dynamic>))
          .toList(),
      strategy: LoadBalanceStrategy.values.firstWhere(
        (s) => s.name == json['strategy'],
        orElse: () => LoadBalanceStrategy.roundRobin,
      ),
      freshness: json['freshness'],
      summary: (json['summary'] ?? true) as bool,
      include: json['include'],
      exclude: json['exclude'],
    );
  }
}

class DuckDuckGoOptions extends SearchServiceOptions {
  final String region;

  DuckDuckGoOptions({
    required String id,
    this.region = 'wt-wt',
  }) : super(id: id);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'duckduckgo',
    'id': id,
    'region': region,
  };

  factory DuckDuckGoOptions.fromJson(Map<String, dynamic> json) => DuckDuckGoOptions(
    id: json['id'],
    region: json['region'] ?? 'wt-wt',
  );
}
