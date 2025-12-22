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
import '../core/utils/inline_think_extractor.dart';
import '../core/utils/tool_schema_sanitizer.dart' show ProviderKind;
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

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
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
    if (mounted) setState(() {});
  }

  Future<void> _saveProvider() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyProvider, _selectedProvider);
  }

  Future<void> _saveApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyApiKey, _apiKeyController.text);
  }

  Future<void> _saveBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyBaseUrl, _baseUrlController.text);
  }

  Future<void> _saveModels() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKeyModels, _availableModels);
    if (_selectedModel != null) {
      await prefs.setString(_prefKeySelectedModel, _selectedModel!);
    }
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

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _selectedModel == null || _isGenerating) return;

    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    if (apiKey.isEmpty || baseUrl.isEmpty) return;

    setState(() {
      _messages.add(_TestMessage(role: 'user', content: text));
      _inputController.clear();
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
                // Scrollable config form
                Expanded(
                  child: SingleChildScrollView(
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
                        const SizedBox(height: 12),
                        // Model list
                        _buildModelListCompact(cs, isDark),
                        if (_availableModels.isNotEmpty && _messages.isNotEmpty) const SizedBox(height: 12),
                        // Clear chat button
                        if (_messages.isNotEmpty)
                          _buildCompactButton(
                            onPressed: _clearChat,
                            icon: lucide.Lucide.Trash2,
                            label: l10n.apiTestClearChat,
                            cs: cs,
                            isPrimary: false,
                          ),
                      ],
                    ),
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
                              return _buildMessageBubble(_messages[index], cs, isDark: isDark);
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
              itemBuilder: (context, index) {
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
              },
            ),
          ),
        ),
      ],
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

  Widget _buildMessageBubble(_TestMessage message, ColorScheme cs, {bool isDark = false, bool isStreaming = false}) {
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
            child: Container(
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
                  if (displayReasoning.trim().isNotEmpty && !isSystem) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
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
                          Text(
                            isStreaming ? l10n.chatMessageWidgetThinking : l10n.chatMessageWidgetDeepThinking,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withOpacity(0.75),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            displayReasoning.trim(),
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withOpacity(0.9),
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (displayContent.trim().isNotEmpty) const SizedBox(height: 10),
                  ],
                  if (displayContent.trim().isNotEmpty || isStreaming)
                    SelectableText(
                      (displayContent.trim().isNotEmpty ? displayContent.trimRight() : '') + (isStreaming ? ' ...' : ''),
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface,
                        height: 1.6,
                      ),
                    ),
                ],
              ),
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
}

class _TestMessage {
  final String role;
  final String content;
  final String? reasoning;

  _TestMessage({required this.role, required this.content, this.reasoning});
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
