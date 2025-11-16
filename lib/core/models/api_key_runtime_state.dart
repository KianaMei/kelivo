import 'package:hive/hive.dart';

part 'api_key_runtime_state.g.dart';

/// Runtime state for API keys - stored separately from configuration
/// This allows frequent updates without serializing entire ProviderConfig
@HiveType(typeId: 2)
class ApiKeyRuntimeState extends HiveObject {
  @HiveField(0)
  final String keyId;

  @HiveField(1)
  final int totalRequests;

  @HiveField(2)
  final int successfulRequests;

  @HiveField(3)
  final int failedRequests;

  @HiveField(4)
  final int consecutiveFailures;

  @HiveField(5)
  final int? lastUsed;

  /// Status: 'active', 'error', 'disabled', 'rateLimited'
  @HiveField(6)
  final String status;

  @HiveField(7)
  final String? lastError;

  @HiveField(8)
  final int updatedAt;

  ApiKeyRuntimeState({
    required this.keyId,
    required this.totalRequests,
    required this.successfulRequests,
    required this.failedRequests,
    required this.consecutiveFailures,
    this.lastUsed,
    required this.status,
    this.lastError,
    required this.updatedAt,
  });

  /// Create initial state for a new key
  factory ApiKeyRuntimeState.initial(String keyId) {
    return ApiKeyRuntimeState(
      keyId: keyId,
      totalRequests: 0,
      successfulRequests: 0,
      failedRequests: 0,
      consecutiveFailures: 0,
      lastUsed: null,
      status: 'active',
      lastError: null,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  ApiKeyRuntimeState copyWith({
    String? keyId,
    int? totalRequests,
    int? successfulRequests,
    int? failedRequests,
    int? consecutiveFailures,
    int? lastUsed,
    String? status,
    String? lastError,
    int? updatedAt,
  }) {
    return ApiKeyRuntimeState(
      keyId: keyId ?? this.keyId,
      totalRequests: totalRequests ?? this.totalRequests,
      successfulRequests: successfulRequests ?? this.successfulRequests,
      failedRequests: failedRequests ?? this.failedRequests,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      lastUsed: lastUsed ?? this.lastUsed,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'keyId': keyId,
        'totalRequests': totalRequests,
        'successfulRequests': successfulRequests,
        'failedRequests': failedRequests,
        'consecutiveFailures': consecutiveFailures,
        'lastUsed': lastUsed,
        'status': status,
        'lastError': lastError,
        'updatedAt': updatedAt,
      };

  factory ApiKeyRuntimeState.fromJson(Map<String, dynamic> json) {
    return ApiKeyRuntimeState(
      keyId: json['keyId'] as String,
      totalRequests: json['totalRequests'] as int? ?? 0,
      successfulRequests: json['successfulRequests'] as int? ?? 0,
      failedRequests: json['failedRequests'] as int? ?? 0,
      consecutiveFailures: json['consecutiveFailures'] as int? ?? 0,
      lastUsed: json['lastUsed'] as int?,
      status: json['status'] as String? ?? 'active',
      lastError: json['lastError'] as String?,
      updatedAt: json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
