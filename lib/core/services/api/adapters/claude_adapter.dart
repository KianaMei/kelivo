/// Claude (Anthropic) Provider Adapter
/// Handles streaming chat completions for Anthropic Claude API.

import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/model_provider.dart';
import '../../../models/token_usage.dart';
import '../helpers/chat_api_helper.dart';
import '../models/chat_stream_chunk.dart';
import '../../http/streaming_http_client.dart';

/// Adapter for Anthropic Claude API streaming.
class ClaudeAdapter {
  ClaudeAdapter._();

  /// Send streaming request to Claude API.
  static Stream<ChatStreamChunk> sendStream(
    Dio dio,
    ProviderConfig config,
    String modelId,
    List<Map<String, dynamic>> messages, {
    List<String>? userImagePaths,
    int? thinkingBudget,
    double? temperature,
    double? topP,
    int? maxTokens,
    int maxToolLoopIterations = 10,
    List<Map<String, dynamic>>? tools,
    Future<String> Function(String, Map<String, dynamic>)? onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
  }) async* {
    final upstreamModelId = ChatApiHelper.apiModelId(config, modelId);
    final base = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final url = Uri.parse('$base/messages');

    final isReasoning = ChatApiHelper.effectiveModelInfo(config, modelId)
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
        continue;
      }
      nonSystemMessages.add({
        'role': role.isEmpty ? 'user' : role,
        'content': [
          {'type': 'text', 'text': m['content'] ?? ''}
        ]
      });
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
            parts.add({'type': 'text', 'text': p});
          } else {
            final mime = ChatApiHelper.mimeFromPath(p);
            final b64 = await ChatApiHelper.encodeBase64File(p, withPrefix: false);
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
        // Convert string content to structured array format
        final contentText = (m['content'] ?? '').toString();
        if (m['content'] is List) {
          // Already structured, keep as is
          transformed.add({'role': m['role'] ?? 'user', 'content': m['content']});
        } else {
          // Convert string to structured format
          transformed.add({
            'role': m['role'] ?? 'user',
            'content': [
              {'type': 'text', 'text': contentText}
            ]
          });
        }
      }
    }

    // Map OpenAI-style tools to Anthropic custom tools
    List<Map<String, dynamic>>? anthropicTools;
    if (tools != null && tools.isNotEmpty) {
      anthropicTools = [];
      for (final t in tools) {
        final fn = (t['function'] as Map<String, dynamic>?);
        if (fn == null) continue;
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

    // Collect final tools list
    final List<Map<String, dynamic>> allTools = [];
    if (anthropicTools != null && anthropicTools.isNotEmpty) allTools.addAll(anthropicTools);
    
    // Pass-through server tools
    if (tools != null && tools.isNotEmpty) {
      for (final t in tools) {
        if (t is Map && t['type'] is String && (t['type'] as String).startsWith('web_search_')) {
          allTools.add(t);
        }
      }
    }
    
    // Enable Claude built-in web search
    final builtIns = ChatApiHelper.builtInTools(config, modelId);
    if (builtIns.contains('search')) {
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
      if (ws['max_uses'] is int && (ws['max_uses'] as int) > 0) entry['max_uses'] = ws['max_uses'];
      if (ws['allowed_domains'] is List) entry['allowed_domains'] = List<String>.from((ws['allowed_domains'] as List).map((e) => e.toString()));
      if (ws['blocked_domains'] is List) entry['blocked_domains'] = List<String>.from((ws['blocked_domains'] as List).map((e) => e.toString()));
      if (ws['user_location'] is Map) entry['user_location'] = (ws['user_location'] as Map).cast<String, dynamic>();
      allTools.add(entry);
    }

    // Convert effort level to actual budget tokens for this model
    final actualBudget = ChatApiHelper.effortToBudget(thinkingBudget, upstreamModelId);

    final body = <String, dynamic>{
      'model': upstreamModelId,
      'max_tokens': maxTokens ?? 4096,
      'messages': transformed,
      'stream': true,
      if (systemPrompt.isNotEmpty) 'system': [
        {'type': 'text', 'text': systemPrompt}
      ],
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'top_p': topP,
      if (allTools.isNotEmpty) 'tools': allTools,
      if (allTools.isNotEmpty) 'tool_choice': {'type': 'auto'},
      if (isReasoning)
        'thinking': {
          'type': (actualBudget == 0) ? 'disabled' : 'enabled',
          if (actualBudget > 0)
            'budget_tokens': actualBudget,
        },
    };

    final headers = <String, String>{
      'Authorization': 'Bearer ${ChatApiHelper.effectiveApiKey(config)}',  // 代理服务需要的认证
      'x-api-key': ChatApiHelper.effectiveApiKey(config),
      'anthropic-version': '2023-06-01',
      'anthropic-dangerous-direct-browser-access': 'true',  // 浏览器访问许可
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };
    headers.addAll(ChatApiHelper.customHeaders(config, modelId));
    if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
    
    final extraClaude = ChatApiHelper.customBody(config, modelId);
    if (extraClaude.isNotEmpty) body.addAll(extraClaude);
    if (extraBody != null && extraBody.isNotEmpty) {
      extraBody.forEach((k, v) {
        body[k] = (v is String) ? ChatApiHelper.parseOverrideValue(v) : v;
      });
    }

    // Send request with streaming HTTP client (works on both IO and Web)
    final response = await postJsonStream(
      dio: dio,
      url: url,
      headers: headers,
      body: body,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBytes = await response.stream.toList();
      final errorBody = utf8.decode(errorBytes.expand((x) => x).toList());
      throw Exception('HTTP ${response.statusCode}: $errorBody');
    }

    final stream = response.stream.cast<List<int>>().transform(utf8.decoder);
    String buffer = '';
    int totalTokens = 0;
    TokenUsage? usage;

    // Tool tracking maps
    final Map<String, Map<String, dynamic>> anthToolUse = {};
    final Map<int, String> srvIndexToId = {};
    final Map<String, String> srvArgsStr = {};
    final Map<String, Map<String, dynamic>> srvArgs = {};

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
                  yield ChatStreamChunk(content: content, isDone: false, totalTokens: totalTokens);
                }
              } else if (delta['type'] == 'thinking_delta') {
                final thinking = (delta['thinking'] ?? delta['text'] ?? '') as String;
                if (thinking.isNotEmpty) {
                  yield ChatStreamChunk(content: '', reasoning: thinking, isDone: false, totalTokens: totalTokens);
                }
              } else if (delta['type'] == 'tool_use_delta') {
                final id = (json['content_block']?['id'] ?? json['id'] ?? '').toString();
                if (id.isNotEmpty) {
                  final entry = anthToolUse.putIfAbsent(id, () => {'name': (json['content_block']?['name'] ?? '').toString(), 'args': ''});
                  final argsDelta = (delta['partial_json'] ?? delta['input'] ?? delta['text'] ?? '').toString();
                  if (argsDelta.isNotEmpty) entry['args'] = (entry['args'] ?? '') + argsDelta;
                }
              } else if (delta['type'] == 'input_json_delta') {
                final idx = json['index'];
                final index = (idx is int) ? idx : int.tryParse((idx ?? '').toString());
                if (index != null && srvIndexToId.containsKey(index)) {
                  final id = srvIndexToId[index]!;
                  final part = (delta['partial_json'] ?? '').toString();
                  if (part.isNotEmpty) {
                    srvArgsStr[id] = (srvArgsStr[id] ?? '') + part;
                  }
                }
              }
            }
          } else if (type == 'content_block_start') {
            final cb = json['content_block'];
            if (cb is Map && (cb['type'] == 'tool_use')) {
              final id = (cb['id'] ?? '').toString();
              final name = (cb['name'] ?? '').toString();
              if (id.isNotEmpty) {
                anthToolUse.putIfAbsent(id, () => {'name': name, 'args': ''});
              }
            } else if (cb is Map && (cb['type'] == 'server_tool_use')) {
              final id = (cb['id'] ?? '').toString();
              final idx = (json['index'] is int) ? json['index'] as int : int.tryParse((json['index'] ?? '').toString()) ?? -1;
              if (id.isNotEmpty && idx >= 0) {
                srvIndexToId[idx] = id;
                srvArgsStr[id] = '';
              }
            } else if (cb is Map && (cb['type'] == 'web_search_tool_result')) {
              final toolUseId = (cb['tool_use_id'] ?? '').toString();
              final contentBlock = cb['content'];
              final items = <Map<String, dynamic>>[];
              String? errorCode;
              if (contentBlock is List) {
                for (int j = 0; j < contentBlock.length; j++) {
                  final it = contentBlock[j];
                  if (it is Map && (it['type'] == 'web_search_result')) {
                    items.add({
                      'index': j + 1,
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
              if (srvArgs.containsKey(toolUseId)) args = srvArgs[toolUseId]!;
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
            final id = (json['content_block']?['id'] ?? json['id'] ?? '').toString();
            if (id.isNotEmpty && anthToolUse.containsKey(id)) {
              final name = (anthToolUse[id]!['name'] ?? '').toString();
              Map<String, dynamic> args;
              try { args = (jsonDecode((anthToolUse[id]!['args'] ?? '{}') as String) as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
              final calls = [ToolCallInfo(id: id, name: name, arguments: args)];
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, toolCalls: calls, usage: usage);
              if (onToolCall != null) {
                final res = await onToolCall(name, args) ?? '';
                final results = [ToolResultInfo(id: id, name: name, arguments: args, content: res)];
                yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, toolResults: results, usage: usage);
              }
            } else {
              final idx = (json['index'] is int) ? json['index'] as int : int.tryParse((json['index'] ?? '').toString());
              if (idx != null && srvIndexToId.containsKey(idx)) {
                final sid = srvIndexToId[idx]!;
                Map<String, dynamic> args;
                try { args = (jsonDecode((srvArgsStr[sid] ?? '{}')) as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
                srvArgs[sid] = args;
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
            yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
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
}
