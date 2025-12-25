/// OpenAI Responses API Handler
/// Handles streaming for OpenAI Responses API format.

import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../providers/model_provider.dart';
import '../../../../models/token_usage.dart';
import '../../helpers/chat_api_helper.dart';
import '../../helpers/inline_image_saver.dart';
import '../../models/chat_stream_chunk.dart';
import '../../../http/streaming_http_client.dart';

/// Handler for OpenAI Responses API streaming.
class OpenAIResponsesApi {
  OpenAIResponsesApi._();

  /// Send streaming request using Responses API.
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
    final url = Uri.parse('$base/responses');

    final effectiveInfo = ChatApiHelper.effectiveModelInfo(config, modelId);
    final isReasoning = effectiveInfo.abilities.contains(ModelAbility.reasoning);
    // OpenAI only supports low/medium/high, map minimal to low
    final rawEffort = ChatApiHelper.effortForBudget(thinkingBudget);
    final effort = rawEffort == 'minimal' ? 'low' : rawEffort;

    // Build input messages and extract system instructions
    final input = <Map<String, dynamic>>[];
    String instructions = '';
    
    // Build tools list
    final List<Map<String, dynamic>> toolList = [];
    if (tools != null && tools.isNotEmpty) {
      for (final t in tools) {
        if (t is Map<String, dynamic>) {
          if (t['type'] == 'function' && t['function'] is Map) {
            final func = t['function'] as Map<String, dynamic>;
            toolList.add({
              'type': 'function',
              'name': func['name'],
              if (func['description'] != null) 'description': func['description'],
              if (func['parameters'] != null) 'parameters': func['parameters'],
            });
          } else {
            toolList.add(Map<String, dynamic>.from(t));
          }
        }
      }
    }

    // Built-in web search for Responses API
    if (_isResponsesWebSearchSupported(modelId)) {
      final builtIns = ChatApiHelper.builtInTools(config, modelId);
      if (builtIns.contains('search')) {
        Map<String, dynamic> ws = const <String, dynamic>{};
        try {
          final ov = config.modelOverrides[modelId];
          if (ov is Map && ov['webSearch'] is Map) {
            ws = (ov['webSearch'] as Map).cast<String, dynamic>();
          }
        } catch (_) {}
        final usePreview = (ws['preview'] == true) || ((ws['tool'] ?? '').toString() == 'preview');
        final entry = <String, dynamic>{'type': usePreview ? 'web_search_preview' : 'web_search'};
        if (ws['allowed_domains'] is List && (ws['allowed_domains'] as List).isNotEmpty) {
          entry['filters'] = {'allowed_domains': List<String>.from((ws['allowed_domains'] as List).map((e) => e.toString()))};
        }
        if (ws['user_location'] is Map) {
          entry['user_location'] = (ws['user_location'] as Map).cast<String, dynamic>();
        }
        if (usePreview && ws['search_context_size'] is String) {
          entry['search_context_size'] = ws['search_context_size'];
        }
        toolList.add(entry);
      }
    }

    // Process messages
    for (int i = 0; i < messages.length; i++) {
      final m = messages[i];
      final isLast = i == messages.length - 1;
      final raw = (m['content'] ?? '').toString();
      final roleRaw = (m['role'] ?? 'user').toString();

      if (roleRaw == 'system') {
        if (raw.isNotEmpty) {
          instructions = instructions.isEmpty ? raw : (instructions + '\n\n' + raw);
        }
        continue;
      }

      final hasMarkdownImages = raw.contains('![') && raw.contains('](');
      final hasCustomImages = raw.contains('[image:');
      final hasAttachedImages = isLast && (userImagePaths?.isNotEmpty == true) && (m['role'] == 'user');

      if (hasMarkdownImages || hasCustomImages || hasAttachedImages) {
        final parsed = ChatApiHelper.parseTextAndImages(raw);
        final parts = <Map<String, dynamic>>[];
        if (parsed.text.isNotEmpty) {
          parts.add({'type': 'input_text', 'text': parsed.text});
        }
        for (final ref in parsed.images) {
          String imgUrl;
          if (ref.type == ImageRefType.data) {
            imgUrl = ref.value;
          } else if (ref.type == ImageRefType.path) {
            imgUrl = await ChatApiHelper.encodeBase64File(ref.value, withPrefix: true);
          } else {
            imgUrl = ref.value;
          }
          parts.add({'type': 'input_image', 'image_url': imgUrl});
        }
        if (hasAttachedImages) {
          for (final p in userImagePaths!) {
            final dataUrl = (p.startsWith('http') || p.startsWith('data:')) ? p : await ChatApiHelper.encodeBase64File(p, withPrefix: true);
            parts.add({'type': 'input_image', 'image_url': dataUrl});
          }
        }
        input.add({'role': roleRaw, 'content': parts});
      } else {
        input.add({'role': roleRaw, 'content': raw});
      }
    }

    // Build request body
    final body = <String, dynamic>{
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
          'summary': 'detailed',
          if (effort != 'auto') 'effort': effort,
        },
      'text': {'verbosity': 'high'},
    };

    // Include web search sources if configured
    try {
      final ov = config.modelOverrides[modelId];
      final ws = (ov is Map ? ov['webSearch'] : null);
      if (ws is Map && ws['include_sources'] == true) {
        body['include'] = ['web_search_call.action.sources'];
      }
    } catch (_) {}

    // Headers
    final apiKey = ChatApiHelper.effectiveApiKey(config);
    final headers = <String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };
    headers.addAll(ChatApiHelper.customHeaders(config, modelId));
    if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);

    // Custom body overrides
    final extraBodyCfg = ChatApiHelper.customBody(config, modelId);
    if (extraBodyCfg.isNotEmpty) body.addAll(extraBodyCfg);
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

    // Process stream
    yield* _processStream(
      dio: dio,
      config: config,
      modelId: modelId,
      messages: messages,
      responseStream: response.stream,
      url: url,
      headers: headers,
      toolList: toolList,
      systemInstructions: instructions,
      thinkingBudget: thinkingBudget,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      tools: tools,
      onToolCall: onToolCall,
      extraHeaders: extraHeaders,
      extraBody: extraBody,
      maxToolLoopIterations: maxToolLoopIterations,
    );
  }

  // ========== Stream Processing ==========

  static Stream<ChatStreamChunk> _processStream({
    required Dio dio,
    required ProviderConfig config,
    required String modelId,
    required List<Map<String, dynamic>> messages,
    required Stream<List<int>> responseStream,
    required Uri url,
    required Map<String, String> headers,
    required List<Map<String, dynamic>> toolList,
    required String systemInstructions,
    required int? thinkingBudget,
    required double? temperature,
    required double? topP,
    required int? maxTokens,
    required List<Map<String, dynamic>>? tools,
    required Future<String> Function(String, Map<String, dynamic>)? onToolCall,
    required Map<String, String>? extraHeaders,
    required Map<String, dynamic>? extraBody,
    required int maxToolLoopIterations,
  }) async* {
    final upstreamModelId = ChatApiHelper.apiModelId(config, modelId);
    final stream = responseStream.cast<List<int>>().transform(utf8.decoder);
    String buffer = '';
    int totalTokens = 0;
    TokenUsage? usage;
    int approxCompletionChars = 0;

    // Tool call tracking
    final Map<String, Map<String, String>> toolAccResp = {};
    final Map<String, String> itemIdToCallId = {};

    await for (final chunk in stream) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.last;

      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i].trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;

        final data = line.substring(5).trimLeft();
        if (data == '[DONE]') {
          yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
          return;
        }

        try {
          final json = jsonDecode(data);
          final type = json['type'];

          if (type == 'response.output_text.delta') {
            final delta = json['delta'];
            if (delta is String && delta.isNotEmpty) {
              approxCompletionChars += delta.length;
              yield ChatStreamChunk(content: delta, isDone: false, totalTokens: totalTokens);
            }
          } else if (type == 'response.reasoning_summary_text.delta') {
            final delta = json['delta'];
            if (delta is String && delta.isNotEmpty) {
              yield ChatStreamChunk(content: '', reasoning: delta, isDone: false, totalTokens: totalTokens);
            }
          } else if (type == 'response.output_item.added') {
            final item = json['item'];
            if (item is Map && item['type'] == 'function_call') {
              final callId = (item['call_id'] ?? '').toString();
              final itemId = (item['id'] ?? '').toString();
              final name = (item['name'] ?? '').toString();
              if (callId.isNotEmpty && itemId.isNotEmpty) {
                itemIdToCallId[itemId] = callId;
                toolAccResp.putIfAbsent(callId, () => {'id': callId, 'name': name, 'args': ''});
              }
            }
          } else if (type == 'response.function_call_arguments.delta') {
            final itemId = (json['item_id'] ?? '').toString();
            final delta = (json['delta'] ?? '').toString();
            if (itemId.isNotEmpty && delta.isNotEmpty) {
              final callId = itemIdToCallId[itemId];
              if (callId != null) {
                final entry = toolAccResp[callId];
                if (entry != null) {
                  entry['args'] = (entry['args'] ?? '') + delta;
                }
              }
            }
          } else if (type == 'response.function_call_arguments.done') {
            final itemId = (json['item_id'] ?? '').toString();
            final args = (json['arguments'] ?? '').toString();
            if (itemId.isNotEmpty && args.isNotEmpty) {
              final callId = itemIdToCallId[itemId];
              if (callId != null) {
                final entry = toolAccResp[callId];
                if (entry != null) {
                  entry['args'] = args;
                }
              }
            }
          } else if (type == 'response.completed') {
            // Extract usage
            final u = json['response']?['usage'];
            if (u != null) {
              final inTok = (u['input_tokens'] ?? 0) as int;
              final outTok = (u['output_tokens'] ?? 0) as int;
              usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: inTok, completionTokens: outTok));
              totalTokens = usage!.totalTokens;
            }

            // Extract web search citations
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
                          final citUrl = (an['url'] ?? '').toString();
                          if (citUrl.isEmpty || seen.contains(citUrl)) continue;
                          final title = (an['title'] ?? '').toString();
                          items.add({'index': idx, 'url': citUrl, if (title.isNotEmpty) 'title': title});
                          seen.add(citUrl);
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

            // Handle image_generation_call outputs (OpenAI native image generation)
            try {
              final output = json['response']?['output'];
              if (output is List) {
                for (final it in output) {
                  if (it is! Map) continue;
                  if (it['type'] == 'image_generation_call') {
                    // Extract base64 image from result
                    final b64 = (it['result'] ?? '').toString();
                    if (b64.isNotEmpty) {
                      final savedPath = await InlineImageSaver.saveToFile('image/png', b64);
                      if (savedPath != null) {
                        yield ChatStreamChunk(
                          content: '\n![Generated Image]($savedPath)\n',
                          isDone: false,
                          totalTokens: totalTokens,
                          usage: usage,
                        );
                      }
                    }
                  }
                }
              }
            } catch (_) {}

            // Handle tool calls
            if (onToolCall != null && toolAccResp.isNotEmpty) {
              yield* _executeToolsAndContinue(
                dio: dio,
                config: config,
                modelId: modelId,
                messages: messages,
                url: url,
                headers: headers,
                toolAccResp: toolAccResp,
                itemIdToCallId: itemIdToCallId,
                usage: usage,
                toolList: toolList,
                systemInstructions: systemInstructions,
                thinkingBudget: thinkingBudget,
                temperature: temperature,
                topP: topP,
                maxTokens: maxTokens,
                tools: tools,
                onToolCall: onToolCall,
                extraHeaders: extraHeaders,
                extraBody: extraBody,
                maxToolLoopIterations: maxToolLoopIterations,
              );
              return;
            }

            yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
            return;
          }
        } catch (e) {
          // Skip malformed JSON
        }
      }
    }
  }

  // ========== Tool Execution ==========

  static Stream<ChatStreamChunk> _executeToolsAndContinue({
    required Dio dio,
    required ProviderConfig config,
    required String modelId,
    required List<Map<String, dynamic>> messages,
    required Uri url,
    required Map<String, String> headers,
    required Map<String, Map<String, String>> toolAccResp,
    required Map<String, String> itemIdToCallId,
    required TokenUsage? usage,
    required List<Map<String, dynamic>> toolList,
    required String systemInstructions,
    required int? thinkingBudget,
    required double? temperature,
    required double? topP,
    required int? maxTokens,
    required List<Map<String, dynamic>>? tools,
    required Future<String> Function(String, Map<String, dynamic>) onToolCall,
    required Map<String, String>? extraHeaders,
    required Map<String, dynamic>? extraBody,
    required int maxToolLoopIterations,
  }) async* {
    final upstreamModelId = ChatApiHelper.apiModelId(config, modelId);
    int totalTokens = usage?.totalTokens ?? 0;

    // Build tool calls
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
      yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, usage: usage, toolCalls: callInfos);
    }

    // Execute tools
    final resultsInfo = <ToolResultInfo>[];
    final toolOutputs = <Map<String, dynamic>>[];
    for (final m in msgs) {
      final nm = m['__name'] as String;
      final id2 = m['__id'] as String;
      final callId = m['__callId'] as String;
      final args = (m['__args'] as Map<String, dynamic>);
      final res = await onToolCall(nm, args) ?? '';
      resultsInfo.add(ToolResultInfo(id: id2, name: nm, arguments: args, content: res));
      toolOutputs.add({'type': 'function_call_output', 'call_id': callId, 'output': res});
    }

    if (resultsInfo.isNotEmpty) {
      yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, usage: usage, toolResults: resultsInfo);
    }

    // Build conversation for follow-up
    var currentMessages = <Map<String, dynamic>>[];
    for (final m in messages) {
      final roleRaw = (m['role'] ?? 'user').toString();
      if (roleRaw == 'system') continue;
      final content = (m['content'] ?? '').toString();
      currentMessages.add({'role': roleRaw, 'content': content});
    }

    // Tool calling loop
    for (int stepIndex = 0; stepIndex < maxToolLoopIterations; stepIndex++) {
      if (toolAccResp.isEmpty) break;

      // Build conversation with tool calls and results
      final conversation = <Map<String, dynamic>>[];
      for (final m in currentMessages) {
        final roleRaw = (m['role'] ?? 'user').toString();
        if (roleRaw == 'system') continue;
        final content = (m['content'] ?? '').toString();
        conversation.add({'role': roleRaw, 'content': content});
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
        final toolResults = m['__toolResults'] as List?;
        if (toolResults != null && toolResults.isNotEmpty) {
          conversation.addAll(toolResults.cast<Map<String, dynamic>>());
        }
      }

      // Add current tool calls
      for (final m in msgs) {
        conversation.add({
          'type': 'function_call',
          'call_id': m['__callId'],
          'name': m['__name'],
          'arguments': jsonEncode(m['__args']),
        });
      }
      conversation.addAll(toolOutputs);

      // Send follow-up request
      final followUpBody = <String, dynamic>{
        'model': upstreamModelId,
        'input': conversation,
        'stream': true,
        if (systemInstructions.isNotEmpty) 'instructions': systemInstructions,
        'reasoning': {'effort': 'high', 'summary': 'detailed'},
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (maxTokens != null && maxTokens > 0) 'max_output_tokens': maxTokens,
        if (toolList.isNotEmpty) 'tools': toolList,
        if (toolList.isNotEmpty) 'tool_choice': 'auto',
      };

      final followUpResp = await postJsonStream(
        dio: dio,
        url: url,
        headers: headers,
        body: followUpBody,
      );

      if (followUpResp.statusCode < 200 || followUpResp.statusCode >= 300) {
        final errorBytes = await followUpResp.stream.toList();
        final errorBody = utf8.decode(errorBytes.expand((x) => x).toList());
        throw Exception('HTTP ${followUpResp.statusCode}: $errorBody');
      }

      // Clear accumulators
      toolAccResp.clear();
      itemIdToCallId.clear();
      String followUpContent = '';

      final followUpChunks = followUpResp.stream.cast<List<int>>().transform(utf8.decoder);
      String followUpBuffer = '';

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

            if (followUpType == 'response.reasoning_summary_text.delta') {
              final delta = followUpJson['delta'];
              if (delta is String && delta.isNotEmpty) {
                yield ChatStreamChunk(content: '', reasoning: delta, isDone: false, totalTokens: totalTokens, usage: usage);
              }
            } else if (followUpType == 'response.output_text.delta') {
              final delta = followUpJson['delta'];
              if (delta is String && delta.isNotEmpty) {
                followUpContent += delta;
                yield ChatStreamChunk(content: delta, isDone: false, totalTokens: totalTokens, usage: usage);
              }
            } else if (followUpType == 'response.output_item.added') {
              final item = followUpJson['item'];
              if (item is Map && item['type'] == 'function_call') {
                final callId = (item['call_id'] ?? '').toString();
                final itemId = (item['id'] ?? '').toString();
                final name = (item['name'] ?? '').toString();
                if (callId.isNotEmpty && itemId.isNotEmpty) {
                  itemIdToCallId[itemId] = callId;
                  toolAccResp.putIfAbsent(callId, () => {'id': callId, 'name': name, 'args': ''});
                }
              }
            } else if (followUpType == 'response.function_call_arguments.delta') {
              final itemId = (followUpJson['item_id'] ?? '').toString();
              final delta = (followUpJson['delta'] ?? '').toString();
              if (itemId.isNotEmpty && delta.isNotEmpty) {
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
                final callId = itemIdToCallId[itemId];
                if (callId != null) {
                  final entry = toolAccResp[callId];
                  if (entry != null) {
                    entry['args'] = args;
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
              }
            }
          } catch (e) {}
        }
      }

      // Update messages for next round
      currentMessages.add({
        'role': 'assistant',
        'content': followUpContent,
        '__toolCalls': msgs.map((m) => {
          'call_id': m['__callId'],
          'name': m['__name'],
          'arguments': jsonEncode(m['__args']),
        }).toList(),
        '__toolResults': toolOutputs,
      });

      // If more tool calls, continue
      if (toolAccResp.isNotEmpty) {
        // Rebuild tool infos for next iteration
        callInfos.clear();
        msgs.clear();
        toolOutputs.clear();
        idx = 0;
        toolAccResp.forEach((key, m) {
          Map<String, dynamic> args;
          try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
          final id2 = (m['id'] ?? key).isNotEmpty ? (m['id'] ?? key) : 'call_$idx';
          callInfos.add(ToolCallInfo(id: id2, name: (m['name'] ?? ''), arguments: args));
          msgs.add({'__id': id2, '__name': (m['name'] ?? ''), '__args': args, '__callId': m['id'] ?? key});
          idx += 1;
        });

        if (callInfos.isNotEmpty) {
          yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, usage: usage, toolCalls: callInfos);
        }

        resultsInfo.clear();
        for (final m in msgs) {
          final nm = m['__name'] as String;
          final id2 = m['__id'] as String;
          final callId = m['__callId'] as String;
          final args = (m['__args'] as Map<String, dynamic>);
          final res = await onToolCall(nm, args) ?? '';
          resultsInfo.add(ToolResultInfo(id: id2, name: nm, arguments: args, content: res));
          toolOutputs.add({'type': 'function_call_output', 'call_id': callId, 'output': res});
        }

        if (resultsInfo.isNotEmpty) {
          yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, usage: usage, toolResults: resultsInfo);
        }
        continue;
      } else {
        break;
      }
    }

    yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
  }

  // ========== Helpers ==========

  static bool _isResponsesWebSearchSupported(String modelId) {
    final m = modelId.toLowerCase();
    if (m.startsWith('gpt-4o')) return true;
    if (m == 'gpt-4.1' || m == 'gpt-4.1-mini') return true;
    if (m.startsWith('o4-mini')) return true;
    if (m == 'o3' || m.startsWith('o3-')) return true;
    if (m.startsWith('gpt-5')) return true;
    return false;
  }
}
