/// Google (Gemini/Vertex AI) Provider Adapter
/// Handles streaming chat completions for Google Gemini and Vertex AI.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../providers/settings_provider.dart';
import '../../../providers/model_provider.dart';
import '../../../models/token_usage.dart';
import '../helpers/chat_api_helper.dart';
import '../models/chat_stream_chunk.dart';
import '../google_service_account_auth.dart';

/// Adapter for Google Gemini/Vertex AI streaming.
class GoogleAdapter {
  GoogleAdapter._();

  /// Send streaming request to Google API.
  static Stream<ChatStreamChunk> sendStream(
    http.Client client,
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
    Future<String> Function(String name, Map<String, dynamic> args)? onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
  }) async* {
    final upstreamModelId = ChatApiHelper.apiModelId(config, modelId);
    
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
      final eff = ChatApiHelper.effectiveApiKey(config);
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

      final hasMarkdownImages = raw.contains('![') && raw.contains('](');
      final hasCustomImages = raw.contains('[image:');
      final hasAttachedImages = isLast && role == 'user' && (userImagePaths?.isNotEmpty == true);

      if (hasMarkdownImages || hasCustomImages || hasAttachedImages) {
        final parsed = ChatApiHelper.parseTextAndImages(raw);
        if (parsed.text.isNotEmpty) parts.add({'text': parsed.text});
        for (final ref in parsed.images) {
          if (ref.type == ImageRefType.data) {
            final mime = ChatApiHelper.mimeFromDataUrl(ref.value);
            final idx = ref.value.indexOf('base64,');
            if (idx > 0) {
              final b64 = ref.value.substring(idx + 7);
              parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
            } else {
              parts.add({'text': ref.value});
            }
          } else if (ref.type == ImageRefType.path) {
            final mime = ChatApiHelper.mimeFromPath(ref.value);
            final b64 = await ChatApiHelper.encodeBase64File(ref.value, withPrefix: false);
            parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
          } else {
            parts.add({'text': '(image) ${ref.value}'});
          }
        }
        if (hasAttachedImages) {
          for (final p in userImagePaths!) {
            if (p.startsWith('data:')) {
              final mime = ChatApiHelper.mimeFromDataUrl(p);
              final idx = p.indexOf('base64,');
              if (idx > 0) {
                final b64 = p.substring(idx + 7);
                parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
              }
            } else if (!(p.startsWith('http://') || p.startsWith('https://'))) {
              final mime = ChatApiHelper.mimeFromPath(p);
              final b64 = await ChatApiHelper.encodeBase64File(p, withPrefix: false);
              parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
            } else {
              parts.add({'text': '(image) $p'});
            }
          }
        }
      } else {
        if (raw.isNotEmpty) parts.add({'text': raw});
      }
      contents.add({'role': role, 'parts': parts});
    }

    // Effective model features
    final effective = ChatApiHelper.effectiveModelInfo(config, modelId);
    final isReasoning = effective.abilities.contains(ModelAbility.reasoning);
    final wantsImageOutput = effective.output.contains(Modality.image);
    bool expectImage = wantsImageOutput;
    bool receivedImage = false;
    final off = ChatApiHelper.isReasoningOff(thinkingBudget);

    // Built-in Gemini tools
    final builtIns = ChatApiHelper.builtInTools(config, modelId);
    final isOfficialGemini = config.vertexAI != true;
    final builtInToolEntries = <Map<String, dynamic>>[];
    if (isOfficialGemini && builtIns.isNotEmpty) {
      if (builtIns.contains('search')) {
        builtInToolEntries.add({'google_search': {}});
      }
      if (builtIns.contains('url_context')) {
        builtInToolEntries.add({'url_context': {}});
      }
    }

    // Map OpenAI-style tools to Gemini functionDeclarations
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
          d['parameters'] = ChatApiHelper.cleanSchemaForGemini(params);
        }
        decls.add(d);
      }
      if (decls.isNotEmpty) geminiTools = [{'function_declarations': decls}];
    }

    // Conversation for multi-round tool calls
    List<Map<String, dynamic>> convo = List<Map<String, dynamic>>.from(contents);
    TokenUsage? usage;
    int totalTokens = 0;
    final List<Map<String, dynamic>> builtinCitations = [];

    while (true) {
      final gen = <String, dynamic>{
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'topP': topP,
        if (maxTokens != null && maxTokens > 0) 'maxOutputTokens': maxTokens,
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
      headers.addAll(ChatApiHelper.customHeaders(config, modelId));
      if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
      request.headers.addAll(headers);
      
      final extra = ChatApiHelper.customBody(config, modelId);
      if (extra.isNotEmpty) body.addAll(extra);
      if (extraBody != null && extraBody.isNotEmpty) {
        extraBody.forEach((k, v) {
          body[k] = (v is String) ? ChatApiHelper.parseOverrideValue(v) : v;
        });
      }
      request.body = jsonEncode(body);

      final resp = await client.send(request);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final errorBody = await resp.stream.bytesToString();
        throw HttpException('HTTP ${resp.statusCode}: $errorBody');
      }

      final stream = resp.stream.transform(utf8.decoder);
      String buffer = '';
      final List<Map<String, dynamic>> calls = [];
      bool imageOpen = false;
      String imageMime = 'image/png';

      await for (final chunk in stream) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.last;

        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isEmpty || !line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data.isEmpty) continue;
          try {
            final obj = jsonDecode(data) as Map<String, dynamic>;
            final um = obj['usageMetadata'];
            if (um is Map<String, dynamic>) {
              final thoughtTokens = (um['thoughtsTokenCount'] ?? 0) as int;
              final candidateTokens = (um['candidatesTokenCount'] ?? 0) as int;
              usage = (usage ?? const TokenUsage()).merge(TokenUsage(
                promptTokens: (um['promptTokenCount'] ?? 0) as int,
                completionTokens: candidateTokens + thoughtTokens,
                thoughtTokens: thoughtTokens,
                totalTokens: (um['totalTokenCount'] ?? 0) as int,
              ));
              totalTokens = usage!.totalTokens;
            }

            final candidates = obj['candidates'];
            if (candidates is List && candidates.isNotEmpty) {
              String textDelta = '';
              String reasoningDelta = '';
              String? finishReason;
              
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
                  
                  // Parse inline image data
                  final inline = (p['inlineData'] ?? p['inline_data']);
                  if (inline is Map) {
                    final mime = (inline['mimeType'] ?? inline['mime_type'] ?? 'image/png').toString();
                    final imgData = (inline['data'] ?? '').toString();
                    if (imgData.isNotEmpty) {
                      imageMime = mime.isNotEmpty ? mime : 'image/png';
                      if (!imageOpen) {
                        textDelta += '\n\n![image](data:$imageMime;base64,';
                        imageOpen = true;
                      }
                      textDelta += imgData;
                      receivedImage = true;
                    }
                  }
                  
                  // Parse fileData
                  final fileData = (p['fileData'] ?? p['file_data']);
                  if (fileData is Map) {
                    final mime = (fileData['mimeType'] ?? fileData['mime_type'] ?? 'image/png').toString();
                    final fileUri = (fileData['fileUri'] ?? fileData['file_uri'] ?? fileData['uri'] ?? '').toString();
                    if (fileUri.startsWith('http')) {
                      try {
                        final b64 = await _downloadRemoteAsBase64(client, config, fileUri);
                        imageMime = mime.isNotEmpty ? mime : 'image/png';
                        if (!imageOpen) {
                          textDelta += '\n\n![image](data:$imageMime;base64,';
                          imageOpen = true;
                        }
                        textDelta += b64;
                        receivedImage = true;
                      } catch (_) {}
                    }
                  }
                  
                  // Function call
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
                
                final fr = cand['finishReason'];
                if (fr is String && fr.isNotEmpty) finishReason = fr;

                // Parse grounding metadata
                final gm = cand['groundingMetadata'] ?? obj['groundingMetadata'];
                final cite = _parseCitations(gm);
                if (cite.isNotEmpty) {
                  final existingUrls = builtinCitations.map((e) => e['url']?.toString() ?? '').toSet();
                  for (final it in cite) {
                    final u = it['url']?.toString() ?? '';
                    if (u.isEmpty || existingUrls.contains(u)) continue;
                    builtinCitations.add(it);
                    existingUrls.add(u);
                  }
                  final payload = jsonEncode({'items': builtinCitations});
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

              if (finishReason != null && calls.isEmpty && (!expectImage || receivedImage)) {
                if (imageOpen) {
                  yield ChatStreamChunk(content: ')', isDone: false, totalTokens: totalTokens, usage: usage);
                  imageOpen = false;
                }
                if (builtinCitations.isNotEmpty) {
                  final payload = jsonEncode({'items': builtinCitations});
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, usage: usage, toolResults: [ToolResultInfo(id: 'builtin_search', name: 'builtin_search', arguments: const <String, dynamic>{}, content: payload)]);
                }
                yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
                return;
              }
            }
          } catch (_) {}
        }
      }

      if (imageOpen) {
        yield ChatStreamChunk(content: ')', isDone: false, totalTokens: totalTokens, usage: usage);
        imageOpen = false;
      }

      if (calls.isEmpty) {
        yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
        return;
      }

      // Append function calls and responses to conversation
      for (final c in calls) {
        final name = (c['name'] ?? '').toString();
        final args = (c['args'] as Map<String, dynamic>? ?? const <String, dynamic>{});
        final resText = (c['result'] ?? '').toString();
        final thoughtSigKey = c['thoughtSigKey'] as String?;
        final thoughtSigVal = c['thoughtSigVal'];
        
        final functionCallObj = <String, dynamic>{'name': name, 'args': args};
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
    }
  }

  // ========== Private Helpers ==========

  static List<Map<String, dynamic>> _parseCitations(dynamic gm) {
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
      if (uri.isEmpty || seen.contains(uri)) continue;
      seen.add(uri);
      final title = (web['title'] ?? web['name'] ?? uri).toString();
      final id = 'c${idx.toString().padLeft(2, '0')}';
      out.add({'id': id, 'index': idx, 'title': title, 'url': uri});
      idx++;
    }
    return out;
  }

  static Future<String> _downloadRemoteAsBase64(http.Client client, ProviderConfig config, String url) async {
    final req = http.Request('GET', Uri.parse(url));
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

  static Future<String?> _maybeVertexAccessToken(ProviderConfig cfg) async {
    if (cfg.vertexAI == true) {
      final jsonStr = (cfg.serviceAccountJson ?? '').trim();
      if (jsonStr.isEmpty) {
        if (cfg.apiKey.isNotEmpty) return cfg.apiKey;
        return null;
      }
      try {
        return await GoogleServiceAccountAuth.getAccessTokenFromJson(jsonStr);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
