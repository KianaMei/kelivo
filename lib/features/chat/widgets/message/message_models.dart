import 'package:flutter/material.dart';

/// Data models for message UI components.
///
/// These models are used by message renderers and should be kept in sync
/// with the main ChatMessage model.

/// Tool call UI representation.
class ToolUIPart {
  final String id;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String? content;
  final bool loading;

  const ToolUIPart({
    required this.id,
    required this.toolName,
    required this.arguments,
    this.content,
    this.loading = false,
  });
}

/// Reasoning segment for structured thinking display.
class ReasoningSegment {
  final String text;
  final bool expanded;
  final bool loading;
  final DateTime? startAt;
  final DateTime? finishedAt;
  final VoidCallback? onToggle;
  final int toolStartIndex;

  const ReasoningSegment({
    required this.text,
    required this.expanded,
    required this.loading,
    this.startAt,
    this.finishedAt,
    this.onToggle,
    this.toolStartIndex = 0,
  });
}

/// Parsed user message content.
class ParsedUserContent {
  final String text;
  final List<String> images;
  final List<DocRef> docs;
  
  ParsedUserContent(this.text, this.images, this.docs);
}

/// Document reference in user message.
class DocRef {
  final String path;
  final String fileName;
  final String mime;
  
  DocRef({
    required this.path,
    required this.fileName,
    required this.mime,
  });
}
