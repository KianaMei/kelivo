enum ApiKeyStatus { active, disabled, error, rateLimited }

class ApiKeyUsage {
  final int totalRequests;
  final int successfulRequests;
  final int failedRequests;
  final int consecutiveFailures;
  final int? lastUsed;

  const ApiKeyUsage({
    this.totalRequests = 0,
    this.successfulRequests = 0,
    this.failedRequests = 0,
    this.consecutiveFailures = 0,
    this.lastUsed,
  });

  ApiKeyUsage copyWith({
    int? totalRequests,
    int? successfulRequests,
    int? failedRequests,
    int? consecutiveFailures,
    int? lastUsed,
  }) => ApiKeyUsage(
        totalRequests: totalRequests ?? this.totalRequests,
        successfulRequests: successfulRequests ?? this.successfulRequests,
        failedRequests: failedRequests ?? this.failedRequests,
        consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
        lastUsed: lastUsed ?? this.lastUsed,
      );

  Map<String, dynamic> toJson() => {
        'totalRequests': totalRequests,
        'successfulRequests': successfulRequests,
        'failedRequests': failedRequests,
        'consecutiveFailures': consecutiveFailures,
        'lastUsed': lastUsed,
      };

  factory ApiKeyUsage.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ApiKeyUsage();
    return ApiKeyUsage(
      totalRequests: (json['totalRequests'] as int?) ?? 0,
      successfulRequests: (json['successfulRequests'] as int?) ?? 0,
      failedRequests: (json['failedRequests'] as int?) ?? 0,
      consecutiveFailures: (json['consecutiveFailures'] as int?) ?? 0,
      lastUsed: json['lastUsed'] as int?,
    );
  }
}

/// API Key configuration - contains only static configuration data
/// Runtime state (usage, status, errors) is stored separately in ApiKeyRuntimeState
class ApiKeyConfig {
  final String id;
  final String key;
  final String? name;
  final bool isEnabled;
  final int priority; // 1-10, smaller means higher priority
  final int sortIndex; // Determines manual ordering for round-robin
  final int? maxRequestsPerMinute;
  final int createdAt;

  const ApiKeyConfig({
    required this.id,
    required this.key,
    this.name,
    this.isEnabled = true,
    this.priority = 5,
    this.sortIndex = 0,
    this.maxRequestsPerMinute,
    required this.createdAt,
  });

  ApiKeyConfig copyWith({
    String? id,
    String? key,
    String? name,
    bool? isEnabled,
    int? priority,
    int? sortIndex,
    int? maxRequestsPerMinute,
    int? createdAt,
  }) => ApiKeyConfig(
        id: id ?? this.id,
        key: key ?? this.key,
        name: name ?? this.name,
        isEnabled: isEnabled ?? this.isEnabled,
        priority: priority ?? this.priority,
        sortIndex: sortIndex ?? this.sortIndex,
        maxRequestsPerMinute: maxRequestsPerMinute ?? this.maxRequestsPerMinute,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'name': name,
        'isEnabled': isEnabled,
        'priority': priority,
        'sortIndex': sortIndex,
        'maxRequestsPerMinute': maxRequestsPerMinute,
        'createdAt': createdAt,
      };

  factory ApiKeyConfig.fromJson(Map<String, dynamic> json) {
    // Backward compatibility: ignore runtime fields (usage, status, lastError, updatedAt)
    // These are now stored separately in ApiKeyRuntimeState
    return ApiKeyConfig(
      id: (json['id'] as String?) ?? _generateKeyId(),
      key: (json['key'] as String?) ?? '',
      name: json['name'] as String?,
      isEnabled: (json['isEnabled'] as bool?) ?? true,
      priority: (json['priority'] as int?) ?? 5,
      sortIndex: (json['sortIndex'] as int?) ?? (json['createdAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      maxRequestsPerMinute: json['maxRequestsPerMinute'] as int?,
      createdAt: (json['createdAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  static String _generateKeyId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rnd = (DateTime.now().microsecondsSinceEpoch % 1000000000).toRadixString(36);
    return 'key_${ts}_$rnd';
  }

  static ApiKeyConfig create(String key, {String? name, int priority = 5}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ApiKeyConfig(
      id: _generateKeyId(),
      key: key,
      name: name,
      isEnabled: true,
      priority: priority,
      sortIndex: now,
      createdAt: now,
    );
  }
}

enum LoadBalanceStrategy { roundRobin, priority, leastUsed, random }

class KeyManagementConfig {
  final LoadBalanceStrategy strategy;
  final int maxFailuresBeforeDisable;
  final int failureRecoveryTimeMinutes;
  final bool enableAutoRecovery;
  final int? roundRobinIndex; // optional persisted pointer

  const KeyManagementConfig({
    this.strategy = LoadBalanceStrategy.roundRobin,
    this.maxFailuresBeforeDisable = 3,
    this.failureRecoveryTimeMinutes = 5,
    this.enableAutoRecovery = true,
    this.roundRobinIndex,
  });

  KeyManagementConfig copyWith({
    LoadBalanceStrategy? strategy,
    int? maxFailuresBeforeDisable,
    int? failureRecoveryTimeMinutes,
    bool? enableAutoRecovery,
    int? roundRobinIndex,
  }) => KeyManagementConfig(
        strategy: strategy ?? this.strategy,
        maxFailuresBeforeDisable: maxFailuresBeforeDisable ?? this.maxFailuresBeforeDisable,
        failureRecoveryTimeMinutes: failureRecoveryTimeMinutes ?? this.failureRecoveryTimeMinutes,
        enableAutoRecovery: enableAutoRecovery ?? this.enableAutoRecovery,
        roundRobinIndex: roundRobinIndex ?? this.roundRobinIndex,
      );

  Map<String, dynamic> toJson() => {
        'strategy': strategy.name,
        'maxFailuresBeforeDisable': maxFailuresBeforeDisable,
        'failureRecoveryTimeMinutes': failureRecoveryTimeMinutes,
        'enableAutoRecovery': enableAutoRecovery,
        'roundRobinIndex': roundRobinIndex,
      };

  factory KeyManagementConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KeyManagementConfig();
    final s = (json['strategy'] as String?) ?? 'roundRobin';
    final strat = LoadBalanceStrategy.values.firstWhere(
      (e) => e.name.toLowerCase() == s.toLowerCase(),
      orElse: () => LoadBalanceStrategy.roundRobin,
    );
    return KeyManagementConfig(
      strategy: strat,
      maxFailuresBeforeDisable: (json['maxFailuresBeforeDisable'] as int?) ?? 3,
      failureRecoveryTimeMinutes: (json['failureRecoveryTimeMinutes'] as int?) ?? 5,
      enableAutoRecovery: (json['enableAutoRecovery'] as bool?) ?? true,
      roundRobinIndex: json['roundRobinIndex'] as int?,
    );
  }
}
