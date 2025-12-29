import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/agent.dart';
import '../models/agent_session.dart';
import '../models/agent_message.dart';
import '../services/agent/agent_service.dart';

/// Agent state management for desktop platforms
class AgentProvider extends ChangeNotifier {
  static const String _agentsKey = 'agents_v1';
  static const String _currentAgentKey = 'current_agent_id_v1';
  static const String _sessionsKey = 'agent_sessions_v1';
  static const String _currentSessionKey = 'current_agent_session_id_v1';
  static const String _messagesKeyPrefix = 'agent_messages_';

  final List<Agent> _agents = <Agent>[];
  final List<AgentSession> _sessions = <AgentSession>[];
  final List<AgentMessage> _messages = <AgentMessage>[];

  String? _currentAgentId;
  String? _currentSessionId;
  bool _isRunning = false;
  PermissionRequest? _pendingPermission;

  StreamSubscription<AgentMessage>? _messageSubscription;
  StreamSubscription<PermissionRequest>? _permissionSubscription;

  bool _isInitialized = false;

  /// Whether agent functionality is available on this platform
  bool get isSupported => AgentService.instance.isSupported;

  /// All agents
  List<Agent> get agents => List.unmodifiable(_agents);

  /// Current agent ID
  String? get currentAgentId => _currentAgentId;

  /// Current agent
  Agent? get currentAgent {
    if (_currentAgentId == null) return null;
    final idx = _agents.indexWhere((a) => a.id == _currentAgentId);
    return idx != -1 ? _agents[idx] : null;
  }

  /// All sessions for current agent
  List<AgentSession> get sessions {
    if (_currentAgentId == null) return const <AgentSession>[];
    return List.unmodifiable(
      _sessions.where((s) => s.agentId == _currentAgentId).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
    );
  }

  /// Current session ID
  String? get currentSessionId => _currentSessionId;

  /// Current session
  AgentSession? get currentSession {
    if (_currentSessionId == null) return null;
    final idx = _sessions.indexWhere((s) => s.id == _currentSessionId);
    return idx != -1 ? _sessions[idx] : null;
  }

  /// Messages for current session
  List<AgentMessage> get currentMessages {
    if (_currentSessionId == null) return const <AgentMessage>[];
    return List.unmodifiable(
      _messages.where((m) => m.sessionId == _currentSessionId).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
    );
  }

  /// Whether agent is currently running
  bool get isRunning => _isRunning;

  /// Current permission request if any
  PermissionRequest? get pendingPermission => _pendingPermission;

  AgentProvider() {
    _init();
  }

  Future<void> _init() async {
    if (_isInitialized) return;

    await AgentService.instance.init();
    await _load();

    // Subscribe to agent service streams
    _messageSubscription = AgentService.instance.messageStream.listen(_onMessage);
    _permissionSubscription = AgentService.instance.permissionStream.listen(_onPermission);

    // Hook up SDK session ID callback for resume functionality
    AgentService.instance.onSdkSessionId = _onSdkSessionId;

    _isInitialized = true;
    notifyListeners();
  }

  void _onSdkSessionId(String sdkSessionId) {
    if (_currentSessionId == null) return;
    final idx = _sessions.indexWhere((s) => s.id == _currentSessionId);
    if (idx != -1) {
      _sessions[idx].sdkSessionId = sdkSessionId;
      _persistSessions();
    }
  }

  Future<void> init() async {
    await _init();
  }

  @override
  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    await _permissionSubscription?.cancel();
    await AgentService.instance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // Load agents
    final agentsRaw = prefs.getString(_agentsKey);
    if (agentsRaw != null && agentsRaw.isNotEmpty) {
      _agents
        ..clear()
        ..addAll(Agent.decodeList(agentsRaw));
    }

    // Load current agent
    final savedAgentId = prefs.getString(_currentAgentKey);
    if (savedAgentId != null && _agents.any((a) => a.id == savedAgentId)) {
      _currentAgentId = savedAgentId;
    }

    // Load sessions
    final sessionsRaw = prefs.getString(_sessionsKey);
    if (sessionsRaw != null && sessionsRaw.isNotEmpty) {
      try {
        final arr = jsonDecode(sessionsRaw) as List<dynamic>;
        _sessions
          ..clear()
          ..addAll([for (final e in arr) AgentSession.fromJson(e as Map<String, dynamic>)]);
      } catch (_) {}
    }

    // Load current session
    final savedSessionId = prefs.getString(_currentSessionKey);
    if (savedSessionId != null && _sessions.any((s) => s.id == savedSessionId)) {
      _currentSessionId = savedSessionId;
      await _loadMessages(savedSessionId);
    }
  }

  Future<void> _persistAgents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_agentsKey, Agent.encodeList(_agents));
  }

  Future<void> _persistSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_sessions.map((s) => s.toJson()).toList());
    await prefs.setString(_sessionsKey, json);
  }

  Future<void> _loadMessages(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_messagesKeyPrefix$sessionId');
    if (raw == null || raw.isEmpty) return;

    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      final msgs = [for (final e in arr) AgentMessage.fromJson(e as Map<String, dynamic>)];
      _messages
        ..removeWhere((m) => m.sessionId == sessionId)
        ..addAll(msgs);
    } catch (_) {}
  }

  Future<void> _persistMessages(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final msgs = _messages.where((m) => m.sessionId == sessionId).toList();
    final json = jsonEncode(msgs.map((m) => m.toJson()).toList());
    await prefs.setString('$_messagesKeyPrefix$sessionId', json);
  }

  void _onMessage(AgentMessage message) {
    if (message.sessionId != _currentSessionId) return;

    // Handle streaming text updates - aggregate by message ID
    if (message.isStreaming && message.type == AgentMessageType.assistant) {
      // Try to find existing message by ID first, fallback to last streaming message
      int idx = -1;
      if (message.id != null) {
        idx = _messages.indexWhere(
          (m) => m.id == message.id && m.type == AgentMessageType.assistant,
        );
      }
      if (idx == -1) {
        idx = _messages.lastIndexWhere(
          (m) => m.sessionId == _currentSessionId && m.type == AgentMessageType.assistant && m.isStreaming,
        );
      }
      if (idx != -1) {
        _messages[idx].content += message.content;
        notifyListeners();
        return;
      }
    }

    // Handle text-done: finalize streaming message
    if (!message.isStreaming && message.type == AgentMessageType.assistant && message.id != null) {
      final idx = _messages.indexWhere(
        (m) => m.id == message.id && m.type == AgentMessageType.assistant && m.isStreaming,
      );
      if (idx != -1) {
        // Replace content with final text and mark as not streaming
        _messages[idx].content = message.content;
        _messages[idx].isStreaming = false;
        notifyListeners();
        _persistMessages(_currentSessionId!);
        return;
      }
    }

    // Handle system messages for done/aborted
    if (message.type == AgentMessageType.system) {
      if (message.content == '[Done]') {
        _isRunning = false;
        _updateSessionStatus(AgentSessionStatus.completed, null);
        _persistMessages(_currentSessionId!);
        notifyListeners();
        return;
      }
      if (message.content == '[Aborted]') {
        _isRunning = false;
        _updateSessionStatus(AgentSessionStatus.aborted, null);
        _persistMessages(_currentSessionId!);
        notifyListeners();
        return;
      }
    }

    // Add new message
    _messages.add(message);
    notifyListeners();

    // Check if agent is done (fallback for non-ID messages)
    if (!message.isStreaming && message.type == AgentMessageType.assistant) {
      _isRunning = false;
      _persistMessages(_currentSessionId!);
      _updateSessionTimestamp();
    }

    if (message.type == AgentMessageType.error) {
      _isRunning = false;
      _updateSessionStatus(AgentSessionStatus.error, message.content);
    }
  }

  void _onPermission(PermissionRequest request) {
    _pendingPermission = request;
    _updateSessionStatus(AgentSessionStatus.waitingPermission, null);
    notifyListeners();
  }

  void _updateSessionTimestamp() {
    if (_currentSessionId == null) return;
    final idx = _sessions.indexWhere((s) => s.id == _currentSessionId);
    if (idx != -1) {
      _sessions[idx].updatedAt = DateTime.now();
      _sessions[idx].status = AgentSessionStatus.idle;
      _persistSessions();
    }
  }

  void _updateSessionStatus(AgentSessionStatus status, String? error) {
    if (_currentSessionId == null) return;
    final idx = _sessions.indexWhere((s) => s.id == _currentSessionId);
    if (idx != -1) {
      _sessions[idx].status = status;
      if (error != null) _sessions[idx].lastError = error;
      _sessions[idx].updatedAt = DateTime.now();
      _persistSessions();
      notifyListeners();
    }
  }

  // ==================== Agent CRUD ====================

  Future<String> addAgent({String? name}) async {
    final now = DateTime.now();
    final agent = Agent(
      id: const Uuid().v4(),
      name: name ?? 'New Agent',
      createdAt: now,
      updatedAt: now,
    );
    _agents.add(agent);
    await _persistAgents();
    notifyListeners();
    return agent.id;
  }

  Future<void> updateAgent(Agent agent) async {
    final idx = _agents.indexWhere((a) => a.id == agent.id);
    if (idx == -1) return;
    _agents[idx] = agent.copyWith(updatedAt: DateTime.now());
    await _persistAgents();
    notifyListeners();
  }

  Future<void> saveAgent(Agent agent) async {
    final idx = _agents.indexWhere((a) => a.id == agent.id);
    if (idx != -1) {
      _agents[idx] = agent.copyWith(updatedAt: DateTime.now());
    } else {
      _agents.add(agent);
    }
    await _persistAgents();
    notifyListeners();
  }

  Future<void> deleteAgent(String id) async {
    _agents.removeWhere((a) => a.id == id);
    // Also delete related sessions
    final sessionIds = _sessions.where((s) => s.agentId == id).map((s) => s.id).toList();
    _sessions.removeWhere((s) => s.agentId == id);
    _messages.removeWhere((m) => sessionIds.contains(m.sessionId));

    if (_currentAgentId == id) {
      _currentAgentId = _agents.isNotEmpty ? _agents.first.id : null;
      _currentSessionId = null;
      final prefs = await SharedPreferences.getInstance();
      if (_currentAgentId != null) {
        await prefs.setString(_currentAgentKey, _currentAgentId!);
      } else {
        await prefs.remove(_currentAgentKey);
      }
      await prefs.remove(_currentSessionKey);
    }

    // Clean up message storage
    final prefs = await SharedPreferences.getInstance();
    for (final sid in sessionIds) {
      await prefs.remove('$_messagesKeyPrefix$sid');
    }

    await _persistAgents();
    await _persistSessions();
    notifyListeners();
  }

  Future<void> setCurrentAgent(String? id) async {
    if (_currentAgentId == id) return;
    _currentAgentId = id;
    _currentSessionId = null;
    _messages.clear();

    final prefs = await SharedPreferences.getInstance();
    if (id != null) {
      await prefs.setString(_currentAgentKey, id);
      // Select first session of this agent if exists
      final agentSessions = _sessions.where((s) => s.agentId == id).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (agentSessions.isNotEmpty) {
        _currentSessionId = agentSessions.first.id;
        await prefs.setString(_currentSessionKey, _currentSessionId!);
        await _loadMessages(_currentSessionId!);
      }
    } else {
      await prefs.remove(_currentAgentKey);
    }
    await prefs.remove(_currentSessionKey);
    notifyListeners();
  }

  Agent? getAgentById(String id) {
    final idx = _agents.indexWhere((a) => a.id == id);
    return idx != -1 ? _agents[idx] : null;
  }

  // ==================== Session CRUD ====================

  Future<String> createSession({String? name}) async {
    if (_currentAgentId == null) {
      throw StateError('No agent selected');
    }

    final session = AgentSession(
      agentId: _currentAgentId!,
      name: name ?? 'New Session',
    );
    _sessions.add(session);
    _currentSessionId = session.id;
    _messages.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentSessionKey, session.id);
    await _persistSessions();
    notifyListeners();
    return session.id;
  }

  Future<void> setCurrentSession(String? id) async {
    if (_currentSessionId == id) return;
    _currentSessionId = id;
    _messages.clear();

    final prefs = await SharedPreferences.getInstance();
    if (id != null) {
      await prefs.setString(_currentSessionKey, id);
      await _loadMessages(id);
    } else {
      await prefs.remove(_currentSessionKey);
    }
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    _messages.removeWhere((m) => m.sessionId == id);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_messagesKeyPrefix$id');

    if (_currentSessionId == id) {
      final remaining = sessions;
      _currentSessionId = remaining.isNotEmpty ? remaining.first.id : null;
      if (_currentSessionId != null) {
        await prefs.setString(_currentSessionKey, _currentSessionId!);
        await _loadMessages(_currentSessionId!);
      } else {
        await prefs.remove(_currentSessionKey);
      }
    }

    await _persistSessions();
    notifyListeners();
  }

  Future<void> renameSession(String id, String newName) async {
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    _sessions[idx].name = newName;
    _sessions[idx].updatedAt = DateTime.now();
    await _persistSessions();
    notifyListeners();
  }

  // ==================== Agent Invocation ====================

  Future<void> invoke({
    required String prompt,
    required String workingDirectory,
    String? apiKey,
    String? apiHost,
  }) async {
    final agent = currentAgent;
    final session = currentSession;
    if (agent == null || session == null) {
      throw StateError('No agent or session selected');
    }

    if (apiKey == null || apiKey.isEmpty) {
      throw ArgumentError('API key is required');
    }

    _isRunning = true;
    _updateSessionStatus(AgentSessionStatus.running, null);
    notifyListeners();

    try {
      await AgentService.instance.invoke(
        agent: agent,
        sessionId: session.id,
        prompt: prompt,
        workingDirectory: workingDirectory,
        apiKey: apiKey,
        apiHost: apiHost,
        sdkSessionId: session.sdkSessionId,
      );
    } catch (e) {
      _isRunning = false;
      _updateSessionStatus(AgentSessionStatus.error, e.toString());
      rethrow;
    }
  }

  Future<void> abort() async {
    if (!_isRunning) return;
    await AgentService.instance.abort();
    _isRunning = false;
    _updateSessionStatus(AgentSessionStatus.aborted, null);
    notifyListeners();
  }

  Future<void> respondToPermission(bool allow) async {
    if (_pendingPermission == null) return;

    await AgentService.instance.respondToPermission(
      requestId: _pendingPermission!.id,
      allow: allow,
    );

    _pendingPermission = null;
    _updateSessionStatus(AgentSessionStatus.running, null);
    notifyListeners();
  }
}
