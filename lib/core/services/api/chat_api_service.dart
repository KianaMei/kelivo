import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../providers/settings_provider.dart';
import '../../models/tool_call_mode.dart';
import 'google_service_account_auth.dart';
import '../../services/api_key_manager.dart';
// Adapters
import 'adapters/openai/openai_adapter.dart';
import 'adapters/claude_adapter.dart';
import 'adapters/google_adapter.dart';
import 'adapters/prompt_tool_adapter.dart';
import 'helpers/chat_api_helper.dart';
import 'models/chat_stream_chunk.dart';

class ChatApiService {
  // NOTE: Helper methods moved to helpers/chat_api_helper.dart

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
        final builtIns = ChatApiHelper.builtInTools(config, modelId);
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

  // NOTE: _sendPromptToolUseStream moved to PromptToolAdapter


  // NOTE: _sendOpenAIStream moved to OpenAIAdapter

  // NOTE: _sendClaudeStream moved to ClaudeAdapter

  // NOTE: _sendGoogleStream moved to GoogleAdapter

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

// NOTE: ChatStreamChunk, ToolCallInfo, ToolResultInfo moved to models/chat_stream_chunk.dart
