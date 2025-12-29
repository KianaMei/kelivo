import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/agent.dart';
import '../../models/agent_message.dart';

/// Permission request from agent bridge
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

  factory PermissionRequest.fromJson(Map<String, dynamic> json) {
    return PermissionRequest(
      id: json['id'] as String,
      toolName: json['toolName'] as String,
      input: (json['input'] as Map<String, dynamic>?) ?? const {},
      inputPreview: json['inputPreview'] as String?,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (json['expiresAt'] as num).toInt(),
      ),
    );
  }
}

/// Agent service for desktop platforms (Windows/macOS/Linux)
/// Communicates with Node.js bridge via JSON-RPC over stdin/stdout
class AgentService {
  static final AgentService _instance = AgentService._();
  static AgentService get instance => _instance;
  AgentService._();

  Process? _bridgeProcess;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;

  final _messageController = StreamController<AgentMessage>.broadcast();
  final _permissionController = StreamController<PermissionRequest>.broadcast();
  final _pendingRequests = <String, Completer<Map<String, dynamic>>>{};

  int _requestIdCounter = 0;
  String? _currentSessionId;
  bool _isInitialized = false;

  /// Whether agent functionality is available on this platform
  bool get isSupported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// Stream of agent messages for a session
  Stream<AgentMessage> get messageStream => _messageController.stream;

  /// Stream of permission requests
  Stream<PermissionRequest> get permissionStream => _permissionController.stream;

  /// Initialize the service
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _stopBridge();
    await _messageController.close();
    await _permissionController.close();
    _isInitialized = false;
  }

  /// Get path to Node.js executable
  Future<String> _getNodePath() async {
    // Development: use system Node.js
    if (kDebugMode) {
      return Platform.isWindows ? 'node.exe' : 'node';
    }

    // Production: use bundled Node.js
    final runtimeDir = await _getAgentRuntimeDirectory();
    final platform = _getPlatformIdentifier();
    final nodePath = p.join(
      runtimeDir,
      platform,
      Platform.isWindows ? 'node.exe' : 'node',
    );

    // Check if bundled node exists, fallback to system node
    if (await File(nodePath).exists()) {
      debugPrint('[AgentService] Using bundled Node.js: $nodePath');
      return nodePath;
    }
    debugPrint('[AgentService] Bundled Node.js not found, using system node');
    return Platform.isWindows ? 'node.exe' : 'node';
  }

  /// Get platform identifier for runtime directory
  String _getPlatformIdentifier() {
    if (Platform.isWindows) {
      return 'win-x64';
    } else if (Platform.isMacOS) {
      // Check for Apple Silicon
      return Platform.version.contains('arm') ? 'darwin-arm64' : 'darwin-x64';
    } else if (Platform.isLinux) {
      // Check for ARM64
      return Platform.version.contains('aarch64') ? 'linux-arm64' : 'linux-x64';
    }
    return 'unknown';
  }

  /// Get the directory containing agent runtime files
  Future<String> _getAgentRuntimeDirectory() async {
    // Try bundled location first (alongside executable)
    final exeDir = p.dirname(Platform.resolvedExecutable);

    if (Platform.isWindows) {
      // Windows: build/windows/x64/runner/Release/data/agent-runtime
      final bundledPath = p.join(exeDir, 'data', 'agent-runtime');
      if (await Directory(bundledPath).exists()) {
        return bundledPath;
      }
    } else if (Platform.isMacOS) {
      // macOS: Kelivo.app/Contents/Resources/agent-runtime
      final bundledPath = p.join(exeDir, '..', 'Resources', 'agent-runtime');
      if (await Directory(bundledPath).exists()) {
        return p.normalize(bundledPath);
      }
    } else if (Platform.isLinux) {
      // Linux: bundle/data/agent-runtime
      final bundledPath = p.join(exeDir, 'data', 'agent-runtime');
      if (await Directory(bundledPath).exists()) {
        return bundledPath;
      }
    }

    // Fallback to app support directory (for manual installation)
    final appDir = await getApplicationSupportDirectory();
    return p.join(appDir.path, 'agent-runtime');
  }

  /// Get path to agent-bridge.js
  Future<String> _getBridgePath() async {
    // Development: use source file
    if (kDebugMode) {
      // In debug mode, the working directory is typically the project root
      // Try multiple possible paths
      final possiblePaths = [
        'assets/agent-bridge/agent-bridge.js',
        '../assets/agent-bridge/agent-bridge.js',
        // Also try relative to the executable location
        p.join(p.dirname(Platform.resolvedExecutable), 'data', 'flutter_assets', 'assets', 'agent-bridge', 'agent-bridge.js'),
      ];
      for (final path in possiblePaths) {
        final file = File(path);
        if (await file.exists()) {
          debugPrint('[AgentService] Found bridge at: ${file.absolute.path}');
          return file.absolute.path;
        }
      }
      // Fallback: try the current directory explicitly
      final cwd = Directory.current.path;
      final cwdPath = p.join(cwd, 'assets', 'agent-bridge', 'agent-bridge.js');
      if (await File(cwdPath).exists()) {
        debugPrint('[AgentService] Found bridge at cwd: $cwdPath');
        return cwdPath;
      }
      debugPrint('[AgentService] Bridge not found in debug paths, cwd: $cwd');
    }

    // Production: use bundled bridge
    final runtimeDir = await _getAgentRuntimeDirectory();
    return p.join(runtimeDir, 'agent-bridge', 'agent-bridge.js');
  }

  /// Start the bridge process
  Future<void> _startBridge() async {
    if (_bridgeProcess != null) return;

    final nodePath = await _getNodePath();
    final bridgePath = await _getBridgePath();

    debugPrint('[AgentService] Starting bridge: $nodePath $bridgePath');

    _bridgeProcess = await Process.start(
      nodePath,
      [bridgePath],
      mode: ProcessStartMode.normal,
    );

    // Handle stdout (JSON-RPC responses and notifications)
    _stdoutSubscription = _bridgeProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdout, onError: _handleError);

    // Handle stderr (debug logs)
    _stderrSubscription = _bridgeProcess!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      debugPrint('[AgentBridge/stderr] $line');
    });

    // Handle process exit
    _bridgeProcess!.exitCode.then((code) {
      debugPrint('[AgentService] Bridge exited with code $code');
      _bridgeProcess = null;
      _cleanup();
    });
  }

  /// Stop the bridge process
  Future<void> _stopBridge() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    if (_bridgeProcess != null) {
      _bridgeProcess!.kill();
      _bridgeProcess = null;
    }

    _cleanup();
  }

  void _cleanup() {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError('Bridge process terminated');
      }
    }
    _pendingRequests.clear();
  }

  void _handleStdout(String line) {
    if (line.trim().isEmpty) return;

    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final jsonrpc = json['jsonrpc'];
      if (jsonrpc != '2.0') return;

      final id = json['id'] as String?;
      final method = json['method'] as String?;

      if (id != null && _pendingRequests.containsKey(id)) {
        // Response to a request we sent
        final completer = _pendingRequests.remove(id)!;
        if (json.containsKey('error')) {
          completer.completeError(json['error']);
        } else {
          completer.complete(json['result'] as Map<String, dynamic>? ?? {});
        }
      } else if (method != null) {
        // Request or notification from bridge
        final params = json['params'] as Map<String, dynamic>?;
        if (method == 'requestPermission' && id != null) {
          // Permission request with ID - we need to respond later
          final request = PermissionRequest.fromJson({
            'id': id,
            ...?params,
          });
          _permissionController.add(request);
        } else {
          // Regular notification
          _handleNotification(method, params);
        }
      }
    } catch (e) {
      debugPrint('[AgentService] Failed to parse stdout: $e');
    }
  }

  void _handleNotification(String method, Map<String, dynamic>? params) {
    if (params == null) return;

    switch (method) {
      case 'stream':
        _handleStreamEvent(params);
        break;
      case 'error':
        debugPrint('[AgentService] Error: ${params['message']}');
        break;
    }
  }

  /// Callback for SDK session ID (for resume functionality)
  void Function(String sdkSessionId)? onSdkSessionId;

  void _handleStreamEvent(Map<String, dynamic> params) {
    final type = params['type'] as String?;
    final sessionId = _currentSessionId;
    if (sessionId == null) return;

    switch (type) {
      case 'text-delta':
        final text = params['text'] as String? ?? '';
        final msgId = params['id'] as String?;
        _messageController.add(AgentMessage(
          id: msgId,
          sessionId: sessionId,
          type: AgentMessageType.assistant,
          content: text,
          isStreaming: true,
        ));
        break;

      case 'text-done':
        final text = params['text'] as String? ?? '';
        final msgId = params['id'] as String?;
        _messageController.add(AgentMessage(
          id: msgId,
          sessionId: sessionId,
          type: AgentMessageType.assistant,
          content: text,
          isStreaming: false,
        ));
        break;

      case 'thinking':
        // Claude's extended thinking (if enabled)
        final text = params['text'] as String? ?? '';
        _messageController.add(AgentMessage(
          sessionId: sessionId,
          type: AgentMessageType.system,
          content: '[Thinking] $text',
          isStreaming: true,
        ));
        break;

      case 'tool-start':
        final toolId = params['id'] as String?;
        _messageController.add(AgentMessage(
          id: toolId,
          sessionId: sessionId,
          type: AgentMessageType.toolCall,
          content: '',
          toolName: params['toolName'] as String?,
          toolInputJson: jsonEncode(params['input']),
          toolInputPreview: params['inputPreview'] as String?,
          toolStatus: ToolCallStatus.running,
        ));
        break;

      case 'tool-done':
        final toolId = params['id'] as String?;
        _messageController.add(AgentMessage(
          sessionId: sessionId,
          type: AgentMessageType.toolResult,
          content: '',
          toolName: params['toolName'] as String?,
          toolResult: params['result'] as String?,
          toolStatus: ToolCallStatus.completed,
          relatedToolCallId: toolId,
        ));
        break;

      case 'tool-progress':
        // Tool execution progress update
        debugPrint('[AgentService] Tool progress: ${params['toolName']} (${params['elapsedSeconds']}s)');
        break;

      case 'session-id':
        // SDK session ID for resume functionality
        final sdkSessionId = params['sessionId'] as String?;
        debugPrint('[AgentService] SDK session ID: $sdkSessionId');
        if (sdkSessionId != null) {
          onSdkSessionId?.call(sdkSessionId);
        }
        break;

      case 'result':
        // Final result with usage stats
        debugPrint('[AgentService] Result - cost: \$${params['costUSD']}');
        break;

      case 'done':
        debugPrint('[AgentService] Agent completed');
        _messageController.add(AgentMessage(
          sessionId: sessionId,
          type: AgentMessageType.system,
          content: '[Done]',
        ));
        break;

      case 'aborted':
        debugPrint('[AgentService] Agent aborted');
        _messageController.add(AgentMessage(
          sessionId: sessionId,
          type: AgentMessageType.system,
          content: '[Aborted]',
        ));
        break;

      case 'error':
        _messageController.add(AgentMessage(
          sessionId: sessionId,
          type: AgentMessageType.error,
          content: params['message'] as String? ?? 'Unknown error',
        ));
        break;
    }
  }

  void _handleError(dynamic error) {
    debugPrint('[AgentService] Stream error: $error');
  }

  /// Send a JSON-RPC request and wait for response
  Future<Map<String, dynamic>> _sendRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (_bridgeProcess == null) {
      await _startBridge();
    }

    final id = 'req-${_requestIdCounter++}';
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final jsonStr = jsonEncode(request);
    _bridgeProcess!.stdin.writeln(jsonStr);

    return completer.future;
  }

  /// Send a JSON-RPC notification (no response expected)
  void _sendNotification(String method, [Map<String, dynamic>? params]) {
    if (_bridgeProcess == null) return;

    final notification = {
      'jsonrpc': '2.0',
      'method': method,
      if (params != null) 'params': params,
    };

    final jsonStr = jsonEncode(notification);
    _bridgeProcess!.stdin.writeln(jsonStr);
  }

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
    if (!isSupported) {
      throw UnsupportedError('Agent is not supported on this platform');
    }

    _currentSessionId = sessionId;

    // Add user message
    _messageController.add(AgentMessage(
      sessionId: sessionId,
      type: AgentMessageType.user,
      content: prompt,
    ));

    try {
      await _sendRequest('invoke', {
        'prompt': prompt,
        'cwd': workingDirectory,
        'model': agent.model,
        'apiKey': apiKey,
        if (apiHost != null) 'apiHost': apiHost,
        if (agent.instructions != null) 'systemPrompt': agent.instructions,
        'permissionMode': agent.permissionMode.name,
        'allowedTools': agent.allowedTools,
        'maxTurns': agent.maxTurns,
        if (sdkSessionId != null) 'resume': sdkSessionId,
      });
    } catch (e) {
      _messageController.add(AgentMessage(
        sessionId: sessionId,
        type: AgentMessageType.error,
        content: 'Failed to invoke agent: $e',
      ));
      rethrow;
    }
  }

  /// Abort the current agent execution
  Future<void> abort() async {
    _sendNotification('abort');
  }

  /// Respond to a permission request
  Future<void> respondToPermission({
    required String requestId,
    required bool allow,
  }) async {
    final response = {
      'jsonrpc': '2.0',
      'id': requestId,
      'result': {'behavior': allow ? 'allow' : 'deny'},
    };

    final jsonStr = jsonEncode(response);
    _bridgeProcess?.stdin.writeln(jsonStr);
  }
}
