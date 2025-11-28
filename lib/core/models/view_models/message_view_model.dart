/// View models for UI rendering, decoupled from provider-specific data structures.
///
/// These models contain only the fields needed for display, with pre-formatted
/// values where appropriate. UI code should consume these instead of raw
/// provider responses.
///
/// **Design Goals**:
/// - UI-friendly field names and types
/// - No provider-specific logic in UI code
/// - Easy to test and mock
/// - Immutable data structures

/// View model for a chat message.
///
/// Represents a single message in the conversation, with all necessary
/// display information pre-computed.
class MessageViewModel {
  final String id;
  final String role; // 'user' | 'assistant' | 'system' | 'tool'
  final String content;
  final DateTime timestamp;

  // Optional fields
  final String? modelName;
  final String? modelIcon;
  final TokenUsageViewModel? tokenUsage;
  final List<ToolCallViewModel>? toolCalls;
  final List<CitationViewModel>? citations;
  final ReasoningViewModel? reasoning;
  final List<AttachmentViewModel>? attachments;

  // UI state
  final bool isStreaming;
  final bool hasError;
  final String? errorMessage;

  const MessageViewModel({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.modelName,
    this.modelIcon,
    this.tokenUsage,
    this.toolCalls,
    this.citations,
    this.reasoning,
    this.attachments,
    this.isStreaming = false,
    this.hasError = false,
    this.errorMessage,
  });

  MessageViewModel copyWith({
    String? id,
    String? role,
    String? content,
    DateTime? timestamp,
    String? modelName,
    String? modelIcon,
    TokenUsageViewModel? tokenUsage,
    List<ToolCallViewModel>? toolCalls,
    List<CitationViewModel>? citations,
    ReasoningViewModel? reasoning,
    List<AttachmentViewModel>? attachments,
    bool? isStreaming,
    bool? hasError,
    String? errorMessage,
  }) {
    return MessageViewModel(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      modelName: modelName ?? this.modelName,
      modelIcon: modelIcon ?? this.modelIcon,
      tokenUsage: tokenUsage ?? this.tokenUsage,
      toolCalls: toolCalls ?? this.toolCalls,
      citations: citations ?? this.citations,
      reasoning: reasoning ?? this.reasoning,
      attachments: attachments ?? this.attachments,
      isStreaming: isStreaming ?? this.isStreaming,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// View model for token usage statistics.
class TokenUsageViewModel {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int? reasoningTokens;

  // Formatted strings for display
  final String promptDisplay; // e.g., "1.2K"
  final String completionDisplay;
  final String totalDisplay;

  // Per-round breakdown (for multi-turn tool calls)
  final List<RoundUsageViewModel>? rounds;

  const TokenUsageViewModel({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    this.reasoningTokens,
    required this.promptDisplay,
    required this.completionDisplay,
    required this.totalDisplay,
    this.rounds,
  });

  /// Creates a view model with auto-formatted display strings.
  factory TokenUsageViewModel.fromCounts({
    required int promptTokens,
    required int completionTokens,
    int? reasoningTokens,
    List<RoundUsageViewModel>? rounds,
  }) {
    return TokenUsageViewModel(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: promptTokens + completionTokens,
      reasoningTokens: reasoningTokens,
      promptDisplay: _formatTokenCount(promptTokens),
      completionDisplay: _formatTokenCount(completionTokens),
      totalDisplay: _formatTokenCount(promptTokens + completionTokens),
      rounds: rounds,
    );
  }

  static String _formatTokenCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

/// View model for per-round token usage (multi-turn tool calls).
class RoundUsageViewModel {
  final int roundNumber;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const RoundUsageViewModel({
    required this.roundNumber,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });
}

/// View model for a tool call.
class ToolCallViewModel {
  final String id;
  final String name;
  final String displayName; // User-friendly name
  final Map<String, dynamic> arguments;
  final String? result;
  final bool isLoading;
  final bool hasError;
  final String? errorMessage;

  const ToolCallViewModel({
    required this.id,
    required this.name,
    required this.displayName,
    required this.arguments,
    this.result,
    this.isLoading = false,
    this.hasError = false,
    this.errorMessage,
  });
}

/// View model for a citation/source reference.
class CitationViewModel {
  final String id;
  final String title;
  final String? url;
  final String? snippet;
  final int? position; // Position in text (for highlighting)

  const CitationViewModel({
    required this.id,
    required this.title,
    this.url,
    this.snippet,
    this.position,
  });
}

/// View model for reasoning/thinking content.
class ReasoningViewModel {
  final String content;
  final List<ReasoningSegmentViewModel>? segments;
  final bool isExpanded;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final Duration? duration;

  const ReasoningViewModel({
    required this.content,
    this.segments,
    this.isExpanded = false,
    this.startedAt,
    this.finishedAt,
    this.duration,
  });
}

/// View model for a reasoning segment (for models with structured thinking).
class ReasoningSegmentViewModel {
  final String id;
  final String title;
  final String content;
  final int order;

  const ReasoningSegmentViewModel({
    required this.id,
    required this.title,
    required this.content,
    required this.order,
  });
}

/// View model for a file attachment.
class AttachmentViewModel {
  final String id;
  final String name;
  final String type; // 'image' | 'file'
  final String? mimeType;
  final String? path; // Local file path
  final String? url; // Remote URL
  final int? size;
  final String? sizeDisplay; // e.g., "2.5 MB"

  const AttachmentViewModel({
    required this.id,
    required this.name,
    required this.type,
    this.mimeType,
    this.path,
    this.url,
    this.size,
    this.sizeDisplay,
  });

  bool get isImage => type == 'image';
  bool get isFile => type == 'file';
}
