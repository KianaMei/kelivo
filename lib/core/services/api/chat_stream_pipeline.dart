import 'dart:async';
import 'models/chat_stream_event.dart';

/// Streaming pipeline that maintains per-request context and normalizes
/// provider-specific chunks into unified `ChatStreamEvent`s.
///
/// **Responsibilities**:
/// - Track chunk sequence numbers
/// - Maintain tool call state (accumulate streaming arguments)
/// - Detect stream completion/errors
/// - Provide consistent event ordering
///
/// **Usage**:
/// ```dart
/// final pipeline = ChatStreamPipeline(
///   requestId: 'req-123',
///   provider: 'openai',
///   modelId: 'gpt-4o',
/// );
///
/// await for (final chunk in providerStream) {
///   final events = pipeline.processChunk(chunk);
///   for (final event in events) {
///     // Handle event (update UI, etc.)
///   }
/// }
/// ```
class ChatStreamPipeline {
  final String requestId;
  final String? conversationId;
  final String? messageId;
  final String provider;
  final String modelId;

  int _eventIndex = 0;
  final Map<String, _ToolCallState> _toolCalls = {};
  String? _lastFinishReason;

  ChatStreamPipeline({
    required this.requestId,
    this.conversationId,
    this.messageId,
    required this.provider,
    required this.modelId,
  });

  /// Processes a raw provider chunk and returns zero or more events.
  ///
  /// **Note**: This is a placeholder for the actual implementation.
  /// In practice, you would have provider-specific adapters that convert
  /// raw chunks into events. For example:
  ///
  /// ```dart
  /// if (provider == 'openai') {
  ///   return _processOpenAIChunk(chunk);
  /// } else if (provider == 'anthropic') {
  ///   return _processClaudeChunk(chunk);
  /// }
  /// ```
  ///
  /// For now, this is a stub that demonstrates the interface.
  List<ChatStreamEvent> processChunk(dynamic chunk) {
    // TODO: Implement provider-specific adapters
    // This is a placeholder implementation
    return [];
  }

  /// Emits a content delta event.
  ContentDelta _emitContentDelta({
    required String text,
    bool isReasoning = false,
    String? segmentId,
    bool isFinal = false,
    List<Citation>? citations,
    String? branchId,
  }) {
    return ContentDelta(
      requestId: requestId,
      conversationId: conversationId,
      messageId: messageId,
      provider: provider,
      modelId: modelId,
      index: _eventIndex++,
      text: text,
      isReasoning: isReasoning,
      segmentId: segmentId,
      isFinal: isFinal,
      citations: citations,
      branchId: branchId,
    );
  }

  /// Emits a tool call start event and initializes tracking state.
  ToolCallStart _emitToolCallStart({
    required String callId,
    required String name,
    ToolType toolType = ToolType.function,
  }) {
    _toolCalls[callId] = _ToolCallState(
      id: callId,
      name: name,
      toolType: toolType,
    );

    return ToolCallStart(
      requestId: requestId,
      conversationId: conversationId,
      messageId: messageId,
      provider: provider,
      modelId: modelId,
      index: _eventIndex++,
      callId: callId,
      name: name,
      toolType: toolType,
    );
  }

  /// Emits a tool call delta event and accumulates arguments.
  ToolCallDelta _emitToolCallDelta({
    required String callId,
    required String argumentsDelta,
    bool isFinal = false,
  }) {
    final state = _toolCalls[callId];
    if (state != null) {
      state.argumentsBuffer += argumentsDelta;
      if (isFinal) {
        state.isComplete = true;
      }
    }

    return ToolCallDelta(
      requestId: requestId,
      conversationId: conversationId,
      messageId: messageId,
      provider: provider,
      modelId: modelId,
      index: _eventIndex++,
      callId: callId,
      argumentsDelta: argumentsDelta,
      isFinal: isFinal,
    );
  }

  /// Emits a tool call complete event.
  ///
  /// This should be called after all argument deltas have been received.
  ToolCallComplete _emitToolCallComplete({
    required String callId,
    required String name,
    required Map<String, dynamic> arguments,
  }) {
    final state = _toolCalls[callId];
    if (state != null) {
      state.isComplete = true;
    }

    return ToolCallComplete(
      requestId: requestId,
      conversationId: conversationId,
      messageId: messageId,
      provider: provider,
      modelId: modelId,
      index: _eventIndex++,
      callId: callId,
      name: name,
      arguments: arguments,
    );
  }

  /// Emits a tool result event.
  ToolResult _emitToolResult({
    required String callId,
    required String content,
    bool isError = false,
    Map<String, dynamic>? metadata,
  }) {
    return ToolResult(
      requestId: requestId,
      conversationId: conversationId,
      messageId: messageId,
      provider: provider,
      modelId: modelId,
      index: _eventIndex++,
      callId: callId,
      content: content,
      isError: isError,
      metadata: metadata,
    );
  }

  /// Emits a usage update event.
  UsageUpdate _emitUsageUpdate({
    required int promptTokens,
    required int completionTokens,
    int? reasoningTokens,
    dynamic detailedUsage,
  }) {
    return UsageUpdate(
      requestId: requestId,
      conversationId: conversationId,
      messageId: messageId,
      provider: provider,
      modelId: modelId,
      index: _eventIndex++,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      reasoningTokens: reasoningTokens,
      detailedUsage: detailedUsage,
    );
  }

  /// Emits a stream complete event.
  StreamComplete _emitStreamComplete({
    required String finishReason,
    String? branchId,
  }) {
    _lastFinishReason = finishReason;

    return StreamComplete(
      requestId: requestId,
      conversationId: conversationId,
      messageId: messageId,
      provider: provider,
      modelId: modelId,
      index: _eventIndex++,
      finishReason: finishReason,
      branchId: branchId,
    );
  }

  /// Emits a stream error event.
  StreamError _emitStreamError({
    required String message,
    int? statusCode,
    String? rawBody,
  }) {
    return StreamError(
      requestId: requestId,
      conversationId: conversationId,
      messageId: messageId,
      provider: provider,
      modelId: modelId,
      index: _eventIndex++,
      message: message,
      statusCode: statusCode,
      rawBody: rawBody,
    );
  }

  /// Returns the current state of a tool call (for debugging/inspection).
  _ToolCallState? getToolCallState(String callId) {
    return _toolCalls[callId];
  }

  /// Returns all tracked tool calls.
  Map<String, _ToolCallState> get toolCalls => Map.unmodifiable(_toolCalls);

  /// Returns the last finish reason (if stream completed).
  String? get finishReason => _lastFinishReason;

  /// Returns the total number of events emitted.
  int get eventCount => _eventIndex;
}

/// Internal state tracking for a streaming tool call.
class _ToolCallState {
  final String id;
  final String name;
  final ToolType toolType;
  String argumentsBuffer = '';
  bool isComplete = false;

  _ToolCallState({
    required this.id,
    required this.name,
    required this.toolType,
  });

  /// Attempts to parse accumulated arguments as JSON.
  Map<String, dynamic>? tryParseArguments() {
    if (argumentsBuffer.isEmpty) return {};
    try {
      final decoded = _parseJson(argumentsBuffer);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Parsing failed, return null
    }
    return null;
  }

  static dynamic _parseJson(String str) {
    // Placeholder for JSON parsing
    // In real implementation, use dart:convert
    return {};
  }
}

/// Provider-specific adapter interface.
///
/// Implementations convert raw provider chunks into `ChatStreamEvent`s.
/// This allows the pipeline to remain provider-agnostic.
///
/// **Example**:
/// ```dart
/// class OpenAIAdapter extends StreamAdapter {
///   @override
///   List<ChatStreamEvent> adapt(dynamic chunk, ChatStreamPipeline pipeline) {
///     // Parse OpenAI SSE chunk
///     // Return list of events
///   }
/// }
/// ```
abstract class StreamAdapter {
  /// Converts a raw provider chunk into zero or more events.
  ///
  /// The adapter can use `pipeline` helper methods to emit events with
  /// proper context and sequencing.
  List<ChatStreamEvent> adapt(dynamic chunk, ChatStreamPipeline pipeline);
}

/// Convenience wrapper that applies an adapter to a stream.
///
/// **Usage**:
/// ```dart
/// final pipeline = ChatStreamPipeline(
///   requestId: 'req-123',
///   provider: 'openai',
///   modelId: 'gpt-4o',
/// );
///
/// final adapter = OpenAIAdapter();
/// final eventStream = adaptStream(rawChunkStream, adapter, pipeline);
///
/// await for (final event in eventStream) {
///   // Handle event
/// }
/// ```
Stream<ChatStreamEvent> adaptStream(
  Stream<dynamic> rawStream,
  StreamAdapter adapter,
  ChatStreamPipeline pipeline,
) async* {
  await for (final chunk in rawStream) {
    final events = adapter.adapt(chunk, pipeline);
    for (final event in events) {
      yield event;
    }
  }
}
