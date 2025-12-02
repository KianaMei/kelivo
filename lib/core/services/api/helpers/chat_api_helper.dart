/// Chat API Helper - Configuration and utility methods for provider adapters.
/// Extracted from ChatApiService for Phase 2A modularization.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/model_provider.dart';
import '../../../models/token_usage.dart';
import '../../../../utils/sandbox_path_resolver.dart';
import '../../api_key_manager.dart';
import 'package:kelivo/secrets/fallback.dart';
import '../models/chat_stream_chunk.dart';
import '../../../utils/http_logger.dart';

export '../models/chat_stream_chunk.dart';

/// Helper class containing shared utilities for all provider adapters.
class ChatApiHelper {
  ChatApiHelper._();

  // ========== Model ID Resolution ==========

  /// Resolve the upstream/vendor model id for a given logical model key.
  /// When per-instance overrides specify `apiModelId`, that value is used for
  /// outbound HTTP requests and vendor-specific heuristics.
  static String apiModelId(ProviderConfig cfg, String modelId) {
    try {
      final ov = cfg.modelOverrides[modelId];
      if (ov is Map<String, dynamic>) {
        final raw = (ov['apiModelId'] ?? ov['api_model_id'])?.toString().trim();
        if (raw != null && raw.isNotEmpty) return raw;
      }
    } catch (_) {}
    return modelId;
  }

  // ========== API Key Management ==========

  /// Get effective API key, considering multi-key rotation.
  static String effectiveApiKey(ProviderConfig cfg) {
    try {
      if (cfg.multiKeyEnabled == true && (cfg.apiKeys?.isNotEmpty == true)) {
        final sel = ApiKeyManager().selectForProvider(cfg);
        if (sel.key != null) return sel.key!.key;
      }
    } catch (_) {}
    return cfg.apiKey;
  }

  /// Get API key for request, with fallback support for specific providers.
  static String apiKeyForRequest(ProviderConfig cfg, String modelId) {
    final orig = effectiveApiKey(cfg).trim();
    if (orig.isNotEmpty) return orig;
    if ((cfg.id) == 'SiliconFlow') {
      final host = Uri.tryParse(cfg.baseUrl)?.host.toLowerCase() ?? '';
      if (!host.contains('siliconflow')) return orig;
      final m = apiModelId(cfg, modelId).toLowerCase();
      final allowed = m == 'thudm/glm-4-9b-0414' || m == 'qwen/qwen3-8b';
      final fallback = siliconflowFallbackKey.trim();
      if (allowed && fallback.isNotEmpty) {
        return fallback;
      }
    }
    return orig;
  }

  // ========== Model Overrides ==========

  /// Read built-in tools configured per model (e.g., ['search', 'url_context']).
  static Set<String> builtInTools(ProviderConfig cfg, String modelId) {
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

  /// Get per-model override map.
  static Map<String, dynamic> modelOverride(ProviderConfig cfg, String modelId) {
    final ov = cfg.modelOverrides[modelId];
    if (ov is Map<String, dynamic>) return ov;
    return const <String, dynamic>{};
  }

  /// Get custom headers from model overrides.
  static Map<String, String> customHeaders(ProviderConfig cfg, String modelId) {
    final ov = modelOverride(cfg, modelId);
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

  /// Get custom body parameters from model overrides.
  static Map<String, dynamic> customBody(ProviderConfig cfg, String modelId) {
    final ov = modelOverride(cfg, modelId);
    final list = (ov['body'] as List?) ?? const <dynamic>[];
    final out = <String, dynamic>{};
    for (final e in list) {
      if (e is Map) {
        final key = (e['key'] ?? e['name'] ?? '').toString().trim();
        final val = (e['value'] ?? '').toString();
        if (key.isNotEmpty) out[key] = parseOverrideValue(val);
      }
    }
    return out;
  }

  /// Parse override value string to appropriate type.
  static dynamic parseOverrideValue(String v) {
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

  // ========== Model Info ==========

  /// Resolve effective model info by respecting per-model overrides.
  static ModelInfo effectiveModelInfo(ProviderConfig cfg, String modelId) {
    final upstreamId = apiModelId(cfg, modelId);
    final base = ModelRegistry.infer(ModelInfo(id: upstreamId, displayName: upstreamId));
    final ov = modelOverride(cfg, modelId);
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

  // ========== Grok Detection ==========

  /// Detect if a model is a Grok model (xAI).
  static bool isGrokModel(ProviderConfig cfg, String modelId) {
    final apiModel = apiModelId(cfg, modelId).toLowerCase();
    final logicalModel = modelId.toLowerCase();
    final grokPatterns = ['grok', 'xai-'];
    for (final pattern in grokPatterns) {
      if (apiModel.contains(pattern) || logicalModel.contains(pattern)) {
        return true;
      }
    }
    return false;
  }

  /// Extract domain name from URL.
  static String extractDomainFromUrl(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) {
        return uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
      }
    } catch (_) {}
    return url;
  }

  /// Extract and format Grok search citations from API response.
  static List<ToolResultInfo> extractGrokCitations(Map<String, dynamic> response) {
    try {
      final citations = response['citations'];
      if (citations is! List || citations.isEmpty) return [];

      final items = <Map<String, dynamic>>[];
      for (int i = 0; i < citations.length; i++) {
        final citation = citations[i];
        if (citation is String) {
          items.add({
            'index': i + 1,
            'url': citation,
            'title': extractDomainFromUrl(citation),
          });
        } else if (citation is Map) {
          final url = (citation['url'] ?? citation['link'] ?? '').toString();
          if (url.isEmpty) continue;
          items.add({
            'index': i + 1,
            'url': url,
            'title': citation['title']?.toString() ?? extractDomainFromUrl(url),
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
      return [];
    }
  }

  // ========== MIME Type Helpers ==========

  /// Get MIME type from file path.
  static String mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/png';
  }

  /// Get MIME type from data URL.
  static String mimeFromDataUrl(String dataUrl) {
    try {
      final start = dataUrl.indexOf(':');
      final semi = dataUrl.indexOf(';');
      if (start >= 0 && semi > start) {
        return dataUrl.substring(start + 1, semi);
      }
    } catch (_) {}
    return 'image/png';
  }

  // ========== File Encoding ==========

  /// Encode file to base64.
  static Future<String> encodeBase64File(String path, {bool withPrefix = false}) async {
    final fixed = SandboxPathResolver.fix(path);
    final file = File(fixed);
    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);
    if (withPrefix) {
      final mime = mimeFromPath(fixed);
      return 'data:$mime;base64,$b64';
    }
    return b64;
  }

  // ========== Text and Image Parsing ==========

  /// Parse text content and extract embedded image references.
  static ParsedTextAndImages parseTextAndImages(String raw) {
    if (raw.isEmpty) return const ParsedTextAndImages('', <ImageRef>[]);
    final mdImg = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');
    final customImg = RegExp(r"\[image:(.+?)\]");
    final images = <ImageRef>[];
    final buf = StringBuffer();
    int i = 0;
    while (i < raw.length) {
      final m1 = mdImg.matchAsPrefix(raw, i);
      final m2 = customImg.matchAsPrefix(raw, i);
      if (m1 != null) {
        final url = (m1.group(1) ?? '').trim();
        if (url.isNotEmpty) {
          if (url.startsWith('data:')) {
            images.add(ImageRef(ImageRefType.data, url));
          } else if (url.startsWith('http://') || url.startsWith('https://')) {
            images.add(ImageRef(ImageRefType.url, url));
          } else {
            images.add(ImageRef(ImageRefType.path, url));
          }
        }
        i = m1.end;
        continue;
      }
      if (m2 != null) {
        final p = (m2.group(1) ?? '').trim();
        if (p.isNotEmpty) images.add(ImageRef(ImageRefType.path, p));
        i = m2.end;
        continue;
      }
      buf.write(raw[i]);
      i++;
    }
    return ParsedTextAndImages(buf.toString().trim(), images);
  }

  // ========== HTTP Client ==========

  /// Create HTTP client with proxy and SSL settings.
  static http.Client clientFor(ProviderConfig cfg) {
    final enabled = cfg.proxyEnabled == true;
    final host = (cfg.proxyHost ?? '').trim();
    final portStr = (cfg.proxyPort ?? '').trim();
    final user = (cfg.proxyUsername ?? '').trim();
    final pass = (cfg.proxyPassword ?? '').trim();
    final allowInsecure = cfg.allowInsecureConnection == true;

    if (enabled || allowInsecure) {
      final io = HttpClient();

      if (allowInsecure) {
        io.badCertificateCallback = (cert, host, port) => true;
      }

      if (enabled && host.isNotEmpty && portStr.isNotEmpty) {
        final port = int.tryParse(portStr) ?? 0;
        if (port > 0) {
          io.findProxy = (uri) => 'PROXY $host:$port';
          if (user.isNotEmpty && pass.isNotEmpty) {
            io.addProxyCredentials(
              host,
              port,
              'Basic',
              HttpClientBasicCredentials(user, pass),
            );
          }
        }
      }
      return TalkerHttpClient(IOClient(io));
    }
    return TalkerHttpClient(http.Client());
  }

  // ========== Timestamp ==========

  /// Generate UTC+8 timestamp string.
  static String timestamp() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  // ========== Reasoning Budget ==========

  /// Check if reasoning is disabled based on budget.
  static bool isReasoningOff(int? budget) => (budget != null && budget != -1 && budget < 1024);

  /// Get OpenRouter effort level for budget.
  static String effortForBudget(int? budget) {
    if (budget == null || budget == -1) return 'auto';
    if (isReasoningOff(budget)) return 'off';
    if (budget <= 2000) return 'low';
    if (budget <= 20000) return 'medium';
    return 'high';
  }

  // ========== Schema Cleaning ==========

  /// Clean JSON Schema for Google Gemini API strict validation.
  static Map<String, dynamic> cleanSchemaForGemini(Map<String, dynamic> schema) {
    final result = Map<String, dynamic>.from(schema);
    if (result['properties'] is Map) {
      final props = Map<String, dynamic>.from(result['properties'] as Map);
      props.forEach((key, value) {
        if (value is Map) {
          final propMap = Map<String, dynamic>.from(value as Map);
          if (propMap['type'] == 'array' && !propMap.containsKey('items')) {
            propMap['items'] = {'type': 'string'};
          }
          if (propMap['type'] == 'object' && propMap.containsKey('properties')) {
            propMap['properties'] = cleanSchemaForGemini({'properties': propMap['properties']})['properties'];
          }
          props[key] = propMap;
        }
      });
      result['properties'] = props;
    }
    if (result['items'] is Map) {
      result['items'] = cleanSchemaForGemini(result['items'] as Map<String, dynamic>);
    }
    return result;
  }

  /// Clean OpenAI-format tools for strict backends.
  static List<Map<String, dynamic>> cleanToolsForCompatibility(List<Map<String, dynamic>> tools) {
    return tools.map((tool) {
      final result = Map<String, dynamic>.from(tool);
      final fn = result['function'];
      if (fn is Map) {
        final fnMap = Map<String, dynamic>.from(fn as Map);
        final params = fnMap['parameters'];
        if (params is Map) {
          fnMap['parameters'] = cleanSchemaForGemini(params as Map<String, dynamic>);
        }
        result['function'] = fnMap;
      }
      return result;
    }).toList();
  }

  // ========== Vendor-Specific Reasoning Config ==========

  /// Apply vendor-specific reasoning parameters to request body.
  /// Returns the modified body map.
  static void applyVendorReasoningConfig({
    required Map<String, dynamic> body,
    required String host,
    required String modelId,
    required bool isReasoning,
    required int? thinkingBudget,
    required String effort,
    required bool isGrokModel,
  }) {
    final off = isReasoningOff(thinkingBudget);
    
    if (host.contains('openrouter.ai')) {
      if (isReasoning) {
        if (off) {
          body['reasoning'] = {'enabled': false};
        } else {
          final obj = <String, dynamic>{'enabled': true};
          if (thinkingBudget != null && thinkingBudget > 0) obj['max_tokens'] = thinkingBudget;
          body['reasoning'] = obj;
        }
        body.remove('reasoning_effort');
      } else {
        body.remove('reasoning');
        body.remove('reasoning_effort');
      }
    } else if (host.contains('dashscope') || host.contains('aliyun')) {
      if (isReasoning) {
        body['enable_thinking'] = !off;
        if (!off && thinkingBudget != null && thinkingBudget > 0) {
          body['thinking_budget'] = thinkingBudget;
        } else {
          body.remove('thinking_budget');
        }
      } else {
        body.remove('enable_thinking');
        body.remove('thinking_budget');
      }
      body.remove('reasoning_effort');
    } else if (host.contains('ark.cn-beijing.volces.com') || host.contains('volc') || host.contains('ark')) {
      if (isReasoning) {
        body['thinking'] = {'type': off ? 'disabled' : 'enabled'};
      } else {
        body.remove('thinking');
      }
      body.remove('reasoning_effort');
    } else if (host.contains('intern-ai') || host.contains('intern') || host.contains('chat.intern-ai.org.cn')) {
      if (isReasoning) {
        body['thinking_mode'] = !off;
      } else {
        body.remove('thinking_mode');
      }
      body.remove('reasoning_effort');
    } else if (host.contains('siliconflow')) {
      if (isReasoning) {
        if (off) {
          body['enable_thinking'] = false;
        } else {
          body.remove('enable_thinking');
        }
      } else {
        body.remove('enable_thinking');
      }
      body.remove('reasoning_effort');
    } else if (host.contains('deepseek') || modelId.toLowerCase().contains('deepseek')) {
      if (isReasoning) {
        if (off) {
          body['reasoning_content'] = false;
          body.remove('reasoning_budget');
        } else {
          body['reasoning_content'] = true;
          if (thinkingBudget != null && thinkingBudget > 0) {
            body['reasoning_budget'] = thinkingBudget;
          } else {
            body.remove('reasoning_budget');
          }
        }
      } else {
        body.remove('reasoning_content');
        body.remove('reasoning_budget');
      }
    } else if (host.contains('opencode')) {
      body.remove('reasoning_effort');
    } else if (isGrokModel) {
      final isGrok3Mini = modelId.toLowerCase().contains('grok-3-mini');
      if (!isGrok3Mini) {
        body.remove('reasoning_effort');
      }
    }
  }
}

// ========== Data Classes ==========

/// Image reference type enum.
enum ImageRefType { data, url, path }

/// Image reference container.
class ImageRef {
  final ImageRefType type;
  final String value;
  const ImageRef(this.type, this.value);
}

/// Parsed text and images container.
class ParsedTextAndImages {
  final String text;
  final List<ImageRef> images;
  const ParsedTextAndImages(this.text, this.images);
}
