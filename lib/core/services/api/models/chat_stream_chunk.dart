/// Chat Stream Data Models
/// Public data classes used by ChatApiService and provider adapters.

import '../../../models/token_usage.dart';

/// A chunk of streamed chat response.
class ChatStreamChunk {
  final String content;
  /// Optional reasoning delta (when model supports reasoning)
  final String? reasoning;
  /// Optional reasoning/thinking signature for Claude (used in multi-turn tool calls)
  final String? reasoningSignature;
  final bool isDone;
  final int totalTokens;
  final TokenUsage? usage;
  final List<ToolCallInfo>? toolCalls;
  final List<ToolResultInfo>? toolResults;

  ChatStreamChunk({
    required this.content,
    this.reasoning,
    this.reasoningSignature,
    required this.isDone,
    required this.totalTokens,
    this.usage,
    this.toolCalls,
    this.toolResults,
  });
}

/// Information about a tool call request.
class ToolCallInfo {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  ToolCallInfo({required this.id, required this.name, required this.arguments});
}

/// Information about a tool call result.
class ToolResultInfo {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String content;
  ToolResultInfo({required this.id, required this.name, required this.arguments, required this.content});
}
