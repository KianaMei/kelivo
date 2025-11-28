/// OpenAI Provider Adapter - Unified entry point
/// Routes to appropriate sub-handler based on API type.

import 'package:http/http.dart' as http;
import '../../../../providers/settings_provider.dart';
import '../../helpers/chat_api_helper.dart';
import '../../models/chat_stream_chunk.dart';
import 'openai_chat_completions.dart';
import 'openai_responses_api.dart';

/// Adapter for OpenAI-compatible API streaming.
class OpenAIAdapter {
  OpenAIAdapter._();

  /// Send streaming request to OpenAI-compatible API.
  /// Routes to Responses API or Chat Completions based on config.
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
    Future<String> Function(String, Map<String, dynamic>)? onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
  }) async* {
    if (config.useResponseApi == true) {
      // Use OpenAI Responses API
      yield* OpenAIResponsesApi.sendStream(
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
      // Use standard Chat Completions API
      yield* OpenAIChatCompletions.sendStream(
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
    }
  }
}
