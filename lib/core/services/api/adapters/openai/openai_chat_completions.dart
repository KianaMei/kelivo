/// OpenAI Chat Completions API Handler
/// Handles streaming chat completions for OpenAI-compatible APIs.

import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../providers/model_provider.dart';
import '../../../../models/token_usage.dart';
import '../../helpers/chat_api_helper.dart';
import '../../models/chat_stream_chunk.dart';
import '../../../http/streaming_http_client.dart';
import 'package:kelivo/secrets/fallback.dart';

/// Handler for OpenAI Chat Completions API streaming.
class OpenAIChatCompletions {
  OpenAIChatCompletions._();

  /// Send streaming request using Chat Completions API.
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
    final path = config.chatPath ?? '/chat/completions';
    final url = Uri.parse('$base$path');
    final host = Uri.tryParse(config.baseUrl)?.host.toLowerCase() ?? '';

    final effectiveInfo = ChatApiHelper.effectiveModelInfo(config, modelId);
    final isReasoning = effectiveInfo.abilities.contains(ModelAbility.reasoning);
    final wantsImageOutput = effectiveInfo.output.contains(Modality.image);
    // OpenAI only supports low/medium/high, map minimal to low
    final rawEffort = ChatApiHelper.effortForBudget(thinkingBudget);
    final effort = rawEffort == 'minimal' ? 'low' : rawEffort;
    final isGrok = ChatApiHelper.isGrokModel(config, modelId);

    // Build messages with images
    final mm = <Map<String, dynamic>>[];
    for (int i = 0; i < messages.length; i++) {
      final m = messages[i];
      final isLast = i == messages.length - 1;
      final raw = (m['content'] ?? '').toString();
      final hasMarkdownImages = raw.contains('![') && raw.contains('](');
      final hasCustomImages = raw.contains('[image:');
      final hasAttachedImages = isLast && (userImagePaths?.isNotEmpty == true) && (m['role'] == 'user');

      if (hasMarkdownImages || hasCustomImages || hasAttachedImages) {
        final parsed = ChatApiHelper.parseTextAndImages(raw);
        final parts = <Map<String, dynamic>>[];
        if (parsed.text.isNotEmpty) {
          parts.add({'type': 'text', 'text': parsed.text});
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
          parts.add({'type': 'image_url', 'image_url': {'url': imgUrl}});
        }
        if (hasAttachedImages) {
          for (final p in userImagePaths!) {
            final dataUrl = (p.startsWith('http') || p.startsWith('data:')) ? p : await ChatApiHelper.encodeBase64File(p, withPrefix: true);
            parts.add({'type': 'image_url', 'image_url': {'url': dataUrl}});
          }
        }
        mm.add({'role': m['role'] ?? 'user', 'content': parts});
      } else {
        mm.add({'role': m['role'] ?? 'user', 'content': raw});
      }
    }

    // Build request body
    var body = <String, dynamic>{
      'model': upstreamModelId,
      'messages': mm,
      'stream': true,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'top_p': topP,
      if (maxTokens != null && maxTokens > 0) 'max_tokens': maxTokens,
      if (isReasoning && effort != 'off' && effort != 'auto') 'reasoning_effort': effort,
      if (tools != null && tools.isNotEmpty) 'tools': ChatApiHelper.cleanToolsForCompatibility(tools),
      if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
    };

    // Apply vendor-specific reasoning config
    ChatApiHelper.applyVendorReasoningConfig(
      body: body,
      host: host,
      modelId: modelId,
      isReasoning: isReasoning,
      thinkingBudget: thinkingBudget,
      effort: effort,
      isGrokModel: isGrok,
    );

    // Build headers
    final apiKey = _apiKeyForRequest(config, modelId);
    final headers = <String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };
    headers.addAll(ChatApiHelper.customHeaders(config, modelId));
    if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);

    // Stream options
    if (!host.contains('mistral.ai')) {
      body['stream_options'] = {'include_usage': true};
    }

    // Grok built-in search
    if (isGrok) {
      final builtIns = ChatApiHelper.builtInTools(config, modelId);
      if (builtIns.contains('search')) {
        body['search_parameters'] = {'mode': 'auto', 'return_citations': true};
      }
    }

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
      isReasoning: isReasoning,
      wantsImageOutput: wantsImageOutput,
      thinkingBudget: thinkingBudget,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      effort: effort,
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
    required bool isReasoning,
    required bool wantsImageOutput,
    required int? thinkingBudget,
    required double? temperature,
    required double? topP,
    required int? maxTokens,
    required String effort,
    required List<Map<String, dynamic>>? tools,
    required Future<String> Function(String, Map<String, dynamic>)? onToolCall,
    required Map<String, String>? extraHeaders,
    required Map<String, dynamic>? extraBody,
    required int maxToolLoopIterations,
  }) async* {
    final upstreamModelId = ChatApiHelper.apiModelId(config, modelId);
    final host = Uri.tryParse(config.baseUrl)?.host.toLowerCase() ?? '';
    final isGrok = ChatApiHelper.isGrokModel(config, modelId);
    
    final stream = responseStream.cast<List<int>>().transform(utf8.decoder);
    String buffer = '';
    int totalTokens = 0;
    TokenUsage? usage;
    
    // Approximate token calculation
    int approxTokensFromChars(int chars) => (chars / 4).round();
    final int approxPromptChars = messages.fold<int>(0, (acc, m) => acc + ((m['content'] ?? '').toString().length));
    final int approxPromptTokens = approxTokensFromChars(approxPromptChars);
    int approxCompletionChars = 0;

    // Tool call tracking
    final Map<int, Map<String, String>> toolAcc = {};
    String? finishReason;

    await for (final chunk in stream) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.last;

      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i].trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;

        final data = line.substring(5).trimLeft();
        if (data == '[DONE]') {
          // Handle tool calls at stream end
          if (onToolCall != null && toolAcc.isNotEmpty) {
            yield* _executeToolsAndContinue(
              dio: dio,
              config: config,
              modelId: modelId,
              messages: messages,
              url: url,
              headers: headers,
              toolAcc: toolAcc,
              usage: usage,
              isReasoning: isReasoning,
              wantsImageOutput: wantsImageOutput,
              thinkingBudget: thinkingBudget,
              temperature: temperature,
              topP: topP,
              maxTokens: maxTokens,
              effort: effort,
              tools: tools,
              onToolCall: onToolCall,
              extraHeaders: extraHeaders,
              extraBody: extraBody,
              maxToolLoopIterations: maxToolLoopIterations,
              approxPromptTokens: approxPromptTokens,
              approxCompletionChars: approxCompletionChars,
            );
            return;
          }

          final approxTotal = approxPromptTokens + approxTokensFromChars(approxCompletionChars);
          yield ChatStreamChunk(content: '', isDone: true, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage);
          return;
        }

        try {
          final json = jsonDecode(data);
          String content = '';
          String? reasoning;

          final choices = json['choices'];
          if (choices != null && choices.isNotEmpty) {
            final c0 = choices[0];
            finishReason = c0['finish_reason'] as String?;
            final message = c0['message'];
            final delta = c0['delta'];

            if (message != null && message['content'] != null) {
              // Non-streaming format
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
              }
              if (content.isNotEmpty) approxCompletionChars += content.length;
            } else if (delta != null) {
              // Streaming format
              final dc = delta['content'];
              if (dc is String) {
                content = dc;
              } else if (dc is List) {
                final sb = StringBuffer();
                for (final it in dc) {
                  if (it is Map) {
                    final t = (it['text'] ?? it['delta'] ?? '') as String? ?? '';
                    if (t.isNotEmpty && (it['type'] == null || it['type'] == 'text')) sb.write(t);
                  }
                }
                content = sb.toString();
              }
              if (content.isNotEmpty) approxCompletionChars += content.length;
              
              final rc = (delta['reasoning_content'] ?? delta['reasoning']) as String?;
              if (rc != null && rc.isNotEmpty) reasoning = rc;

              // Handle image outputs
              if (wantsImageOutput) {
                final imageContent = _extractImageContent(delta);
                if (imageContent.isNotEmpty) content += imageContent;
              }

              // Accumulate tool calls
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

          // XinLiu compatibility: root-level tool_calls
          final rootToolCalls = json['tool_calls'] as List?;
          if (rootToolCalls != null) {
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
              final idx = toolAcc.length;
              final entry = toolAcc.putIfAbsent(idx, () => {'id': id.isEmpty ? 'call_$idx' : id, 'name': name, 'args': argsStr});
              if (id.isNotEmpty) entry['id'] = id;
              entry['name'] = name;
              entry['args'] = argsStr;
            }
            if (rootToolCalls.isNotEmpty) finishReason = 'tool_calls';
          }

          // Usage tracking
          final u = json['usage'];
          if (u != null) {
            var prompt = (u['prompt_tokens'] ?? 0) as int;
            final completion = (u['completion_tokens'] ?? 0) as int;
            final cached = (u['prompt_tokens_details']?['cached_tokens'] ?? 0) as int? ?? 0;
            if (prompt == 0 && approxPromptTokens > 0) prompt = approxPromptTokens;
            usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: prompt, completionTokens: completion, cachedTokens: cached));
            totalTokens = usage!.totalTokens;
          }

          // Grok citations
          if (isGrok) {
            final citations = ChatApiHelper.extractGrokCitations(Map<String, dynamic>.from(json));
            if (citations.isNotEmpty) {
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: citations);
            }
          }

          if (content.isNotEmpty || (reasoning != null && reasoning.isNotEmpty)) {
            final approxTotal = approxPromptTokens + approxTokensFromChars(approxCompletionChars);
            yield ChatStreamChunk(
              content: content,
              reasoning: reasoning,
              isDone: false,
              totalTokens: totalTokens > 0 ? totalTokens : approxTotal,
              usage: usage,
            );
          }

          // Handle immediate tool execution for finish_reason='tool_calls'
          if (finishReason == 'tool_calls' && toolAcc.isNotEmpty && onToolCall != null) {
            yield* _executeToolsAndContinue(
              dio: dio,
              config: config,
              modelId: modelId,
              messages: messages,
              url: url,
              headers: headers,
              toolAcc: toolAcc,
              usage: usage,
              isReasoning: isReasoning,
              wantsImageOutput: wantsImageOutput,
              thinkingBudget: thinkingBudget,
              temperature: temperature,
              topP: topP,
              maxTokens: maxTokens,
              effort: effort,
              tools: tools,
              onToolCall: onToolCall,
              extraHeaders: extraHeaders,
              extraBody: extraBody,
              maxToolLoopIterations: maxToolLoopIterations,
              approxPromptTokens: approxPromptTokens,
              approxCompletionChars: approxCompletionChars,
            );
            return;
          }
        } catch (e) {
          // Skip malformed JSON
        }
      }
    }

    // Fallback: provider closed SSE without [DONE]
    yield ChatStreamChunk(content: '', isDone: true, totalTokens: usage?.totalTokens ?? 0, usage: usage);
  }

  // ========== Tool Execution ==========

  static Stream<ChatStreamChunk> _executeToolsAndContinue({
    required Dio dio,
    required ProviderConfig config,
    required String modelId,
    required List<Map<String, dynamic>> messages,
    required Uri url,
    required Map<String, String> headers,
    required Map<int, Map<String, String>> toolAcc,
    required TokenUsage? usage,
    required bool isReasoning,
    required bool wantsImageOutput,
    required int? thinkingBudget,
    required double? temperature,
    required double? topP,
    required int? maxTokens,
    required String effort,
    required List<Map<String, dynamic>>? tools,
    required Future<String> Function(String, Map<String, dynamic>) onToolCall,
    required Map<String, String>? extraHeaders,
    required Map<String, dynamic>? extraBody,
    required int maxToolLoopIterations,
    required int approxPromptTokens,
    required int approxCompletionChars,
  }) async* {
    final upstreamModelId = ChatApiHelper.apiModelId(config, modelId);
    final host = Uri.tryParse(config.baseUrl)?.host.toLowerCase() ?? '';
    final isGrok = ChatApiHelper.isGrokModel(config, modelId);
    
    // Build tool calls
    final calls = <Map<String, dynamic>>[];
    final callInfos = <ToolCallInfo>[];
    final toolMsgs = <Map<String, dynamic>>[];
    toolAcc.forEach((idx, m) {
      final id = (m['id'] ?? 'call_$idx');
      final name = (m['name'] ?? '');
      Map<String, dynamic> args;
      try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
      callInfos.add(ToolCallInfo(id: id, name: name, arguments: args));
      calls.add({'id': id, 'type': 'function', 'function': {'name': name, 'arguments': jsonEncode(args)}});
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

    // Build follow-up messages
    var currentMessages = <Map<String, dynamic>>[];
    for (final m in messages) {
      currentMessages.add({'role': m['role'] ?? 'user', 'content': m['content'] ?? ''});
    }
    currentMessages.add({'role': 'assistant', 'content': '', 'tool_calls': calls});
    for (final r in results) {
      final id = r['tool_call_id'];
      final name = calls.firstWhere((c) => c['id'] == id, orElse: () => const {'function': {'name': ''}})['function']['name'];
      currentMessages.add({'role': 'tool', 'tool_call_id': id, 'name': name, 'content': r['content']});
    }

    // Multi-round tool calling loop
    for (int round = 0; round < maxToolLoopIterations; round++) {
      final body2 = <String, dynamic>{
        'model': upstreamModelId,
        'messages': currentMessages,
        'stream': true,
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (maxTokens != null && maxTokens > 0) 'max_tokens': maxTokens,
        if (isReasoning && effort != 'off' && effort != 'auto') 'reasoning_effort': effort,
        if (tools != null && tools.isNotEmpty) 'tools': ChatApiHelper.cleanToolsForCompatibility(tools),
        if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
      };

      ChatApiHelper.applyVendorReasoningConfig(
        body: body2,
        host: host,
        modelId: modelId,
        isReasoning: isReasoning,
        thinkingBudget: thinkingBudget,
        effort: effort,
        isGrokModel: isGrok,
      );

      if (!host.contains('mistral.ai')) {
        body2['stream_options'] = {'include_usage': true};
      }
      if (extraBody != null && extraBody.isNotEmpty) {
        extraBody.forEach((k, v) {
          body2[k] = (v is String) ? ChatApiHelper.parseOverrideValue(v) : v;
        });
      }

      final headers2 = Map<String, String>.from(headers);
      if (extraHeaders != null && extraHeaders.isNotEmpty) headers2.addAll(extraHeaders);

      final resp2 = await postJsonStream(
        dio: dio,
        url: url,
        headers: headers2,
        body: body2,
      );

      if (resp2.statusCode < 200 || resp2.statusCode >= 300) {
        final errorBytes = await resp2.stream.toList();
        final errorBody = utf8.decode(errorBytes.expand((x) => x).toList());
        throw Exception('HTTP ${resp2.statusCode}: $errorBody');
      }

      final s2 = resp2.stream.cast<List<int>>().transform(utf8.decoder);
      String buf2 = '';
      final Map<int, Map<String, String>> toolAcc2 = {};
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
          if (d == '[DONE]') continue;
          
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
                if (prompt == 0 && approxPromptTokens > 0) prompt = approxPromptTokens;
                usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: prompt, completionTokens: completion, cachedTokens: cached));
              }
              
              if (isGrok) {
                final citations = ChatApiHelper.extractGrokCitations(Map<String, dynamic>.from(o));
                if (citations.isNotEmpty) {
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: citations);
                }
              }
              
              if (rc is String && rc.isNotEmpty) {
                yield ChatStreamChunk(content: '', reasoning: rc, isDone: false, totalTokens: 0, usage: usage);
              }
              if (txt is String && txt.isNotEmpty) {
                contentAccum += txt;
                yield ChatStreamChunk(content: txt, isDone: false, totalTokens: 0, usage: usage);
              }
              
              // Handle image outputs
              if (wantsImageOutput) {
                final imageContent = _extractImageContent(delta);
                if (imageContent.isNotEmpty) {
                  contentAccum += imageContent;
                  yield ChatStreamChunk(content: imageContent, isDone: false, totalTokens: 0, usage: usage);
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
            
            // XinLiu compatibility
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
              if (rootToolCalls2.isNotEmpty && finishReason2 == null) finishReason2 = 'tool_calls';
            }
          } catch (_) {}
        }
      }

      // Check for more tool calls
      if ((finishReason2 == 'tool_calls' || toolAcc2.isNotEmpty)) {
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
        yield ChatStreamChunk(content: '', isDone: true, totalTokens: usage?.totalTokens ?? 0, usage: usage);
        return;
      }
    }
    
    // Max iterations reached
    yield ChatStreamChunk(content: '', isDone: true, totalTokens: usage?.totalTokens ?? 0, usage: usage);
  }

  // ========== Helpers ==========

  static String _extractImageContent(Map? delta) {
    if (delta == null) return '';
    final buf = StringBuffer();
    final List<dynamic> imageItems = [];
    final imgs = delta['images'];
    if (imgs is List) imageItems.addAll(imgs);
    final contentArr = delta['content'] as List?;
    if (contentArr is List) {
      for (final it in contentArr) {
        if (it is Map && (it['type'] == 'image_url' || it['type'] == 'image')) {
          imageItems.add(it);
        }
      }
    }
    final singleImage = delta['image_url'];
    if (singleImage is Map || singleImage is String) {
      imageItems.add({'type': 'image_url', 'image_url': singleImage});
    }
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
        buf.write('\n\n![image]($url)');
      }
    }
    return buf.toString();
  }

  static String _apiKeyForRequest(ProviderConfig cfg, String modelId) {
    final orig = ChatApiHelper.effectiveApiKey(cfg).trim();
    if (orig.isNotEmpty) return orig;
    if ((cfg.id) == 'SiliconFlow') {
      final host = Uri.tryParse(cfg.baseUrl)?.host.toLowerCase() ?? '';
      if (!host.contains('siliconflow')) return orig;
      final m = ChatApiHelper.apiModelId(cfg, modelId).toLowerCase();
      final allowed = m == 'thudm/glm-4-9b-0414' || m == 'qwen/qwen3-8b';
      final fallback = siliconflowFallbackKey.trim();
      if (allowed && fallback.isNotEmpty) return fallback;
    }
    return orig;
  }
}
