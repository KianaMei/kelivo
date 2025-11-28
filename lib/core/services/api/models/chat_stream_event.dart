import '../../../models/token_usage.dart';

/// Unified streaming event model for chat completions.
///
/// This module defines a provider-agnostic event stream that normalizes
/// chunks from different LLM providers (OpenAI, Claude, Gemini, etc.) into
/// a consistent format for UI consumption.
///
/// **Event Types**:
/// - `ContentDelta`: Text content increments
/// - `ToolCallStart`: Tool invocation begins
/// - `ToolCallDelta`: Tool arguments streaming
/// - `ToolCallComplete`: Tool invocation finalized
/// - `ToolResult`: Tool execution result
/// - `UsageUpdate`: Token consumption stats
/// - `StreamComplete`: Stream finished successfully
/// - `StreamError`: Stream encountered an error
///
/// **Design Goals**:
/// - UI code only consumes events, never raw provider chunks
/// - All provider-specific logic stays in adapters
/// - Events carry full context (requestId, messageId, provider, model)
abstract class ChatStreamEvent {
  /// Unique identifier for this request (for debugging/logging)
  final String requestId;

  /// Conversation ID (if applicable)
  final String? conversationId;

  /// Message ID being generated
  final String? messageId;

  /// Provider key (e.g., 'openai', 'anthropic')
  final String provider;

  /// Model ID being used
  final String modelId;

  /// Sequential index of this event in the stream
  final int index;

  const ChatStreamEvent({
    required this.requestId,
    this.conversationId,
    this.messageId,
    required this.provider,
    required this.modelId,
    required this.index,
  });
}

/// Text content increment event.
///
/// **Fields**:
/// - `text`: The incremental text to append
/// - `isReasoning`: Whether this is reasoning/thinking content (vs. final answer)
/// - `segmentId`: For multi-segment reasoning (e.g., DeepSeek R1)
/// - `isFinal`: Whether this segment is complete
/// - `citations`: Source references (for RAG/search results)
/// - `branchId`: For branching responses (rare)
class ContentDelta extends ChatStreamEvent {
  final String text;
  final bool isReasoning;
  final String? segmentId;
  final bool isFinal;
  final List<Citation>? citations;
  final String? branchId;

  const ContentDelta({
    required super.requestId,
    super.conversationId,
    super.messageId,
    required super.provider,
    required super.modelId,
    required super.index,
    required this.text,
    this.isReasoning = false,
    this.segmentId,
    this.isFinal = false,
    this.citations,
    this.branchId,
  });
}

/// Tool call initiation event.
///
/// Signals that the model wants to invoke a tool. Arguments may follow
/// in subsequent `ToolCallDelta` events (for streaming tool calls).
class ToolCallStart extends ChatStreamEvent {
  final String callId;
  final String name;
  final ToolType toolType;

  const ToolCallStart({
    required super.requestId,
    super.conversationId,
    super.messageId,
    required super.provider,
    required super.modelId,
    required super.index,
    required this.callId,
    required this.name,
    this.toolType = ToolType.function,
  });
}

/// Tool call arguments streaming event.
///
/// For providers that stream tool arguments incrementally (e.g., OpenAI).
class ToolCallDelta extends ChatStreamEvent {
  final String callId;
  final String argumentsDelta;
  final bool isFinal;

  const ToolCallDelta({
    required super.requestId,
    super.conversationId,
    super.messageId,
    required super.provider,
    required super.modelId,
    required super.index,
    required this.callId,
    required this.argumentsDelta,
    this.isFinal = false,
  });
}

/// Tool call completion event.
///
/// Emitted when all arguments have been received and the tool call is ready
/// for execution.
class ToolCallComplete extends ChatStreamEvent {
  final String callId;
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCallComplete({
    required super.requestId,
    super.conversationId,
    super.messageId,
    required super.provider,
    required super.modelId,
    required super.index,
    required this.callId,
    required this.name,
    required this.arguments,
  });
}

/// Tool execution result event.
///
/// Contains the output from executing a tool call.
class ToolResult extends ChatStreamEvent {
  final String callId;
  final String content;
  final bool isError;
  final Map<String, dynamic>? metadata;

  const ToolResult({
    required super.requestId,
    super.conversationId,
    super.messageId,
    required super.provider,
    required super.modelId,
    required super.index,
    required this.callId,
    required this.content,
    this.isError = false,
    this.metadata,
  });
}

/// Token usage update event.
///
/// Reports cumulative token consumption for the request.
class UsageUpdate extends ChatStreamEvent {
  final int promptTokens;
  final int completionTokens;
  final int? reasoningTokens;
  final TokenUsage? detailedUsage;

  const UsageUpdate({
    required super.requestId,
    super.conversationId,
    super.messageId,
    required super.provider,
    required super.modelId,
    required super.index,
    required this.promptTokens,
    required this.completionTokens,
    this.reasoningTokens,
    this.detailedUsage,
  });

  int get totalTokens => promptTokens + completionTokens;
}

/// Stream completion event.
///
/// Signals that the stream has finished successfully.
class StreamComplete extends ChatStreamEvent {
  final String finishReason;
  final String? branchId;

  const StreamComplete({
    required super.requestId,
    super.conversationId,
    super.messageId,
    required super.provider,
    required super.modelId,
    required super.index,
    required this.finishReason,
    this.branchId,
  });
}

/// Stream error event.
///
/// Signals that the stream encountered an error and will terminate.
class StreamError extends ChatStreamEvent {
  final String message;
  final int? statusCode;
  final String? rawBody;

  const StreamError({
    required super.requestId,
    super.conversationId,
    super.messageId,
    required super.provider,
    required super.modelId,
    required super.index,
    required this.message,
    this.statusCode,
    this.rawBody,
  });
}

// ========== Supporting Types ==========

/// Citation/source reference for RAG responses.
class Citation {
  final String id;
  final String? title;
  final String? url;
  final String? snippet;
  final Map<String, dynamic>? metadata;

  const Citation({
    required this.id,
    this.title,
    this.url,
    this.snippet,
    this.metadata,
  });
}

/// Tool invocation type.
enum ToolType {
  function,
  builtIn, // Provider-native tools (e.g., Gemini search)
}
