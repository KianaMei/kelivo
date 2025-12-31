/// xAI Provider Adapter - Unified entry point for xAI/Grok API.
/// Always uses the Responses API for Agentic Tool Calling support.

import 'package:dio/dio.dart';
import '../../../../providers/settings_provider.dart';
import '../../models/chat_stream_chunk.dart';
import 'xai_responses_api.dart';

/// Adapter for xAI API streaming.
/// Routes all requests to the Responses API for Agentic Tool Calling support.
class XAIAdapter {
  XAIAdapter._();

  /// Send streaming request to xAI API.
  /// Always uses Responses API for web_search, x_search, and code_execution support.
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
    // xAI always uses Responses API for Agentic Tool Calling
    yield* XAIResponsesApi.sendStream(
      dio,
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
  }
}
