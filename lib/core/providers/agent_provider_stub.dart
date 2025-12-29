import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/agent_session.dart';
import '../models/agent_message.dart';

/// Stub implementation for web platform (Agent not supported)
class AgentProvider extends ChangeNotifier {
  /// Whether agent functionality is available on this platform
  bool get isSupported => false;

  /// All agents
  List<Agent> get agents => const <Agent>[];

  /// Current agent
  Agent? get currentAgent => null;

  /// All sessions for current agent
  List<AgentSession> get sessions => const <AgentSession>[];

  /// Current session
  AgentSession? get currentSession => null;

  /// Current session ID
  String? get currentSessionId => null;

  /// Messages for current session
  List<AgentMessage> get currentMessages => const <AgentMessage>[];

  /// Whether agent is currently running
  bool get isRunning => false;

  /// Current permission request if any
  dynamic get pendingPermission => null;

  Future<void> init() async {}

  Future<String> addAgent({String? name}) async {
    throw UnsupportedError('Agent not supported on web');
  }

  Future<void> updateAgent(Agent agent) async {}

  Future<void> deleteAgent(String id) async {}

  Future<void> setCurrentAgent(String? id) async {}

  Future<String> createSession({String? name}) async {
    throw UnsupportedError('Agent not supported on web');
  }

  Future<void> setCurrentSession(String? id) async {}

  Future<void> deleteSession(String id) async {}

  Future<void> renameSession(String id, String newName) async {}

  Future<void> invoke({
    required String prompt,
    required String workingDirectory,
    String? apiKey,
    String? apiHost,
  }) async {}

  Future<void> abort() async {}

  Future<void> respondToPermission(bool allow) async {}
}
