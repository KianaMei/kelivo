import 'dart:async';
import '../../models/agent.dart';
import '../../models/agent_message.dart';

/// Stub implementation for web platform (Agent not supported)
class AgentService {
  static final AgentService _instance = AgentService._();
  static AgentService get instance => _instance;
  AgentService._();

  /// Whether agent functionality is available on this platform
  bool get isSupported => false;

  /// Stream of agent messages for a session
  Stream<AgentMessage> get messageStream => const Stream.empty();

  /// Stream of permission requests
  Stream<PermissionRequest> get permissionStream => const Stream.empty();

  /// Initialize the service
  Future<void> init() async {}

  /// Dispose resources
  Future<void> dispose() async {}

  /// Invoke an agent with a prompt
  Future<void> invoke({
    required Agent agent,
    required String sessionId,
    required String prompt,
    required String workingDirectory,
    required String apiKey,
    String? apiHost,
    String? sdkSessionId,
  }) async {
    throw UnsupportedError('Agent is not supported on web platform');
  }

  /// Abort the current agent execution
  Future<void> abort() async {}

  /// Respond to a permission request
  Future<void> respondToPermission({
    required String requestId,
    required bool allow,
  }) async {}
}

/// Permission request from agent
class PermissionRequest {
  final String id;
  final String toolName;
  final Map<String, dynamic> input;
  final String? inputPreview;
  final DateTime expiresAt;

  const PermissionRequest({
    required this.id,
    required this.toolName,
    required this.input,
    this.inputPreview,
    required this.expiresAt,
  });
}
