import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/agent.dart';
import '../../core/models/provider_config.dart';
import '../../core/providers/agent_provider.dart'
    if (dart.library.html) '../../core/providers/agent_provider_stub.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/agent/agent_service.dart'
    if (dart.library.html) '../../core/services/agent/agent_service_stub.dart';
import '../widgets/tool_permission_dialog.dart';
import 'agent_sidebar.dart';
import 'agent_message_list.dart';
import 'agent_input_area.dart';
import 'agent_settings_dialog.dart';

/// Main agent page for desktop
class DesktopAgentPage extends StatefulWidget {
  const DesktopAgentPage({super.key});

  @override
  State<DesktopAgentPage> createState() => _DesktopAgentPageState();
}

class _DesktopAgentPageState extends State<DesktopAgentPage> {
  final _promptController = TextEditingController();
  final _scrollController = ScrollController();
  String _workingDirectory = '';
  bool _initialized = false;
  bool _showingPermissionDialog = false;

  @override
  void initState() {
    super.initState();
    _workingDirectory = 'C:\\mycode'; // Default working directory
    _initAgent();
  }

  Future<void> _initAgent() async {
    final provider = context.read<AgentProvider>();
    await provider.init();

    // Create default agent if none exists
    if (provider.agents.isEmpty && provider.isSupported) {
      final agentId = await provider.addAgent(name: 'Default Agent');
      await provider.setCurrentAgent(agentId);
    } else if (provider.agents.isNotEmpty && provider.currentAgent == null) {
      await provider.setCurrentAgent(provider.agents.first.id);
    }

    // Listen for permission requests
    provider.addListener(_checkPermissionRequest);

    setState(() => _initialized = true);
  }

  void _checkPermissionRequest() {
    final provider = context.read<AgentProvider>();
    final pending = provider.pendingPermission;
    if (pending != null && !_showingPermissionDialog) {
      _showingPermissionDialog = true;
      _showPermissionDialog(pending);
    }
  }

  Future<void> _showPermissionDialog(PermissionRequest request) async {
    final provider = context.read<AgentProvider>();
    final result = await showToolPermissionDialog(context, request: request);
    _showingPermissionDialog = false;

    await provider.respondToPermission(result ?? false);
  }

  Future<void> _submit(String prompt) async {
    final provider = context.read<AgentProvider>();
    final settings = context.read<SettingsProvider>();

    if (provider.currentSession == null) {
      await provider.createSession(name: _generateSessionName(prompt));
    }

    // Get API config based on agent's settings
    final agent = provider.currentAgent;

    String? apiKey;
    String? apiHost;

    // Check for custom API config first
    if (agent?.customApiKey != null && agent!.customApiKey!.isNotEmpty) {
      apiKey = agent.customApiKey;
      apiHost = agent.customBaseUrl;
    } else {
      // Use existing provider config
      final providerId = agent?.apiProvider;
      ProviderConfig? config;

      if (providerId != null && providerId.isNotEmpty) {
        config = settings.providerConfigs[providerId];
      }
      // Fallback to claude or anthropic
      config ??= settings.providerConfigs['claude'] ??
          settings.providerConfigs['anthropic'];

      apiKey = config?.apiKey;
      apiHost = config?.baseUrl;
    }

    if (apiKey == null || apiKey.isEmpty) {
      _showApiKeyError();
      return;
    }

    try {
      await provider.invoke(
        prompt: prompt,
        workingDirectory: _workingDirectory,
        apiKey: apiKey,
        apiHost: apiHost,
      );
      _scrollToBottom();
    } catch (e) {
      debugPrint('[AgentPage] Error: $e');
    }
  }

  void _showApiKeyError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please configure your Claude/Anthropic API key in Settings'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _generateSessionName(String prompt) {
    final words = prompt.split(' ').take(4).join(' ');
    return words.length > 30 ? '${words.substring(0, 30)}...' : words;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _selectDirectory() async {
    // TODO: Implement directory picker
    // For now, show a simple dialog
    final controller = TextEditingController(text: _workingDirectory);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Working Directory'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter directory path',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _workingDirectory = result);
    }
  }

  void _createNewAgent() async {
    final provider = context.read<AgentProvider>();
    final agentId = await provider.addAgent(name: 'New Agent');
    await provider.setCurrentAgent(agentId);
  }

  void _createNewSession() async {
    final provider = context.read<AgentProvider>();
    await provider.createSession(name: 'New Session');
  }

  void _openAgentSettings(Agent agent) {
    showDialog(
      context: context,
      builder: (context) => AgentSettingsDialog(agent: agent),
    );
  }

  @override
  void dispose() {
    try {
      context.read<AgentProvider>().removeListener(_checkPermissionRequest);
    } catch (_) {}
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<AgentProvider>();

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!provider.isSupported) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber, size: 48, color: cs.error),
            const SizedBox(height: 16),
            Text(
              'Agent is not supported on this platform',
              style: TextStyle(fontSize: 16, color: cs.onSurface),
            ),
          ],
        ),
      );
    }

    // Listen to messages for auto-scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (provider.isRunning) {
        _scrollToBottom();
      }
    });

    return Material(
      color: cs.surface,
      child: Row(
        children: [
          // Sidebar
          AgentSidebar(
            onNewAgent: _createNewAgent,
            onNewSession: _createNewSession,
            onAgentSettings: _openAgentSettings,
          ),

          // Main content area
          Expanded(
            child: Container(
              color: cs.surface,
              child: Column(
                children: [
                  // Header
                  _PageHeader(
                    session: provider.currentSession,
                    isRunning: provider.isRunning,
                  ),

                  // Messages
                  Expanded(
                    child: AgentMessageList(
                      messages: provider.currentMessages,
                      scrollController: _scrollController,
                    ),
                  ),

                  // Input area
                  AgentInputArea(
                    controller: _promptController,
                    onSubmit: _submit,
                    onAbort: provider.abort,
                    isRunning: provider.isRunning,
                    workingDirectory: _workingDirectory,
                    onSelectDirectory: _selectDirectory,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    this.session,
    required this.isRunning,
  });

  final dynamic session;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outline.withOpacity(0.15))),
      ),
      child: Row(
        children: [
          if (session != null) ...[
            Text(
              session.name ?? 'Session',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            if (isRunning)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Running',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
          ] else
            Text(
              'No session selected',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withOpacity(0.5),
              ),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}
