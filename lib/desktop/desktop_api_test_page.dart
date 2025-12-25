import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../icons/lucide_adapter.dart' as lucide;
import '../core/providers/settings_provider.dart';
import '../core/models/provider_config.dart';
import '../core/models/api_test_config.dart';
import '../core/utils/inline_think_extractor.dart';
import '../core/utils/tool_schema_sanitizer.dart' show ProviderKind;
import '../shared/widgets/markdown_with_highlight.dart';
import '../shared/widgets/snackbar.dart';
import 'add_provider_dialog.dart';

/// Desktop API Test Page: Left panel for API config, Right panel for chat testing.
class DesktopApiTestPage extends StatefulWidget {
  const DesktopApiTestPage({super.key});

  @override
  State<DesktopApiTestPage> createState() => _DesktopApiTestPageState();
}

class _DesktopApiTestPageState extends State<DesktopApiTestPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  String _selectedProvider = 'openai';
  String? _selectedModel;
  List<String> _availableModels = [];
  bool _loadingModels = false;
  String? _modelError;

  final List<_TestMessage> _messages = [];
  bool _isGenerating = false;
  String _streamingContent = '';
  String _streamingReasoning = '';
  StreamSubscription? _streamSubscription;

  static const _providers = <String, _ProviderConfig>{
    'openai': _ProviderConfig(
      name: 'OpenAI',
      defaultUrl: 'https://api.openai.com/v1',
      modelsPath: '/models',
      chatPath: '/chat/completions',
    ),
    'anthropic': _ProviderConfig(
      name: 'Anthropic',
      defaultUrl: 'https://api.anthropic.com/v1',
      modelsPath: '/models',
      chatPath: '/messages',
    ),
    'google': _ProviderConfig(
      name: 'Google AI',
      defaultUrl: 'https://generativelanguage.googleapis.com/v1beta',
      modelsPath: '/models',
      chatPath: '/models/{model}:generateContent',
    ),
    'custom': _ProviderConfig(
      name: 'Custom (OpenAI-Compatible)',
      defaultUrl: '',
      modelsPath: '/models',
      chatPath: '/chat/completions',
    ),
  };

  static const _prefKeyProvider = 'api_test_provider';
  static const _prefKeyApiKey = 'api_test_api_key';
  static const _prefKeyBaseUrl = 'api_test_base_url';
  static const _prefKeyModels = 'api_test_models';
  static const _prefKeySelectedModel = 'api_test_selected_model';
  // Multi-config keys
  static const _prefKeyConfigs = 'api_test_configs';
  static const _prefKeyActiveConfigId = 'api_test_active_config_id';

  // Multi-config state
  List<ApiTestConfig> _configs = [];
  String? _activeConfigId;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();

    // Load multi-config list
    final configsJson = prefs.getStringList(_prefKeyConfigs);
    if (configsJson != null && configsJson.isNotEmpty) {
      _configs = configsJson.map((s) => ApiTestConfig.fromJsonString(s)).toList();
      _activeConfigId = prefs.getString(_prefKeyActiveConfigId);

      // Find active config and apply it
      final active = _configs.firstWhere(
        (c) => c.id == _activeConfigId,
        orElse: () => _configs.first,
      );
      _activeConfigId = active.id;
      _selectedProvider = active.provider;
      _apiKeyController.text = active.apiKey;
      _baseUrlController.text = active.baseUrl.isNotEmpty
          ? active.baseUrl
          : _providers[_selectedProvider]!.defaultUrl;
      _availableModels = active.models;
      _selectedModel = active.selectedModel;
    } else {
      // Legacy: migrate from single config
      final savedProvider = prefs.getString(_prefKeyProvider);
      final savedApiKey = prefs.getString(_prefKeyApiKey);
      final savedBaseUrl = prefs.getString(_prefKeyBaseUrl);
      final savedModels = prefs.getStringList(_prefKeyModels);
      final savedSelectedModel = prefs.getString(_prefKeySelectedModel);

      if (savedProvider != null && _providers.containsKey(savedProvider)) {
        _selectedProvider = savedProvider;
      }
      _apiKeyController.text = savedApiKey ?? '';
      _baseUrlController.text = savedBaseUrl ?? _providers[_selectedProvider]!.defaultUrl;
      if (savedModels != null && savedModels.isNotEmpty) {
        _availableModels = savedModels;
        if (savedSelectedModel != null && savedModels.contains(savedSelectedModel)) {
          _selectedModel = savedSelectedModel;
        }
      }

      // Create initial config if we have data
      if (savedApiKey?.isNotEmpty == true || savedBaseUrl?.isNotEmpty == true) {
        final initial = ApiTestConfig.create(
          provider: _selectedProvider,
          apiKey: _apiKeyController.text,
          baseUrl: _baseUrlController.text,
          models: _availableModels,
          selectedModel: _selectedModel,
        );
        _configs = [initial];
        _activeConfigId = initial.id;
        await _saveConfigs();
      }
    }
    if (mounted) setState(() {});
  }

  /// Save all configs to SharedPreferences
  Future<void> _saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefKeyConfigs,
      _configs.map((c) => c.toJsonString()).toList(),
    );
    if (_activeConfigId != null) {
      await prefs.setString(_prefKeyActiveConfigId, _activeConfigId!);
    }
  }

  /// Update current active config with current UI state
  void _updateActiveConfig() {
    if (_activeConfigId == null) return;
    final idx = _configs.indexWhere((c) => c.id == _activeConfigId);
    if (idx >= 0) {
      _configs[idx] = _configs[idx].copyWith(
        provider: _selectedProvider,
        apiKey: _apiKeyController.text,
        baseUrl: _baseUrlController.text,
        models: _availableModels,
        selectedModel: _selectedModel,
      );
      _saveConfigs();
    }
  }

  /// Switch to a different config
  void _switchConfig(String configId) {
    final config = _configs.firstWhere((c) => c.id == configId, orElse: () => _configs.first);
    setState(() {
      _activeConfigId = config.id;
      _selectedProvider = config.provider;
      _apiKeyController.text = config.apiKey;
      _baseUrlController.text = config.baseUrl.isNotEmpty
          ? config.baseUrl
          : _providers[_selectedProvider]!.defaultUrl;
      _availableModels = config.models;
      _selectedModel = config.selectedModel;
      _modelError = null;
    });
    _saveConfigs();
  }

  /// Add a new config
  void _addNewConfig() {
    final newConfig = ApiTestConfig.create(
      provider: 'openai',
      baseUrl: _providers['openai']!.defaultUrl,
    );
    setState(() {
      _configs.add(newConfig);
      _activeConfigId = newConfig.id;
      _selectedProvider = newConfig.provider;
      _apiKeyController.text = '';
      _baseUrlController.text = newConfig.baseUrl;
      _availableModels = [];
      _selectedModel = null;
      _modelError = null;
    });
    _saveConfigs();
  }

  /// Delete a config
  void _deleteConfig(String configId) {
    if (_configs.length <= 1) return; // Keep at least one config
    setState(() {
      _configs.removeWhere((c) => c.id == configId);
      if (_activeConfigId == configId) {
        _switchConfig(_configs.first.id);
      }
    });
    _saveConfigs();
  }

  /// Rename current config
  Future<void> _renameConfig() async {
    if (_activeConfigId == null) return;
    final idx = _configs.indexWhere((c) => c.id == _activeConfigId);
    if (idx < 0) return;

    final current = _configs[idx];
    final controller = TextEditingController(text: current.name);
    final l10n = AppLocalizations.of(context)!;

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.apiTestRenameConfigTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: current.displayName),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.sideDrawerCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.sideDrawerOK),
          ),
        ],
      ),
    );

    if (newName != null) {
      setState(() {
        _configs[idx] = current.copyWith(name: newName);
      });
      _saveConfigs();
    }
  }

  Future<void> _saveProvider() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyProvider, _selectedProvider);
    _updateActiveConfig();
  }

  Future<void> _saveApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyApiKey, _apiKeyController.text);
    _updateActiveConfig();
  }

  Future<void> _saveBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyBaseUrl, _baseUrlController.text);
    _updateActiveConfig();
  }

  Future<void> _saveModels() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKeyModels, _availableModels);
    if (_selectedModel != null) {
      await prefs.setString(_prefKeySelectedModel, _selectedModel!);
    }
    _updateActiveConfig();
  }

  ProviderKind _getProviderKind() {
    switch (_selectedProvider) {
      case 'openai':
      case 'custom':
        return ProviderKind.openai;
      case 'anthropic':
        return ProviderKind.claude;
      case 'google':
        return ProviderKind.google;
      default:
        return ProviderKind.openai;
    }
  }

  Future<void> _convertToProvider() async {
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final providerKind = _getProviderKind();
    
    // Show dialog with prefilled values
    final createdKey = await showDesktopAddProviderDialogWithPrefill(
      context,
      providerKind: providerKind,
      apiKey: apiKey,
      baseUrl: baseUrl,
    );
    
    if (createdKey != null && createdKey.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Provider "$createdKey" created')),
      );
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _inputController.dispose();
    _chatScrollController.dispose();
    _inputFocus.dispose();
    _streamSubscription?.cancel();
    super.dispose();
  }

  void _onProviderChanged(String? value) {
    if (value == null) return;
    setState(() {
      _selectedProvider = value;
      _modelError = null;
    });
    _saveProvider();
  }

  void _onApiKeyChanged() {
    _saveApiKey();
  }

  void _onBaseUrlChanged() {
    _saveBaseUrl();
  }

  Future<void> _fetchModels() async {
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    if (apiKey.isEmpty || baseUrl.isEmpty) {
      setState(() => _modelError = 'Please enter API Key and Base URL');
      return;
    }

    setState(() {
      _loadingModels = true;
      _modelError = null;
      _availableModels = [];
      _selectedModel = null;
    });

    try {
      final config = _providers[_selectedProvider]!;
      final uri = Uri.parse('$baseUrl${config.modelsPath}');
      
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      
      if (_selectedProvider == 'anthropic') {
        headers['Authorization'] = 'Bearer $apiKey';  // 代理服务需要的认证
        headers['x-api-key'] = apiKey;
        headers['anthropic-version'] = '2023-06-01';
        headers['anthropic-dangerous-direct-browser-access'] = 'true';  // 浏览器访问许可
      } else if (_selectedProvider == 'google') {
        // Google uses query param for API key
      } else {
        headers['Authorization'] = 'Bearer $apiKey';
      }

      final requestUri = _selectedProvider == 'google'
          ? uri.replace(queryParameters: {'key': apiKey})
          : uri;

      final response = await http.get(requestUri, headers: headers).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<String> models = [];
        
        if (_selectedProvider == 'google') {
          final list = data['models'] as List? ?? [];
          models = list
              .map((m) => (m['name'] as String? ?? '').replaceFirst('models/', ''))
              .where((m) => m.isNotEmpty)
              .toList();
        } else {
          final list = data['data'] as List? ?? [];
          models = list.map((m) => m['id'] as String? ?? '').where((m) => m.isNotEmpty).toList();
        }
        
        models.sort();
        setState(() {
          _availableModels = models;
          _selectedModel = models.isNotEmpty ? models.first : null;
        });
        _saveModels();
      } else {
        setState(() => _modelError = 'Error ${response.statusCode}: ${response.body.take(200)}');
      }
    } catch (e) {
      // 检测 Cloudflare/TLS 握手错误并提供友好提示
      final errStr = e.toString();
      String friendlyError;
      if (errStr.contains('HandshakeException') ||
          errStr.contains('Connection terminated during handshake') ||
          errStr.contains('CERTIFICATE_VERIFY_FAILED')) {
        friendlyError = '连接被拒绝 (可能是 Cloudflare 防护)\n建议在浏览器中访问该站点完成验证';
      } else if (errStr.contains('SocketException') || errStr.contains('Connection refused')) {
        friendlyError = '无法连接到服务器，请检查网络连接';
      } else {
        friendlyError = errStr.take(200);
      }
      setState(() => _modelError = friendlyError);
    } finally {
      setState(() => _loadingModels = false);
    }
  }

  Future<void> _sendMessage([String? inputText, bool addToMessages = true]) async {
    final text = inputText ?? _inputController.text.trim();
    if (text.isEmpty || _selectedModel == null || _isGenerating) return;

    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    if (apiKey.isEmpty || baseUrl.isEmpty) return;

    setState(() {
      if (addToMessages) {
        _messages.add(_TestMessage(role: 'user', content: text));
        _inputController.clear();
      }
      _isGenerating = true;
      _streamingContent = '';
      _streamingReasoning = '';
    });
    _scrollToBottom();

    try {
      final config = _providers[_selectedProvider]!;
      String chatPath = config.chatPath;
      if (_selectedProvider == 'google') {
        chatPath = chatPath.replaceAll('{model}', _selectedModel!);
      }
      final uri = Uri.parse('$baseUrl$chatPath');

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      Map<String, dynamic> body;

      if (_selectedProvider == 'anthropic') {
        headers['Authorization'] = 'Bearer $apiKey';  // 代理服务需要的认证
        headers['x-api-key'] = apiKey;
        headers['anthropic-version'] = '2023-06-01';
        headers['anthropic-dangerous-direct-browser-access'] = 'true';  // 浏览器访问许可
        body = {
          'model': _selectedModel,
          'max_tokens': 4096,
          'stream': true,
          'messages': _messages
              .where((m) => m.role == 'user' || m.role == 'assistant')
              .map((m) => {
                    'role': m.role,
                    'content': [
                      {'type': 'text', 'text': m.content}
                    ]
                  })
              .toList(),
        };
      } else if (_selectedProvider == 'google') {
        body = {
          'contents': _messages
              .where((m) => m.role == 'user' || m.role == 'assistant')
              .map((m) => {
                    'role': m.role == 'user' ? 'user' : 'model',
                    'parts': [
                      {'text': m.content}
                    ],
                  })
              .toList(),
        };
      } else {
        headers['Authorization'] = 'Bearer $apiKey';
        body = {
          'model': _selectedModel,
          'stream': true,
          'messages': _messages
              .where((m) => m.role == 'user' || m.role == 'assistant')
              .map((m) => {'role': m.role, 'content': m.content})
              .toList(),
        };
      }

      final requestUri = _selectedProvider == 'google'
          ? uri.replace(queryParameters: {'key': apiKey, 'alt': 'sse'})
          : uri;

      final request = http.Request('POST', requestUri);
      request.headers.addAll(headers);
      request.body = jsonEncode(body);

      final streamedResponse = await http.Client().send(request);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception('Error ${streamedResponse.statusCode}: ${errorBody.take(300)}');
      }

      final stream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      _streamSubscription = stream.listen(
        (line) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') return;
            
            try {
              final json = jsonDecode(data);
              String textDelta = '';
              String reasoningDelta = '';
              
              if (_selectedProvider == 'anthropic') {
                if (json['type'] == 'content_block_delta') {
                  final delta = json['delta'];
                  final deltaType = delta?['type'];
                  if (deltaType == 'text_delta') {
                    textDelta = (delta?['text'] ?? '').toString();
                  } else if (deltaType == 'thinking_delta') {
                    reasoningDelta = (delta?['thinking'] ?? delta?['text'] ?? '').toString();
                  }
                }
              } else if (_selectedProvider == 'google') {
                final candidates = json['candidates'];
                if (candidates is List) {
                  for (final cand in candidates) {
                    if (cand is! Map) continue;
                    final content = cand['content'];
                    if (content is! Map) continue;
                    final parts = content['parts'];
                    if (parts is! List) continue;
                    for (final p in parts) {
                      if (p is! Map) continue;
                      final t = (p['text'] ?? '').toString();
                      final thought = p['thought'] == true;
                      if (t.isEmpty) continue;
                      if (thought) {
                        reasoningDelta += t;
                      } else {
                        textDelta += t;
                      }
                    }
                  }
                }
              } else {
                final delta = json['choices']?[0]?['delta'];
                final c = delta?['content'];
                if (c is String) textDelta = c;
                final rc = delta?['reasoning_content'] ?? delta?['reasoning'];
                if (rc is String) reasoningDelta = rc;
              }
              
              if (textDelta.isNotEmpty || reasoningDelta.isNotEmpty) {
                setState(() {
                  if (textDelta.isNotEmpty) _streamingContent += textDelta;
                  if (reasoningDelta.isNotEmpty) _streamingReasoning += reasoningDelta;
                });
                _scrollToBottom();
              }
            } catch (_) {}
          }
        },
        onDone: _finalizeStreamingAssistantMessage,
        onError: (e) {
          setState(() {
            _messages.add(_TestMessage(role: 'system', content: 'Error: $e'));
            _isGenerating = false;
            _streamingContent = '';
            _streamingReasoning = '';
          });
        },
      );
    } catch (e) {
      setState(() {
        _messages.add(_TestMessage(role: 'system', content: 'Error: $e'));
        _isGenerating = false;
        _streamingContent = '';
        _streamingReasoning = '';
      });
    }
  }

  void _finalizeStreamingAssistantMessage() {
    if (!_isGenerating) return;

    final hasAny = _streamingContent.isNotEmpty || _streamingReasoning.isNotEmpty;
    if (!hasAny) {
      setState(() {
        _isGenerating = false;
        _streamingContent = '';
        _streamingReasoning = '';
      });
      return;
    }

    var content = _streamingContent;
    var reasoning = _streamingReasoning;
    if (reasoning.trim().isEmpty) {
      final extracted = extractInlineThink(content);
      content = extracted.content;
      reasoning = extracted.reasoning;
    }

    setState(() {
      _messages.add(
        _TestMessage(
          role: 'assistant',
          content: content.trim(),
          reasoning: reasoning.trim().isEmpty ? null : reasoning.trim(),
        ),
      );
      _isGenerating = false;
      _streamingContent = '';
      _streamingReasoning = '';
    });
    _scrollToBottom();
  }

  void _stopGeneration() {
    _streamSubscription?.cancel();
    _finalizeStreamingAssistantMessage();
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _streamingContent = '';
      _streamingReasoning = '';
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          // Left panel: API configuration (glass morphism)
          Container(
            width: 280,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isDark ? Colors.white.withOpacity(0.06) : cs.outlineVariant.withOpacity(0.25),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title header at top
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white.withOpacity(0.06) : cs.outlineVariant.withOpacity(0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(lucide.Lucide.FlaskConical, size: 16, color: cs.primary),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.apiTestPageTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                // Config selector row
                _buildConfigSelector(cs, isDark, l10n),
                // Top config form (non-scrollable)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Provider selector (list)
                      _buildCompactLabel(l10n.apiTestProviderLabel, cs),
                      const SizedBox(height: 6),
                      _buildProviderList(cs, isDark),
                      const SizedBox(height: 12),
                      // API Key
                      _buildCompactLabel(l10n.apiTestApiKeyLabel, cs),
                      const SizedBox(height: 6),
                      _buildCompactTextField(
                        controller: _apiKeyController,
                        hintText: l10n.apiTestApiKeyHint,
                        obscureText: false,
                        cs: cs,
                        isDark: isDark,
                        onChanged: (_) => _onApiKeyChanged(),
                      ),
                      const SizedBox(height: 12),
                      // Base URL
                      _buildCompactLabel(l10n.apiTestBaseUrlLabel, cs),
                      const SizedBox(height: 6),
                      _buildCompactTextField(
                        controller: _baseUrlController,
                        hintText: l10n.apiTestBaseUrlHint,
                        cs: cs,
                        isDark: isDark,
                        onChanged: (_) => _onBaseUrlChanged(),
                      ),
                      const SizedBox(height: 14),
                      // Fetch models + Convert to provider buttons
                      Row(
                        children: [
                          Expanded(
                            child: _buildCompactButton(
                              onPressed: _loadingModels ? null : _fetchModels,
                              icon: _loadingModels ? null : lucide.Lucide.RefreshCw,
                              label: l10n.apiTestFetchModels,
                              isLoading: _loadingModels,
                              cs: cs,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: '转为供应商',
                            child: Material(
                              color: cs.primaryContainer.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: _convertToProvider,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  child: Icon(lucide.Lucide.FolderPlus, size: 16, color: cs.primary),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_modelError != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cs.errorContainer.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(_modelError!, style: TextStyle(fontSize: 11, color: cs.error)),
                        ),
                      ],
                    ],
                  ),
                ),
                // Model list - fills remaining space
                if (_availableModels.isNotEmpty)
                  Expanded(child: _buildModelListExpanded(cs, isDark)),
                // Clear chat button at bottom
                if (_messages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _buildCompactButton(
                      onPressed: _clearChat,
                      icon: lucide.Lucide.Trash2,
                      label: l10n.apiTestClearChat,
                      cs: cs,
                      isPrimary: false,
                    ),
                  ),
              ],
            ),
          ),
          // Right panel: Chat interface (glass morphism)
          Expanded(
            child: Column(
              children: [
                // Chat messages
                Expanded(
                  child: _messages.isEmpty && _streamingContent.isEmpty && _streamingReasoning.isEmpty
                      ? _buildEmptyState(l10n, cs)
                      : ListView.builder(
                          controller: _chatScrollController,
                          padding: const EdgeInsets.all(20),
                          itemCount: _messages.length + ((_streamingContent.isNotEmpty || _streamingReasoning.isNotEmpty) ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index < _messages.length) {
                              return _buildMessageBubble(_messages[index], cs, isDark: isDark, messageIndex: index);
                            } else {
                              return _buildMessageBubble(
                                _TestMessage(role: 'assistant', content: _streamingContent, reasoning: _streamingReasoning),
                                cs,
                                isDark: isDark,
                                isStreaming: true,
                              );
                            }
                          },
                        ),
                ),
                // Input bar
                _buildInputBar(l10n, cs, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassPanel({
    required ColorScheme cs,
    required bool isDark,
    double? width,
    required Widget child,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: isDark
                ? cs.surface.withOpacity(0.6)
                : cs.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : cs.outlineVariant.withOpacity(0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildCompactLabel(String text, ColorScheme cs) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: cs.onSurface.withOpacity(0.6),
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildProviderList(ColorScheme cs, bool isDark) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _providers.entries.map((e) {
        final isSelected = e.key == _selectedProvider;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _onProviderChanged(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? cs.primary.withOpacity(isDark ? 0.25 : 0.15)
                    : isDark
                        ? Colors.white.withOpacity(0.05)
                        : cs.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? cs.primary.withOpacity(0.5)
                      : isDark
                          ? Colors.white.withOpacity(0.06)
                          : cs.outlineVariant.withOpacity(0.3),
                ),
              ),
              child: Text(
                e.value.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.onSurface.withOpacity(0.8),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCompactTextField({
    required TextEditingController controller,
    required String hintText,
    required ColorScheme cs,
    required bool isDark,
    bool obscureText = false,
    Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onChanged: onChanged,
      style: TextStyle(fontSize: 12, color: cs.onSurface),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.4), fontSize: 12),
        filled: true,
        fillColor: isDark
            ? Colors.white.withOpacity(0.05)
            : cs.surfaceVariant.withOpacity(0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.06) : cs.outlineVariant.withOpacity(0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.primary, width: 1),
        ),
      ),
    );
  }

  Widget _buildCompactButton({
    required VoidCallback? onPressed,
    IconData? icon,
    required String label,
    required ColorScheme cs,
    bool isLoading = false,
    bool isPrimary = true,
  }) {
    return SizedBox(
      height: 34,
      child: isPrimary
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading)
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                  else if (icon != null)
                    Icon(icon, size: 14),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface.withOpacity(0.7),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) Icon(icon, size: 14),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
    );
  }

  Widget _buildModelListCompact(ColorScheme cs, bool isDark) {
    if (_availableModels.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCompactLabel(AppLocalizations.of(context)!.apiTestModelLabel, cs),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 180),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.03)
                : cs.surfaceVariant.withOpacity(0.25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.05) : cs.outlineVariant.withOpacity(0.2),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _availableModels.length,
              itemBuilder: (context, index) => _buildModelItem(index, cs, isDark),
            ),
          ),
        ),
      ],
    );
  }

  /// Expanded model list that fills remaining vertical space
  Widget _buildModelListExpanded(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCompactLabel(AppLocalizations.of(context)!.apiTestModelLabel, cs),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.03)
                    : cs.surfaceVariant.withOpacity(0.25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.05) : cs.outlineVariant.withOpacity(0.2),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _availableModels.length,
                  itemBuilder: (context, index) => _buildModelItem(index, cs, isDark),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelItem(int index, ColorScheme cs, bool isDark) {
    final model = _availableModels[index];
    final isSelected = model == _selectedModel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _selectedModel = model);
          _saveModels();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primary.withOpacity(isDark ? 0.2 : 0.1)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? cs.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  model,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? cs.primary : cs.onSurface.withOpacity(0.8),
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSelected)
                Icon(lucide.Lucide.Check, size: 12, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(lucide.Lucide.MessageSquare, size: 40, color: cs.primary.withOpacity(0.5)),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.apiTestEmptyHint,
            style: TextStyle(
              color: cs.onSurface.withOpacity(0.5),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(AppLocalizations l10n, ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.08) : cs.outlineVariant.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : cs.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.08) : cs.outlineVariant.withOpacity(0.3),
                ),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                maxLines: null,
                textInputAction: TextInputAction.send,
                style: TextStyle(fontSize: 14, color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: l10n.apiTestInputHint,
                  hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.4)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildSendButton(l10n, cs),
        ],
      ),
    );
  }

  Widget _buildSendButton(AppLocalizations l10n, ColorScheme cs) {
    final canSend = _selectedModel != null && !_isGenerating;
    return Material(
      color: _isGenerating
          ? cs.errorContainer
          : canSend
              ? cs.primary
              : cs.surfaceVariant,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _isGenerating
            ? _stopGeneration
            : canSend
                ? _sendMessage
                : null,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(
            _isGenerating ? lucide.Lucide.Square : lucide.Lucide.Send,
            size: 20,
            color: _isGenerating
                ? cs.onErrorContainer
                : canSend
                    ? cs.onPrimary
                    : cs.onSurface.withOpacity(0.3),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(_TestMessage message, ColorScheme cs, {bool isDark = false, bool isStreaming = false, int? messageIndex}) {
    final isUser = message.role == 'user';
    final isSystem = message.role == 'system';
    final l10n = AppLocalizations.of(context)!;

    final rawContent = message.content;
    final explicitReasoning = (message.reasoning ?? '').trim();
    final extracted = (explicitReasoning.isEmpty && !isUser && !isSystem)
        ? extractInlineThink(rawContent)
        : (content: rawContent, reasoning: '');
    final displayReasoning = explicitReasoning.isNotEmpty ? explicitReasoning : extracted.reasoning;
    final displayContent = explicitReasoning.isNotEmpty ? rawContent : extracted.content;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: isSystem
                    ? LinearGradient(
                        colors: [cs.error.withOpacity(0.2), cs.errorContainer],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [cs.primary.withOpacity(0.3), cs.primaryContainer],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: (isSystem ? cs.error : cs.primary).withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                isSystem ? lucide.Lucide.AlertCircle : lucide.Lucide.Bot,
                size: 18,
                color: isSystem ? cs.error : cs.primary,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? cs.primary.withOpacity(isDark ? 0.25 : 0.12)
                        : isSystem
                            ? cs.errorContainer.withOpacity(isDark ? 0.4 : 0.25)
                            : isDark
                                ? Colors.white.withOpacity(0.08)
                                : cs.surfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isUser ? 18 : 4),
                      topRight: Radius.circular(isUser ? 4 : 18),
                      bottomLeft: const Radius.circular(18),
                      bottomRight: const Radius.circular(18),
                    ),
                    border: Border.all(
                      color: isUser
                          ? cs.primary.withOpacity(0.2)
                          : isSystem
                              ? cs.error.withOpacity(0.2)
                              : isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : cs.outlineVariant.withOpacity(0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.15 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Reasoning section (collapsible)
                      if (displayReasoning.trim().isNotEmpty && !isSystem)
                        _buildReasoningSection(displayReasoning, cs, isDark, l10n, isStreaming, message),
                      if (displayReasoning.trim().isNotEmpty && displayContent.trim().isNotEmpty && !isSystem)
                        const SizedBox(height: 10),
                      // Content with Markdown rendering
                      if (displayContent.trim().isNotEmpty || isStreaming)
                        isUser
                            ? SelectableText(
                                displayContent.trimRight(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurface,
                                  height: 1.6,
                                ),
                              )
                            : MarkdownWithCodeHighlight(
                                text: displayContent.trimRight() + (isStreaming ? ' ▍' : ''),
                                isStreaming: isStreaming,
                              ),
                    ],
                  ),
                ),
                // Action buttons for assistant messages
                if (!isUser && !isSystem && !isStreaming && displayContent.trim().isNotEmpty)
                  _buildMessageActions(message, cs, isDark, l10n, messageIndex),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary.withOpacity(0.3), cs.primary.withOpacity(0.15)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(lucide.Lucide.User, size: 18, color: cs.primary),
            ),
          ],
        ],
      ),
    );
  }

  /// Build collapsible reasoning section
  Widget _buildReasoningSection(String reasoning, ColorScheme cs, bool isDark, AppLocalizations l10n, bool isStreaming, _TestMessage message) {
    final isExpanded = message.reasoningExpanded;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : cs.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : cs.outlineVariant.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            onTap: () {
              setState(() {
                message.reasoningExpanded = !message.reasoningExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    lucide.Lucide.Brain,
                    size: 14,
                    color: cs.primary.withOpacity(0.8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isStreaming ? l10n.chatMessageWidgetThinking : l10n.chatMessageWidgetDeepThinking,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(0.75),
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded ? lucide.Lucide.ChevronUp : lucide.Lucide.ChevronDown,
                    size: 16,
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
          // Collapsible content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: MarkdownWithCodeHighlight(
                text: reasoning.trim(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build action buttons for assistant messages
  Widget _buildMessageActions(_TestMessage message, ColorScheme cs, bool isDark, AppLocalizations l10n, int? messageIndex) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Copy button
          _buildActionButton(
            icon: lucide.Lucide.Copy,
            tooltip: l10n.codeCardCopy,
            onTap: () {
              Clipboard.setData(ClipboardData(text: message.content));
              showAppSnackBar(context, message: l10n.chatMessageWidgetCopiedToClipboard, type: NotificationType.success);
            },
            cs: cs,
            isDark: isDark,
          ),
          const SizedBox(width: 4),
          // Regenerate button (only show if this is the last assistant message)
          if (messageIndex != null && messageIndex == _messages.length - 1 && !_isGenerating)
            _buildActionButton(
              icon: lucide.Lucide.RefreshCw,
              tooltip: l10n.chatMessageWidgetRegenerateTooltip,
              onTap: () => _regenerateLastMessage(),
              cs: cs,
              isDark: isDark,
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required ColorScheme cs,
    required bool isDark,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : cs.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 14,
              color: cs.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      ),
    );
  }

  /// Regenerate the last assistant message
  Future<void> _regenerateLastMessage() async {
    if (_messages.isEmpty) return;

    // Find the last user message
    String? lastUserMessage;
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == 'user') {
        lastUserMessage = _messages[i].content;
        break;
      }
    }

    if (lastUserMessage == null) return;

    // Remove the last assistant message
    setState(() {
      if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
        _messages.removeLast();
      }
    });

    // Regenerate
    _sendMessage(lastUserMessage, false);
  }

  /// Build config selector horizontal scroll list
  Widget _buildConfigSelector(ColorScheme cs, bool isDark, AppLocalizations l10n) {
    if (_configs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.06) : cs.outlineVariant.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Scrollable config list (supports mouse drag on desktop)
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: _configs.length,
                itemBuilder: (context, index) {
                final config = _configs[index];
                final isActive = config.id == _activeConfigId;

                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => _switchConfig(config.id),
                    onDoubleTap: () {
                      _switchConfig(config.id);
                      _renameConfig();
                    },
                    onLongPressStart: (details) => _showConfigMenu(config, cs, l10n, details.globalPosition),
                    onSecondaryTapDown: (details) => _showConfigMenu(config, cs, l10n, details.globalPosition),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive
                            ? cs.primary.withOpacity(isDark ? 0.25 : 0.15)
                            : isDark
                                ? Colors.white.withOpacity(0.05)
                                : cs.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive
                              ? cs.primary.withOpacity(0.4)
                              : isDark
                                  ? Colors.white.withOpacity(0.08)
                                  : cs.outlineVariant.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isActive ? lucide.Lucide.CloudCheck : lucide.Lucide.Cloud,
                            size: 14,
                            color: isActive ? cs.primary : cs.onSurface.withOpacity(0.5),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            config.displayName.length > 12
                                ? '${config.displayName.substring(0, 12)}...'
                                : config.displayName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              color: isActive ? cs.primary : cs.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            ),
          ),
          // Fixed add button on right
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _addNewConfig,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.1) : cs.outlineVariant.withOpacity(0.3),
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    lucide.Lucide.Plus,
                    size: 16,
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show context menu for config with modern glass morphism style
  void _showConfigMenu(ApiTestConfig config, ColorScheme cs, AppLocalizations l10n, Offset position) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;

    // Calculate menu position, ensuring it stays within screen bounds
    const menuWidth = 160.0;
    const menuHeight = 100.0; // approximate height

    double left = position.dx;
    double top = position.dy;

    // Adjust if menu would overflow right edge
    if (left + menuWidth > screenSize.width - 16) {
      left = screenSize.width - menuWidth - 16;
    }

    // Adjust if menu would overflow bottom edge
    if (top + menuHeight > screenSize.height - 16) {
      top = position.dy - menuHeight;
    }

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return Stack(
          children: [
            // Tap outside to dismiss
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(color: Colors.transparent),
              ),
            ),
            // Menu positioned at click location
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 160,
                      decoration: BoxDecoration(
                        color: isDark
                            ? cs.surface.withOpacity(0.85)
                            : cs.surface.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : cs.outlineVariant.withOpacity(0.3),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Rename option
                          _buildMenuOption(
                            icon: lucide.Lucide.Pencil,
                            label: l10n.apiTestRenameConfig,
                            color: cs.onSurface,
                            isDark: isDark,
                            cs: cs,
                            onTap: () {
                              Navigator.pop(ctx);
                              _switchConfig(config.id);
                              _renameConfig();
                            },
                          ),
                          // Divider
                          if (_configs.length > 1)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Divider(
                                height: 1,
                                color: isDark
                                    ? Colors.white.withOpacity(0.08)
                                    : cs.outlineVariant.withOpacity(0.3),
                              ),
                            ),
                          // Delete option
                          if (_configs.length > 1)
                            _buildMenuOption(
                              icon: lucide.Lucide.Trash2,
                              label: l10n.apiTestDeleteConfig,
                              color: cs.error,
                              isDark: isDark,
                              cs: cs,
                              onTap: () {
                                Navigator.pop(ctx);
                                _deleteConfig(config.id);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuOption({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required ColorScheme cs,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: isDark
            ? Colors.white.withOpacity(0.08)
            : cs.primary.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestMessage {
  final String role;
  final String content;
  final String? reasoning;
  bool reasoningExpanded;

  _TestMessage({required this.role, required this.content, this.reasoning, this.reasoningExpanded = false});
}

class _ProviderConfig {
  final String name;
  final String defaultUrl;
  final String modelsPath;
  final String chatPath;

  const _ProviderConfig({
    required this.name,
    required this.defaultUrl,
    required this.modelsPath,
    required this.chatPath,
  });
}

extension _StringTake on String {
  String take(int n) => length <= n ? this : '${substring(0, n)}...';
}
