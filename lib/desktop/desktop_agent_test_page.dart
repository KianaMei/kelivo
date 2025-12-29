import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/providers/agent_provider.dart'
    if (dart.library.html) '../core/providers/agent_provider_stub.dart';
import '../core/providers/settings_provider.dart';
import '../core/models/agent_message.dart';
import 'widgets/tool_permission_dialog.dart';

/// Temporary test page for Agent communication verification
class DesktopAgentTestPage extends StatefulWidget {
  const DesktopAgentTestPage({super.key});

  @override
  State<DesktopAgentTestPage> createState() => _DesktopAgentTestPageState();
}

class _DesktopAgentTestPageState extends State<DesktopAgentTestPage> {
  final _promptController = TextEditingController();
  final _cwdController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _scrollController = ScrollController();
  String _log = '';
  bool _initialized = false;
  bool _showingPermissionDialog = false;

  @override
  void initState() {
    super.initState();
    _cwdController.text = 'C:\\mycode\\start-kelivo\\kelivo';
    _initAgent();
  }

  Future<void> _initAgent() async {
    final provider = context.read<AgentProvider>();
    final settings = context.read<SettingsProvider>();
    await provider.init();
    setState(() => _initialized = true);
    _appendLog('[Init] Agent provider initialized');
    _appendLog('[Init] isSupported: ${provider.isSupported}');

    // Try to load API key from settings (claude/anthropic provider)
    final claudeConfig = settings.providerConfigs['claude'] ??
        settings.providerConfigs['anthropic'];
    if (claudeConfig != null && claudeConfig.apiKey.isNotEmpty) {
      _apiKeyController.text = claudeConfig.apiKey;
      _appendLog('[Init] Loaded API key from claude/anthropic provider');
    }

    // Create a default test agent if none exists
    if (provider.agents.isEmpty && provider.isSupported) {
      final agentId = await provider.addAgent(name: 'Test Agent');
      _appendLog('[Init] Created test agent: $agentId');
      await provider.setCurrentAgent(agentId);
      _appendLog('[Init] Set current agent: $agentId');
    } else if (provider.agents.isNotEmpty && provider.currentAgent == null) {
      await provider.setCurrentAgent(provider.agents.first.id);
      _appendLog('[Init] Set current agent: ${provider.agents.first.id}');
    }

    // Listen for permission requests
    provider.addListener(_checkPermissionRequest);
  }

  void _checkPermissionRequest() {
    final provider = context.read<AgentProvider>();
    final pending = provider.pendingPermission;
    if (pending != null && !_showingPermissionDialog) {
      _showingPermissionDialog = true;
      _appendLog('[Permission] Request for tool: ${pending.toolName}');
      _showPermissionDialog(pending);
    }
  }

  Future<void> _showPermissionDialog(dynamic request) async {
    final provider = context.read<AgentProvider>();
    final result = await showToolPermissionDialog(context, request: request);
    _showingPermissionDialog = false;

    if (result != null) {
      _appendLog('[Permission] User response: ${result ? "allow" : "deny"}');
      await provider.respondToPermission(result);
    } else {
      // Dialog dismissed without action, treat as deny
      _appendLog('[Permission] Dialog dismissed, denying');
      await provider.respondToPermission(false);
    }
  }

  void _appendLog(String msg) {
    setState(() {
      _log += '${DateTime.now().toIso8601String().substring(11, 19)} $msg\n';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _runTest() async {
    final provider = context.read<AgentProvider>();
    if (!provider.isSupported) {
      _appendLog('[Error] Agent not supported on this platform');
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _appendLog('[Error] Prompt is empty');
      return;
    }

    final cwd = _cwdController.text.trim();
    if (cwd.isEmpty) {
      _appendLog('[Error] Working directory is empty');
      return;
    }

    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _appendLog('[Error] API key is empty');
      return;
    }

    _appendLog('[Test] Starting invoke with prompt: $prompt');
    _appendLog('[Test] Working directory: $cwd');
    _appendLog('[Test] Current agent: ${provider.currentAgent?.name ?? "none"}');

    try {
      // Ensure we have a current agent
      if (provider.currentAgent == null) {
        _appendLog('[Error] No agent selected');
        return;
      }

      // Create session if needed
      if (provider.currentSession == null) {
        final sessionId = await provider.createSession(name: 'Test Session');
        _appendLog('[Test] Created session: $sessionId');
      }

      _appendLog('[Test] Current session: ${provider.currentSession?.id ?? "none"}');

      await provider.invoke(
        prompt: prompt,
        workingDirectory: cwd,
        apiKey: apiKey,
      );
      _appendLog('[Test] Invoke completed');
    } catch (e, st) {
      _appendLog('[Error] Invoke failed: $e');
      _appendLog('[Stack] ${st.toString().split('\n').take(5).join('\n')}');
    }
  }

  Future<void> _abort() async {
    final provider = context.read<AgentProvider>();
    await provider.abort();
    _appendLog('[Test] Abort requested');
  }

  @override
  void dispose() {
    // Remove permission listener
    try {
      context.read<AgentProvider>().removeListener(_checkPermissionRequest);
    } catch (_) {}
    _promptController.dispose();
    _cwdController.dispose();
    _apiKeyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Communication Test'),
        backgroundColor: cs.surfaceContainerHighest,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // API Key input
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key (Anthropic)',
                hintText: 'sk-ant-...',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),

            // Working directory input
            TextField(
              controller: _cwdController,
              decoration: const InputDecoration(
                labelText: 'Working Directory',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Prompt input
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                hintText: 'e.g., List files in current directory',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _initialized ? _runTest : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Invoke'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _abort,
                  icon: const Icon(Icons.stop),
                  label: const Text('Abort'),
                ),
                const Spacer(),
                Text(
                  _initialized ? 'Ready' : 'Initializing...',
                  style: TextStyle(
                    color: _initialized ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Messages from provider
            Consumer<AgentProvider>(
              builder: (context, provider, _) {
                final messages = provider.currentMessages;
                if (messages.isEmpty) {
                  return const Text('No messages yet');
                }
                return Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _MessageTile(message: msg);
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Debug log
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  border: Border.all(color: cs.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    _log.isEmpty ? 'Debug log will appear here...' : _log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(0.8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});
  final AgentMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    IconData icon;
    Color color;

    switch (message.type) {
      case AgentMessageType.user:
        icon = Icons.person;
        color = cs.primary;
        break;
      case AgentMessageType.assistant:
        icon = Icons.smart_toy;
        color = cs.secondary;
        break;
      case AgentMessageType.toolCall:
        icon = Icons.build;
        color = cs.tertiary;
        break;
      case AgentMessageType.toolResult:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case AgentMessageType.error:
        icon = Icons.error;
        color = cs.error;
        break;
      case AgentMessageType.system:
        icon = Icons.info;
        color = cs.outline;
        break;
    }

    String content = message.content;
    if (message.type == AgentMessageType.toolCall) {
      content = '${message.toolName}: ${message.toolInputPreview ?? message.content}';
    } else if (message.type == AgentMessageType.toolResult) {
      content = '${message.toolName} → ${message.toolResult?.take(100) ?? 'done'}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              content.isEmpty ? '(streaming...)' : content,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (message.isStreaming)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

extension _StringExt on String {
  String take(int n) => length <= n ? this : '${substring(0, n)}...';
}
