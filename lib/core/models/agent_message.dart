import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'agent_message.g.dart';

/// Type of agent message
@HiveType(typeId: 13)
enum AgentMessageType {
  @HiveField(0)
  user,
  @HiveField(1)
  assistant,
  @HiveField(2)
  toolCall,
  @HiveField(3)
  toolResult,
  @HiveField(4)
  system,
  @HiveField(5)
  error,
}

/// Tool call status
@HiveType(typeId: 14)
enum ToolCallStatus {
  @HiveField(0)
  pending,
  @HiveField(1)
  running,
  @HiveField(2)
  completed,
  @HiveField(3)
  failed,
  @HiveField(4)
  denied,
}

/// Agent message with tool call support
@HiveType(typeId: 12)
class AgentMessage extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String sessionId;

  @HiveField(2)
  final AgentMessageType type;

  @HiveField(3)
  String content;

  @HiveField(4)
  final DateTime timestamp;

  /// For tool calls: tool name
  @HiveField(5)
  final String? toolName;

  /// For tool calls: input as JSON string
  @HiveField(6)
  final String? toolInputJson;

  /// For tool calls: preview text
  @HiveField(7)
  final String? toolInputPreview;

  /// For tool results: result content
  @HiveField(8)
  String? toolResult;

  /// Tool call status
  @HiveField(9)
  ToolCallStatus? toolStatus;

  /// Related tool call ID (for tool results)
  @HiveField(10)
  final String? relatedToolCallId;

  /// Is this message still streaming
  @HiveField(11)
  bool isStreaming;

  /// Model ID used for this message
  @HiveField(12)
  final String? modelId;

  AgentMessage({
    String? id,
    required this.sessionId,
    required this.type,
    required this.content,
    DateTime? timestamp,
    this.toolName,
    this.toolInputJson,
    this.toolInputPreview,
    this.toolResult,
    this.toolStatus,
    this.relatedToolCallId,
    this.isStreaming = false,
    this.modelId,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  /// Get tool input as Map
  Map<String, dynamic>? get toolInput {
    if (toolInputJson == null) return null;
    try {
      return jsonDecode(toolInputJson!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  AgentMessage copyWith({
    String? id,
    String? sessionId,
    AgentMessageType? type,
    String? content,
    DateTime? timestamp,
    String? toolName,
    String? toolInputJson,
    String? toolInputPreview,
    String? toolResult,
    ToolCallStatus? toolStatus,
    String? relatedToolCallId,
    bool? isStreaming,
    String? modelId,
    bool clearToolResult = false,
  }) {
    return AgentMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      type: type ?? this.type,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      toolName: toolName ?? this.toolName,
      toolInputJson: toolInputJson ?? this.toolInputJson,
      toolInputPreview: toolInputPreview ?? this.toolInputPreview,
      toolResult: clearToolResult ? null : (toolResult ?? this.toolResult),
      toolStatus: toolStatus ?? this.toolStatus,
      relatedToolCallId: relatedToolCallId ?? this.relatedToolCallId,
      isStreaming: isStreaming ?? this.isStreaming,
      modelId: modelId ?? this.modelId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'type': type.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'toolName': toolName,
      'toolInputJson': toolInputJson,
      'toolInputPreview': toolInputPreview,
      'toolResult': toolResult,
      'toolStatus': toolStatus?.name,
      'relatedToolCallId': relatedToolCallId,
      'isStreaming': isStreaming,
      'modelId': modelId,
    };
  }

  factory AgentMessage.fromJson(Map<String, dynamic> json) {
    return AgentMessage(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      type: AgentMessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AgentMessageType.assistant,
      ),
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      toolName: json['toolName'] as String?,
      toolInputJson: json['toolInputJson'] as String?,
      toolInputPreview: json['toolInputPreview'] as String?,
      toolResult: json['toolResult'] as String?,
      toolStatus: json['toolStatus'] != null
          ? ToolCallStatus.values.firstWhere(
              (e) => e.name == json['toolStatus'],
              orElse: () => ToolCallStatus.pending,
            )
          : null,
      relatedToolCallId: json['relatedToolCallId'] as String?,
      isStreaming: json['isStreaming'] as bool? ?? false,
      modelId: json['modelId'] as String?,
    );
  }
}
