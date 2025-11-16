import 'dart:math';
import 'package:hive/hive.dart';
import '../models/api_keys.dart';
import '../models/api_key_runtime_state.dart';
import '../providers/settings_provider.dart';

class KeySelectionResult {
  final ApiKeyConfig? key;
  final String reason;
  const KeySelectionResult(this.key, this.reason);
}

/// Manages API key selection and runtime state tracking
/// Runtime state (usage, status, errors) is stored in Hive for persistence
class ApiKeyManager {
  static final ApiKeyManager _instance = ApiKeyManager._internal();
  factory ApiKeyManager() => _instance;
  ApiKeyManager._internal();

  Box<ApiKeyRuntimeState>? _stateBox;
  bool _initialized = false;

  /// Initialize Hive box for runtime state storage
  /// Must be called before using selectForProvider or updateKeyStatus
  Future<void> init() async {
    if (_initialized) return;

    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ApiKeyRuntimeStateAdapter());
    }

    _stateBox = await Hive.openBox<ApiKeyRuntimeState>('api_key_states');
    _initialized = true;
  }

  /// Get runtime state for a key, or create initial state if not found
  ApiKeyRuntimeState _getOrCreateState(String keyId) {
    return _stateBox?.get(keyId) ?? ApiKeyRuntimeState.initial(keyId);
  }

  /// Check if a key is available based on its runtime state
  bool _isKeyAvailable(ApiKeyConfig key, int now, int cooldownMs) {
    final state = _getOrCreateState(key.id);

    // Check status
    if (state.status == 'disabled') return false;
    if (state.status == 'error') {
      final since = now - state.updatedAt;
      if (since < cooldownMs) return false; // Still in cooldown
    }

    return true; // Active or recovered from error
  }

  /// Select the best available API key for a provider using configured strategy
  KeySelectionResult selectForProvider(ProviderConfig provider) {
    final keys = (provider.apiKeys ?? const <ApiKeyConfig>[])
        .where((k) => k.isEnabled)
        .toList();

    if (keys.isEmpty) return const KeySelectionResult(null, 'no_keys');

    // Filter available keys (simplified logic - no special cases)
    final now = DateTime.now().millisecondsSinceEpoch;
    final cooldownMs = (provider.keyManagement?.failureRecoveryTimeMinutes ?? 5) * 60 * 1000;

    final available = keys.where((k) => _isKeyAvailable(k, now, cooldownMs)).toList();

    if (available.isEmpty) {
      return const KeySelectionResult(null, 'no_available_keys');
    }

    final strategy = provider.keyManagement?.strategy ?? LoadBalanceStrategy.roundRobin;
    ApiKeyConfig chosen;

    switch (strategy) {
      case LoadBalanceStrategy.priority:
        available.sort((a, b) => a.priority.compareTo(b.priority));
        chosen = available.first;
        break;

      case LoadBalanceStrategy.leastUsed:
        // Sort by total requests from runtime state
        available.sort((a, b) {
          final stateA = _getOrCreateState(a.id);
          final stateB = _getOrCreateState(b.id);
          return stateA.totalRequests.compareTo(stateB.totalRequests);
        });
        chosen = available.first;
        break;

      case LoadBalanceStrategy.random:
        chosen = available[Random().nextInt(available.length)];
        break;

      case LoadBalanceStrategy.roundRobin:
      default:
        // Stable ordering by sortIndex
        available.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

        // Use persisted roundRobinIndex from provider config
        final cur = provider.keyManagement?.roundRobinIndex ?? 0;
        final idx = cur % available.length;
        chosen = available[idx];

        // Note: Incrementing roundRobinIndex should be done by caller
        // after persisting the updated provider config
        break;
    }

    return KeySelectionResult(chosen, 'strategy_${strategy.name}');
  }

  /// Update runtime state for a key after API request
  /// This is the only method that modifies key state - ensures single source of truth
  Future<void> updateKeyStatus(
    String keyId,
    bool success, {
    String? error,
    int? maxFailuresBeforeDisable,
  }) async {
    if (!_initialized) {
      throw StateError('ApiKeyManager not initialized. Call init() first.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final old = _getOrCreateState(keyId);
    final maxFailures = maxFailuresBeforeDisable ?? 3;

    final newConsecutiveFailures = success ? 0 : (old.consecutiveFailures + 1);
    final newStatus = success
        ? 'active'
        : (newConsecutiveFailures >= maxFailures)
            ? 'error'
            : old.status;

    final newState = ApiKeyRuntimeState(
      keyId: keyId,
      totalRequests: old.totalRequests + 1,
      successfulRequests: old.successfulRequests + (success ? 1 : 0),
      failedRequests: old.failedRequests + (success ? 0 : 1),
      consecutiveFailures: newConsecutiveFailures,
      lastUsed: now,
      status: newStatus,
      lastError: success ? null : (error ?? old.lastError),
      updatedAt: now,
    );

    await _stateBox?.put(keyId, newState);
  }

  /// Get runtime state for a key (for UI display)
  ApiKeyRuntimeState? getKeyState(String keyId) {
    return _stateBox?.get(keyId);
  }

  /// Clear runtime state for a key (e.g., when key is deleted)
  Future<void> clearKeyState(String keyId) async {
    await _stateBox?.delete(keyId);
  }

  /// Reset all runtime states (for testing/debugging)
  Future<void> resetAllStates() async {
    await _stateBox?.clear();
  }
}
