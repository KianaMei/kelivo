// Claude (Anthropic) Provider Adapter
// Handles streaming chat completions for Anthropic Claude API.
// Following Cherry Studio's approach for message handling and tool calling.

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/model_provider.dart';
import '../../../models/token_usage.dart';
import '../helpers/chat_api_helper.dart';
import '../models/chat_stream_chunk.dart';

// ============================================================================
// Claude Thinking Budget Configuration (Reference: Cherry Studio)
// ============================================================================

/// Effort level to ratio mapping for Claude thinking budget
const Map<String, double> _claudeEffortRatio = {
  'off': 0,
  'minimal': 0.05,
  'low': 0.05,
  'medium': 0.5,
  'high': 1.0,
  'auto': 0.8,
};

/// Claude model thinking token limits (min, max)
const Map<String, List<int>> _claudeThinkingLimits = {
  r'claude-3[.-]7.*sonnet': [1024, 64000],
  r'claude-opus-4[.-]1': [1024, 32000],
  r'claude-opus-4[.-]5': [1024, 64000],
  r'claude-(?:haiku|sonnet)-4': [1024, 64000],
  r'claude-opus-4(?![\d.-])': [1024, 64000],
};

List<int> _getClaudeThinkingLimits(String modelId) {
  final lower = modelId.toLowerCase();
  for (final entry in _claudeThinkingLimits.entries) {
    if (RegExp(entry.key, caseSensitive: false).hasMatch(lower)) {
      return entry.value;
    }
  }
  return [1024, 64000];
}

int? _computeClaudeBudgetTokens(String modelId, int? userBudget, int maxTokens) {
  final limits = _getClaudeThinkingLimits(modelId);
  final minBudget = limits[0];
  final maxBudget = limits[1];
  final effort = ChatApiHelper.effortForBudget(userBudget);

  if (effort == 'off') return null;

  final ratio = _claudeEffortRatio[effort] ?? 0.8;
  int budget;
  if (effort == 'auto') {
    budget = (maxBudget * ratio).floor();
  } else if (ratio >= 1.0) {
    budget = maxBudget;
  } else {
    budget = ((maxBudget - minBudget) * ratio + minBudget).floor();
  }

  if (budget < 1024) budget = 1024;
  if (budget >= maxTokens) budget = (maxTokens * 0.9).floor();

  return budget;
}

// ============================================================================
// Content Block Tracking (Following Cherry Studio SDK approach)
// ============================================================================

/// Tracks a content block during streaming, accumulating content and signature
class _ContentBlockTracker {
  final String type;
  String thinking = '';
  String signature = '';
  String text = '';
  String? toolId;
  String? toolName;
  String toolArgs = '';

  _ContentBlockTracker(this.type);

  /// Convert to ContentBlockParam format (Cherry Studio: convertContentBlocksToParams)
  Map<String, dynamic> toContentBlockParam() {
    switch (type) {
      case 'thinking':
        return {
          'type': 'thinking',
          'thinking': thinking,
          'signature': signature,
        };
      case 'text':
        return {
          'type': 'text',
          'text': text,
        };
      case 'tool_use':
        Map<String, dynamic> input;
        try {
          input = (jsonDecode(toolArgs.isEmpty ? '{}' : toolArgs) as Map).cast<String, dynamic>();
        } catch (_) {
          input = <String, dynamic>{};
        }
        return {
          'type': 'tool_use',
          'id': toolId ?? '',
          'name': toolName ?? '',
          'input': input,
        };
      default:
        return {'type': type};
    }
  }
}

// ============================================================================

/// Adapter for Anthropic Claude API streaming.
class ClaudeAdapter {
  ClaudeAdapter._();

  /// Send streaming request to Claude API with multi-turn tool calling support.
  /// Following Cherry Studio's approach: SDK-style message accumulation with signature tracking.
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

    // Extract system prompt
    String systemPrompt = '';
    final nonSystemMessages = <Map<String, dynamic>>[];
    for (final m in messages) {
      final role = (m['role'] ?? '').toString();
      if (role == 'system') {
        final s = (m['content'] ?? '').toString();
        if (s.isNotEmpty) {
          systemPrompt = systemPrompt.isEmpty ? s : '$systemPrompt\n\n$s';
        }
        continue;
      }
      final content = m['content'];
      if (content is List) {
        nonSystemMessages.add({
          'role': role.isEmpty ? 'user' : role,
          'content': content,
        });
      } else {
        nonSystemMessages.add({
          'role': role.isEmpty ? 'user' : role,
          'content': [
            {'type': 'text', 'text': (content ?? '').toString()}
          ]
        });
      }
    }

    // Transform messages with images
    var currentMessages = <Map<String, dynamic>>[];
    for (int i = 0; i < nonSystemMessages.length; i++) {
      final m = nonSystemMessages[i];
      final isLast = i == nonSystemMessages.length - 1;
      if (isLast && (userImagePaths?.isNotEmpty == true) && (m['role'] == 'user')) {
        final existingContent = m['content'];
        final parts = <Map<String, dynamic>>[];
        if (existingContent is List) {
          for (final block in existingContent) {
            if (block is Map<String, dynamic>) parts.add(block);
          }
        } else {
          final text = (existingContent ?? '').toString();
          if (text.isNotEmpty) parts.add({'type': 'text', 'text': text});
        }
        for (final p in userImagePaths!) {
          if (p.startsWith('http') || p.startsWith('data:')) {
            parts.add({'type': 'text', 'text': p});
          } else {
            final mime = ChatApiHelper.mimeFromPath(p);
            final b64 = await ChatApiHelper.encodeBase64File(p, withPrefix: false);
            parts.add({
              'type': 'image',
              'source': {'type': 'base64', 'media_type': mime, 'data': b64}
            });
          }
        }
        currentMessages.add({'role': 'user', 'content': parts});
      } else {
        if (m['content'] is List) {
          currentMessages.add({'role': m['role'] ?? 'user', 'content': m['content']});
        } else {
          final contentText = (m['content'] ?? '').toString();
          currentMessages.add({
            'role': m['role'] ?? 'user',
            'content': [{'type': 'text', 'text': contentText}]
          });
        }
      }
    }

    // Map tools to Anthropic format
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

    final List<Map<String, dynamic>> allTools = [];
    if (anthropicTools != null && anthropicTools.isNotEmpty) allTools.addAll(anthropicTools);

    // Pass-through server tools
    if (tools != null && tools.isNotEmpty) {
      for (final t in tools) {
        final tType = t['type'];
        if (tType is String && tType.startsWith('web_search_')) {
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

    // Calculate tokens
    int effectiveMaxTokens = maxTokens ?? 8192;
    final isThinkingOff = thinkingBudget != null && thinkingBudget >= 0 && thinkingBudget < 1024;
    int? effectiveBudgetTokens;

    if (isReasoning && !isThinkingOff) {
      effectiveBudgetTokens = _computeClaudeBudgetTokens(upstreamModelId, thinkingBudget, effectiveMaxTokens);
      if (effectiveBudgetTokens != null && effectiveBudgetTokens >= effectiveMaxTokens) {
        effectiveMaxTokens = effectiveBudgetTokens + 1024;
      }
    }

    final headers = <String, String>{
      'Authorization': 'Bearer ${ChatApiHelper.effectiveApiKey(config)}',
      'x-api-key': ChatApiHelper.effectiveApiKey(config),
      'anthropic-version': '2023-06-01',
      'anthropic-beta': 'web-fetch-2025-09-10,interleaved-thinking-2025-05-14,context-1m-2025-08-07',
      'anthropic-dangerous-direct-browser-access': 'true',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };
    headers.addAll(ChatApiHelper.customHeaders(config, modelId));
    if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);

    int totalTokens = 0;
    TokenUsage? usage;

    // =========================================================================
    // Multi-turn tool calling loop (Following Cherry Studio's approach)
    // =========================================================================
    for (int round = 0; round < maxToolLoopIterations; round++) {
      print('[ClaudeAdapter] === Starting round $round ===');

      final body = <String, dynamic>{
        'model': upstreamModelId,
        'max_tokens': effectiveMaxTokens,
        'messages': currentMessages,
        'stream': true,
        if (systemPrompt.isNotEmpty) 'system': [{'type': 'text', 'text': systemPrompt}],
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (allTools.isNotEmpty) 'tools': allTools,
        if (allTools.isNotEmpty) 'tool_choice': {'type': 'auto'},
        if (isReasoning)
          'thinking': {
            'type': isThinkingOff ? 'disabled' : 'enabled',
            if (!isThinkingOff && effectiveBudgetTokens != null && effectiveBudgetTokens > 0)
              'budget_tokens': effectiveBudgetTokens,
          },
      };

      final extraClaude = ChatApiHelper.customBody(config, modelId);
      if (extraClaude.isNotEmpty) body.addAll(extraClaude);
      if (extraBody != null && extraBody.isNotEmpty) {
        extraBody.forEach((k, v) {
          body[k] = (v is String) ? ChatApiHelper.parseOverrideValue(v) : v;
        });
      }

      final Response<ResponseBody> response;
      try {
        response = await dio.post<ResponseBody>(
          url.toString(),
          data: body,
          options: Options(
            headers: headers,
            responseType: ResponseType.stream,
            validateStatus: (status) => true,
          ),
        );
      } on DioException catch (e) {
        throw HttpException('Dio error: ${e.message}');
      }

      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        final errorBytes = await response.data?.stream.toList() ?? [];
        final errorBody = utf8.decode(errorBytes.expand((x) => x).toList());
        throw HttpException('HTTP ${response.statusCode}: $errorBody');
      }

      final stream = response.data!.stream.cast<List<int>>().transform(utf8.decoder);
      String buffer = '';

      // Content block tracking (SDK-style: accumulate complete blocks with signatures)
      final Map<int, _ContentBlockTracker> contentBlocks = {};
      final Map<int, String> srvIndexToId = {};
      final Map<String, String> srvArgsStr = {};
      final Map<String, Map<String, dynamic>> srvArgs = {};

      // Track tools executed in this round
      final executedTools = <Map<String, dynamic>>[];
      bool hasToolCalls = false;

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

            if (type == 'content_block_start') {
              final cb = json['content_block'];
              final cbType = (cb is Map) ? cb['type'] : null;
              final idx = _parseIndex(json['index']);

              if (cbType == 'thinking') {
                contentBlocks[idx] = _ContentBlockTracker('thinking');
              } else if (cbType == 'text') {
                contentBlocks[idx] = _ContentBlockTracker('text');
              } else if (cbType == 'tool_use' && cb is Map) {
                final tracker = _ContentBlockTracker('tool_use');
                tracker.toolId = (cb['id'] ?? '').toString();
                tracker.toolName = (cb['name'] ?? '').toString();
                contentBlocks[idx] = tracker;
                print('[ClaudeAdapter] tool_use START: name=${tracker.toolName}, id=${tracker.toolId}');
              } else if (cbType == 'server_tool_use' && cb is Map) {
                final id = (cb['id'] ?? '').toString();
                if (id.isNotEmpty) {
                  srvIndexToId[idx] = id;
                  srvArgsStr[id] = '';
                }
              } else if (cbType == 'web_search_tool_result' && cb is Map) {
                // Handle web search result
                final toolUseId = (cb['tool_use_id'] ?? '').toString();
                final contentBlock = cb['content'];
                final items = <Map<String, dynamic>>[];
                String? errorCode;
                if (contentBlock is List) {
                  for (int j = 0; j < contentBlock.length; j++) {
                    final it = contentBlock[j];
                    if (it is Map && it['type'] == 'web_search_result') {
                      items.add({
                        'index': j + 1,
                        'title': (it['title'] ?? '').toString(),
                        'url': (it['url'] ?? '').toString(),
                        if ((it['page_age'] ?? '').toString().isNotEmpty) 'page_age': it['page_age'].toString(),
                      });
                    }
                  }
                } else if (contentBlock is Map && contentBlock['type'] == 'web_search_tool_result_error') {
                  errorCode = (contentBlock['error_code'] ?? '').toString();
                }
                final payload = jsonEncode({'items': items, if (errorCode != null && errorCode.isNotEmpty) 'error': errorCode});
                yield ChatStreamChunk(
                  content: '',
                  isDone: false,
                  totalTokens: totalTokens,
                  usage: usage,
                  toolResults: [ToolResultInfo(id: toolUseId.isEmpty ? 'builtin_search' : toolUseId, name: 'search_web', arguments: srvArgs[toolUseId] ?? {}, content: payload)],
                );
              }
            } else if (type == 'content_block_delta') {
              final delta = json['delta'];
              final idx = _parseIndex(json['index']);
              if (delta != null) {
                final deltaType = delta['type'];

                if (deltaType == 'thinking_delta') {
                  // Accumulate thinking content
                  final thinking = (delta['thinking'] ?? '').toString();
                  if (contentBlocks.containsKey(idx)) {
                    contentBlocks[idx]!.thinking += thinking;
                  }
                  if (thinking.isNotEmpty) {
                    yield ChatStreamChunk(content: '', reasoning: thinking, isDone: false, totalTokens: totalTokens);
                  }
                } else if (deltaType == 'signature_delta') {
                  // KEY: Capture signature from signature_delta event (SDK approach)
                  final sig = (delta['signature'] ?? '').toString();
                  if (contentBlocks.containsKey(idx) && sig.isNotEmpty) {
                    contentBlocks[idx]!.signature += sig;
                  }
                } else if (deltaType == 'text_delta') {
                  final text = (delta['text'] ?? '').toString();
                  if (contentBlocks.containsKey(idx)) {
                    contentBlocks[idx]!.text += text;
                  }
                  if (text.isNotEmpty) {
                    yield ChatStreamChunk(content: text, isDone: false, totalTokens: totalTokens);
                  }
                } else if (deltaType == 'input_json_delta') {
                  final part = (delta['partial_json'] ?? '').toString();
                  if (contentBlocks.containsKey(idx) && contentBlocks[idx]!.type == 'tool_use') {
                    contentBlocks[idx]!.toolArgs += part;
                  } else if (srvIndexToId.containsKey(idx)) {
                    final id = srvIndexToId[idx]!;
                    srvArgsStr[id] = (srvArgsStr[id] ?? '') + part;
                  }
                }
              }
            } else if (type == 'content_block_stop') {
              final idx = _parseIndex(json['index']);

              // Check if this is a tool_use block that needs execution
              if (contentBlocks.containsKey(idx) && contentBlocks[idx]!.type == 'tool_use') {
                final tracker = contentBlocks[idx]!;
                final toolId = tracker.toolId ?? '';
                final toolName = tracker.toolName ?? '';
                Map<String, dynamic> args;
                try {
                  args = (jsonDecode(tracker.toolArgs.isEmpty ? '{}' : tracker.toolArgs) as Map).cast<String, dynamic>();
                } catch (_) {
                  args = <String, dynamic>{};
                }

                print('[ClaudeAdapter] tool_use STOP: name=$toolName, id=$toolId');
                hasToolCalls = true;

                // Yield tool call info
                yield ChatStreamChunk(
                  content: '',
                  isDone: false,
                  totalTokens: totalTokens,
                  toolCalls: [ToolCallInfo(id: toolId, name: toolName, arguments: args)],
                  usage: usage,
                );

                // Execute tool
                if (onToolCall != null && toolId.isNotEmpty) {
                  print('[ClaudeAdapter] Executing tool: $toolName');
                  final result = await onToolCall(toolName, args) ?? '';
                  print('[ClaudeAdapter] Tool result length: ${result.length}');
                  executedTools.add({
                    'tool_use_id': toolId,
                    'name': toolName,
                    'args': args,
                    'result': result,
                  });
                  // Yield tool result
                  yield ChatStreamChunk(
                    content: '',
                    isDone: false,
                    totalTokens: totalTokens,
                    toolResults: [ToolResultInfo(id: toolId, name: toolName, arguments: args, content: result)],
                    usage: usage,
                  );
                }
              } else if (srvIndexToId.containsKey(idx)) {
                // Server tool use stop
                final sid = srvIndexToId[idx]!;
                Map<String, dynamic> args;
                try {
                  args = (jsonDecode(srvArgsStr[sid] ?? '{}') as Map).cast<String, dynamic>();
                } catch (_) {
                  args = <String, dynamic>{};
                }
                srvArgs[sid] = args;
                yield ChatStreamChunk(
                  content: '',
                  isDone: false,
                  totalTokens: totalTokens,
                  usage: usage,
                  toolCalls: [ToolCallInfo(id: sid, name: 'search_web', arguments: args)],
                );
              }
            } else if (type == 'message_delta') {
              final u = json['usage'] ?? json['message']?['usage'];
              if (u != null) {
                final inTok = (u['input_tokens'] ?? 0) as int;
                final outTok = (u['output_tokens'] ?? 0) as int;
                usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: inTok, completionTokens: outTok));
                totalTokens = usage!.totalTokens;
              }
            } else if (type == 'message_stop') {
              print('[ClaudeAdapter] message_stop, executedTools=${executedTools.length}');

              if (executedTools.isEmpty) {
                // No tools executed, we're done
                yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
                return;
              }

              // Build continuation messages (Cherry Studio: buildSdkMessages)
              // Convert accumulated content blocks to ContentBlockParams with signatures
              final assistantContentParams = <Map<String, dynamic>>[];
              final sortedIndices = contentBlocks.keys.toList()..sort();
              for (final idx in sortedIndices) {
                final tracker = contentBlocks[idx]!;
                assistantContentParams.add(tracker.toContentBlockParam());
              }

              // Add assistant message with complete content blocks (including signatures!)
              currentMessages.add({
                'role': 'assistant',
                'content': assistantContentParams,
              });

              // Add user message with tool results
              final toolResultBlocks = <Map<String, dynamic>>[];
              for (final tool in executedTools) {
                toolResultBlocks.add({
                  'type': 'tool_result',
                  'tool_use_id': tool['tool_use_id'],
                  'content': tool['result'],
                });
              }
              currentMessages.add({
                'role': 'user',
                'content': toolResultBlocks,
              });

              print('[ClaudeAdapter] Continuing to round ${round + 1}...');
              break; // Continue to next round
            }
          } catch (e) {
            print('[ClaudeAdapter] Parse error: $e');
          }
        }
      }

      // If we exited without message_stop and no tools, we're done
      if (executedTools.isEmpty && !hasToolCalls) {
        yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
        return;
      }
    }

    // Max iterations reached
    print('[ClaudeAdapter] Max tool loop iterations reached');
    yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
  }

  static int _parseIndex(dynamic idx) {
    if (idx is int) return idx;
    return int.tryParse((idx ?? '').toString()) ?? -1;
  }
}
