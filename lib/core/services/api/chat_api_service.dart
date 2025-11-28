import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../../providers/settings_provider.dart';
import '../../providers/model_provider.dart';
import '../../models/token_usage.dart';
import '../../models/tool_call_mode.dart';
import '../../../utils/sandbox_path_resolver.dart';
import 'google_service_account_auth.dart';
import '../../services/api_key_manager.dart';
import '../prompt_tool_use/prompt_tool_use_service.dart';
import '../prompt_tool_use/xml_tag_extractor.dart';
import 'package:kelivo/secrets/fallback.dart';
// Adapters
import 'adapters/openai/openai_adapter.dart';
import 'adapters/claude_adapter.dart';
import 'adapters/google_adapter.dart';
import 'adapters/prompt_tool_adapter.dart';
import 'helpers/chat_api_helper.dart';
import 'models/chat_stream_chunk.dart';

class ChatApiService {
  /// Resolve the upstream/vendor model id for a given logical model key.
  /// When per-instance overrides specify `apiModelId`, that value is used for
  /// outbound HTTP requests and vendor-specific heuristics. Otherwise the
  /// logical `modelId` key is treated as the upstream id (backwards compatible).
  static String _apiModelId(ProviderConfig cfg, String modelId) {
    try {
      final ov = cfg.modelOverrides[modelId];
      if (ov is Map<String, dynamic>) {
        final raw = (ov['apiModelId'] ?? ov['api_model_id'])?.toString().trim();
        if (raw != null && raw.isNotEmpty) return raw;
      }
    } catch (_) {}
    return modelId;
  }

  // 生成东八区时间戳: 年-月-日 时:分:秒
  static String _timestamp() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  static String _apiKeyForRequest(ProviderConfig cfg, String modelId) {
    final orig = _effectiveApiKey(cfg).trim();
    if (orig.isNotEmpty) return orig;
    if ((cfg.id) == 'SiliconFlow') {
      final host = Uri.tryParse(cfg.baseUrl)?.host.toLowerCase() ?? '';
      if (!host.contains('siliconflow')) return orig;
      final m = _apiModelId(cfg, modelId).toLowerCase();
      final allowed = m == 'thudm/glm-4-9b-0414' || m == 'qwen/qwen3-8b';
      final fallback = siliconflowFallbackKey.trim();
      if (allowed && fallback.isNotEmpty) {
        return fallback;
      }
    }
    return orig;
  }
  static String _effectiveApiKey(ProviderConfig cfg) {
    try {
      if (cfg.multiKeyEnabled == true && (cfg.apiKeys?.isNotEmpty == true)) {
        final sel = ApiKeyManager().selectForProvider(cfg);
        if (sel.key != null) return sel.key!.key;
      }
    } catch (_) {}
    return cfg.apiKey;
  }
  // Read built-in tools configured per model (e.g., ['search', 'url_context']).
  // Stored under ProviderConfig.modelOverrides[modelId].builtInTools.
  static Set<String> _builtInTools(ProviderConfig cfg, String modelId) {
    try {
      final ov = cfg.modelOverrides[modelId];
      if (ov is Map<String, dynamic>) {
        final raw = ov['builtInTools'];
        if (raw is List) {
          return raw.map((e) => e.toString().trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
        }
      }
    } catch (_) {}
    return const <String>{};
  }

  // Detect if a model is a Grok model (xAI) with robust checking
  // Checks both the logical modelId and the upstream apiModelId
  static bool _isGrokModel(ProviderConfig cfg, String modelId) {
    final apiModel = _apiModelId(cfg, modelId).toLowerCase();
    final logicalModel = modelId.toLowerCase();

    // Check common Grok model name patterns
    final grokPatterns = ['grok', 'xai-'];
    for (final pattern in grokPatterns) {
      if (apiModel.contains(pattern) || logicalModel.contains(pattern)) {
        return true;
      }
    }

    return false;
  }

  // Extract and format Grok search citations from API response
  // Returns a list of ToolResultInfo for UI rendering
  static List<ToolResultInfo> _extractGrokCitations(Map<String, dynamic> response) {
    try {
      final citations = response['citations'];
      if (citations is! List || citations.isEmpty) return [];

      final items = <Map<String, dynamic>>[];
      for (int i = 0; i < citations.length; i++) {
        final citation = citations[i];

        // Handle both string URLs and structured citation objects
        if (citation is String) {
          items.add({
            'index': i + 1,
            'url': citation,
            'title': _extractDomainFromUrl(citation),
          });
        } else if (citation is Map) {
          final url = (citation['url'] ?? citation['link'] ?? '').toString();
          if (url.isEmpty) continue;

          items.add({
            'index': i + 1,
            'url': url,
            'title': citation['title']?.toString() ?? _extractDomainFromUrl(url),
            if (citation['snippet'] != null) 'snippet': citation['snippet'].toString(),
          });
        }
      }

      if (items.isEmpty) return [];

      return [
        ToolResultInfo(
          id: 'builtin_search',
          name: 'search_web',
          arguments: const {},
          content: jsonEncode({'items': items}),
        )
      ];
    } catch (e) {
      // Silently fail if citation parsing fails
      return [];
    }
  }

  // Extract domain name from URL for better citation titles
  static String _extractDomainFromUrl(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) {
        // Remove 'www.' prefix if present
        return uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
      }
    } catch (_) {}
    return url;
  }
  // Helpers to read per-model overrides (headers/body) from ProviderConfig
  static Map<String, dynamic> _modelOverride(ProviderConfig cfg, String modelId) {
    final ov = cfg.modelOverrides[modelId];
    if (ov is Map<String, dynamic>) return ov;
    return const <String, dynamic>{};
  }

  static Map<String, String> _customHeaders(ProviderConfig cfg, String modelId) {
    final ov = _modelOverride(cfg, modelId);
    final list = (ov['headers'] as List?) ?? const <dynamic>[];
    final out = <String, String>{};
    for (final e in list) {
      if (e is Map) {
        final name = (e['name'] ?? e['key'] ?? '').toString().trim();
        final value = (e['value'] ?? '').toString();
        if (name.isNotEmpty) out[name] = value;
      }
    }
    return out;
  }

  static dynamic _parseOverrideValue(String v) {
    final s = v.trim();
    if (s.isEmpty) return s;
    if (s == 'true') return true;
    if (s == 'false') return false;
    if (s == 'null') return null;
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s);
    if (d != null) return d;
    if ((s.startsWith('{') && s.endsWith('}')) || (s.startsWith('[') && s.endsWith(']'))) {
      try {
        return jsonDecode(s);
      } catch (_) {}
    }
    return v;
  }

  static Map<String, dynamic> _customBody(ProviderConfig cfg, String modelId) {
    final ov = _modelOverride(cfg, modelId);
    final list = (ov['body'] as List?) ?? const <dynamic>[];
    final out = <String, dynamic>{};
    for (final e in list) {
      if (e is Map) {
        final key = (e['key'] ?? e['name'] ?? '').toString().trim();
        final val = (e['value'] ?? '').toString();
        if (key.isNotEmpty) out[key] = _parseOverrideValue(val);
      }
    }
    return out;
  }

  // Resolve effective model info by respecting per-model overrides; fallback to inference
  static ModelInfo _effectiveModelInfo(ProviderConfig cfg, String modelId) {
    final upstreamId = _apiModelId(cfg, modelId);
    final base = ModelRegistry.infer(ModelInfo(id: upstreamId, displayName: upstreamId));
    final ov = _modelOverride(cfg, modelId);
    ModelType? type;
    final t = (ov['type'] as String?) ?? '';
    if (t == 'embedding') type = ModelType.embedding; else if (t == 'chat') type = ModelType.chat;
    List<Modality>? input;
    if (ov['input'] is List) {
      input = [for (final e in (ov['input'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)];
    }
    List<Modality>? output;
    if (ov['output'] is List) {
      output = [for (final e in (ov['output'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)];
    }
    List<ModelAbility>? abilities;
    if (ov['abilities'] is List) {
      abilities = [for (final e in (ov['abilities'] as List)) (e.toString() == 'reasoning' ? ModelAbility.reasoning : ModelAbility.tool)];
    }
    return base.copyWith(
      type: type ?? base.type,
      input: input ?? base.input,
      output: output ?? base.output,
      abilities: abilities ?? base.abilities,
    );
  }
  static String _mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/png';
  }

  static String _mimeFromDataUrl(String dataUrl) {
    try {
      final start = dataUrl.indexOf(':');
      final semi = dataUrl.indexOf(';');
      if (start >= 0 && semi > start) {
        return dataUrl.substring(start + 1, semi);
      }
    } catch (_) {}
    return 'image/png';
  }

  // Simple container for parsed text + image refs
  static _ParsedTextAndImages _parseTextAndImages(String raw) {
    if (raw.isEmpty) return const _ParsedTextAndImages('', <_ImageRef>[]);
    final mdImg = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');
    // Match custom inline image markers like: [image:/absolute/path.png]
    // Use a single backslash in a raw string to escape '[' and ']' in regex.
    final customImg = RegExp(r"\[image:(.+?)\]");
    final images = <_ImageRef>[];
    final buf = StringBuffer();
    int i = 0;
    while (i < raw.length) {
      final m1 = mdImg.matchAsPrefix(raw, i);
      final m2 = customImg.matchAsPrefix(raw, i);
      if (m1 != null) {
        final url = (m1.group(1) ?? '').trim();
        if (url.isNotEmpty) {
          if (url.startsWith('data:')) {
            images.add(_ImageRef('data', url));
          } else if (url.startsWith('http://') || url.startsWith('https://')) {
            images.add(_ImageRef('url', url));
          } else {
            images.add(_ImageRef('path', url));
          }
        }
        i = m1.end;
        continue;
      }
      if (m2 != null) {
        final p = (m2.group(1) ?? '').trim();
        if (p.isNotEmpty) images.add(_ImageRef('path', p));
        i = m2.end;
        continue;
      }
      buf.write(raw[i]);
      i++;
    }
    return _ParsedTextAndImages(buf.toString().trim(), images);
  }

  static Future<String> _encodeBase64File(String path, {bool withPrefix = false}) async {
    final fixed = SandboxPathResolver.fix(path);
    final file = File(fixed);
    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);
    if (withPrefix) {
      final mime = _mimeFromPath(fixed);
      return 'data:$mime;base64,$b64';
    }
    return b64;
  }
  static http.Client _clientFor(ProviderConfig cfg) {
    final enabled = cfg.proxyEnabled == true;
    final host = (cfg.proxyHost ?? '').trim();
    final portStr = (cfg.proxyPort ?? '').trim();
    final user = (cfg.proxyUsername ?? '').trim();
    final pass = (cfg.proxyPassword ?? '').trim();
    final allowInsecure = cfg.allowInsecureConnection == true;

    // Create HttpClient if proxy is enabled OR SSL verification needs to be disabled
    if (enabled || allowInsecure) {
      final io = HttpClient();

      // Configure proxy if enabled
      if (enabled && host.isNotEmpty && portStr.isNotEmpty) {
        final port = int.tryParse(portStr) ?? 8080;
        io.findProxy = (uri) => 'PROXY $host:$port';
        if (user.isNotEmpty) {
          io.addProxyCredentials(host, port, '', HttpClientBasicCredentials(user, pass));
        }
      }

      // Skip SSL certificate verification if requested (for self-signed certs)
      if (allowInsecure) {
        io.badCertificateCallback = (cert, host, port) => true;
      }

      return IOClient(io);
    }

    return http.Client();
  }

  static Stream<ChatStreamChunk> sendMessageStream({
    required ProviderConfig config,
    required String modelId,
    required List<Map<String, dynamic>> messages,
    List<String>? userImagePaths,
    int? thinkingBudget,
    double? temperature,
    double? topP,
    int? maxTokens,
    int maxToolLoopIterations = 10,
    List<Map<String, dynamic>>? tools,
    Future<String> Function(String name, Map<String, dynamic> args)? onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
    ToolCallMode toolCallMode = ToolCallMode.native,
  }) async* {
    // Route to prompt tool use stream if in prompt mode with tools
    if (toolCallMode == ToolCallMode.prompt && tools != null && tools.isNotEmpty && onToolCall != null) {
      yield* PromptToolAdapter.sendStream(
        config: config,
        modelId: modelId,
        messages: messages,
        userImagePaths: userImagePaths,
        thinkingBudget: thinkingBudget,
        temperature: temperature,
        topP: topP,
        maxTokens: maxTokens,
        maxToolLoopIterations: maxToolLoopIterations,
        tools: tools,
        onToolCall: onToolCall,
        extraHeaders: extraHeaders,
        extraBody: extraBody,
      );
      return;
    }

    final kind = ProviderConfig.classify(config.id, explicitType: config.providerType);
    final client = ChatApiHelper.clientFor(config);

    // Track selected key for multi-key management
    String? selectedKeyId;
    try {
      if (config.multiKeyEnabled == true && (config.apiKeys?.isNotEmpty == true)) {
        final sel = ApiKeyManager().selectForProvider(config);
        selectedKeyId = sel.key?.id;
      }
    } catch (_) {
      // Ignore key selection errors
    }

    bool streamCompleted = false;
    String? streamError;

    try {
      Stream<ChatStreamChunk> stream;
      if (kind == ProviderKind.openai) {
        stream = OpenAIAdapter.sendStream(
          client,
          config,
          modelId,
          messages,
          userImagePaths: userImagePaths,
          thinkingBudget: thinkingBudget,
          temperature: temperature,
          topP: topP,
          maxTokens: maxTokens,
          maxToolLoopIterations: maxToolLoopIterations,
          tools: tools,
          onToolCall: onToolCall,
          extraHeaders: extraHeaders,
          extraBody: extraBody,
        );
      } else if (kind == ProviderKind.claude) {
        stream = ClaudeAdapter.sendStream(
          client,
          config,
          modelId,
          messages,
          userImagePaths: userImagePaths,
          thinkingBudget: thinkingBudget,
          temperature: temperature,
          topP: topP,
          maxTokens: maxTokens,
          maxToolLoopIterations: maxToolLoopIterations,
          tools: tools,
          onToolCall: onToolCall,
          extraHeaders: extraHeaders,
          extraBody: extraBody,
        );
      } else if (kind == ProviderKind.google) {
        stream = GoogleAdapter.sendStream(
          client,
          config,
          modelId,
          messages,
          userImagePaths: userImagePaths,
          thinkingBudget: thinkingBudget,
          temperature: temperature,
          topP: topP,
          maxTokens: maxTokens,
          maxToolLoopIterations: maxToolLoopIterations,
          tools: tools,
          onToolCall: onToolCall,
          extraHeaders: extraHeaders,
          extraBody: extraBody,
        );
      } else {
        return; // Unknown provider kind
      }

      // Wrap stream to track completion and errors
      await for (final chunk in stream) {
        yield chunk;
      }
      streamCompleted = true;
    } catch (e) {
      streamError = e.toString();
      rethrow;
    } finally {
      client.close();

      // Update key status after stream completes or fails
      if (selectedKeyId != null) {
        try {
          final maxFailures = config.keyManagement?.maxFailuresBeforeDisable;
          await ApiKeyManager().updateKeyStatus(
            selectedKeyId,
            streamCompleted && streamError == null, // success if completed without error
            error: streamError,
            maxFailuresBeforeDisable: maxFailures,
          );
        } catch (_) {
          // Ignore status update errors to avoid breaking main flow
        }
      }
    }
  }

  // Non-streaming text generation for utilities like title summarization
  static Future<String> generateText({
    required ProviderConfig config,
    required String modelId,
    required String prompt,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
  }) async {
    final upstreamModelId = ChatApiHelper.apiModelId(config, modelId);
    final kind = ProviderConfig.classify(config.id, explicitType: config.providerType);
    final client = ChatApiHelper.clientFor(config);

    // Track selected key for multi-key management
    String? selectedKeyId;
    try {
      if (config.multiKeyEnabled == true && (config.apiKeys?.isNotEmpty == true)) {
        final sel = ApiKeyManager().selectForProvider(config);
        selectedKeyId = sel.key?.id;
      }
    } catch (_) {
      // Ignore key selection errors
    }

    String? requestError;

    try {
      if (kind == ProviderKind.openai) {
        final base = config.baseUrl.endsWith('/')
            ? config.baseUrl.substring(0, config.baseUrl.length - 1)
            : config.baseUrl;
        final path = (config.useResponseApi == true) ? '/responses' : (config.chatPath ?? '/chat/completions');
        final url = Uri.parse('$base$path');
        Map<String, dynamic> body;
        if (config.useResponseApi == true) {
          // Inject built-in web_search tool when enabled and supported
          final toolsList = <Map<String, dynamic>>[];
          bool _isResponsesWebSearchSupported(String id) {
            final m = id.toLowerCase();
            if (m.startsWith('gpt-4o')) return true;
            if (m == 'gpt-4.1' || m == 'gpt-4.1-mini') return true;
            if (m.startsWith('o4-mini')) return true;
            if (m == 'o3' || m.startsWith('o3-')) return true;
            if (m.startsWith('gpt-5')) return true;
            return false;
          }
          if (_isResponsesWebSearchSupported(modelId)) {
            final builtIns = ChatApiHelper.builtInTools(config, modelId);
            if (builtIns.contains('search')) {
              Map<String, dynamic> ws = const <String, dynamic>{};
              try {
                final ov = config.modelOverrides[modelId];
                if (ov is Map && ov['webSearch'] is Map) ws = (ov['webSearch'] as Map).cast<String, dynamic>();
              } catch (_) {}
              final usePreview = (ws['preview'] == true) || ((ws['tool'] ?? '').toString() == 'preview');
              final entry = <String, dynamic>{'type': usePreview ? 'web_search_preview' : 'web_search'};
              if (ws['allowed_domains'] is List && (ws['allowed_domains'] as List).isNotEmpty) {
                entry['filters'] = {'allowed_domains': List<String>.from((ws['allowed_domains'] as List).map((e) => e.toString()))};
              }
              if (ws['user_location'] is Map) entry['user_location'] = (ws['user_location'] as Map).cast<String, dynamic>();
              if (usePreview && ws['search_context_size'] is String) entry['search_context_size'] = ws['search_context_size'];
              toolsList.add(entry);
            }
          }
          body = {
            'model': upstreamModelId,
            'input': [
              {'role': 'user', 'content': prompt}
            ],
            if (toolsList.isNotEmpty) 'tools': toolsList,
            if (toolsList.isNotEmpty) 'tool_choice': 'auto',
          };
        } else {
          body = {
            'model': upstreamModelId,
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'temperature': 0.3,
          };
        }
        final headers = <String, String>{
          'Authorization': 'Bearer ${ChatApiHelper.apiKeyForRequest(config, modelId)}',
          'Content-Type': 'application/json',
        };
        headers.addAll(ChatApiHelper.customHeaders(config, modelId));
        if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
        final extra = ChatApiHelper.customBody(config, modelId);
        if (extra.isNotEmpty) (body as Map<String, dynamic>).addAll(extra);
        if (extraBody != null && extraBody.isNotEmpty) {
          (extraBody).forEach((k, v) {
            (body as Map<String, dynamic>)[k] = (v is String) ? ChatApiHelper.parseOverrideValue(v) : v;
          });
        }
        final resp = await client.post(url, headers: headers, body: jsonEncode(body));
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw HttpException('HTTP ${resp.statusCode}: ${resp.body}');
        }
        final data = jsonDecode(resp.body);
        if (config.useResponseApi == true) {
          // Prefer SDK-style convenience when present
          final ot = data['output_text'];
          if (ot is String && ot.isNotEmpty) return ot;
          // Aggregate text from `output` list of message blocks
          final out = data['output'];
          if (out is List) {
            final buf = StringBuffer();
            for (final item in out) {
              if (item is! Map) continue;
              final content = item['content'];
              if (content is List) {
                for (final c in content) {
                  if (c is Map && (c['type'] == 'output_text') && (c['text'] is String)) {
                    buf.write(c['text']);
                  }
                }
              }
            }
            final s = buf.toString();
            if (s.isNotEmpty) return s;
          }
          return '';
        } else {
          final choices = data['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final msg = choices.first['message'];
            return (msg?['content'] ?? '').toString();
          }
          return '';
        }
      } else if (kind == ProviderKind.claude) {
        final base = config.baseUrl.endsWith('/')
            ? config.baseUrl.substring(0, config.baseUrl.length - 1)
            : config.baseUrl;
        final url = Uri.parse('$base/messages');
        final body = {
          'model': upstreamModelId,
          'max_tokens': 512,
          'temperature': 0.3,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        };
        final headers = <String, String>{
          'x-api-key': ChatApiHelper.apiKeyForRequest(config, modelId),
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
        };
        headers.addAll(ChatApiHelper.customHeaders(config, modelId));
        if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
        final extra = ChatApiHelper.customBody(config, modelId);
        if (extra.isNotEmpty) (body as Map<String, dynamic>).addAll(extra);
        if (extraBody != null && extraBody.isNotEmpty) {
          (extraBody).forEach((k, v) {
            (body as Map<String, dynamic>)[k] = (v is String) ? ChatApiHelper.parseOverrideValue(v) : v;
          });
        }
        final resp = await client.post(url, headers: headers, body: jsonEncode(body));
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw HttpException('HTTP ${resp.statusCode}: ${resp.body}');
        }
        final data = jsonDecode(resp.body);
        final content = data['content'] as List?;
        if (content != null && content.isNotEmpty) {
          final text = content.first['text'];
          return (text ?? '').toString();
        }
        return '';
      } else {
        // Google
        String url;
        if (config.vertexAI == true && (config.location?.isNotEmpty == true) && (config.projectId?.isNotEmpty == true)) {
          final loc = config.location!;
          final proj = config.projectId!;
          url = 'https://aiplatform.googleapis.com/v1/projects/$proj/locations/$loc/publishers/google/models/$modelId:generateContent';
        } else {
          final base = config.baseUrl.endsWith('/')
              ? config.baseUrl.substring(0, config.baseUrl.length - 1)
              : config.baseUrl;
          url = '$base/models/$modelId:generateContent?key=${Uri.encodeComponent(ChatApiHelper.apiKeyForRequest(config, modelId))}';
        }
        final body = {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {'temperature': 0.3},
        };

        // Inject Gemini built-in tools (only for official Gemini API; Vertex may not support these)
        final builtIns = _builtInTools(config, modelId);
        final isOfficialGemini = config.vertexAI != true; // heuristic per requirement
        if (isOfficialGemini && builtIns.isNotEmpty) {
          final toolsArr = <Map<String, dynamic>>[];
          if (builtIns.contains('search')) {
            toolsArr.add({'google_search': {}});
          }
          if (builtIns.contains('url_context')) {
            toolsArr.add({'url_context': {}});
          }
          if (toolsArr.isNotEmpty) {
            (body as Map<String, dynamic>)['tools'] = toolsArr;
          }
        }
        final headers = <String, String>{'Content-Type': 'application/json'};
        // Add Bearer for Vertex via service account JSON
        if (config.vertexAI == true) {
          final token = await _maybeVertexAccessToken(config);
          if (token != null && token.isNotEmpty) {
            headers['Authorization'] = 'Bearer $token';
          }
          final proj = (config.projectId ?? '').trim();
          if (proj.isNotEmpty) headers['X-Goog-User-Project'] = proj;
        }
        headers.addAll(ChatApiHelper.customHeaders(config, modelId));
        if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
        final extra = ChatApiHelper.customBody(config, modelId);
        if (extra.isNotEmpty) (body as Map<String, dynamic>).addAll(extra);
        if (extraBody != null && extraBody.isNotEmpty) {
          (extraBody).forEach((k, v) {
            (body as Map<String, dynamic>)[k] = (v is String) ? ChatApiHelper.parseOverrideValue(v) : v;
          });
        }
        final resp = await client.post(Uri.parse(url), headers: headers, body: jsonEncode(body));
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw HttpException('HTTP ${resp.statusCode}: ${resp.body}');
        }
        final data = jsonDecode(resp.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates.first['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return (parts.first['text'] ?? '').toString();
          }
        }
        return '';
      }
    } catch (e) {
      requestError = e.toString();
      rethrow;
    } finally {
      client.close();

      // Update key status after request completes or fails
      if (selectedKeyId != null) {
        try {
          final maxFailures = config.keyManagement?.maxFailuresBeforeDisable;
          await ApiKeyManager().updateKeyStatus(
            selectedKeyId,
            requestError == null, // success if no error captured
            error: requestError,
            maxFailuresBeforeDisable: maxFailures,
          );
        } catch (_) {
          // Ignore status update errors to avoid breaking main flow
        }
      }
    }
  }

  static bool _isOff(int? budget) => (budget != null && budget != -1 && budget < 1024);
  static String _effortForBudget(int? budget) {
    if (budget == null || budget == -1) return 'auto';
    if (_isOff(budget)) return 'off';
    if (budget <= 2000) return 'low';
    if (budget <= 20000) return 'medium';
    return 'high';
  }

  // Clean JSON Schema for Google Gemini API strict validation
  // Google requires array types to have 'items' field
  static Map<String, dynamic> _cleanSchemaForGemini(Map<String, dynamic> schema) {
    final result = Map<String, dynamic>.from(schema);

    // Recursively fix 'properties' if present
    if (result['properties'] is Map) {
      final props = Map<String, dynamic>.from(result['properties'] as Map);
      props.forEach((key, value) {
        if (value is Map) {
          final propMap = Map<String, dynamic>.from(value as Map);
          // print('[ChatApi/Schema] Property $key: type=${propMap['type']}, hasItems=${propMap.containsKey('items')}');
          // If type is array but items is missing, add a permissive items schema
          if (propMap['type'] == 'array' && !propMap.containsKey('items')) {
            // print('[ChatApi/Schema] Adding items to array property: $key');
            propMap['items'] = {'type': 'string'}; // Default to string array
          }
          // Recursively clean nested objects
          if (propMap['type'] == 'object' && propMap.containsKey('properties')) {
            propMap['properties'] = _cleanSchemaForGemini({'properties': propMap['properties']})['properties'];
          }
          props[key] = propMap;
        }
      });
      result['properties'] = props;
    }

    // Handle array items recursively
    if (result['items'] is Map) {
      result['items'] = _cleanSchemaForGemini(result['items'] as Map<String, dynamic>);
    }

    return result;
  }

  // Clean OpenAI-format tools for compatibility with strict backends (like Gemini via NewAPI)
  static List<Map<String, dynamic>> _cleanToolsForCompatibility(List<Map<String, dynamic>> tools) {
    final cleaned = tools.map((tool) {
      final result = Map<String, dynamic>.from(tool);
      final fn = result['function'];
      if (fn is Map) {
        final fnMap = Map<String, dynamic>.from(fn as Map);
        final params = fnMap['parameters'];
        if (params is Map) {
          fnMap['parameters'] = _cleanSchemaForGemini(params as Map<String, dynamic>);
        }
        result['function'] = fnMap;
      }
      return result;
    }).toList();
    // print('[ChatApi/Tools] Cleaned ${cleaned.length} tools: ${jsonEncode(cleaned)}');
    return cleaned;
  }

  /// Send message stream using prompt-based tool use
  /// 
  /// This method injects tool definitions into the system prompt and parses
  /// XML tool calls from the model output, enabling tool use for models
  /// that don't support native function calling.
  /// 
  /// Requirements: 5.1, 5.2, 6.1, 6.2, 6.3
  static Stream<ChatStreamChunk> _sendPromptToolUseStream({
    required ProviderConfig config,
    required String modelId,
    required List<Map<String, dynamic>> messages,
    List<String>? userImagePaths,
    int? thinkingBudget,
    double? temperature,
    double? topP,
    int? maxTokens,
    required int maxToolLoopIterations,
    required List<Map<String, dynamic>> tools,
    required Future<String> Function(String name, Map<String, dynamic> args) onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
  }) async* {
    // Build enhanced system prompt with tool definitions
    String userSystemPrompt = '';
    final enhancedMessages = <Map<String, dynamic>>[];
    
    for (final msg in messages) {
      final role = (msg['role'] ?? '').toString();
      final content = (msg['content'] ?? '').toString();
      
      if (role == 'system') {
        userSystemPrompt = content;
      } else {
        enhancedMessages.add(Map<String, dynamic>.from(msg));
      }
    }
    
    // Build enhanced system prompt with tool definitions
    final enhancedSystemPrompt = PromptToolUseService.buildSystemPrompt(
      userSystemPrompt: userSystemPrompt,
      tools: tools,
    );
    
    // Insert enhanced system prompt at the beginning
    final messagesWithPrompt = <Map<String, dynamic>>[
      {'role': 'system', 'content': enhancedSystemPrompt},
      ...enhancedMessages,
    ];
    
    // Track conversation for multi-turn tool calls
    var currentMessages = messagesWithPrompt;
    int iteration = 0;
    
    while (iteration < maxToolLoopIterations) {
      iteration++;
      
      // Create XML tag extractor for this iteration
      final extractor = XmlTagExtractor();
      String accumulatedContent = '';
      ParsedToolUse? detectedToolCall;
      
      // Send request WITHOUT tools parameter (Requirement 6.2)
      final stream = sendMessageStream(
        config: config,
        modelId: modelId,
        messages: currentMessages,
        userImagePaths: iteration == 1 ? userImagePaths : null,
        thinkingBudget: thinkingBudget,
        temperature: temperature,
        topP: topP,
        maxTokens: maxTokens,
        maxToolLoopIterations: maxToolLoopIterations,
        tools: null, // Don't send tools - they're in the prompt
        onToolCall: null, // Don't use native tool handling
        extraHeaders: extraHeaders,
        extraBody: extraBody,
        toolCallMode: ToolCallMode.native, // Use native mode for underlying request
      );
      
      await for (final chunk in stream) {
        if (chunk.isDone) {
          // Stream completed - check if we have a pending tool call
          if (detectedToolCall != null) {
            // Emit tool call info
            yield ChatStreamChunk(
              content: '',
              isDone: false,
              totalTokens: chunk.totalTokens,
              usage: chunk.usage,
              toolCalls: [
                ToolCallInfo(
                  id: detectedToolCall.id,
                  name: detectedToolCall.name,
                  arguments: detectedToolCall.arguments,
                ),
              ],
            );
            
            // Execute the tool
            final result = await onToolCall(detectedToolCall.name, detectedToolCall.arguments);
            
            // Emit tool result
            yield ChatStreamChunk(
              content: '',
              isDone: false,
              totalTokens: chunk.totalTokens,
              usage: chunk.usage,
              toolResults: [
                ToolResultInfo(
                  id: detectedToolCall.id,
                  name: detectedToolCall.name,
                  arguments: detectedToolCall.arguments,
                  content: result,
                ),
              ],
            );
            
            // Build tool result message
            final toolResultMessage = PromptToolUseService.buildToolResultMessage(
              toolName: detectedToolCall.name,
              result: result,
            );
            
            // Add assistant message with tool call and user message with result
            currentMessages = [
              ...currentMessages,
              {'role': 'assistant', 'content': accumulatedContent + detectedToolCall.toXml()},
              {'role': 'user', 'content': toolResultMessage},
            ];
            
            // Reset for next iteration
            detectedToolCall = null;
            accumulatedContent = '';
            
            // Continue to next iteration
            break;
          } else {
            // No tool call detected, we're done
            yield ChatStreamChunk(
              content: '',
              isDone: true,
              totalTokens: chunk.totalTokens,
              usage: chunk.usage,
            );
            return;
          }
        }
        
        // Process content through XML extractor
        if (chunk.content.isNotEmpty) {
          final results = extractor.processChunk(chunk.content);
          
          for (final result in results) {
            if (result.isTagContent) {
              // This is tool_use tag content - parse it
              final parsed = XmlTagExtractor.parseToolUse(result.content);
              if (parsed != null) {
                detectedToolCall = parsed;
              }
            } else {
              // Regular content - emit it
              if (result.content.isNotEmpty) {
                accumulatedContent += result.content;
                yield ChatStreamChunk(
                  content: result.content,
                  reasoning: chunk.reasoning,
                  isDone: false,
                  totalTokens: chunk.totalTokens,
                  usage: chunk.usage,
                );
              }
            }
          }
        } else if (chunk.reasoning != null && chunk.reasoning!.isNotEmpty) {
          // Pass through reasoning content
          yield ChatStreamChunk(
            content: '',
            reasoning: chunk.reasoning,
            isDone: false,
            totalTokens: chunk.totalTokens,
            usage: chunk.usage,
          );
        }
      }
      
      // If no tool call was detected in this iteration, we're done
      if (detectedToolCall == null && iteration > 1) {
        return;
      }
    }
    
    // Reached max iterations - emit final done chunk
    yield ChatStreamChunk(
      content: '',
      isDone: true,
      totalTokens: 0,
    );
  }

  static Stream<ChatStreamChunk> _sendOpenAIStream(
      http.Client client,
      ProviderConfig config,
      String modelId,
      List<Map<String, dynamic>> messages,
      {List<String>? userImagePaths, int? thinkingBudget, double? temperature, double? topP, int? maxTokens, int maxToolLoopIterations = 10, List<Map<String, dynamic>>? tools, Future<String> Function(String, Map<String, dynamic>)? onToolCall, Map<String, String>? extraHeaders, Map<String, dynamic>? extraBody}
      ) async* {
    final upstreamModelId = _apiModelId(config, modelId);

    // 🔍 DEBUG: Print model ID resolution
    print('═══════════════════════════════════════════════════════════');
    print('🔍 [KELIVO DEBUG] OpenAI Stream Request');
    print('📋 Provider: ${config.id}');
    print('🏷️  Logical Model ID (from UI): $modelId');
    print('🎯 Upstream Model ID (for API): $upstreamModelId');
    print('═══════════════════════════════════════════════════════════');

    final base = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final path = (config.useResponseApi == true)
        ? '/responses'
        : (config.chatPath ?? '/chat/completions');
    final url = Uri.parse('$base$path');

    final effectiveInfo = _effectiveModelInfo(config, modelId);
    final isReasoning = effectiveInfo.abilities.contains(ModelAbility.reasoning);
    final wantsImageOutput = effectiveInfo.output.contains(Modality.image);

    final effort = _effortForBudget(thinkingBudget);
    final host = Uri.tryParse(config.baseUrl)?.host.toLowerCase() ?? '';
    Map<String, dynamic> body;
    if (config.useResponseApi == true) {
      final input = <Map<String, dynamic>>[];
      // Extract system messages into `instructions` (Responses API best practice)
      String instructions = '';
      // Prepare tools list for Responses path (may be augmented with built-in web search)
      final List<Map<String, dynamic>> toolList = [];
      if (tools != null && tools.isNotEmpty) {
        for (final t in tools) {
          if (t is Map<String, dynamic>) {
            // Convert Chat Completions format to Response API format
            // Chat Completions: {"type": "function", "function": {"name": "...", "description": "...", "parameters": {...}}}
            // Response API: {"type": "function", "name": "...", "description": "...", "parameters": {...}}
            if (t['type'] == 'function' && t['function'] is Map) {
              final func = t['function'] as Map<String, dynamic>;
              toolList.add({
                'type': 'function',
                'name': func['name'],
                if (func['description'] != null) 'description': func['description'],
                if (func['parameters'] != null) 'parameters': func['parameters'],
              });
            } else {
              // Already in Response API format or other format
              toolList.add(Map<String, dynamic>.from(t));
            }
          }
        }
      }

      // Built-in web search for Responses API when enabled on supported models
      bool _isResponsesWebSearchSupported(String id) {
        final m = id.toLowerCase();
        if (m.startsWith('gpt-4o')) return true; // gpt-4o, gpt-4o-mini
        if (m == 'gpt-4.1' || m == 'gpt-4.1-mini') return true;
        if (m.startsWith('o4-mini')) return true;
        if (m == 'o3' || m.startsWith('o3-')) return true;
        if (m.startsWith('gpt-5')) return true; // supports reasoning web search
        return false;
      }

      if (_isResponsesWebSearchSupported(modelId)) {
        final builtIns = _builtInTools(config, modelId);
        if (builtIns.contains('search')) {
          // Optional per-model configuration under modelOverrides[modelId]['webSearch']
          Map<String, dynamic> ws = const <String, dynamic>{};
          try {
            final ov = config.modelOverrides[modelId];
            if (ov is Map && ov['webSearch'] is Map) {
              ws = (ov['webSearch'] as Map).cast<String, dynamic>();
            }
          } catch (_) {}
          final usePreview = (ws['preview'] == true) || ((ws['tool'] ?? '').toString() == 'preview');
          final entry = <String, dynamic>{'type': usePreview ? 'web_search_preview' : 'web_search'};
          // Domain filters
          if (ws['allowed_domains'] is List && (ws['allowed_domains'] as List).isNotEmpty) {
            entry['filters'] = {
              'allowed_domains': List<String>.from((ws['allowed_domains'] as List).map((e) => e.toString())),
            };
          }
          // User location
          if (ws['user_location'] is Map) {
            entry['user_location'] = (ws['user_location'] as Map).cast<String, dynamic>();
          }
          // Search context size (preview tool only)
          if (usePreview && ws['search_context_size'] is String) {
            entry['search_context_size'] = ws['search_context_size'];
          }
          toolList.add(entry);
          // Optionally request sources in output
          if (ws['include_sources'] == true) {
            // Merge/append include array
            // We'll add this after input loop when building body
          }
        }
      }
      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];
        final isLast = i == messages.length - 1;
        final raw = (m['content'] ?? '').toString();
        final roleRaw = (m['role'] ?? 'user').toString();

        // Responses API supports a top-level `instructions` field that has higher priority
        if (roleRaw == 'system') {
          if (raw.isNotEmpty) {
            instructions = instructions.isEmpty ? raw : (instructions + '\n\n' + raw);
          }
          continue;
        }

        // Only parse images if there are images to process
        final hasMarkdownImages = raw.contains('![') && raw.contains('](');
        final hasCustomImages = raw.contains('[image:');
        final hasAttachedImages = isLast && (userImagePaths?.isNotEmpty == true) && (m['role'] == 'user');

        if (hasMarkdownImages || hasCustomImages || hasAttachedImages) {
          final parsed = _parseTextAndImages(raw);
          final parts = <Map<String, dynamic>>[];
          if (parsed.text.isNotEmpty) {
            parts.add({'type': 'input_text', 'text': parsed.text});
          }
          // Images extracted from this message's text
          for (final ref in parsed.images) {
            String url;
            if (ref.kind == 'data') {
              url = ref.src;
            } else if (ref.kind == 'path') {
              url = await _encodeBase64File(ref.src, withPrefix: true);
            } else {
              url = ref.src; // http(s)
            }
            parts.add({'type': 'input_image', 'image_url': url});
          }
          // Additional images explicitly attached to the last user message
          if (hasAttachedImages) {
            for (final p in userImagePaths!) {
              final dataUrl = (p.startsWith('http') || p.startsWith('data:')) ? p : await _encodeBase64File(p, withPrefix: true);
              parts.add({'type': 'input_image', 'image_url': dataUrl});
            }
          }
          input.add({'role': roleRaw, 'content': parts});
        } else {
          // No images, use simple string content
          input.add({'role': roleRaw, 'content': raw});
        }
      }
      body = {
        'model': upstreamModelId,
        'input': input,
        'stream': true,
        if (instructions.isNotEmpty) 'instructions': instructions,
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (maxTokens != null && maxTokens > 0) 'max_output_tokens': maxTokens,
        if (toolList.isNotEmpty) 'tools': toolList,
        if (toolList.isNotEmpty) 'tool_choice': 'auto',
        if (isReasoning && effort != 'off')
          'reasoning': {
            'summary': 'detailed',  // 固定使用 detailed
            if (effort != 'auto') 'effort': effort,
          },
        'text': {
          'verbosity': 'high',  // 固定使用 high
        },
      };
      // Append include parameter if we opted into sources via overrides
      try {
        final ov = config.modelOverrides[modelId];
        final ws = (ov is Map ? ov['webSearch'] : null);
        if (ws is Map && ws['include_sources'] == true) {
          (body as Map<String, dynamic>)['include'] = ['web_search_call.action.sources'];
        }
      } catch (_) {}
    } else {
      final mm = <Map<String, dynamic>>[];
      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];
        final isLast = i == messages.length - 1;
        final raw = (m['content'] ?? '').toString();

        // Only parse images if there are images to process
        final hasMarkdownImages = raw.contains('![') && raw.contains('](');
        final hasCustomImages = raw.contains('[image:');
        final hasAttachedImages = isLast && (userImagePaths?.isNotEmpty == true) && (m['role'] == 'user');

        if (hasMarkdownImages || hasCustomImages || hasAttachedImages) {
          final parsed = _parseTextAndImages(raw);
          final parts = <Map<String, dynamic>>[];
          if (parsed.text.isNotEmpty) {
            parts.add({'type': 'text', 'text': parsed.text});
          }
          for (final ref in parsed.images) {
            String url;
            if (ref.kind == 'data') {
              url = ref.src;
            } else if (ref.kind == 'path') {
              url = await _encodeBase64File(ref.src, withPrefix: true);
            } else {
              url = ref.src;
            }
            parts.add({'type': 'image_url', 'image_url': {'url': url}});
          }
          if (hasAttachedImages) {
            for (final p in userImagePaths!) {
              final dataUrl = (p.startsWith('http') || p.startsWith('data:')) ? p : await _encodeBase64File(p, withPrefix: true);
              parts.add({'type': 'image_url', 'image_url': {'url': dataUrl}});
            }
          }
          mm.add({'role': m['role'] ?? 'user', 'content': parts});
        } else {
          // No images, use simple string content
          mm.add({'role': m['role'] ?? 'user', 'content': raw});
        }
      }
      body = {
        'model': upstreamModelId,
        'messages': mm,
        'stream': true,
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (maxTokens != null && maxTokens > 0) 'max_tokens': maxTokens,
        if (isReasoning && effort != 'off' && effort != 'auto') 'reasoning_effort': effort,
        if (tools != null && tools.isNotEmpty) 'tools': _cleanToolsForCompatibility(tools),
        if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
      };
    }

    // Vendor-specific reasoning knobs for chat-completions compatible hosts
    if (config.useResponseApi != true) {
      final off = _isOff(thinkingBudget);
      if (host.contains('openrouter.ai')) {
        if (isReasoning) {
          // OpenRouter uses `reasoning.enabled/max_tokens`
          if (off) {
            (body as Map<String, dynamic>)['reasoning'] = {'enabled': false};
          } else {
            final obj = <String, dynamic>{'enabled': true};
            if (thinkingBudget != null && thinkingBudget > 0) obj['max_tokens'] = thinkingBudget;
            (body as Map<String, dynamic>)['reasoning'] = obj;
          }
          (body as Map<String, dynamic>).remove('reasoning_effort');
        } else {
          (body as Map<String, dynamic>).remove('reasoning');
          (body as Map<String, dynamic>).remove('reasoning_effort');
        }
      } else if (host.contains('dashscope') || host.contains('aliyun')) {
        // Aliyun DashScope: enable_thinking + thinking_budget
        if (isReasoning) {
          (body as Map<String, dynamic>)['enable_thinking'] = !off;
          if (!off && thinkingBudget != null && thinkingBudget > 0) {
            (body as Map<String, dynamic>)['thinking_budget'] = thinkingBudget;
          } else {
            (body as Map<String, dynamic>).remove('thinking_budget');
          }
        } else {
          (body as Map<String, dynamic>).remove('enable_thinking');
          (body as Map<String, dynamic>).remove('thinking_budget');
        }
        (body as Map<String, dynamic>).remove('reasoning_effort');
      } else if (host.contains('ark.cn-beijing.volces.com') || host.contains('volc') || host.contains('ark')) {
        // Volc Ark: thinking: { type: enabled|disabled }
        if (isReasoning) {
          (body as Map<String, dynamic>)['thinking'] = {'type': off ? 'disabled' : 'enabled'};
        } else {
          (body as Map<String, dynamic>).remove('thinking');
        }
        (body as Map<String, dynamic>).remove('reasoning_effort');
      } else if (host.contains('intern-ai') || host.contains('intern') || host.contains('chat.intern-ai.org.cn')) {
        // InternLM (InternAI): thinking_mode boolean switch
        if (isReasoning) {
          (body as Map<String, dynamic>)['thinking_mode'] = !off;
        } else {
          (body as Map<String, dynamic>).remove('thinking_mode');
        }
        (body as Map<String, dynamic>).remove('reasoning_effort');
      } else if (host.contains('siliconflow')) {
        // SiliconFlow: OFF -> enable_thinking: false; otherwise omit
        if (isReasoning) {
          if (off) {
            (body as Map<String, dynamic>)['enable_thinking'] = false;
          } else {
            (body as Map<String, dynamic>).remove('enable_thinking');
          }
        } else {
          (body as Map<String, dynamic>).remove('enable_thinking');
        }
        (body as Map<String, dynamic>).remove('reasoning_effort');
      } else if (host.contains('deepseek') || modelId.toLowerCase().contains('deepseek')) {
        if (isReasoning) {
          if (off) {
            (body as Map<String, dynamic>)['reasoning_content'] = false;
            (body as Map<String, dynamic>).remove('reasoning_budget');
          } else {
            (body as Map<String, dynamic>)['reasoning_content'] = true;
            if (thinkingBudget != null && thinkingBudget > 0) {
              (body as Map<String, dynamic>)['reasoning_budget'] = thinkingBudget;
            } else {
              (body as Map<String, dynamic>).remove('reasoning_budget');
            }
          }
        } else {
          (body as Map<String, dynamic>).remove('reasoning_content');
          (body as Map<String, dynamic>).remove('reasoning_budget');
        }
      } else if (host.contains('opencode')) {
        // opencode.ai doesn't support reasoning_effort parameter
        (body as Map<String, dynamic>).remove('reasoning_effort');
      } else if (_isGrokModel(config, modelId)) {
        // Grok 4 series doesn't support reasoning_effort parameter
        // Only Grok 3 Mini series supports it
        final isGrok3Mini = modelId.toLowerCase().contains('grok-3-mini');
        if (!isGrok3Mini) {
          (body as Map<String, dynamic>).remove('reasoning_effort');
        }
      }
    }

    final request = http.Request('POST', url);
    final headers = <String, String>{
      'Authorization': 'Bearer ${_apiKeyForRequest(config, modelId)}',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };
    // Merge custom headers (override takes precedence)
    headers.addAll(_customHeaders(config, modelId));
    if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
    request.headers.addAll(headers);
    // Ask for usage in streaming for chat-completions compatible hosts (when supported)
    if (config.useResponseApi != true) {
      final h = Uri.tryParse(config.baseUrl)?.host.toLowerCase() ?? '';
      if (!h.contains('mistral.ai')) {
        (body as Map<String, dynamic>)['stream_options'] = {'include_usage': true};
      }
    }
    // Inject Grok built-in search if configured
    if (_isGrokModel(config, modelId)) {
      final builtIns = _builtInTools(config, modelId);
      if (builtIns.contains('search')) {
        (body as Map<String, dynamic>)['search_parameters'] = {
          'mode': 'auto',
          'return_citations': true,
        };
      }
    }
    // Merge custom body keys (override takes precedence)
    final extraBodyCfg = _customBody(config, modelId);
    if (extraBodyCfg.isNotEmpty) {
      (body as Map<String, dynamic>).addAll(extraBodyCfg);
    }
    if (extraBody != null && extraBody.isNotEmpty) {
      extraBody.forEach((k, v) {
        (body as Map<String, dynamic>)[k] = (v is String) ? ChatApiHelper.parseOverrideValue(v) : v;
      });
    }
    request.body = jsonEncode(body);

    // 🔍 DEBUG: Print complete request details
    print('───────────────────────────────────────────────────────────');
    print('📤 [KELIVO] Sending OpenAI Request');
    print('🌐 URL: $url');
    print('🔑 API Key: ${_apiKeyForRequest(config, modelId).substring(0, 20)}...');
    print('📦 Request Body:');
    print(jsonEncode(body));
    print('───────────────────────────────────────────────────────────');

    // 记录完整的请求信息
    try {
      final timestamp = _timestamp();
      final logFile = File('c:/mycode/kelivo/debug_api.log');
      final separator = '=' * 80;

      logFile.writeAsStringSync('\n$separator\n', mode: FileMode.append);
      logFile.writeAsStringSync('[$timestamp] API REQUEST\n', mode: FileMode.append);
      logFile.writeAsStringSync('$separator\n', mode: FileMode.append);
      logFile.writeAsStringSync('URL: $url\n', mode: FileMode.append);
      logFile.writeAsStringSync('Method: POST\n\n', mode: FileMode.append);

      logFile.writeAsStringSync('Headers:\n', mode: FileMode.append);
      headers.forEach((key, value) {
        // 隐藏敏感的 API Key
        if (key == 'Authorization') {
          logFile.writeAsStringSync('  $key: Bearer ***\n', mode: FileMode.append);
        } else {
          logFile.writeAsStringSync('  $key: $value\n', mode: FileMode.append);
        }
      });

      logFile.writeAsStringSync('\nPayload:\n', mode: FileMode.append);
      // 格式化 JSON 输出
      final encoder = JsonEncoder.withIndent('  ');
      final prettyBody = encoder.convert(body);
      logFile.writeAsStringSync('$prettyBody\n', mode: FileMode.append);
      logFile.writeAsStringSync('$separator\n', mode: FileMode.append);
    } catch (e) {
      // 日志写入失败,静默继续
    }

    final response = await client.send(request);

    // 记录响应状态
    try {
      final timestamp = _timestamp();
      final logFile = File('c:/mycode/kelivo/debug_api.log');
      final separator = '=' * 80;

      logFile.writeAsStringSync('\n[$timestamp] API RESPONSE\n', mode: FileMode.append);
      logFile.writeAsStringSync('$separator\n', mode: FileMode.append);
      logFile.writeAsStringSync('Status Code: ${response.statusCode}\n', mode: FileMode.append);
      logFile.writeAsStringSync('Response Headers:\n', mode: FileMode.append);
      response.headers.forEach((key, value) {
        logFile.writeAsStringSync('  $key: $value\n', mode: FileMode.append);
      });
      logFile.writeAsStringSync('\nResponse Body (streaming):\n', mode: FileMode.append);
    } catch (e) {
      // 日志写入失败,静默继续
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await response.stream.bytesToString();

      // 🔍 DEBUG: Print error response
      print('❌ [KELIVO ERROR] HTTP ${response.statusCode}');
      print('📄 Error Body: $errorBody');
      print('═══════════════════════════════════════════════════════════');

      // 记录错误响应
      try {
        final timestamp = _timestamp();
        final logFile = File('c:/mycode/kelivo/debug_api.log');
        logFile.writeAsStringSync('[$timestamp] ERROR Response Body:\n$errorBody\n', mode: FileMode.append);
        logFile.writeAsStringSync('${'=' * 80}\n\n', mode: FileMode.append);
      } catch (e) {
        // 日志写入失败,静默继续
      }

      throw HttpException('HTTP ${response.statusCode}: $errorBody');
    }

    final stream = response.stream.transform(utf8.decoder);
    String buffer = '';
    int totalTokens = 0;
    TokenUsage? usage;
    // Fallback approx token calculation when provider doesn't include usage
    int _approxTokensFromChars(int chars) => (chars / 4).round();
    final int approxPromptChars = messages.fold<int>(0, (acc, m) => acc + ((m['content'] ?? '').toString().length));
    final int approxPromptTokens = _approxTokensFromChars(approxPromptChars);
    int approxCompletionChars = 0;

    // Track potential tool calls (OpenAI Chat Completions)
    final Map<int, Map<String, String>> toolAcc = <int, Map<String, String>>{}; // index -> {id,name,args}
    // Track potential tool calls (OpenAI Responses API)
    final Map<String, Map<String, String>> toolAccResp = <String, Map<String, String>>{}; // call_id -> {id,name,args}
    // Map item_id to call_id for Responses API argument accumulation
    final Map<String, String> itemIdToCallId = <String, String>{}; // item_id -> call_id
    String? finishReason;

    // 用于累积完整响应内容
    final List<String> responseChunks = [];

    await for (final chunk in stream) {
      // 记录每个接收到的chunk
      responseChunks.add(chunk);

      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.last;

      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i].trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;

        final data = line.substring(5).trimLeft();

        // 记录每个SSE事件
        try {
          final timestamp = _timestamp();
          final logFile = File('c:/mycode/kelivo/debug_api.log');
          logFile.writeAsStringSync('[$timestamp] SSE: $line\n', mode: FileMode.append);
        } catch (e) {
          // 日志写入失败,静默继续
        }
        if (data == '[DONE]') {
          // If model streamed tool_calls but didn't include finish_reason on prior chunks,
          // execute tool flow now and start follow-up request.
          if (onToolCall != null && toolAcc.isNotEmpty) {
            final calls = <Map<String, dynamic>>[];
            final callInfos = <ToolCallInfo>[];
            final toolMsgs = <Map<String, dynamic>>[];
            toolAcc.forEach((idx, m) {
              final id = (m['id'] ?? 'call_$idx');
              final name = (m['name'] ?? '');
              Map<String, dynamic> args;
              try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
              callInfos.add(ToolCallInfo(id: id, name: name, arguments: args));
              calls.add({
                'id': id,
                'type': 'function',
                'function': {
                  'name': name,
                  'arguments': jsonEncode(args),
                },
              });
              toolMsgs.add({'__name': name, '__id': id, '__args': args});
            });

            if (callInfos.isNotEmpty) {
              final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage, toolCalls: callInfos);
            }

            // Execute tools and emit results
            final results = <Map<String, dynamic>>[];
            final resultsInfo = <ToolResultInfo>[];
            for (final m in toolMsgs) {
              final name = m['__name'] as String;
              final id = m['__id'] as String;
              final args = (m['__args'] as Map<String, dynamic>);
              final res = await onToolCall(name, args) ?? '';
              results.add({'tool_call_id': id, 'content': res});
              resultsInfo.add(ToolResultInfo(id: id, name: name, arguments: args, content: res));
            }
            if (resultsInfo.isNotEmpty) {
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo);
            }

            // Build follow-up messages
            final mm2 = <Map<String, dynamic>>[];
            for (final m in messages) {
              mm2.add({'role': m['role'] ?? 'user', 'content': m['content'] ?? ''});
            }
            mm2.add({'role': 'assistant', 'content': '', 'tool_calls': calls});
            for (final r in results) {
              final id = r['tool_call_id'];
              final name = calls.firstWhere((c) => c['id'] == id, orElse: () => const {'function': {'name': ''}})['function']['name'];
              mm2.add({'role': 'tool', 'tool_call_id': id, 'name': name, 'content': r['content']});
            }

            // Follow-up request(s) with multi-round tool calls
            var currentMessages = mm2;
            while (true) {
              final body2 = {
                'model': upstreamModelId,
                'messages': currentMessages,
                'stream': true,
                if (temperature != null) 'temperature': temperature,
                if (topP != null) 'top_p': topP,
                if (maxTokens != null && maxTokens > 0) 'max_tokens': maxTokens,
                if (isReasoning && effort != 'off' && effort != 'auto') 'reasoning_effort': effort,
                if (tools != null && tools.isNotEmpty) 'tools': _cleanToolsForCompatibility(tools),
                if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
              };

              // Apply the same vendor-specific reasoning settings as the original request
              final off = _isOff(thinkingBudget);
              if (host.contains('openrouter.ai')) {
                if (isReasoning) {
                  if (off) {
                    body2['reasoning'] = {'enabled': false};
                  } else {
                    final obj = <String, dynamic>{'enabled': true};
                    if (thinkingBudget != null && thinkingBudget > 0) obj['max_tokens'] = thinkingBudget;
                    body2['reasoning'] = obj;
                  }
                  body2.remove('reasoning_effort');
                } else {
                  body2.remove('reasoning');
                  body2.remove('reasoning_effort');
                }
              } else if (host.contains('dashscope') || host.contains('aliyun')) {
                if (isReasoning) {
                  body2['enable_thinking'] = !off;
                  if (!off && thinkingBudget != null && thinkingBudget > 0) {
                    body2['thinking_budget'] = thinkingBudget;
                  } else {
                    body2.remove('thinking_budget');
                  }
                } else {
                  body2.remove('enable_thinking');
                  body2.remove('thinking_budget');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('ark.cn-beijing.volces.com') || host.contains('volc') || host.contains('ark')) {
                if (isReasoning) {
                  body2['thinking'] = {'type': off ? 'disabled' : 'enabled'};
                } else {
                  body2.remove('thinking');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('intern-ai') || host.contains('intern') || host.contains('chat.intern-ai.org.cn')) {
                if (isReasoning) {
                  body2['thinking_mode'] = !off;
                } else {
                  body2.remove('thinking_mode');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('siliconflow')) {
                if (isReasoning) {
                  if (off) {
                    body2['enable_thinking'] = false;
                  } else {
                    body2.remove('enable_thinking');
                  }
                } else {
                  body2.remove('enable_thinking');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('deepseek') || modelId.toLowerCase().contains('deepseek')) {
                if (isReasoning) {
                  if (off) {
                    body2['reasoning_content'] = false;
                    body2.remove('reasoning_budget');
                  } else {
                    body2['reasoning_content'] = true;
                    if (thinkingBudget != null && thinkingBudget > 0) {
                      body2['reasoning_budget'] = thinkingBudget;
                    } else {
                      body2.remove('reasoning_budget');
                    }
                  }
                } else {
                  body2.remove('reasoning_content');
                  body2.remove('reasoning_budget');
                }
              } else if (host.contains('opencode')) {
                // opencode.ai doesn't support reasoning_effort parameter
                body2.remove('reasoning_effort');
              } else if (_isGrokModel(config, modelId)) {
                // Grok 4 series doesn't support reasoning_effort parameter
                final isGrok3Mini = modelId.toLowerCase().contains('grok-3-mini');
                if (!isGrok3Mini) {
                  body2.remove('reasoning_effort');
                }
              }

              // Ask for usage in streaming (when supported)
              if (!host.contains('mistral.ai')) {
                body2['stream_options'] = {'include_usage': true};
              }

              // Apply custom body overrides
              if (extraBody != null && extraBody.isNotEmpty) {
                extraBody.forEach((k, v) {
                  body2[k] = (v is String) ? _parseOverrideValue(v) : v;
                });
              }

              final req2 = http.Request('POST', url);
              final headers2 = <String, String>{
                'Authorization': 'Bearer ${_apiKeyForRequest(config, modelId)}',
                'Content-Type': 'application/json',
                'Accept': 'text/event-stream',
              };
              // Apply custom headers
              headers2.addAll(_customHeaders(config, modelId));
              if (extraHeaders != null && extraHeaders.isNotEmpty) headers2.addAll(extraHeaders);
              req2.headers.addAll(headers2);
              req2.body = jsonEncode(body2);
              final resp2 = await client.send(req2);
              if (resp2.statusCode < 200 || resp2.statusCode >= 300) {
                final errorBody = await resp2.stream.bytesToString();
                throw HttpException('HTTP ${resp2.statusCode}: $errorBody');
              }
              final s2 = resp2.stream.transform(utf8.decoder);
              String buf2 = '';
              // Track potential subsequent tool calls
              final Map<int, Map<String, String>> toolAcc2 = <int, Map<String, String>>{};
              String? finishReason2;
              String contentAccum = ''; // Accumulate content for this round
              await for (final ch in s2) {
                buf2 += ch;
                final lines2 = buf2.split('\n');
                buf2 = lines2.last;
                for (int j = 0; j < lines2.length - 1; j++) {
                  final l = lines2[j].trim();
                  if (l.isEmpty || !l.startsWith('data:')) continue;
                  final d = l.substring(5).trimLeft();
                  if (d == '[DONE]') {
                    // This round finished; handle below
                    continue;
                  }
                  try {
                    final o = jsonDecode(d);
                    if (o is Map && o['choices'] is List && (o['choices'] as List).isNotEmpty) {
                      final c0 = (o['choices'] as List).first;
                      finishReason2 = c0['finish_reason'] as String?;
                      final delta = c0['delta'] as Map?;
                      final txt = delta?['content'];
                      final rc = delta?['reasoning_content'] ?? delta?['reasoning'];
                      final u = o['usage'];
                      if (u != null) {
                        var prompt = (u['prompt_tokens'] ?? 0) as int;
                        final completion = (u['completion_tokens'] ?? 0) as int;
                        final cached = (u['prompt_tokens_details']?['cached_tokens'] ?? 0) as int? ?? 0;
                        // Fix: If API returns usage but prompt_tokens is 0, use approximation
                        if (prompt == 0 && approxPromptTokens > 0) {
                          prompt = approxPromptTokens;
                        }
                        usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: prompt, completionTokens: completion, cachedTokens: cached));
                        totalTokens = usage!.totalTokens;
                      }
                      // Capture Grok citations if present
                      if (_isGrokModel(config, modelId)) {
                        final citations = _extractGrokCitations(Map<String, dynamic>.from(o));
                        if (citations.isNotEmpty) {
                          yield ChatStreamChunk(
                            content: '',
                            isDone: false,
                            totalTokens: usage?.totalTokens ?? 0,
                            usage: usage,
                            toolResults: citations,
                          );
                        }
                      }
                      if (rc is String && rc.isNotEmpty) {
                        yield ChatStreamChunk(content: '', reasoning: rc, isDone: false, totalTokens: 0, usage: usage);
                      }
                      if (txt is String && txt.isNotEmpty) {
                        contentAccum += txt; // Accumulate content
                        yield ChatStreamChunk(content: txt, isDone: false, totalTokens: 0, usage: usage);
                      }
                      // Handle image outputs from OpenRouter-style deltas
                      // Possible shapes:
                      // - delta['images']: [ { type: 'image_url', image_url: { url: 'data:...' }, index: 0 }, ... ]
                      // - delta['content']: [ { type: 'image_url', image_url: { url: '...' } }, { type: 'text', text: '...' } ]
                      // - delta['image_url'] directly (less common)
                      if (wantsImageOutput) {
                        final List<dynamic> imageItems = <dynamic>[];
                        final imgs = delta?['images'];
                        if (imgs is List) imageItems.addAll(imgs);
                        final contentArr = (txt is List) ? txt : (delta?['content'] as List?);
                        if (contentArr is List) {
                          for (final it in contentArr) {
                            if (it is Map && (it['type'] == 'image_url' || it['type'] == 'image')) {
                              imageItems.add(it);
                            }
                          }
                        }
                        final singleImage = delta?['image_url'];
                        if (singleImage is Map || singleImage is String) {
                          imageItems.add({'type': 'image_url', 'image_url': singleImage});
                        }
                        if (imageItems.isNotEmpty) {
                          final buf = StringBuffer();
                          for (final it in imageItems) {
                            if (it is! Map) continue;
                            dynamic iu = it['image_url'];
                            String? url;
                            if (iu is String) {
                              url = iu;
                            } else if (iu is Map) {
                              final u2 = iu['url'];
                              if (u2 is String) url = u2;
                            }
                            if (url != null && url.isNotEmpty) {
                              final md = '\n\n![image](' + url + ')';
                              buf.write(md);
                              contentAccum += md;
                            }
                          }
                          final out = buf.toString();
                          if (out.isNotEmpty) {
                            yield ChatStreamChunk(content: out, isDone: false, totalTokens: 0, usage: usage);
                          }
                        }
                      }
                      final tcs = delta?['tool_calls'] as List?;
                      if (tcs != null) {
                        for (final t in tcs) {
                          final idx = (t['index'] as int?) ?? 0;
                          final id = t['id'] as String?;
                          final func = t['function'] as Map<String, dynamic>?;
                          final name = func?['name'] as String?;
                          final argsDelta = func?['arguments'] as String?;
                          final entry = toolAcc2.putIfAbsent(idx, () => {'id': '', 'name': '', 'args': ''});
                          if (id != null) entry['id'] = id;
                          if (name != null && name.isNotEmpty) entry['name'] = name;
                          if (argsDelta != null && argsDelta.isNotEmpty) entry['args'] = (entry['args'] ?? '') + argsDelta;
                        }
                      }
                    }
                  } catch (_) {}
                }
              }

              // After this follow-up round finishes: if tool calls again, execute and loop
              if ((finishReason2 == 'tool_calls' || toolAcc2.isNotEmpty) && onToolCall != null) {
                final calls2 = <Map<String, dynamic>>[];
                final callInfos2 = <ToolCallInfo>[];
                final toolMsgs2 = <Map<String, dynamic>>[];
                toolAcc2.forEach((idx, m) {
                  final id = (m['id'] ?? 'call_$idx');
                  final name = (m['name'] ?? '');
                  Map<String, dynamic> args;
                  try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
                  callInfos2.add(ToolCallInfo(id: id, name: name, arguments: args));
                  calls2.add({'id': id, 'type': 'function', 'function': {'name': name, 'arguments': jsonEncode(args)}});
                  toolMsgs2.add({'__name': name, '__id': id, '__args': args});
                });
                if (callInfos2.isNotEmpty) {
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolCalls: callInfos2);
                }
                final results2 = <Map<String, dynamic>>[];
                final resultsInfo2 = <ToolResultInfo>[];
                for (final m in toolMsgs2) {
                  final name = m['__name'] as String;
                  final id = m['__id'] as String;
                  final args = (m['__args'] as Map<String, dynamic>);
                  final res = await onToolCall(name, args) ?? '';
                  results2.add({'tool_call_id': id, 'content': res});
                  resultsInfo2.add(ToolResultInfo(id: id, name: name, arguments: args, content: res));
                }
                if (resultsInfo2.isNotEmpty) {
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo2);
                }
                // Append for next loop - including any content accumulated in this round
                currentMessages = [
                  ...currentMessages,
                  if (contentAccum.isNotEmpty) {'role': 'assistant', 'content': contentAccum},
                  {'role': 'assistant', 'content': '', 'tool_calls': calls2},
                  for (final r in results2)
                    {
                      'role': 'tool',
                      'tool_call_id': r['tool_call_id'],
                      'name': calls2.firstWhere((c) => c['id'] == r['tool_call_id'], orElse: () => const {'function': {'name': ''}})['function']['name'],
                      'content': r['content'],
                    },
                ];
                // Continue loop
                continue;
              } else {
                // No further tool calls; finish
                final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
                yield ChatStreamChunk(content: '', isDone: true, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage);
                return;
              }
            }
            // Should not reach here
            return;
          }

          final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
          yield ChatStreamChunk(
            content: '',
            isDone: true,
            totalTokens: usage?.totalTokens ?? approxTotal,
            usage: usage,
          );
          return;
        }

        try {
          final json = jsonDecode(data);
          String content = '';
          String? reasoning;

          if (config.useResponseApi == true) {
            // OpenAI /responses SSE types
            final type = json['type'];

            // Log all event types
            try {
              final timestamp = _timestamp();
              final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
              logFile.writeAsStringSync('[$timestamp] [Response Event] type: $type, json: ${jsonEncode(json)}\n', mode: FileMode.append);
            } catch (_) {}

            if (type == 'response.output_text.delta') {
              final delta = json['delta'];
              if (delta is String) {
                content = delta;
                approxCompletionChars += content.length;
              }
            } else if (type == 'response.reasoning_summary_text.delta') {
              final delta = json['delta'];
              if (delta is String) reasoning = delta;
            } else if (type == 'response.output_item.added') {
              // New output item added (could be function_call, message, etc.)
              final item = json['item'];
              if (item is Map && item['type'] == 'function_call') {
                final callId = (item['call_id'] ?? '').toString();
                final itemId = (item['id'] ?? '').toString();
                final name = (item['name'] ?? '').toString();
                if (callId.isNotEmpty && itemId.isNotEmpty) {
                  // Map item_id to call_id for later argument accumulation
                  itemIdToCallId[itemId] = callId;
                  toolAccResp.putIfAbsent(callId, () => {'id': callId, 'name': name, 'args': ''});
                }
              }
            } else if (type == 'response.function_call_arguments.delta') {
              // Accumulate function call arguments
              final itemId = (json['item_id'] ?? '').toString();
              final delta = (json['delta'] ?? '').toString();
              if (itemId.isNotEmpty && delta.isNotEmpty) {
                // Map item_id to call_id
                final callId = itemIdToCallId[itemId];
                if (callId != null) {
                  final entry = toolAccResp[callId];
                  if (entry != null) {
                    entry['args'] = (entry['args'] ?? '') + delta;
                  }
                }
              }
            } else if (type == 'response.function_call_arguments.done') {
              // Function call arguments complete
              final itemId = (json['item_id'] ?? '').toString();
              final args = (json['arguments'] ?? '').toString();
              if (itemId.isNotEmpty && args.isNotEmpty) {
                // Map item_id to call_id
                final callId = itemIdToCallId[itemId];
                if (callId != null) {
                  final entry = toolAccResp[callId];
                  if (entry != null) {
                    entry['args'] = args; // Use final complete args
                  }
                }
              }
            } else if (type == 'response.completed') {
              // Response fully completed - extract usage
              final u = json['response']?['usage'];
              if (u != null) {
                final inTok = (u['input_tokens'] ?? 0) as int;
                final outTok = (u['output_tokens'] ?? 0) as int;
                usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: inTok, completionTokens: outTok));
                totalTokens = usage!.totalTokens;
              }
              
              // DON'T clear toolAccResp here! Tool calls have already been accumulated through events
              // (response.output_item.added + response.function_call_arguments.done)
              // Just extract usage, tool calls are already ready
              
              // Extract web search citations from final output (Responses API)
              try {
                final output = json['response']?['output'];
                final items = <Map<String, dynamic>>[];
                if (output is List) {
                  int idx = 1;
                  final seen = <String>{};
                  for (final it in output) {
                    if (it is! Map) continue;
                    if (it['type'] == 'message') {
                      final content = it['content'] as List? ?? const <dynamic>[];
                      for (final block in content) {
                        if (block is! Map) continue;
                        final anns = block['annotations'] as List? ?? const <dynamic>[];
                        for (final an in anns) {
                          if (an is! Map) continue;
                          if ((an['type'] ?? '') == 'url_citation') {
                            final url = (an['url'] ?? '').toString();
                            if (url.isEmpty || seen.contains(url)) continue;
                            final title = (an['title'] ?? '').toString();
                            items.add({'index': idx, 'url': url, if (title.isNotEmpty) 'title': title});
                            seen.add(url);
                            idx += 1;
                          }
                        }
                      }
                    }
                  }
                }
                if (items.isNotEmpty) {
                  final payload = jsonEncode({'items': items});
                  yield ChatStreamChunk(
                    content: '',
                    isDone: false,
                    totalTokens: totalTokens,
                    usage: usage,
                    toolResults: [ToolResultInfo(id: 'builtin_search', name: 'search_web', arguments: const <String, dynamic>{}, content: payload)],
                  );
                }
              } catch (_) {}
              // Responses: emit any collected tool calls from previous deltas
              if (onToolCall != null && toolAccResp.isNotEmpty) {
                try {
                  final timestamp = _timestamp();
                  final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                  logFile.writeAsStringSync('[$timestamp] [Tool Execution] toolAccResp: ${jsonEncode(toolAccResp)}\n', mode: FileMode.append);
                } catch (_) {}

                final callInfos = <ToolCallInfo>[];
                final msgs = <Map<String, dynamic>>[];
                int idx = 0;
                toolAccResp.forEach((key, m) {
                  Map<String, dynamic> args;
                  try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
                  final id2 = (m['id'] ?? key).isNotEmpty ? (m['id'] ?? key) : 'call_$idx';
                  callInfos.add(ToolCallInfo(id: id2, name: (m['name'] ?? ''), arguments: args));
                  msgs.add({'__id': id2, '__name': (m['name'] ?? ''), '__args': args, '__callId': m['id'] ?? key});
                  idx += 1;
                });
                if (callInfos.isNotEmpty) {
                  final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage, toolCalls: callInfos);
                }
                final resultsInfo = <ToolResultInfo>[];
                final toolOutputs = <Map<String, dynamic>>[];
                for (final m in msgs) {
                  final nm = m['__name'] as String;
                  final id2 = m['__id'] as String;
                  final callId = m['__callId'] as String;
                  final args = (m['__args'] as Map<String, dynamic>);
                  final res = await onToolCall(nm, args) ?? '';
                  resultsInfo.add(ToolResultInfo(id: id2, name: nm, arguments: args, content: res));
                  toolOutputs.add({
                    'type': 'function_call_output',
                    'call_id': callId,
                    'output': res,
                  });

                  try {
                    final timestamp = _timestamp();
                    final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                    logFile.writeAsStringSync('[$timestamp] [Tool Execution] Executed $nm with args $args, result length: ${res.length}\n', mode: FileMode.append);
                  } catch (_) {}
                }
                if (resultsInfo.isNotEmpty) {
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo);
                }

                // === Tool Calling Loop (like rikkahub) ===
                // Initialize current messages and system instructions
                var currentMessages = <Map<String, dynamic>>[];
                String systemInstructions = '';

                // Extract system messages and build initial message list
                for (final m in messages) {
                  final roleRaw = (m['role'] ?? 'user').toString();
                  if (roleRaw == 'system') {
                    final content = (m['content'] ?? '').toString();
                    if (content.isNotEmpty) {
                      systemInstructions = systemInstructions.isEmpty ? content : (systemInstructions + '\n\n' + content);
                    }
                  } else {
                    currentMessages.add(Map<String, dynamic>.from(m));
                  }
                }

                // Tool calling loop (max iterations to prevent infinite loops)
                for (int stepIndex = 0; stepIndex < maxToolLoopIterations; stepIndex++) {
                  try {
                    final timestamp = _timestamp();
                    final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                    logFile.writeAsStringSync('[$timestamp] [Tool Loop] ========================================\n', mode: FileMode.append);
                    logFile.writeAsStringSync('[$timestamp] [Tool Loop] === Step #$stepIndex (max $maxToolLoopIterations) ===\n', mode: FileMode.append);
                    logFile.writeAsStringSync('[$timestamp] [Tool Loop] toolAccResp count: ${toolAccResp.length}\n', mode: FileMode.append);
                    logFile.writeAsStringSync('[$timestamp] [Tool Loop] toolAccResp: ${jsonEncode(toolAccResp)}\n', mode: FileMode.append);
                  } catch (_) {}

                  // Check if we have tool calls to process
                  if (toolAccResp.isEmpty) {
                    try {
                      final timestamp = _timestamp();
                      final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                      logFile.writeAsStringSync('[$timestamp] [Tool Loop] ✓ No tool calls, exiting loop normally\n', mode: FileMode.append);
                    } catch (_) {}
                    break;
                  }

                  // Safety check: if we've reached max iterations, log warning and break
                  if (stepIndex >= maxToolLoopIterations - 1) {
                    try {
                      final timestamp = _timestamp();
                      final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                      logFile.writeAsStringSync('[$timestamp] [Tool Loop] ⚠️ WARNING: Reached max iterations ($maxToolLoopIterations), forcing exit to prevent infinite loop\n', mode: FileMode.append);
                      logFile.writeAsStringSync('[$timestamp] [Tool Loop] ⚠️ Remaining tool calls will be ignored: ${jsonEncode(toolAccResp)}\n', mode: FileMode.append);
                    } catch (_) {}
                    break;
                  }

                  // Execute all tool calls
                  final callInfos = <ToolCallInfo>[];
                  final toolCallMsgs = <Map<String, dynamic>>[];
                  final toolOutputs = <Map<String, dynamic>>[];
                  int idx = 0;

                  toolAccResp.forEach((key, m) {
                    Map<String, dynamic> args;
                    try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
                    final id2 = (m['id'] ?? key).isNotEmpty ? (m['id'] ?? key) : 'call_$idx';
                    callInfos.add(ToolCallInfo(id: id2, name: (m['name'] ?? ''), arguments: args));
                    toolCallMsgs.add({
                      '__id': id2,
                      '__name': (m['name'] ?? ''),
                      '__args': args,
                      '__callId': m['id'] ?? key,
                    });
                    idx += 1;
                  });

                  if (callInfos.isNotEmpty) {
                    final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
                    yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage, toolCalls: callInfos);
                  }

                  // Execute tools
                  final resultsInfo = <ToolResultInfo>[];
                  for (final m in toolCallMsgs) {
                    final nm = m['__name'] as String;
                    final id2 = m['__id'] as String;
                    final callId = m['__callId'] as String;
                    final args = (m['__args'] as Map<String, dynamic>);
                    final res = await onToolCall(nm, args) ?? '';
                    resultsInfo.add(ToolResultInfo(id: id2, name: nm, arguments: args, content: res));
                    toolOutputs.add({
                      'type': 'function_call_output',
                      'call_id': callId,
                      'output': res,
                    });

                    try {
                      final timestamp = _timestamp();
                      final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                      logFile.writeAsStringSync('[$timestamp] [Tool Loop] Executed $nm, result length: ${res.length}\n', mode: FileMode.append);
                    } catch (_) {}
                  }

                  if (resultsInfo.isNotEmpty) {
                    yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo);
                  }

                  // Build conversation (like rikkahub's buildMessages)
                  final conversation = <Map<String, dynamic>>[];

                  // Add all current messages
                  for (final m in currentMessages) {
                    final roleRaw = (m['role'] ?? 'user').toString();
                    if (roleRaw == 'system') continue;

                    final content = (m['content'] ?? '').toString();
                    conversation.add({'role': roleRaw, 'content': content});

                    // If message has tool calls, add them
                    final toolCalls = m['__toolCalls'] as List?;
                    if (toolCalls != null && toolCalls.isNotEmpty) {
                      for (final tc in toolCalls) {
                        conversation.add({
                          'type': 'function_call',
                          'call_id': tc['call_id'],
                          'name': tc['name'],
                          'arguments': tc['arguments'],
                        });
                      }
                    }

                    // If message has tool results, add them
                    final toolResults = m['__toolResults'] as List?;
                    if (toolResults != null && toolResults.isNotEmpty) {
                      conversation.addAll(toolResults.cast<Map<String, dynamic>>());
                    }
                  }

                  // Add current tool calls
                  for (final m in toolCallMsgs) {
                    conversation.add({
                      'type': 'function_call',
                      'call_id': m['__callId'],
                      'name': m['__name'],
                      'arguments': jsonEncode(m['__args']),
                    });
                  }

                  // Add tool outputs
                  conversation.addAll(toolOutputs);

                  try {
                    final timestamp = _timestamp();
                    final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                    logFile.writeAsStringSync('[$timestamp] [Tool Loop] Conversation: ${jsonEncode(conversation)}\n', mode: FileMode.append);
                  } catch (_) {}

                  // Send follow-up request
                  // Reconstruct tools list from initial tools parameter
                  final List<Map<String, dynamic>> followUpTools = [];
                  if (tools != null && tools.isNotEmpty) {
                    for (final t in tools) {
                      if (t is Map<String, dynamic>) {
                        if (t['type'] == 'function' && t['function'] is Map) {
                          final func = t['function'] as Map<String, dynamic>;
                          followUpTools.add({
                            'type': 'function',
                            'name': func['name'],
                            if (func['description'] != null) 'description': func['description'],
                            if (func['parameters'] != null) 'parameters': func['parameters'],
                          });
                        } else {
                          followUpTools.add(Map<String, dynamic>.from(t));
                        }
                      }
                    }
                  }

                  final followUpBody = {
                    'model': upstreamModelId,
                    'input': conversation,
                    'stream': true,
                    if (systemInstructions.isNotEmpty) 'instructions': systemInstructions,
                    'reasoning': {'effort': 'high', 'summary': 'detailed'},
                    if (temperature != null) 'temperature': temperature,
                    if (topP != null) 'top_p': topP,
                    if (maxTokens != null && maxTokens > 0) 'max_output_tokens': maxTokens,
                    if (followUpTools.isNotEmpty) 'tools': followUpTools,
                    if (followUpTools.isNotEmpty) 'tool_choice': 'auto',
                  };

                  final followUpReq = http.Request('POST', url);
                  followUpReq.headers.addAll(headers);
                  followUpReq.body = jsonEncode(followUpBody);

                  final followUpStream = await client.send(followUpReq);

                  try {
                    final timestamp = _timestamp();
                    final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                    logFile.writeAsStringSync('[$timestamp] [Tool Loop] Response status: ${followUpStream.statusCode}\n', mode: FileMode.append);
                  } catch (_) {}

                  // Process follow-up response
                  final followUpChunks = followUpStream.stream.transform(utf8.decoder);
                  String followUpBuffer = '';
                  String followUpContent = ''; // 累积follow-up的文本内容

                  // Clear tool accumulator and itemId mapping for next response
                  toolAccResp.clear();
                  itemIdToCallId.clear();

                  await for (final chunk in followUpChunks) {
                    followUpBuffer += chunk;
                    final lines = followUpBuffer.split('\n');
                    followUpBuffer = lines.last;

                    for (int i = 0; i < lines.length - 1; i++) {
                      final line = lines[i].trim();
                      if (line.isEmpty || !line.startsWith('data:')) continue;
                      final data = line.substring(5).trimLeft();
                      if (data == '[DONE]') continue;

                      try {
                        final followUpJson = jsonDecode(data);
                        final followUpType = followUpJson['type'];

                        try {
                          final timestamp = _timestamp();
                          final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                          logFile.writeAsStringSync('[$timestamp] [Follow-up Event] type: $followUpType\n', mode: FileMode.append);
                          // Only log full JSON for important events to reduce log size
                          if (followUpType == 'response.output_item.added' ||
                              followUpType == 'response.function_call_arguments.done' ||
                              followUpType == 'response.completed') {
                            logFile.writeAsStringSync('[$timestamp] [Follow-up Event] json: ${jsonEncode(followUpJson)}\n', mode: FileMode.append);
                          }
                        } catch (_) {}

                        // Handle all event types
                        if (followUpType == 'response.reasoning_summary_text.delta') {
                          final delta = followUpJson['delta'];
                          if (delta is String && delta.isNotEmpty) {
                            try {
                              final timestamp = _timestamp();
                              final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                              logFile.writeAsStringSync('[$timestamp] [Follow-up Event] 🧠 Reasoning delta: ${delta.length} chars\n', mode: FileMode.append);
                            } catch (_) {}
                            yield ChatStreamChunk(content: '', reasoning: delta, isDone: false, totalTokens: totalTokens, usage: usage);
                          }
                        } else if (followUpType == 'response.output_text.delta') {
                          final delta = followUpJson['delta'];
                          if (delta is String && delta.isNotEmpty) {
                            try {
                              final timestamp = _timestamp();
                              final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                              logFile.writeAsStringSync('[$timestamp] [Follow-up Event] 📝 Output text delta: "${delta.substring(0, delta.length > 50 ? 50 : delta.length)}${delta.length > 50 ? '...' : ''}"\n', mode: FileMode.append);
                            } catch (_) {}
                            followUpContent += delta; // 累积文本
                            yield ChatStreamChunk(content: delta, isDone: false, totalTokens: totalTokens, usage: usage);
                          }
                        } else if (followUpType == 'response.output_item.added') {
                          final item = followUpJson['item'];
                          if (item is Map && item['type'] == 'function_call') {
                            final callId = (item['call_id'] ?? '').toString();
                            final itemId = (item['id'] ?? '').toString();
                            final name = (item['name'] ?? '').toString();
                            if (callId.isNotEmpty && itemId.isNotEmpty) {
                              try {
                                final timestamp = _timestamp();
                                final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                                logFile.writeAsStringSync('[$timestamp] [Follow-up Event] 🔧 New tool call added: $name (callId: $callId, itemId: $itemId)\n', mode: FileMode.append);
                              } catch (_) {}
                              // Map item_id to call_id for later argument accumulation
                              itemIdToCallId[itemId] = callId;
                              toolAccResp.putIfAbsent(callId, () => {'id': callId, 'name': name, 'args': ''});
                            }
                          }
                        } else if (followUpType == 'response.function_call_arguments.delta') {
                          final itemId = (followUpJson['item_id'] ?? '').toString();
                          final delta = (followUpJson['delta'] ?? '').toString();
                          if (itemId.isNotEmpty && delta.isNotEmpty) {
                            // Map item_id to call_id
                            final callId = itemIdToCallId[itemId];
                            if (callId != null) {
                              final entry = toolAccResp[callId];
                              if (entry != null) {
                                entry['args'] = (entry['args'] ?? '') + delta;
                              }
                            }
                          }
                        } else if (followUpType == 'response.function_call_arguments.done') {
                          final itemId = (followUpJson['item_id'] ?? '').toString();
                          final args = (followUpJson['arguments'] ?? '').toString();
                          if (itemId.isNotEmpty && args.isNotEmpty) {
                            // Map item_id to call_id
                            final callId = itemIdToCallId[itemId];
                            if (callId != null) {
                              final entry = toolAccResp[callId];
                              if (entry != null) {
                                entry['args'] = args;
                                try {
                                  final timestamp = _timestamp();
                                  final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                                  final toolName = entry['name'] ?? 'unknown';
                                  logFile.writeAsStringSync('[$timestamp] [Follow-up Event] ✓ Tool arguments complete: $toolName, args: ${args.substring(0, args.length > 100 ? 100 : args.length)}${args.length > 100 ? '...' : ''}\n', mode: FileMode.append);
                                } catch (_) {}
                              }
                            }
                          }
                        } else if (followUpType == 'response.completed') {
                          final u = followUpJson['response']?['usage'];
                          if (u != null) {
                            final inTok = (u['input_tokens'] ?? 0) as int;
                            final outTok = (u['output_tokens'] ?? 0) as int;
                            usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: inTok, completionTokens: outTok));
                            totalTokens = usage!.totalTokens;
                            try {
                              final timestamp = _timestamp();
                              final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                              logFile.writeAsStringSync('[$timestamp] [Follow-up Event] ✓ Response completed, tokens: input=$inTok, output=$outTok, total=$totalTokens\n', mode: FileMode.append);
                            } catch (_) {}
                          }
                        }
                      } catch (e) {
                        try {
                          final timestamp = _timestamp();
                          final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                          logFile.writeAsStringSync('[$timestamp] [Tool Loop] Parse error: $e\n', mode: FileMode.append);
                        } catch (_) {}
                      }
                    }
                  }

                  // Update current messages - 保存累积的文本内容
                  currentMessages.add({
                    'role': 'assistant',
                    'content': followUpContent, // 使用累积的文本而不是空字符串
                    '__toolCalls': toolCallMsgs.map((m) => {
                      'call_id': m['__callId'],
                      'name': m['__name'],
                      'arguments': jsonEncode(m['__args']),
                    }).toList(),
                    '__toolResults': toolOutputs,
                  });

                  try {
                    final timestamp = _timestamp();
                    final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                    logFile.writeAsStringSync('[$timestamp] [Tool Loop] After follow-up response:\n', mode: FileMode.append);
                    logFile.writeAsStringSync('[$timestamp] [Tool Loop]   - New toolAccResp count: ${toolAccResp.length}\n', mode: FileMode.append);
                    logFile.writeAsStringSync('[$timestamp] [Tool Loop]   - New toolAccResp: ${jsonEncode(toolAccResp)}\n', mode: FileMode.append);
                    logFile.writeAsStringSync('[$timestamp] [Tool Loop]   - Accumulated content length: ${followUpContent.length} chars\n', mode: FileMode.append);
                    logFile.writeAsStringSync('[$timestamp] [Tool Loop]   - Will continue loop: ${toolAccResp.isNotEmpty}\n', mode: FileMode.append);
                  } catch (_) {}

                  // Continue loop if there are more tool calls
                }

                try {
                  final timestamp = _timestamp();
                  final logFile = File('c:/mycode/start-kelivo/kelivo/debug_tools.log');
                  logFile.writeAsStringSync('[$timestamp] [Tool Loop] ========================================\n', mode: FileMode.append);
                  logFile.writeAsStringSync('[$timestamp] [Tool Loop] ✓ Exited loop, finishing stream\n', mode: FileMode.append);
                  logFile.writeAsStringSync('[$timestamp] [Tool Loop] ========================================\n', mode: FileMode.append);
                } catch (_) {}
              }
              final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
              yield ChatStreamChunk(
                content: '',
                reasoning: null,
                isDone: true,
                totalTokens: usage?.totalTokens ?? approxTotal,
                usage: usage,
              );
              return;
            } else {
              // Fallback for providers that inline output
              final output = json['output'];
              if (output != null) {
                content = (output['content'] ?? '').toString();
                approxCompletionChars += content.length;
                final u = json['usage'];
                if (u != null) {
                  final inTok = (u['input_tokens'] ?? 0) as int;
                  final outTok = (u['output_tokens'] ?? 0) as int;
                  usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: inTok, completionTokens: outTok));
                  totalTokens = usage!.totalTokens;
                }
              }
            }
          } else {
            // Handle standard OpenAI Chat Completions format
            final choices = json['choices'];
            if (choices != null && choices.isNotEmpty) {
              final c0 = choices[0];
              finishReason = c0['finish_reason'] as String?;
              // if (finishReason != null) {
              //   print('[ChatApi] Received finishReason from choices: $finishReason');
              // }

              // Some providers return non-streaming format (message.content) in SSE
              final message = c0['message'];
              final delta = c0['delta'];

              if (message != null && message['content'] != null) {
                // Non-streaming format: choices[0].message.content
                final mc = message['content'];
                if (mc is String) {
                  content = mc;
                } else if (mc is List) {
                  final sb = StringBuffer();
                  for (final it in mc) {
                    if (it is Map) {
                      final t = (it['text'] ?? '') as String? ?? '';
                      if (t.isNotEmpty && (it['type'] == null || it['type'] == 'text')) sb.write(t);
                    }
                  }
                  content = sb.toString();
                } else {
                  content = (mc ?? '').toString();
                }
                if (content.isNotEmpty) {
                  approxCompletionChars += content.length;
                }

                // Parse possible image outputs in message content, gated by model output capability
                if (wantsImageOutput && mc is List) {
                  final List<dynamic> imageItems = <dynamic>[];
                  for (final it in mc) {
                    if (it is Map && (it['type'] == 'image_url' || it['type'] == 'image')) imageItems.add(it);
                  }
                  if (imageItems.isNotEmpty) {
                    final buf = StringBuffer();
                    for (final it in imageItems) {
                      if (it is! Map) continue;
                      dynamic iu = it['image_url'];
                      String? url;
                      if (iu is String) {
                        url = iu;
                      } else if (iu is Map) {
                        final u2 = iu['url'];
                        if (u2 is String) url = u2;
                      }
                      if (url != null && url.isNotEmpty) buf.write('\n\n![image](' + url + ')');
                    }
                    if (buf.isNotEmpty) content = content + buf.toString();
                  }
                }
              } else if (delta != null) {
                // Streaming format: choices[0].delta.content
                // content may be string or list of parts
                final dc = delta['content'];
                if (dc is String) {
                  content = dc;
                } else if (dc is List) {
                  // collect text pieces
                  final sb = StringBuffer();
                  for (final it in dc) {
                    if (it is Map) {
                      final t = (it['text'] ?? it['delta'] ?? '') as String? ?? '';
                      if (t.isNotEmpty && (it['type'] == null || it['type'] == 'text')) sb.write(t);
                    }
                  }
                  content = sb.toString();
                } else {
                  content = (dc ?? '') as String;
                }
                if (content.isNotEmpty) {
                  approxCompletionChars += content.length;
                }
                final rc = (delta['reasoning_content'] ?? delta['reasoning']) as String?;
                if (rc != null && rc.isNotEmpty) reasoning = rc;

                // Parse possible image outputs in delta, gated by model output capability
                if (wantsImageOutput) {
                  final List<dynamic> imageItems = <dynamic>[];
                  final imgs = delta['images'];
                  if (imgs is List) imageItems.addAll(imgs);
                  if (dc is List) {
                    for (final it in dc) {
                      if (it is Map && (it['type'] == 'image_url' || it['type'] == 'image')) imageItems.add(it);
                    }
                  }
                  final singleImage = delta['image_url'];
                  if (singleImage is Map || singleImage is String) {
                    imageItems.add({'type': 'image_url', 'image_url': singleImage});
                  }
                  if (imageItems.isNotEmpty) {
                    final buf = StringBuffer();
                    for (final it in imageItems) {
                      if (it is! Map) continue;
                      dynamic iu = it['image_url'];
                      String? url;
                      if (iu is String) {
                        url = iu;
                      } else if (iu is Map) {
                        final u2 = iu['url'];
                        if (u2 is String) url = u2;
                      }
                      if (url != null && url.isNotEmpty) buf.write('\n\n![image](' + url + ')');
                    }
                    if (buf.isNotEmpty) content = content + buf.toString();
                  }
                }

                // Accumulate tool_calls deltas if present in delta
                final tcs = delta['tool_calls'] as List?;
                if (tcs != null) {
                  for (final t in tcs) {
                    final idx = (t['index'] as int?) ?? 0;
                    final id = t['id'] as String?;
                    final func = t['function'] as Map<String, dynamic>?;
                    final name = func?['name'] as String?;
                    final argsDelta = func?['arguments'] as String?;
                    
                    final entry = toolAcc.putIfAbsent(idx, () => {'id': '', 'name': '', 'args': ''});
                    if (id != null) entry['id'] = id;
                    if (name != null && name.isNotEmpty) entry['name'] = name;
                    if (argsDelta != null && argsDelta.isNotEmpty) entry['args'] = (entry['args'] ?? '') + argsDelta;
                  }
                }
              }
            }
            // XinLiu (iflow.cn) compatibility: tool_calls at root level instead of delta
            final rootToolCalls = json['tool_calls'] as List?;
            if (rootToolCalls != null) {
              // print('[ChatApi/XinLiu] Detected root-level tool_calls, count: ${rootToolCalls.length}, original finishReason: $finishReason');
              // print('[ChatApi/XinLiu] Full JSON keys: ${json.keys.toList()}');
              // print('[ChatApi/XinLiu] Full JSON: ${jsonEncode(json)}');
              for (final t in rootToolCalls) {
                if (t is! Map) continue;
                final id = (t['id'] ?? '').toString();
                final type = (t['type'] ?? 'function').toString();
                if (type != 'function') continue;
                final func = t['function'] as Map<String, dynamic>?;
                if (func == null) continue;
                final name = (func['name'] ?? '').toString();
                final argsStr = (func['arguments'] ?? '').toString();
                if (name.isEmpty) continue;
                // print('[ChatApi/XinLiu] Tool call: id=$id, name=$name, args=${argsStr.length} chars');
                final idx = toolAcc.length;
                final entry = toolAcc.putIfAbsent(idx, () => {'id': id.isEmpty ? 'call_$idx' : id, 'name': name, 'args': argsStr});
                if (id.isNotEmpty) entry['id'] = id;
                entry['name'] = name;
                entry['args'] = argsStr;
              }
              // When root-level tool_calls are present, always treat as tool_calls finish reason
              // (override any other finish_reason from provider)
              if (rootToolCalls.isNotEmpty) {
                // print('[ChatApi/XinLiu] Overriding finishReason from "$finishReason" to "tool_calls"');
                finishReason = 'tool_calls';
              }
            }
            final u = json['usage'];
            if (u != null) {
              var prompt = (u['prompt_tokens'] ?? 0) as int;
              final completion = (u['completion_tokens'] ?? 0) as int;
              final cached = (u['prompt_tokens_details']?['cached_tokens'] ?? 0) as int? ?? 0;
              // Fix: If API returns usage but prompt_tokens is 0, use approximation
              if (prompt == 0 && approxPromptTokens > 0) {
                prompt = approxPromptTokens;
              }
              usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: prompt, completionTokens: completion, cachedTokens: cached));
              totalTokens = usage!.totalTokens;
            }
          }

          if (content.isNotEmpty || (reasoning != null && reasoning!.isNotEmpty)) {
            final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
            yield ChatStreamChunk(
              content: content,
              reasoning: reasoning,
              isDone: false,
              totalTokens: totalTokens > 0 ? totalTokens : approxTotal,
              usage: usage,
            );
          }

          // Some providers (e.g., OpenRouter) may omit the [DONE] sentinel
          // and only send finish_reason on the last delta. If we see a
          // definitive finish that's not tool_calls, end the stream now so
          // the UI can persist the message.
          // XinLiu compatibility: Execute tools immediately if we have finish_reason='tool_calls' and accumulated calls
          if (config.useResponseApi != true && finishReason == 'tool_calls' && toolAcc.isNotEmpty && onToolCall != null) {
            // print('[ChatApi/XinLiu] Executing tools immediately (finishReason=tool_calls, toolAcc.size=${toolAcc.length})');
            // Some providers (like XinLiu) return tool_calls with finish_reason='tool_calls' but no [DONE]
            // Execute tools immediately in this case
            final calls = <Map<String, dynamic>>[];
            final callInfos = <ToolCallInfo>[];
            final toolMsgs = <Map<String, dynamic>>[];
            toolAcc.forEach((idx, m) {
              final id = (m['id'] ?? 'call_$idx');
              final name = (m['name'] ?? '');
              Map<String, dynamic> args;
              try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
              callInfos.add(ToolCallInfo(id: id, name: name, arguments: args));
              calls.add({
                'id': id,
                'type': 'function',
                'function': {
                  'name': name,
                  'arguments': jsonEncode(args),
                },
              });
              toolMsgs.add({'__name': name, '__id': id, '__args': args});
            });
            if (callInfos.isNotEmpty) {
              final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage, toolCalls: callInfos);
            }
            // Execute tools and emit results
            final results = <Map<String, dynamic>>[];
            final resultsInfo = <ToolResultInfo>[];
            for (final m in toolMsgs) {
              final name = m['__name'] as String;
              final id = m['__id'] as String;
              final args = (m['__args'] as Map<String, dynamic>);
              final res = await onToolCall(name, args) ?? '';
              results.add({'tool_call_id': id, 'content': res});
              resultsInfo.add(ToolResultInfo(id: id, name: name, arguments: args, content: res));
            }
            if (resultsInfo.isNotEmpty) {
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo);
            }
            // Build follow-up messages
            final mm2 = <Map<String, dynamic>>[];
            for (final m in messages) {
              mm2.add({'role': m['role'] ?? 'user', 'content': m['content'] ?? ''});
            }
            mm2.add({'role': 'assistant', 'content': '', 'tool_calls': calls});
            for (final r in results) {
              final id = r['tool_call_id'];
              final name = calls.firstWhere((c) => c['id'] == id, orElse: () => const {'function': {'name': ''}})['function']['name'];
              mm2.add({'role': 'tool', 'tool_call_id': id, 'name': name, 'content': r['content']});
            }
            // Continue streaming with follow-up request
            var currentMessages = mm2;
            while (true) {
              final body2 = {
                'model': upstreamModelId,
                'messages': currentMessages,
                'stream': true,
                if (temperature != null) 'temperature': temperature,
                if (topP != null) 'top_p': topP,
                if (maxTokens != null && maxTokens > 0) 'max_tokens': maxTokens,
                if (isReasoning && effort != 'off' && effort != 'auto') 'reasoning_effort': effort,
                if (tools != null && tools.isNotEmpty) 'tools': _cleanToolsForCompatibility(tools),
                if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
              };
              final off = _isOff(thinkingBudget);
              if (host.contains('openrouter.ai')) {
                if (isReasoning) {
                  if (off) {
                    body2['reasoning'] = {'enabled': false};
                  } else {
                    final obj = <String, dynamic>{'enabled': true};
                    if (thinkingBudget != null && thinkingBudget > 0) obj['max_tokens'] = thinkingBudget;
                    body2['reasoning'] = obj;
                  }
                  body2.remove('reasoning_effort');
                } else {
                  body2.remove('reasoning');
                  body2.remove('reasoning_effort');
                }
              } else if (host.contains('dashscope') || host.contains('aliyun')) {
                if (isReasoning) {
                  body2['enable_thinking'] = !off;
                  if (!off && thinkingBudget != null && thinkingBudget > 0) {
                    body2['thinking_budget'] = thinkingBudget;
                  } else {
                    body2.remove('thinking_budget');
                  }
                } else {
                  body2.remove('enable_thinking');
                  body2.remove('thinking_budget');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('ark.cn-beijing.volces.com') || host.contains('volc') || host.contains('ark')) {
                if (isReasoning) {
                  body2['thinking'] = {'type': off ? 'disabled' : 'enabled'};
                } else {
                  body2.remove('thinking');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('intern-ai') || host.contains('intern') || host.contains('chat.intern-ai.org.cn')) {
                if (isReasoning) {
                  body2['thinking_mode'] = !off;
                } else {
                  body2.remove('thinking_mode');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('siliconflow')) {
                if (isReasoning) {
                  if (off) {
                    body2['enable_thinking'] = false;
                  } else {
                    body2.remove('enable_thinking');
                  }
                } else {
                  body2.remove('enable_thinking');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('deepseek') || modelId.toLowerCase().contains('deepseek')) {
                if (isReasoning) {
                  if (off) {
                    body2['reasoning_content'] = false;
                    body2.remove('reasoning_budget');
                  } else {
                    body2['reasoning_content'] = true;
                    if (thinkingBudget != null && thinkingBudget > 0) {
                      body2['reasoning_budget'] = thinkingBudget;
                    } else {
                      body2.remove('reasoning_budget');
                    }
                  }
                } else {
                  body2.remove('reasoning_content');
                  body2.remove('reasoning_budget');
                }
              } else if (host.contains('opencode')) {
                // opencode.ai doesn't support reasoning_effort parameter
                body2.remove('reasoning_effort');
              } else if (_isGrokModel(config, modelId)) {
                // Grok 4 series doesn't support reasoning_effort parameter
                final isGrok3Mini = modelId.toLowerCase().contains('grok-3-mini');
                if (!isGrok3Mini) {
                  body2.remove('reasoning_effort');
                }
              }
              if (!host.contains('mistral.ai')) {
                body2['stream_options'] = {'include_usage': true};
              }
              if (extraBody != null && extraBody.isNotEmpty) {
                extraBody.forEach((k, v) {
                  body2[k] = (v is String) ? _parseOverrideValue(v) : v;
                });
              }

              final req2 = http.Request('POST', url);
              final headers2 = <String, String>{
                'Authorization': 'Bearer ${_effectiveApiKey(config)}',
                'Content-Type': 'application/json',
                'Accept': 'text/event-stream',
              };
              headers2.addAll(_customHeaders(config, modelId));
              if (extraHeaders != null && extraHeaders.isNotEmpty) headers2.addAll(extraHeaders);
              req2.headers.addAll(headers2);
              req2.body = jsonEncode(body2);

              final resp2 = await client.send(req2);
              if (resp2.statusCode < 200 || resp2.statusCode >= 300) {
                final errorBody = await resp2.stream.bytesToString();
                throw HttpException('HTTP ${resp2.statusCode}: $errorBody');
              }
              final s2 = resp2.stream.transform(utf8.decoder);
              String buf2 = '';
              final Map<int, Map<String, String>> toolAcc2 = <int, Map<String, String>>{};
              String? finishReason2;
              String contentAccum = '';
              await for (final ch in s2) {
                buf2 += ch;
                final lines2 = buf2.split('\n');
                buf2 = lines2.last;
                for (int j = 0; j < lines2.length - 1; j++) {
                  final l = lines2[j].trim();
                  if (l.isEmpty || !l.startsWith('data:')) continue;
                  final d = l.substring(5).trimLeft();
                  if (d == '[DONE]') {
                    continue;
                  }
                  try {
                    final o = jsonDecode(d);
                    if (o is Map && o['choices'] is List && (o['choices'] as List).isNotEmpty) {
                      final c0 = (o['choices'] as List).first;
                      finishReason2 = c0['finish_reason'] as String?;
                      final delta = c0['delta'] as Map?;
                      final txt = delta?['content'];
                      final rc = delta?['reasoning_content'] ?? delta?['reasoning'];
                      final u = o['usage'];
                      if (u != null) {
                        var prompt = (u['prompt_tokens'] ?? 0) as int;
                        final completion = (u['completion_tokens'] ?? 0) as int;
                        final cached = (u['prompt_tokens_details']?['cached_tokens'] ?? 0) as int? ?? 0;
                        // Fix: If API returns usage but prompt_tokens is 0, use approximation
                        if (prompt == 0 && approxPromptTokens > 0) {
                          prompt = approxPromptTokens;
                        }
                        usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: prompt, completionTokens: completion, cachedTokens: cached));
                        totalTokens = usage!.totalTokens;
                      }
                      // Capture Grok citations if present
                      if (_isGrokModel(config, modelId)) {
                        final citations = _extractGrokCitations(Map<String, dynamic>.from(o));
                        if (citations.isNotEmpty) {
                          yield ChatStreamChunk(
                            content: '',
                            isDone: false,
                            totalTokens: usage?.totalTokens ?? 0,
                            usage: usage,
                            toolResults: citations,
                          );
                        }
                      }
                      if (rc is String && rc.isNotEmpty) {
                        yield ChatStreamChunk(content: '', reasoning: rc, isDone: false, totalTokens: 0, usage: usage);
                      }
                      if (txt is String && txt.isNotEmpty) {
                        contentAccum += txt;
                        yield ChatStreamChunk(content: txt, isDone: false, totalTokens: 0, usage: usage);
                      }
                      if (wantsImageOutput) {
                        final List<dynamic> imageItems = <dynamic>[];
                        final imgs = delta?['images'];
                        if (imgs is List) imageItems.addAll(imgs);
                        final contentArr = (txt is List) ? txt : (delta?['content'] as List?);
                        if (contentArr is List) {
                          for (final it in contentArr) {
                            if (it is Map && (it['type'] == 'image_url' || it['type'] == 'image')) {
                              imageItems.add(it);
                            }
                          }
                        }
                        final singleImage = delta?['image_url'];
                        if (singleImage is Map || singleImage is String) {
                          imageItems.add({'type': 'image_url', 'image_url': singleImage});
                        }
                        if (imageItems.isNotEmpty) {
                          final buf = StringBuffer();
                          for (final it in imageItems) {
                            if (it is! Map) continue;
                            dynamic iu = it['image_url'];
                            String? url;
                            if (iu is String) {
                              url = iu;
                            } else if (iu is Map) {
                              final u2 = iu['url'];
                              if (u2 is String) url = u2;
                            }
                            if (url != null && url.isNotEmpty) {
                              final md = '\n\n![image](' + url + ')';
                              buf.write(md);
                              contentAccum += md;
                            }
                          }
                          final out = buf.toString();
                          if (out.isNotEmpty) {
                            yield ChatStreamChunk(content: out, isDone: false, totalTokens: 0, usage: usage);
                          }
                        }
                      }
                      final tcs = delta?['tool_calls'] as List?;
                      if (tcs != null) {
                        for (final t in tcs) {
                          final idx = (t['index'] as int?) ?? 0;
                          final id = t['id'] as String?;
                          final func = t['function'] as Map<String, dynamic>?;
                          final name = func?['name'] as String?;
                          final argsDelta = func?['arguments'] as String?;
                          final entry = toolAcc2.putIfAbsent(idx, () => {'id': '', 'name': '', 'args': ''});
                          if (id != null) entry['id'] = id;
                          if (name != null && name.isNotEmpty) entry['name'] = name;
                          if (argsDelta != null && argsDelta.isNotEmpty) entry['args'] = (entry['args'] ?? '') + argsDelta;
                        }
                      }
                    }
                    // XinLiu compatibility for follow-up requests too
                    final rootToolCalls2 = o['tool_calls'] as List?;
                    if (rootToolCalls2 != null) {
                      for (final t in rootToolCalls2) {
                        if (t is! Map) continue;
                        final id = (t['id'] ?? '').toString();
                        final type = (t['type'] ?? 'function').toString();
                        if (type != 'function') continue;
                        final func = t['function'] as Map<String, dynamic>?;
                        if (func == null) continue;
                        final name = (func['name'] ?? '').toString();
                        final argsStr = (func['arguments'] ?? '').toString();
                        if (name.isEmpty) continue;
                        final idx = toolAcc2.length;
                        final entry = toolAcc2.putIfAbsent(idx, () => {'id': id.isEmpty ? 'call_$idx' : id, 'name': name, 'args': argsStr});
                        if (id.isNotEmpty) entry['id'] = id;
                        entry['name'] = name;
                        entry['args'] = argsStr;
                      }
                      if (rootToolCalls2.isNotEmpty) {
                        finishReason2 = 'tool_calls';
                      }
                    }
                  } catch (_) {}
                }
              }
              if ((finishReason2 == 'tool_calls' || toolAcc2.isNotEmpty) && onToolCall != null) {
                final calls2 = <Map<String, dynamic>>[];
                final callInfos2 = <ToolCallInfo>[];
                final toolMsgs2 = <Map<String, dynamic>>[];
                toolAcc2.forEach((idx, m) {
                  final id = (m['id'] ?? 'call_$idx');
                  final name = (m['name'] ?? '');
                  Map<String, dynamic> args;
                  try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
                  callInfos2.add(ToolCallInfo(id: id, name: name, arguments: args));
                  calls2.add({'id': id, 'type': 'function', 'function': {'name': name, 'arguments': jsonEncode(args)}});
                  toolMsgs2.add({'__name': name, '__id': id, '__args': args});
                });
                if (callInfos2.isNotEmpty) {
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolCalls: callInfos2);
                }
                final results2 = <Map<String, dynamic>>[];
                final resultsInfo2 = <ToolResultInfo>[];
                for (final m in toolMsgs2) {
                  final name = m['__name'] as String;
                  final id = m['__id'] as String;
                  final args = (m['__args'] as Map<String, dynamic>);
                  final res = await onToolCall(name, args) ?? '';
                  results2.add({'tool_call_id': id, 'content': res});
                  resultsInfo2.add(ToolResultInfo(id: id, name: name, arguments: args, content: res));
                }
                if (resultsInfo2.isNotEmpty) {
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo2);
                }
                currentMessages = [
                  ...currentMessages,
                  if (contentAccum.isNotEmpty) {'role': 'assistant', 'content': contentAccum},
                  {'role': 'assistant', 'content': '', 'tool_calls': calls2},
                  for (final r in results2)
                    {
                      'role': 'tool',
                      'tool_call_id': r['tool_call_id'],
                      'name': calls2.firstWhere((c) => c['id'] == r['tool_call_id'], orElse: () => const {'function': {'name': ''}})['function']['name'],
                      'content': r['content'],
                    },
                ];
                continue;
              } else {
                final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
                yield ChatStreamChunk(content: '', isDone: true, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage);
                return;
              }
            }
          }
          // XinLiu compatibility: Don't end early if we have accumulated tool calls
          if (config.useResponseApi != true && finishReason != null && finishReason != 'tool_calls') {
            final bool hasPendingToolCalls = toolAcc.isNotEmpty || toolAccResp.isNotEmpty;
            if (hasPendingToolCalls) {
              // Some providers (like XinLiu/iflow.cn) may return tool_calls with finish_reason='stop'
              // and may not send a [DONE] marker. Execute tools immediately in this case.
              if (onToolCall != null && toolAcc.isNotEmpty) {
                final calls = <Map<String, dynamic>>[];
                final callInfos = <ToolCallInfo>[];
                final toolMsgs = <Map<String, dynamic>>[];
                toolAcc.forEach((idx, m) {
                  final id = (m['id'] ?? 'call_$idx');
                  final name = (m['name'] ?? '');
                  Map<String, dynamic> args;
                  try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
                  callInfos.add(ToolCallInfo(id: id, name: name, arguments: args));
                  calls.add({
                    'id': id,
                    'type': 'function',
                    'function': {
                      'name': name,
                      'arguments': jsonEncode(args),
                    },
                  });
                  toolMsgs.add({'__name': name, '__id': id, '__args': args});
                });
                if (callInfos.isNotEmpty) {
                  final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage, toolCalls: callInfos);
                }
                // Execute tools and emit results
                final results = <Map<String, dynamic>>[];
                final resultsInfo = <ToolResultInfo>[];
                for (final m in toolMsgs) {
                  final name = m['__name'] as String;
                  final id = m['__id'] as String;
                  final args = (m['__args'] as Map<String, dynamic>);
                  final res = await onToolCall(name, args) ?? '';
                  results.add({'tool_call_id': id, 'content': res});
                  resultsInfo.add(ToolResultInfo(id: id, name: name, arguments: args, content: res));
                }
                if (resultsInfo.isNotEmpty) {
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo);
                }
                // Build follow-up messages
                final mm2 = <Map<String, dynamic>>[];
                for (final m in messages) {
                  mm2.add({'role': m['role'] ?? 'user', 'content': m['content'] ?? ''});
                }
                mm2.add({'role': 'assistant', 'content': '', 'tool_calls': calls});
                for (final r in results) {
                  final id = r['tool_call_id'];
                  final name = calls.firstWhere((c) => c['id'] == id, orElse: () => const {'function': {'name': ''}})['function']['name'];
                  mm2.add({'role': 'tool', 'tool_call_id': id, 'name': name, 'content': r['content']});
                }
                // Continue streaming with follow-up request - reuse existing multi-round logic from [DONE] handler
                var currentMessages = mm2;
                while (true) {
                  final body2 = {
                    'model': upstreamModelId,
                    'messages': currentMessages,
                    'stream': true,
                    if (temperature != null) 'temperature': temperature,
                    if (topP != null) 'top_p': topP,
                    if (maxTokens != null && maxTokens > 0) 'max_tokens': maxTokens,
                    if (isReasoning && effort != 'off' && effort != 'auto') 'reasoning_effort': effort,
                    if (tools != null && tools.isNotEmpty) 'tools': _cleanToolsForCompatibility(tools),
                    if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
                  };
                  final off = _isOff(thinkingBudget);
                  if (host.contains('openrouter.ai')) {
                    if (isReasoning) {
                      if (off) {
                        body2['reasoning'] = {'enabled': false};
                      } else {
                        final obj = <String, dynamic>{'enabled': true};
                        if (thinkingBudget != null && thinkingBudget > 0) obj['max_tokens'] = thinkingBudget;
                        body2['reasoning'] = obj;
                      }
                      body2.remove('reasoning_effort');
                    } else {
                      body2.remove('reasoning');
                      body2.remove('reasoning_effort');
                    }
                  } else if (host.contains('dashscope') || host.contains('aliyun')) {
                    if (isReasoning) {
                      body2['enable_thinking'] = !off;
                      if (!off && thinkingBudget != null && thinkingBudget > 0) {
                        body2['thinking_budget'] = thinkingBudget;
                      } else {
                        body2.remove('thinking_budget');
                      }
                    } else {
                      body2.remove('enable_thinking');
                      body2.remove('thinking_budget');
                    }
                    body2.remove('reasoning_effort');
                  } else if (host.contains('ark.cn-beijing.volces.com') || host.contains('volc') || host.contains('ark')) {
                    if (isReasoning) {
                      body2['thinking'] = {'type': off ? 'disabled' : 'enabled'};
                    } else {
                      body2.remove('thinking');
                    }
                    body2.remove('reasoning_effort');
                  } else if (host.contains('intern-ai') || host.contains('intern') || host.contains('chat.intern-ai.org.cn')) {
                    if (isReasoning) {
                      body2['thinking_mode'] = !off;
                    } else {
                      body2.remove('thinking_mode');
                    }
                    body2.remove('reasoning_effort');
                  } else if (host.contains('siliconflow')) {
                    if (isReasoning) {
                      if (off) {
                        body2['enable_thinking'] = false;
                      } else {
                        body2.remove('enable_thinking');
                      }
                    } else {
                      body2.remove('enable_thinking');
                    }
                    body2.remove('reasoning_effort');
                  } else if (host.contains('deepseek') || modelId.toLowerCase().contains('deepseek')) {
                    if (isReasoning) {
                      if (off) {
                        body2['reasoning_content'] = false;
                        body2.remove('reasoning_budget');
                      } else {
                        body2['reasoning_content'] = true;
                        if (thinkingBudget != null && thinkingBudget > 0) {
                          body2['reasoning_budget'] = thinkingBudget;
                        } else {
                          body2.remove('reasoning_budget');
                        }
                      }
                    } else {
                      body2.remove('reasoning_content');
                      body2.remove('reasoning_budget');
                    }
                  } else if (host.contains('opencode')) {
                    // opencode.ai doesn't support reasoning_effort parameter
                    body2.remove('reasoning_effort');
                  } else if (_isGrokModel(config, modelId)) {
                    // Grok 4 series doesn't support reasoning_effort parameter
                    final isGrok3Mini = modelId.toLowerCase().contains('grok-3-mini');
                    if (!isGrok3Mini) {
                      body2.remove('reasoning_effort');
                    }
                  }
                  if (!host.contains('mistral.ai')) {
                    body2['stream_options'] = {'include_usage': true};
                  }
                  if (extraBody != null && extraBody.isNotEmpty) {
                    extraBody.forEach((k, v) {
                      body2[k] = (v is String) ? _parseOverrideValue(v) : v;
                    });
                  }
                  final req2 = http.Request('POST', url);
                  final headers2 = <String, String>{
                    'Authorization': 'Bearer ${_effectiveApiKey(config)}',
                    'Content-Type': 'application/json',
                    'Accept': 'text/event-stream',
                  };
                  headers2.addAll(_customHeaders(config, modelId));
                  if (extraHeaders != null && extraHeaders.isNotEmpty) headers2.addAll(extraHeaders);
                  req2.headers.addAll(headers2);
                  req2.body = jsonEncode(body2);
                  final resp2 = await client.send(req2);
                  if (resp2.statusCode < 200 || resp2.statusCode >= 300) {
                    final errorBody = await resp2.stream.bytesToString();
                    throw HttpException('HTTP ${resp2.statusCode}: $errorBody');
                  }
                  final s2 = resp2.stream.transform(utf8.decoder);
                  String buf2 = '';
                  final Map<int, Map<String, String>> toolAcc2 = <int, Map<String, String>>{};
                  String? finishReason2;
                  String contentAccum = '';
                  await for (final ch in s2) {
                    buf2 += ch;
                    final lines2 = buf2.split('\n');
                    buf2 = lines2.last;
                    for (int j = 0; j < lines2.length - 1; j++) {
                      final l = lines2[j].trim();
                      if (l.isEmpty || !l.startsWith('data:')) continue;
                      final d = l.substring(5).trimLeft();
                      if (d == '[DONE]') {
                        continue;
                      }
                      try {
                        final o = jsonDecode(d);
                        if (o is Map && o['choices'] is List && (o['choices'] as List).isNotEmpty) {
                          final c0 = (o['choices'] as List).first;
                          finishReason2 = c0['finish_reason'] as String?;
                          final delta = c0['delta'] as Map?;
                          final txt = delta?['content'];
                          final rc = delta?['reasoning_content'] ?? delta?['reasoning'];
                          final u = o['usage'];
                          if (u != null) {
                            var prompt = (u['prompt_tokens'] ?? 0) as int;
                            final completion = (u['completion_tokens'] ?? 0) as int;
                            final cached = (u['prompt_tokens_details']?['cached_tokens'] ?? 0) as int? ?? 0;
                            // Fix: If API returns usage but prompt_tokens is 0, use approximation
                            if (prompt == 0 && approxPromptTokens > 0) {
                              prompt = approxPromptTokens;
                            }
                            usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: prompt, completionTokens: completion, cachedTokens: cached));
                            totalTokens = usage!.totalTokens;
                          }
                          // Capture Grok citations if present
                          if (_isGrokModel(config, modelId)) {
                            final citations = _extractGrokCitations(Map<String, dynamic>.from(o));
                            if (citations.isNotEmpty) {
                              yield ChatStreamChunk(
                                content: '',
                                isDone: false,
                                totalTokens: usage?.totalTokens ?? 0,
                                usage: usage,
                                toolResults: citations,
                              );
                            }
                          }
                          if (rc is String && rc.isNotEmpty) {
                            yield ChatStreamChunk(content: '', reasoning: rc, isDone: false, totalTokens: 0, usage: usage);
                          }
                          if (txt is String && txt.isNotEmpty) {
                            contentAccum += txt;
                            yield ChatStreamChunk(content: txt, isDone: false, totalTokens: 0, usage: usage);
                          }
                          if (wantsImageOutput) {
                            final List<dynamic> imageItems = <dynamic>[];
                            final imgs = delta?['images'];
                            if (imgs is List) imageItems.addAll(imgs);
                            final contentArr = (txt is List) ? txt : (delta?['content'] as List?);
                            if (contentArr is List) {
                              for (final it in contentArr) {
                                if (it is Map && (it['type'] == 'image_url' || it['type'] == 'image')) {
                                  imageItems.add(it);
                                }
                              }
                            }
                            final singleImage = delta?['image_url'];
                            if (singleImage is Map || singleImage is String) {
                              imageItems.add({'type': 'image_url', 'image_url': singleImage});
                            }
                            if (imageItems.isNotEmpty) {
                              final buf = StringBuffer();
                              for (final it in imageItems) {
                                if (it is! Map) continue;
                                dynamic iu = it['image_url'];
                                String? url;
                                if (iu is String) {
                                  url = iu;
                                } else if (iu is Map) {
                                  final u2 = iu['url'];
                                  if (u2 is String) url = u2;
                                }
                                if (url != null && url.isNotEmpty) {
                                  final md = '\n\n![image](' + url + ')';
                                  buf.write(md);
                                  contentAccum += md;
                                }
                              }
                              final out = buf.toString();
                              if (out.isNotEmpty) {
                                yield ChatStreamChunk(content: out, isDone: false, totalTokens: 0, usage: usage);
                              }
                            }
                          }
                          final tcs = delta?['tool_calls'] as List?;
                          if (tcs != null) {
                            for (final t in tcs) {
                              final idx = (t['index'] as int?) ?? 0;
                              final id = t['id'] as String?;
                              final func = t['function'] as Map<String, dynamic>?;
                              final name = func?['name'] as String?;
                              final argsDelta = func?['arguments'] as String?;
                              final entry = toolAcc2.putIfAbsent(idx, () => {'id': '', 'name': '', 'args': ''});
                              if (id != null) entry['id'] = id;
                              if (name != null && name.isNotEmpty) entry['name'] = name;
                              if (argsDelta != null && argsDelta.isNotEmpty) entry['args'] = (entry['args'] ?? '') + argsDelta;
                            }
                          }
                        }
                        // XinLiu compatibility for follow-up requests too
                        final rootToolCalls2 = o['tool_calls'] as List?;
                        if (rootToolCalls2 != null) {
                          for (final t in rootToolCalls2) {
                            if (t is! Map) continue;
                            final id = (t['id'] ?? '').toString();
                            final type = (t['type'] ?? 'function').toString();
                            if (type != 'function') continue;
                            final func = t['function'] as Map<String, dynamic>?;
                            if (func == null) continue;
                            final name = (func['name'] ?? '').toString();
                            final argsStr = (func['arguments'] ?? '').toString();
                            if (name.isEmpty) continue;
                            final idx = toolAcc2.length;
                            final entry = toolAcc2.putIfAbsent(idx, () => {'id': id.isEmpty ? 'call_$idx' : id, 'name': name, 'args': argsStr});
                            if (id.isNotEmpty) entry['id'] = id;
                            entry['name'] = name;
                            entry['args'] = argsStr;
                          }
                          if (rootToolCalls2.isNotEmpty && finishReason2 == null) {
                            finishReason2 = 'tool_calls';
                          }
                        }
                      } catch (_) {}
                    }
                  }
                  if ((finishReason2 == 'tool_calls' || toolAcc2.isNotEmpty) && onToolCall != null) {
                    final calls2 = <Map<String, dynamic>>[];
                    final callInfos2 = <ToolCallInfo>[];
                    final toolMsgs2 = <Map<String, dynamic>>[];
                    toolAcc2.forEach((idx, m) {
                      final id = (m['id'] ?? 'call_$idx');
                      final name = (m['name'] ?? '');
                      Map<String, dynamic> args;
                      try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
                      callInfos2.add(ToolCallInfo(id: id, name: name, arguments: args));
                      calls2.add({'id': id, 'type': 'function', 'function': {'name': name, 'arguments': jsonEncode(args)}});
                      toolMsgs2.add({'__name': name, '__id': id, '__args': args});
                    });
                    if (callInfos2.isNotEmpty) {
                      yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolCalls: callInfos2);
                    }
                    final results2 = <Map<String, dynamic>>[];
                    final resultsInfo2 = <ToolResultInfo>[];
                    for (final m in toolMsgs2) {
                      final name = m['__name'] as String;
                      final id = m['__id'] as String;
                      final args = (m['__args'] as Map<String, dynamic>);
                      final res = await onToolCall(name, args) ?? '';
                      results2.add({'tool_call_id': id, 'content': res});
                      resultsInfo2.add(ToolResultInfo(id: id, name: name, arguments: args, content: res));
                    }
                    if (resultsInfo2.isNotEmpty) {
                      yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo2);
                    }
                    currentMessages = [
                      ...currentMessages,
                      if (contentAccum.isNotEmpty) {'role': 'assistant', 'content': contentAccum},
                      {'role': 'assistant', 'content': '', 'tool_calls': calls2},
                      for (final r in results2)
                        {
                          'role': 'tool',
                          'tool_call_id': r['tool_call_id'],
                          'name': calls2.firstWhere((c) => c['id'] == r['tool_call_id'], orElse: () => const {'function': {'name': ''}})['function']['name'],
                          'content': r['content'],
                        },
                    ];
                    continue;
                  } else {
                    final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
                    yield ChatStreamChunk(content: '', isDone: true, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage);
                    return;
                  }
                }
              }
            } else if (host.contains('openrouter.ai')) {
            } else {
              // final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
              // yield ChatStreamChunk(
              //   content: '',
              //   isDone: false,
              //   totalTokens: usage?.totalTokens ?? approxTotal,
              //   usage: usage,
              // );
              // return;
            }
          }

          // If model finished with tool_calls, execute them and follow-up
          if (false && config.useResponseApi != true && finishReason == 'tool_calls' && onToolCall != null) {
            // Build messages for follow-up
            final calls = <Map<String, dynamic>>[];
            // Emit UI tool call placeholders
            final callInfos = <ToolCallInfo>[];
            final toolMsgs = <Map<String, dynamic>>[];
            toolAcc.forEach((idx, m) {
              final id = (m['id'] ?? 'call_$idx');
              final name = (m['name'] ?? '');
              Map<String, dynamic> args;
              try {
                args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>();
              } catch (_) {
                args = <String, dynamic>{};
              }
              callInfos.add(ToolCallInfo(id: id, name: name, arguments: args));
              calls.add({
                'id': id,
                'type': 'function',
                'function': {
                  'name': name,
                  'arguments': jsonEncode(args),
                },
              });
              toolMsgs.add({'__name': name, '__id': id, '__args': args});
            });

            if (callInfos.isNotEmpty) {
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolCalls: callInfos);
            }

            // Execute tools
            final results = <Map<String, dynamic>>[];
            final resultsInfo = <ToolResultInfo>[];
            for (final m in toolMsgs) {
              final name = m['__name'] as String;
              final id = m['__id'] as String;
              final args = (m['__args'] as Map<String, dynamic>);
              final res = await onToolCall(name, args) ?? '';
              results.add({'tool_call_id': id, 'content': res});
              resultsInfo.add(ToolResultInfo(id: id, name: name, arguments: args, content: res));
            }

            if (resultsInfo.isNotEmpty) {
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo);
            }

            // Follow-up request with assistant tool_calls + tool messages
            final mm2 = <Map<String, dynamic>>[];
            for (final m in messages) {
              mm2.add({'role': m['role'] ?? 'user', 'content': m['content'] ?? ''});
            }
            mm2.add({'role': 'assistant', 'content': '', 'tool_calls': calls});
            for (final r in results) {
              final id = r['tool_call_id'];
              final name = calls.firstWhere((c) => c['id'] == id, orElse: () => const {'function': {'name': ''}})['function']['name'];
              mm2.add({'role': 'tool', 'tool_call_id': id, 'name': name, 'content': r['content']});
            }

            final body2 = {
              'model': upstreamModelId,
              'messages': mm2,
              'stream': true,
              if (tools != null && tools.isNotEmpty) 'tools': _cleanToolsForCompatibility(tools),
              if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
            };

            final request2 = http.Request('POST', url);
            request2.headers.addAll({
              'Authorization': 'Bearer ${_apiKeyForRequest(config, modelId)}',
              'Content-Type': 'application/json',
              'Accept': 'text/event-stream',
            });
            request2.body = jsonEncode(body2);
            final resp2 = await client.send(request2);
            if (resp2.statusCode < 200 || resp2.statusCode >= 300) {
              final errorBody = await resp2.stream.bytesToString();
              throw HttpException('HTTP ${resp2.statusCode}: $errorBody');
            }
            final s2 = resp2.stream.transform(utf8.decoder);
            String buf2 = '';
            await for (final ch in s2) {
              buf2 += ch;
              final lines2 = buf2.split('\n');
              buf2 = lines2.last;
              for (int j = 0; j < lines2.length - 1; j++) {
                final l = lines2[j].trim();
                if (l.isEmpty || !l.startsWith('data:')) continue;
                final d = l.substring(5).trimLeft();
                if (d == '[DONE]') {
                  yield ChatStreamChunk(content: '', isDone: true, totalTokens: usage?.totalTokens ?? 0, usage: usage);
                  return;
                }
                try {
                  final o = jsonDecode(d);
                  if (o is Map && o['choices'] is List && (o['choices'] as List).isNotEmpty) {
                    final delta = (o['choices'] as List).first['delta'] as Map?;
                    final txt = delta?['content'];
                    final rc = delta?['reasoning_content'] ?? delta?['reasoning'];
                    if (rc is String && rc.isNotEmpty) {
                      yield ChatStreamChunk(content: '', reasoning: rc, isDone: false, totalTokens: 0, usage: usage);
                    }
                    if (txt is String && txt.isNotEmpty) {
                      yield ChatStreamChunk(content: txt, isDone: false, totalTokens: 0, usage: usage);
                    }
                  }
                } catch (_) {}
              }
            }
            return;
          }
        } catch (e) {
          // Skip malformed JSON
        }
      }
    }

    // 记录完整响应总结
    try {
      final timestamp = _timestamp();
      final logFile = File('c:/mycode/kelivo/debug_api.log');
      final separator = '=' * 80;

      logFile.writeAsStringSync('\n[$timestamp] RESPONSE SUMMARY\n', mode: FileMode.append);
      logFile.writeAsStringSync('$separator\n', mode: FileMode.append);
      logFile.writeAsStringSync('Total Chunks Received: ${responseChunks.length}\n', mode: FileMode.append);
      logFile.writeAsStringSync('Total Tokens: ${usage?.totalTokens ?? 0}\n', mode: FileMode.append);
      if (usage != null) {
        logFile.writeAsStringSync('Prompt Tokens: ${usage.promptTokens}\n', mode: FileMode.append);
        logFile.writeAsStringSync('Completion Tokens: ${usage.completionTokens}\n', mode: FileMode.append);
        if (usage.cachedTokens > 0) {
          logFile.writeAsStringSync('Cached Tokens: ${usage.cachedTokens}\n', mode: FileMode.append);
        }
      }
      logFile.writeAsStringSync('Finish Reason: ${finishReason ?? "N/A"}\n', mode: FileMode.append);
      logFile.writeAsStringSync('$separator\n\n', mode: FileMode.append);
    } catch (e) {
      // 日志写入失败,静默继续
    }

    // Fallback: provider closed SSE without sending [DONE]
    yield ChatStreamChunk(content: '', isDone: true, totalTokens: usage?.totalTokens ?? 0, usage: usage);
  }

  static Stream<ChatStreamChunk> _sendClaudeStream(
      http.Client client,
      ProviderConfig config,
      String modelId,
      List<Map<String, dynamic>> messages,
      {List<String>? userImagePaths, int? thinkingBudget, double? temperature, double? topP, int? maxTokens, int maxToolLoopIterations = 10, List<Map<String, dynamic>>? tools, Future<String> Function(String, Map<String, dynamic>)? onToolCall, Map<String, String>? extraHeaders, Map<String, dynamic>? extraBody}
      ) async* {
    final upstreamModelId = _apiModelId(config, modelId);
    final base = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final url = Uri.parse('$base/messages');

    final isReasoning = _effectiveModelInfo(config, modelId)
        .abilities
        .contains(ModelAbility.reasoning);

    // Extract system prompt (Anthropic uses top-level `system`, not a `system` role)
    String systemPrompt = '';
    final nonSystemMessages = <Map<String, dynamic>>[];
    for (final m in messages) {
      final role = (m['role'] ?? '').toString();
      if (role == 'system') {
        final s = (m['content'] ?? '').toString();
        if (s.isNotEmpty) {
          systemPrompt = systemPrompt.isEmpty ? s : (systemPrompt + '\n\n' + s);
        }
        continue; // skip adding to messages array
      }
      nonSystemMessages.add({'role': role.isEmpty ? 'user' : role, 'content': m['content'] ?? ''});
    }

    // Transform last user message to include images per Anthropic schema
    final transformed = <Map<String, dynamic>>[];
    for (int i = 0; i < nonSystemMessages.length; i++) {
      final m = nonSystemMessages[i];
      final isLast = i == nonSystemMessages.length - 1;
      if (isLast && (userImagePaths?.isNotEmpty == true) && (m['role'] == 'user')) {
        final parts = <Map<String, dynamic>>[];
        final text = (m['content'] ?? '').toString();
        if (text.isNotEmpty) parts.add({'type': 'text', 'text': text});
        for (final p in userImagePaths!) {
          if (p.startsWith('http') || p.startsWith('data:')) {
            // Fallback: include link as text
            parts.add({'type': 'text', 'text': p});
          } else {
            final mime = _mimeFromPath(p);
            final b64 = await _encodeBase64File(p, withPrefix: false);
            parts.add({
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': mime,
                'data': b64,
              }
            });
          }
        }
        transformed.add({'role': 'user', 'content': parts});
      } else {
        transformed.add({'role': m['role'] ?? 'user', 'content': m['content'] ?? ''});
      }
    }

    // Map OpenAI-style tools to Anthropic custom tools if provided
    List<Map<String, dynamic>>? anthropicTools;
    if (tools != null && tools.isNotEmpty) {
      anthropicTools = [];
      for (final t in tools) {
        final fn = (t['function'] as Map<String, dynamic>?);
        if (fn == null) continue; // skip non-function entries here (server tools handled below)
        final name = (fn['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final desc = (fn['description'] ?? '').toString();
        final params = (fn['parameters'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{'type': 'object'};
        anthropicTools.add({
          'name': name,
          if (desc.isNotEmpty) 'description': desc,
          'input_schema': params,
        });
      }
    }

    // Collect final tools list: custom tools + pass-through server tool entries + built-in web_search if enabled
    final List<Map<String, dynamic>> allTools = [];
    if (anthropicTools != null && anthropicTools.isNotEmpty) allTools.addAll(anthropicTools);
    // Pass-through server tools provided directly by caller (e.g., web_search_20250305)
    if (tools != null && tools.isNotEmpty) {
      for (final t in tools) {
        if (t is Map && t['type'] is String && (t['type'] as String).startsWith('web_search_')) {
          allTools.add(t);
        }
      }
    }
    // Enable Claude built-in web search via per-model override "builtInTools": ["search"]
    final builtIns = _builtInTools(config, modelId);
    if (builtIns.contains('search')) {
      // Optional parameters can be supplied via modelOverrides[modelId]['webSearch'] map
      Map<String, dynamic> ws = const <String, dynamic>{};
      try {
        final ov = config.modelOverrides[modelId];
        if (ov is Map && ov['webSearch'] is Map) {
          ws = (ov['webSearch'] as Map).cast<String, dynamic>();
        }
      } catch (_) {}
      final entry = <String, dynamic>{
        'type': 'web_search_20250305',
        'name': 'web_search',
      };
      // Copy supported optional fields if present and valid
      if (ws['max_uses'] is int && (ws['max_uses'] as int) > 0) entry['max_uses'] = ws['max_uses'];
      if (ws['allowed_domains'] is List) entry['allowed_domains'] = List<String>.from((ws['allowed_domains'] as List).map((e) => e.toString()));
      if (ws['blocked_domains'] is List) entry['blocked_domains'] = List<String>.from((ws['blocked_domains'] as List).map((e) => e.toString()));
      if (ws['user_location'] is Map) entry['user_location'] = (ws['user_location'] as Map).cast<String, dynamic>();
      allTools.add(entry);
    }

    final body = <String, dynamic>{
      'model': upstreamModelId,
      'max_tokens': maxTokens ?? 4096,
      'messages': transformed,
      'stream': true,
      if (systemPrompt.isNotEmpty) 'system': systemPrompt,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'top_p': topP,
      if (allTools.isNotEmpty) 'tools': allTools,
      if (allTools.isNotEmpty) 'tool_choice': {'type': 'auto'},
      if (isReasoning)
        'thinking': {
          'type': (thinkingBudget == 0) ? 'disabled' : 'enabled',
          if (thinkingBudget != null && thinkingBudget > 0)
            'budget_tokens': thinkingBudget,
        },
    };

    final request = http.Request('POST', url);
    final headers = <String, String>{
      'x-api-key': _effectiveApiKey(config),
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };
    headers.addAll(_customHeaders(config, modelId));
    if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
    request.headers.addAll(headers);
    final extraClaude = _customBody(config, modelId);
    if (extraClaude.isNotEmpty) (body as Map<String, dynamic>).addAll(extraClaude);
    if (extraBody != null && extraBody.isNotEmpty) {
      extraBody.forEach((k, v) {
        (body as Map<String, dynamic>)[k] = (v is String) ? ChatApiHelper.parseOverrideValue(v) : v;
      });
    }
    request.body = jsonEncode(body);

    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await response.stream.bytesToString();
      throw HttpException('HTTP ${response.statusCode}: $errorBody');
    }

    final stream = response.stream.transform(utf8.decoder);
    String buffer = '';
    int totalTokens = 0;
    TokenUsage? usage;

    // Accumulate tool_use inputs by id (client tools)
    final Map<String, Map<String, dynamic>> _anthToolUse = <String, Map<String, dynamic>>{}; // id -> {name, argsStr}
    // Track server tool use (web_search) input JSON by block index/id
    final Map<int, String> _srvIndexToId = <int, String>{};
    final Map<String, String> _srvArgsStr = <String, String>{}; // id -> raw partial_json concatenated
    final Map<String, Map<String, dynamic>> _srvArgs = <String, Map<String, dynamic>>{}; // id -> parsed args

    await for (final chunk in stream) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.last;

      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i].trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;

        final data = line.substring(5).trimLeft();
        try {
          final json = jsonDecode(data);
          final type = json['type'];

          if (type == 'content_block_delta') {
            final delta = json['delta'];
            if (delta != null) {
              if (delta['type'] == 'text_delta') {
                final content = delta['text'] ?? '';
                if (content is String && content.isNotEmpty) {
                  yield ChatStreamChunk(
                    content: content,
                    isDone: false,
                    totalTokens: totalTokens,
                  );
                }
              } else if (delta['type'] == 'thinking_delta') {
                final thinking = (delta['thinking'] ?? delta['text'] ?? '') as String;
                if (thinking.isNotEmpty) {
                  yield ChatStreamChunk(
                    content: '',
                    reasoning: thinking,
                    isDone: false,
                    totalTokens: totalTokens,
                  );
                }
              } else if (delta['type'] == 'tool_use_delta') {
                final id = (json['content_block']?['id'] ?? json['id'] ?? '').toString();
                if (id.isNotEmpty) {
                  final entry = _anthToolUse.putIfAbsent(id, () => {'name': (json['content_block']?['name'] ?? '').toString(), 'args': ''});
                  final argsDelta = (delta['partial_json'] ?? delta['input'] ?? delta['text'] ?? '').toString();
                  if (argsDelta.isNotEmpty) entry['args'] = (entry['args'] ?? '') + argsDelta;
                }
              } else if (delta['type'] == 'input_json_delta') {
                // Server tool (web_search) input streamed as JSON
                final idx = json['index'];
                final index = (idx is int) ? idx : int.tryParse((idx ?? '').toString());
                if (index != null && _srvIndexToId.containsKey(index)) {
                  final id = _srvIndexToId[index]!;
                  final part = (delta['partial_json'] ?? '').toString();
                  if (part.isNotEmpty) {
                    _srvArgsStr[id] = (_srvArgsStr[id] ?? '') + part;
                  }
                }
              }
            }
          } else if (type == 'content_block_start') {
            // Start of tool_use block: we can pre-register name/id
            final cb = json['content_block'];
            if (cb is Map && (cb['type'] == 'tool_use')) {
              final id = (cb['id'] ?? '').toString();
              final name = (cb['name'] ?? '').toString();
              if (id.isNotEmpty) {
                _anthToolUse.putIfAbsent(id, () => {'name': name, 'args': ''});
              }
            } else if (cb is Map && (cb['type'] == 'server_tool_use')) {
              // Record mapping index -> id so we can attach input_json_delta fragments
              final id = (cb['id'] ?? '').toString();
              final idx = (json['index'] is int) ? json['index'] as int : int.tryParse((json['index'] ?? '').toString()) ?? -1;
              if (id.isNotEmpty && idx >= 0) {
                _srvIndexToId[idx] = id;
                _srvArgsStr[id] = '';
              }
            } else if (cb is Map && (cb['type'] == 'web_search_tool_result')) {
              // Emit a tool result for web_search with simplified items list for UI
              final toolUseId = (cb['tool_use_id'] ?? '').toString();
              final contentBlock = cb['content'];
              final items = <Map<String, dynamic>>[];
              String? errorCode;
              if (contentBlock is List) {
                for (int i = 0; i < contentBlock.length; i++) {
                  final it = contentBlock[i];
                  if (it is Map && (it['type'] == 'web_search_result')) {
                    items.add({
                      'index': i + 1,
                      'title': (it['title'] ?? '').toString(),
                      'url': (it['url'] ?? '').toString(),
                      if ((it['page_age'] ?? '').toString().isNotEmpty) 'page_age': (it['page_age'] ?? '').toString(),
                    });
                  }
                }
              } else if (contentBlock is Map && (contentBlock['type'] == 'web_search_tool_result_error')) {
                errorCode = (contentBlock['error_code'] ?? '').toString();
              }
              Map<String, dynamic> args = const <String, dynamic>{};
              if (_srvArgs.containsKey(toolUseId)) args = _srvArgs[toolUseId]!;
              // Use toolName 'search_web' for UI consistency
              final payload = jsonEncode({
                'items': items,
                if ((errorCode ?? '').isNotEmpty) 'error': errorCode,
              });
              yield ChatStreamChunk(
                content: '',
                isDone: false,
                totalTokens: totalTokens,
                usage: usage,
                toolResults: [ToolResultInfo(id: toolUseId.isEmpty ? 'builtin_search' : toolUseId, name: 'search_web', arguments: args, content: payload)],
              );
            }
          } else if (type == 'content_block_stop') {
            // Finalize tool_use and emit tool call + result
            final id = (json['content_block']?['id'] ?? json['id'] ?? '').toString();
            if (id.isNotEmpty && _anthToolUse.containsKey(id)) {
              final name = (_anthToolUse[id]!['name'] ?? '').toString();
              Map<String, dynamic> args;
              try { args = (jsonDecode((_anthToolUse[id]!['args'] ?? '{}') as String) as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
              // Emit placeholder
              final calls = [ToolCallInfo(id: id, name: name, arguments: args)];
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, toolCalls: calls, usage: usage);
              // Execute tool and emit result
              if (onToolCall != null) {
                final res = await onToolCall(name, args) ?? '';
                final results = [ToolResultInfo(id: id, name: name, arguments: args, content: res)];
                yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, toolResults: results, usage: usage);
              }
            } else {
              // Possibly end of server_tool_use: map by index
              final idx = (json['index'] is int) ? json['index'] as int : int.tryParse((json['index'] ?? '').toString());
              if (idx != null && _srvIndexToId.containsKey(idx)) {
                final sid = _srvIndexToId[idx]!;
                Map<String, dynamic> args;
                try { args = (jsonDecode((_srvArgsStr[sid] ?? '{}')) as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
                _srvArgs[sid] = args;
                // Emit a placeholder tool call for UI with name 'search_web'
                yield ChatStreamChunk(
                  content: '',
                  isDone: false,
                  totalTokens: totalTokens,
                  usage: usage,
                  toolCalls: [ToolCallInfo(id: sid, name: 'search_web', arguments: args)],
                );
              }
            }
          } else if (type == 'message_stop') {
            yield ChatStreamChunk(
              content: '',
              isDone: true,
              totalTokens: totalTokens,
              usage: usage,
            );
            return;
          } else if (type == 'message_delta') {
            final u = json['usage'] ?? json['message']?['usage'];
            if (u != null) {
              final inTok = (u['input_tokens'] ?? 0) as int;
              final outTok = (u['output_tokens'] ?? 0) as int;
              usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: inTok, completionTokens: outTok));
              totalTokens = usage!.totalTokens;
            }
          }
        } catch (e) {
          // Skip malformed JSON
        }
      }
    }
  }

  static Stream<ChatStreamChunk> _sendGoogleStream(
      http.Client client,
      ProviderConfig config,
      String modelId,
      List<Map<String, dynamic>> messages,
      {List<String>? userImagePaths, int? thinkingBudget, double? temperature, double? topP, int? maxTokens, int maxToolLoopIterations = 10, List<Map<String, dynamic>>? tools, Future<String> Function(String name, Map<String, dynamic> args)? onToolCall, Map<String, String>? extraHeaders, Map<String, dynamic>? extraBody}
      ) async* {
    final upstreamModelId = _apiModelId(config, modelId);
    // Implement SSE streaming via :streamGenerateContent with alt=sse
    // Build endpoint per Vertex vs Gemini
    String baseUrl;
    if (config.vertexAI == true && (config.location?.isNotEmpty == true) && (config.projectId?.isNotEmpty == true)) {
      final loc = config.location!.trim();
      final proj = config.projectId!.trim();
      baseUrl = 'https://aiplatform.googleapis.com/v1/projects/$proj/locations/$loc/publishers/google/models/$upstreamModelId:streamGenerateContent';
    } else {
      final base = config.baseUrl.endsWith('/')
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      baseUrl = '$base/models/$upstreamModelId:streamGenerateContent';
    }

    // Build query with key (for non-Vertex) and alt=sse
    final uriBase = Uri.parse(baseUrl);
    final qp = Map<String, String>.from(uriBase.queryParameters);
    if (!(config.vertexAI == true)) {
      final eff = _effectiveApiKey(config);
      if (eff.isNotEmpty) qp['key'] = eff;
    }
    qp['alt'] = 'sse';
    final uri = uriBase.replace(queryParameters: qp);

    // Convert messages to Google contents format
    final contents = <Map<String, dynamic>>[];
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final role = msg['role'] == 'assistant' ? 'model' : 'user';
      final isLast = i == messages.length - 1;
      final parts = <Map<String, dynamic>>[];
      final raw = (msg['content'] ?? '').toString();

      // Only parse images if there are images to process
      final hasMarkdownImages = raw.contains('![') && raw.contains('](');
      final hasCustomImages = raw.contains('[image:');
      final hasAttachedImages = isLast && role == 'user' && (userImagePaths?.isNotEmpty == true);

      if (hasMarkdownImages || hasCustomImages || hasAttachedImages) {
        final parsed = _parseTextAndImages(raw);
        if (parsed.text.isNotEmpty) parts.add({'text': parsed.text});
        // Images extracted from this message's text
        for (final ref in parsed.images) {
          if (ref.kind == 'data') {
            final mime = _mimeFromDataUrl(ref.src);
            final idx = ref.src.indexOf('base64,');
            if (idx > 0) {
              final b64 = ref.src.substring(idx + 7);
              parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
            } else {
              // If malformed data URL, include as plain text fallback
              parts.add({'text': ref.src});
            }
          } else if (ref.kind == 'path') {
            final mime = _mimeFromPath(ref.src);
            final b64 = await _encodeBase64File(ref.src, withPrefix: false);
            parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
          } else {
            // Remote URL: Gemini official API doesn't fetch http(s) here; keep short reference
            parts.add({'text': '(image) ${ref.src}'});
          }
        }
        if (hasAttachedImages) {
          for (final p in userImagePaths!) {
            if (p.startsWith('data:')) {
              final mime = _mimeFromDataUrl(p);
              final idx = p.indexOf('base64,');
              if (idx > 0) {
                final b64 = p.substring(idx + 7);
                parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
              }
            } else if (!(p.startsWith('http://') || p.startsWith('https://'))) {
              final mime = _mimeFromPath(p);
              final b64 = await _encodeBase64File(p, withPrefix: false);
              parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
            } else {
              // http url fallback reference text
              parts.add({'text': '(image) ${p}'});
            }
          }
        }
      } else {
        // No images, use simple text content
        if (raw.isNotEmpty) parts.add({'text': raw});
      }
      contents.add({'role': role, 'parts': parts});
    }

    // Effective model features (includes user overrides)
    final effective = _effectiveModelInfo(config, modelId);
    final isReasoning = effective.abilities.contains(ModelAbility.reasoning);
    final wantsImageOutput = effective.output.contains(Modality.image);
    bool _expectImage = wantsImageOutput;
    bool _receivedImage = false;
    final off = _isOff(thinkingBudget);
    // Built-in Gemini tools (only for official Gemini API)
    final builtIns = _builtInTools(config, modelId);
    final isOfficialGemini = config.vertexAI != true; // requirement: only Gemini official API
    final builtInToolEntries = <Map<String, dynamic>>[];
    if (isOfficialGemini && builtIns.isNotEmpty) {
      if (builtIns.contains('search')) {
        builtInToolEntries.add({'google_search': {}});
      }
      if (builtIns.contains('url_context')) {
        builtInToolEntries.add({'url_context': {}});
      }
    }

    // Map OpenAI-style tools to Gemini functionDeclarations (skip if built-in tools are enabled, as they are not compatible)
    List<Map<String, dynamic>>? geminiTools;
    if (builtInToolEntries.isEmpty && tools != null && tools.isNotEmpty) {
      final decls = <Map<String, dynamic>>[];
      for (final t in tools) {
        final fn = (t['function'] as Map<String, dynamic>?);
        if (fn == null) continue;
        final name = (fn['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final desc = (fn['description'] ?? '').toString();
        final params = (fn['parameters'] as Map?)?.cast<String, dynamic>();
        final d = <String, dynamic>{'name': name, if (desc.isNotEmpty) 'description': desc};
        if (params != null) {
          // Google Gemini requires strict JSON Schema compliance
          // Fix array properties that are missing 'items' field
          final cleanedParams = _cleanSchemaForGemini(params);
          d['parameters'] = cleanedParams;
        }
        decls.add(d);
      }
      if (decls.isNotEmpty) geminiTools = [{'function_declarations': decls}];
    }

    // Maintain a rolling conversation for multi-round tool calls
    List<Map<String, dynamic>> convo = List<Map<String, dynamic>>.from(contents);
    TokenUsage? usage;
    int totalTokens = 0;

    // Accumulate built-in search citations across stream rounds
    final List<Map<String, dynamic>> _builtinCitations = <Map<String, dynamic>>[];

    List<Map<String, dynamic>> _parseCitations(dynamic gm) {
      final out = <Map<String, dynamic>>[];
      if (gm is! Map) return out;
      final chunks = gm['groundingChunks'] as List? ?? const <dynamic>[];
      int idx = 1;
      final seen = <String>{};
      for (final ch in chunks) {
        if (ch is! Map) continue;
        final web = ch['web'] as Map? ?? ch['webSite'] as Map? ?? ch['webPage'] as Map?;
        if (web is! Map) continue;
        final uri = (web['uri'] ?? web['url'] ?? '').toString();
        if (uri.isEmpty) continue;
        // Deduplicate by uri
        if (seen.contains(uri)) continue;
        seen.add(uri);
        final title = (web['title'] ?? web['name'] ?? uri).toString();
        final id = 'c${idx.toString().padLeft(2, '0')}';
        out.add({'id': id, 'index': idx, 'title': title, 'url': uri});
        idx++;
      }
      return out;
    }

    while (true) {
      final gen = <String, dynamic>{
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'topP': topP,
        if (maxTokens != null && maxTokens > 0) 'maxOutputTokens': maxTokens,
        // Enable IMAGE+TEXT output modalities when model is configured to output images
        if (wantsImageOutput) 'responseModalities': ['TEXT', 'IMAGE'],
        if (isReasoning)
          'thinkingConfig': {
            'includeThoughts': off ? false : true,
            if (!off && thinkingBudget != null && thinkingBudget >= 0)
              'thinkingBudget': thinkingBudget,
          },
      };
      final body = <String, dynamic>{
        'contents': convo,
        if (gen.isNotEmpty) 'generationConfig': gen,
        // Prefer built-in tools when configured; otherwise map function tools
        if (builtInToolEntries.isNotEmpty) 'tools': builtInToolEntries,
        if (builtInToolEntries.isEmpty && geminiTools != null && geminiTools.isNotEmpty) 'tools': geminiTools,
      };

      final request = http.Request('POST', uri);
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      };
      if (config.vertexAI == true) {
        final token = await _maybeVertexAccessToken(config);
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
        final proj = (config.projectId ?? '').trim();
        if (proj.isNotEmpty) headers['X-Goog-User-Project'] = proj;
      }
      headers.addAll(_customHeaders(config, modelId));
      if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
      request.headers.addAll(headers);
      final extra = _customBody(config, modelId);
      if (extra.isNotEmpty) (body as Map<String, dynamic>).addAll(extra);
      if (extraBody != null && extraBody.isNotEmpty) {
        extraBody.forEach((k, v) {
          (body as Map<String, dynamic>)[k] = (v is String) ? ChatApiHelper.parseOverrideValue(v) : v;
        });
      }
      
      // DEBUG LOG: Print full request body for ALL Google requests to debug 400 error
      print('DEBUG [Google] Request URL: $uri');
      print('DEBUG [Google] Request Body: ${jsonEncode(body)}');

      request.body = jsonEncode(body);

      final resp = await client.send(request);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final errorBody = await resp.stream.bytesToString();
        throw HttpException('HTTP ${resp.statusCode}: $errorBody');
      }

      final stream = resp.stream.transform(utf8.decoder);
      String buffer = '';
      // Collect any function calls in this round
      final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[]; // {id,name,args,res}
      
      // Track a streaming inline image (append base64 progressively)
      bool _imageOpen = false; // true after we emit the data URL prefix
      String _imageMime = 'image/png';

      await for (final chunk in stream) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.last; // keep incomplete line

        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim(); // after 'data:'
          if (data.isEmpty) continue;
          try {
            final obj = jsonDecode(data) as Map<String, dynamic>;
            final um = obj['usageMetadata'];
            if (um is Map<String, dynamic>) {
              final thoughtTokens = (um['thoughtsTokenCount'] ?? 0) as int;
              final candidateTokens = (um['candidatesTokenCount'] ?? 0) as int;
              usage = (usage ?? const TokenUsage()).merge(TokenUsage(
                promptTokens: (um['promptTokenCount'] ?? 0) as int,
                completionTokens: candidateTokens + thoughtTokens, // Include thought tokens in completion
                thoughtTokens: thoughtTokens,
                totalTokens: (um['totalTokenCount'] ?? 0) as int,
              ));
              totalTokens = usage!.totalTokens;
            }

            final candidates = obj['candidates'];
            if (candidates is List && candidates.isNotEmpty) {
              String textDelta = '';
              String reasoningDelta = '';
              String? finishReason; // detect stream completion from server
              for (final cand in candidates) {
                if (cand is! Map) continue;
                final content = cand['content'];
                if (content is! Map) continue;
                final parts = content['parts'];
                if (parts is! List) continue;
                for (final p in parts) {
                  if (p is! Map) continue;
                  final t = (p['text'] ?? '') as String? ?? '';
                  final thought = p['thought'] as bool? ?? false;
                  if (t.isNotEmpty) {
                    if (thought) {
                      reasoningDelta += t;
                    } else {
                      textDelta += t;
                    }
                  }
                  // Parse inline image data from Gemini (inlineData)
                  // Response shape: { inlineData: { mimeType: 'image/png', data: '...base64...' } }
                  final inline = (p['inlineData'] ?? p['inline_data']);
                  if (inline is Map) {
                    final mime = (inline['mimeType'] ?? inline['mime_type'] ?? 'image/png').toString();
                    final data = (inline['data'] ?? '').toString();
                    if (data.isNotEmpty) {
                      _imageMime = mime.isNotEmpty ? mime : 'image/png';
                      if (!_imageOpen) {
                        textDelta += '\n\n![image](data:${_imageMime};base64,';
                        _imageOpen = true;
                      }
                      textDelta += data;
                      _receivedImage = true;
                    }
                  }
                  
                  // Parse fileData: { fileUri: 'https://...', mimeType: 'image/png' }
                  final fileData = (p['fileData'] ?? p['file_data']);
                  if (fileData is Map) {
                    final mime = (fileData['mimeType'] ?? fileData['mime_type'] ?? 'image/png').toString();
                    final uri = (fileData['fileUri'] ?? fileData['file_uri'] ?? fileData['uri'] ?? '').toString();
                    if (uri.startsWith('http')) {
                      try {
                        final b64 = await _downloadRemoteAsBase64(client, config, uri);
                        _imageMime = mime.isNotEmpty ? mime : 'image/png';
                        if (!_imageOpen) {
                          textDelta += '\n\n![image](data:${_imageMime};base64,';
                          _imageOpen = true;
                        }
                        textDelta += b64;
                        _receivedImage = true;
                      } catch (_) {}
                    }
                  }
                  final fc = p['functionCall'];
                  if (fc is Map) {
                    final name = (fc['name'] ?? '').toString();
                    Map<String, dynamic> args = const <String, dynamic>{};
                    final rawArgs = fc['args'];
                    if (rawArgs is Map) {
                      args = rawArgs.cast<String, dynamic>();
                    } else if (rawArgs is String && rawArgs.isNotEmpty) {
                      try { args = (jsonDecode(rawArgs) as Map).cast<String, dynamic>(); } catch (_) {}
                    }
                    
                    // Capture thought signature (Gemini 3 Pro requirement)
                    // Preserve exact key/value as received from functionCall object
                    String? thoughtSigKey;
                    dynamic thoughtSigVal;
                    if (fc.containsKey('thoughtSignature')) {
                      thoughtSigKey = 'thoughtSignature';
                      thoughtSigVal = fc['thoughtSignature'];
                    } else if (fc.containsKey('thought_signature')) {
                      thoughtSigKey = 'thought_signature';
                      thoughtSigVal = fc['thought_signature'];
                    }
                    
                    final id = 'call_${DateTime.now().microsecondsSinceEpoch}';
                    // Emit placeholder immediately
                    yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, usage: usage, toolCalls: [ToolCallInfo(id: id, name: name, arguments: args)]);
                    String resText = '';
                    if (onToolCall != null) {
                      resText = await onToolCall(name, args) ?? '';
                      yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, usage: usage, toolResults: [ToolResultInfo(id: id, name: name, arguments: args, content: resText)]);
                    }
                    calls.add({
                      'id': id,
                      'name': name,
                      'args': args,
                      'result': resText,
                      'thoughtSigKey': thoughtSigKey,
                      'thoughtSigVal': thoughtSigVal,
                    });
                  }
                }
                // Capture explicit finish reason if present
                final fr = cand['finishReason'];
                if (fr is String && fr.isNotEmpty) finishReason = fr;

                // Parse grounding metadata for citations if present
                final gm = cand['groundingMetadata'] ?? obj['groundingMetadata'];
                final cite = _parseCitations(gm);
                if (cite.isNotEmpty) {
                  // merge unique by url
                  final existingUrls = _builtinCitations.map((e) => e['url']?.toString() ?? '').toSet();
                  for (final it in cite) {
                    final u = it['url']?.toString() ?? '';
                    if (u.isEmpty || existingUrls.contains(u)) continue;
                    _builtinCitations.add(it);
                    existingUrls.add(u);
                  }
                  // emit a tool result chunk so UI can render citations card
                  final payload = jsonEncode({'items': _builtinCitations});
                  yield ChatStreamChunk(
                    content: '',
                    isDone: false,
                    totalTokens: totalTokens,
                    usage: usage,
                    toolResults: [ToolResultInfo(id: 'builtin_search', name: 'builtin_search', arguments: const <String, dynamic>{}, content: payload)],
                  );
                }
              }

              if (reasoningDelta.isNotEmpty) {
                yield ChatStreamChunk(content: '', reasoning: reasoningDelta, isDone: false, totalTokens: totalTokens, usage: usage);
              }
              if (textDelta.isNotEmpty) {
                yield ChatStreamChunk(content: textDelta, isDone: false, totalTokens: totalTokens, usage: usage);
              }

              // If server signaled finish, close image markdown and end stream immediately
              if (finishReason != null && calls.isEmpty && (!_expectImage || _receivedImage)) {
                if (_imageOpen) {
                  yield ChatStreamChunk(content: ')', isDone: false, totalTokens: totalTokens, usage: usage);
                  _imageOpen = false;
                }
                // Emit final citations if any not emitted
                if (_builtinCitations.isNotEmpty) {
                  final payload = jsonEncode({'items': _builtinCitations});
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, usage: usage, toolResults: [ToolResultInfo(id: 'builtin_search', name: 'builtin_search', arguments: const <String, dynamic>{}, content: payload)]);
                }
                yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
                return;
              }
            }
          } catch (_) {
            // ignore malformed chunk
          }
        }
      }

      // If we streamed an inline image but never closed the markdown, close it now
      if (_imageOpen) {
        yield ChatStreamChunk(content: ')', isDone: false, totalTokens: totalTokens, usage: usage);
        _imageOpen = false;
      }

      if (calls.isEmpty) {
        // No tool calls; this round finished
        if (_imageOpen) {
          yield ChatStreamChunk(content: ')', isDone: false, totalTokens: totalTokens, usage: usage);
          _imageOpen = false;
        }
        yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
        return;
      }

      // Append model functionCall(s) and user functionResponse(s) to conversation, then loop
      for (final c in calls) {
         final name = (c['name'] ?? '').toString();
         final args = (c['args'] as Map<String, dynamic>? ?? const <String, dynamic>{});
         final resText = (c['result'] ?? '').toString();
         final thoughtSigKey = c['thoughtSigKey'] as String?;
         final thoughtSigVal = c['thoughtSigVal'];
         
         // Build the model's functionCall turn with optional thought signature
         final functionCallObj = <String, dynamic>{
           'name': name,
           'args': args,
         };
         if (thoughtSigKey != null && thoughtSigVal != null) {
           functionCallObj[thoughtSigKey] = thoughtSigVal;
         }
         
         convo.add({'role': 'model', 'parts': [{'functionCall': functionCallObj}]});
         
         Map<String, dynamic> responseObj;
         try {
           responseObj = (jsonDecode(resText) as Map).cast<String, dynamic>();
         } catch (_) {
           responseObj = {'result': resText};
         }
         convo.add({'role': 'user', 'parts': [{'functionResponse': {'name': name, 'response': responseObj}}]});
      }

      // Continue while(true) for next round
    }
  }

  static Future<String> _downloadRemoteAsBase64(http.Client client, ProviderConfig config, String url) async {
    final req = http.Request('GET', Uri.parse(url));
    // Add Vertex auth if enabled
    if (config.vertexAI == true) {
      try {
        final token = await _maybeVertexAccessToken(config);
        if (token != null && token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
      } catch (_) {}
      final proj = (config.projectId ?? '').trim();
      if (proj.isNotEmpty) req.headers['X-Goog-User-Project'] = proj;
    }
    final resp = await client.send(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final err = await resp.stream.bytesToString();
      throw HttpException('HTTP ${resp.statusCode}: $err');
    }
    final bytes = await resp.stream.fold<List<int>>(<int>[], (acc, b) { acc.addAll(b); return acc; });
    return base64Encode(bytes);
  }
  // Returns OAuth token for Vertex AI when serviceAccountJson is configured; otherwise null.
  static Future<String?> _maybeVertexAccessToken(ProviderConfig cfg) async {
    if (cfg.vertexAI == true) {
      final jsonStr = (cfg.serviceAccountJson ?? '').trim();
      if (jsonStr.isEmpty) {
        // Fallback: some users may paste a temporary OAuth token into apiKey
        if (cfg.apiKey.isNotEmpty) return cfg.apiKey;
        return null;
      }
      try {
        return await GoogleServiceAccountAuth.getAccessTokenFromJson(jsonStr);
      } catch (_) {
        // On failure, do not crash streaming; let server return 401 and surface error upstream
        return null;
      }
    }
    return null;
  }
}

class _ImageRef {
  final String kind; // 'data' | 'path' | 'url'
  final String src;
  const _ImageRef(this.kind, this.src);
}

class _ParsedTextAndImages {
  final String text;
  final List<_ImageRef> images;
  const _ParsedTextAndImages(this.text, this.images);
}

class ChatStreamChunk {
  final String content;
  // Optional reasoning delta (when model supports reasoning)
  final String? reasoning;
  final bool isDone;
  final int totalTokens;
  final TokenUsage? usage;
  final List<ToolCallInfo>? toolCalls;
  final List<ToolResultInfo>? toolResults;

  ChatStreamChunk({
    required this.content,
    this.reasoning,
    required this.isDone,
    required this.totalTokens,
    this.usage,
    this.toolCalls,
    this.toolResults,
  });
}

class ToolCallInfo {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  ToolCallInfo({required this.id, required this.name, required this.arguments});
}

class ToolResultInfo {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String content;
  ToolResultInfo({required this.id, required this.name, required this.arguments, required this.content});
}
