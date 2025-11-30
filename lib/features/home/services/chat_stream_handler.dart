import 'dart:convert';
import '../../../core/services/api/models/chat_stream_chunk.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/models/token_usage.dart';
import '../../../core/models/chat_message.dart';
import '../../chat/widgets/message/message_models.dart';
import '../state/reasoning_state.dart';

/// 流处理上下文 - 封装流处理所需的状态和回调
class StreamContext {
  final ChatMessage assistantMessage;
  final String conversationId;
  final ChatService chatService;
  final bool streamOutput;
  final bool supportsReasoning;
  final bool autoCollapseThinking;
  final DateTime startTime;

  // 状态访问器
  final Map<String, ReasoningData> reasoning;
  final Map<String, List<ReasoningSegmentData>> reasoningSegments;
  final Map<String, List<ToolUIPart>> toolParts;
  final Map<String, String> inlineThinkBuffer;
  final Map<String, bool> inInlineThink;

  // UI 更新回调
  final void Function() notifyUI;
  final void Function() scrollToBottom;
  final bool Function() isMounted;
  final bool Function() isCurrentConversation;

  // 可变状态
  String fullContent = '';
  TokenUsage? usage;
  int totalTokens = 0;
  DateTime? firstTokenTime;
  String bufferedReasoning = '';
  DateTime? reasoningStartAt;

  StreamContext({
    required this.assistantMessage,
    required this.conversationId,
    required this.chatService,
    required this.streamOutput,
    required this.supportsReasoning,
    required this.autoCollapseThinking,
    required this.startTime,
    required this.reasoning,
    required this.reasoningSegments,
    required this.toolParts,
    required this.inlineThinkBuffer,
    required this.inInlineThink,
    required this.notifyUI,
    required this.scrollToBottom,
    required this.isMounted,
    required this.isCurrentConversation,
  });

  String get messageId => assistantMessage.id;
}

/// 流处理结果
class StreamResult {
  final String content;
  final TokenUsage? usage;
  final int totalTokens;

  StreamResult({
    required this.content,
    this.usage,
    required this.totalTokens,
  });
}

/// 聊天流处理器 - 统一处理 sendMessage 和 regenerateAtMessage 的流处理逻辑
class ChatStreamHandler {
  /// 去重工具事件列表
  static List<Map<String, dynamic>> dedupeToolEvents(List<Map<String, dynamic>> events) {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final e in events.reversed) {
      final id = e['id'] as String? ?? '';
      if (id.isNotEmpty && !seen.contains(id)) {
        seen.add(id);
        result.insert(0, e);
      } else if (id.isEmpty) {
        result.insert(0, e);
      }
    }
    return result;
  }

  /// 去重 ToolUIPart 列表
  static List<ToolUIPart> dedupeToolPartsList(List<ToolUIPart> parts) {
    final seen = <String>{};
    final result = <ToolUIPart>[];
    for (final p in parts.reversed) {
      if (p.id.isNotEmpty && !seen.contains(p.id)) {
        seen.add(p.id);
        result.insert(0, p);
      } else if (p.id.isEmpty) {
        result.insert(0, p);
      }
    }
    return result;
  }

  /// 处理推理块
  static Future<void> handleReasoningChunk(
    StreamContext ctx,
    String reasoningText,
  ) async {
    if (reasoningText.isEmpty) return;

    if (ctx.streamOutput) {
      final r = ctx.reasoning[ctx.messageId] ?? ReasoningData();
      r.text += reasoningText;
      r.startAt ??= DateTime.now();
      r.expanded = false;
      ctx.reasoning[ctx.messageId] = r;

      // 更新 reasoning segments
      final segments = ctx.reasoningSegments[ctx.messageId] ?? <ReasoningSegmentData>[];
      final toolCount = ctx.toolParts[ctx.messageId]?.length ?? 0;

      if (segments.isEmpty) {
        final seg = ReasoningSegmentData();
        seg.text = reasoningText;
        seg.startAt = DateTime.now();
        seg.expanded = false;
        seg.toolStartIndex = toolCount;
        segments.add(seg);
      } else {
        final last = segments.last;
        final hasToolsAfter = (ctx.toolParts[ctx.messageId]?.isNotEmpty ?? false) && last.finishedAt != null;
        if (hasToolsAfter) {
          final seg = ReasoningSegmentData();
          seg.text = reasoningText;
          seg.startAt = DateTime.now();
          seg.expanded = false;
          seg.toolStartIndex = toolCount;
          segments.add(seg);
        } else {
          last.text += reasoningText;
          last.startAt ??= DateTime.now();
        }
      }
      ctx.reasoningSegments[ctx.messageId] = segments;

      // 持久化
      await ctx.chatService.updateMessage(
        ctx.messageId,
        reasoningText: r.text,
        reasoningStartAt: r.startAt,
        reasoningSegmentsJson: ReasoningStateManager.serializeSegments(segments),
      );

      if (ctx.isMounted() && ctx.isCurrentConversation()) ctx.notifyUI();
    } else {
      ctx.reasoningStartAt ??= DateTime.now();
      ctx.bufferedReasoning += reasoningText;
    }
  }

  /// 处理工具调用块
  static Future<void> handleToolCallChunk(
    StreamContext ctx,
    List<ToolCallInfo> toolCalls,
  ) async {
    if (toolCalls.isEmpty) return;

    // 处理未完成的内联 think 块
    final inThink = ctx.inInlineThink[ctx.messageId] ?? false;
    if (inThink) {
      final buffer = ctx.inlineThinkBuffer[ctx.messageId] ?? '';
      if (buffer.trim().isNotEmpty) {
        final segs = ctx.reasoningSegments[ctx.messageId] ?? <ReasoningSegmentData>[];
        final toolCount = ctx.toolParts[ctx.messageId]?.length ?? 0;
        if (segs.isEmpty || segs.last.finishedAt != null) {
          final seg = ReasoningSegmentData();
          seg.text = buffer.trim();
          seg.startAt = DateTime.now();
          seg.expanded = true;
          seg.toolStartIndex = toolCount;
          seg.finishedAt = DateTime.now();
          segs.add(seg);
        } else {
          segs.last.text += '\n\n${buffer.trim()}';
          segs.last.finishedAt = DateTime.now();
        }
        if (ctx.autoCollapseThinking && segs.isNotEmpty) {
          segs.last.expanded = false;
        }
        ctx.reasoningSegments[ctx.messageId] = segs;
      }
      ctx.inlineThinkBuffer[ctx.messageId] = '';
      ctx.inInlineThink[ctx.messageId] = false;
    }

    // 添加工具调用 UI 部件
    final existing = List<ToolUIPart>.of(ctx.toolParts[ctx.messageId] ?? const []);
    for (final c in toolCalls) {
      existing.add(ToolUIPart(id: c.id, toolName: c.name, arguments: c.arguments, loading: true));
    }
    ctx.toolParts[ctx.messageId] = dedupeToolPartsList(existing);
    if (ctx.isMounted() && ctx.isCurrentConversation()) ctx.notifyUI();

    // 完成当前 reasoning segment
    final segments = ctx.reasoningSegments[ctx.messageId] ?? <ReasoningSegmentData>[];
    if (segments.isNotEmpty && segments.last.finishedAt == null) {
      segments.last.finishedAt = DateTime.now();
      if (ctx.autoCollapseThinking) {
        segments.last.expanded = false;
        final rd = ctx.reasoning[ctx.messageId];
        if (rd != null) rd.expanded = false;
      }
      ctx.reasoningSegments[ctx.messageId] = segments;
      await ctx.chatService.updateMessage(
        ctx.messageId,
        reasoningSegmentsJson: ReasoningStateManager.serializeSegments(segments),
      );
    }

    // 持久化工具事件
    try {
      final prev = ctx.chatService.getToolEvents(ctx.messageId);
      final newEvents = <Map<String, dynamic>>[
        ...prev,
        for (final c in toolCalls)
          {'id': c.id, 'name': c.name, 'arguments': c.arguments, 'content': null},
      ];
      await ctx.chatService.setToolEvents(ctx.messageId, dedupeToolEvents(newEvents));
    } catch (_) {}
  }

  /// 处理工具结果块
  static Future<void> handleToolResultChunk(
    StreamContext ctx,
    List<ToolResultInfo> toolResults,
  ) async {
    if (toolResults.isEmpty) return;

    final parts = List<ToolUIPart>.of(ctx.toolParts[ctx.messageId] ?? const []);
    for (final r in toolResults) {
      // 查找第一个匹配的 loading 工具
      int idx = -1;
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].loading && (parts[i].id == r.id || (parts[i].id.isEmpty && parts[i].toolName == r.name))) {
          idx = i;
          break;
        }
      }

      if (idx >= 0) {
        parts[idx] = ToolUIPart(
          id: parts[idx].id,
          toolName: parts[idx].toolName,
          arguments: parts[idx].arguments,
          content: r.content,
          loading: false,
        );
      } else {
        parts.add(ToolUIPart(
          id: r.id,
          toolName: r.name,
          arguments: r.arguments,
          content: r.content,
          loading: false,
        ));
      }

      // 持久化事件更新
      try {
        await ctx.chatService.upsertToolEvent(
          ctx.messageId,
          id: r.id,
          name: r.name,
          arguments: r.arguments,
          content: r.content,
        );
      } catch (_) {}
    }

    ctx.toolParts[ctx.messageId] = dedupeToolPartsList(parts);
    if (ctx.isMounted() && ctx.isCurrentConversation()) ctx.notifyUI();
    ctx.scrollToBottom();
  }

  /// 处理内容块
  static void handleContentChunk(StreamContext ctx, String content) {
    if (content.isEmpty) return;

    if (ctx.firstTokenTime == null) {
      ctx.firstTokenTime = DateTime.now();
    }
    ctx.fullContent += content;
  }

  /// 处理 usage 更新
  static void handleUsageChunk(StreamContext ctx, TokenUsage? chunkUsage) {
    if (chunkUsage != null) {
      ctx.usage = (ctx.usage ?? const TokenUsage()).merge(chunkUsage);
    }
  }

  /// 构建 token usage JSON
  static String? buildTokenUsageJson(StreamContext ctx) {
    if (ctx.usage == null) return null;

    final now = DateTime.now();
    final firstToken = ctx.firstTokenTime;
    final Map<String, dynamic> usageMap = {
      'promptTokens': ctx.usage!.promptTokens,
      'completionTokens': ctx.usage!.completionTokens,
      'cachedTokens': ctx.usage!.cachedTokens,
      'thoughtTokens': ctx.usage!.thoughtTokens,
      'totalTokens': ctx.usage!.totalTokens,
      if (ctx.usage!.rounds != null) 'rounds': ctx.usage!.rounds,
    };

    if (firstToken != null) {
      final timeFirstTokenMs = firstToken.difference(ctx.startTime).inMilliseconds;
      final timeCompletionMs = now.difference(firstToken).inMilliseconds;
      final safeCompletionMs = timeCompletionMs > 0 ? timeCompletionMs : 1;
      final tokenSpeed = ctx.usage!.completionTokens / (safeCompletionMs / 1000.0);
      usageMap['time_first_token_millsec'] = timeFirstTokenMs;
      usageMap['time_completion_millsec'] = timeCompletionMs;
      usageMap['token_speed'] = double.parse(tokenSpeed.toStringAsFixed(1));
    }

    return jsonEncode(usageMap);
  }

  /// 检查是否有 loading 的工具调用
  static bool hasLoadingToolParts(StreamContext ctx) {
    return ctx.toolParts[ctx.messageId]?.any((p) => p.loading) ?? false;
  }

  /// 完成推理 (当内容开始时)
  static Future<void> finishReasoningOnContent(StreamContext ctx) async {
    final r = ctx.reasoning[ctx.messageId];
    if (r != null && r.startAt != null && r.finishedAt == null) {
      r.finishedAt = DateTime.now();
      if (ctx.autoCollapseThinking) {
        r.expanded = false;
      }
      ctx.reasoning[ctx.messageId] = r;
      await ctx.chatService.updateMessage(
        ctx.messageId,
        reasoningText: r.text,
        reasoningFinishedAt: r.finishedAt,
      );
      if (ctx.isMounted()) ctx.notifyUI();
    }

    // 完成 reasoning segments
    final segments = ctx.reasoningSegments[ctx.messageId];
    if (segments != null && segments.isNotEmpty && segments.last.finishedAt == null) {
      segments.last.finishedAt = DateTime.now();
      if (ctx.autoCollapseThinking) {
        segments.last.expanded = false;
      }
      ctx.reasoningSegments[ctx.messageId] = segments;
      await ctx.chatService.updateMessage(
        ctx.messageId,
        reasoningSegmentsJson: ReasoningStateManager.serializeSegments(segments),
      );
      if (ctx.isMounted()) ctx.notifyUI();
    }
  }

  /// 处理流完成
  static Future<void> handleStreamDone(
    StreamContext ctx,
    Future<void> Function() finish,
  ) async {
    // 如果有 loading 的工具，等待后续回合
    if (hasLoadingToolParts(ctx)) return;

    await finish();

    // 持久化 buffered reasoning (非 streaming 模式)
    if (!ctx.streamOutput && ctx.bufferedReasoning.isNotEmpty) {
      final now = DateTime.now();
      final startAt = ctx.reasoningStartAt ?? now;
      await ctx.chatService.updateMessage(
        ctx.messageId,
        reasoningText: ctx.bufferedReasoning,
        reasoningStartAt: startAt,
        reasoningFinishedAt: now,
      );
      ctx.reasoning[ctx.messageId] = ReasoningData()
        ..text = ctx.bufferedReasoning
        ..startAt = startAt
        ..finishedAt = now
        ..expanded = !ctx.autoCollapseThinking;
      if (ctx.isMounted() && ctx.isCurrentConversation()) ctx.notifyUI();
    }

    // 完成推理
    final r = ctx.reasoning[ctx.messageId];
    if (r != null && r.finishedAt == null) {
      r.finishedAt = DateTime.now();
      await ctx.chatService.updateMessage(
        ctx.messageId,
        reasoningText: r.text,
        reasoningFinishedAt: r.finishedAt,
      );
    }
  }

  /// 处理错误时完成推理状态
  static Future<void> finishReasoningOnError(StreamContext ctx) async {
    final r = ctx.reasoning[ctx.messageId];
    if (r != null) {
      if (r.finishedAt == null) {
        r.finishedAt = DateTime.now();
        try {
          await ctx.chatService.updateMessage(
            ctx.messageId,
            reasoningText: r.text,
            reasoningFinishedAt: r.finishedAt,
          );
        } catch (_) {}
      }
      if (ctx.autoCollapseThinking) {
        r.expanded = false;
      }
      ctx.reasoning[ctx.messageId] = r;
    }

    // 完成未完成的 reasoning segments
    final segments = ctx.reasoningSegments[ctx.messageId];
    if (segments != null && segments.isNotEmpty && segments.last.finishedAt == null) {
      segments.last.finishedAt = DateTime.now();
      if (ctx.autoCollapseThinking) {
        segments.last.expanded = false;
      }
      ctx.reasoningSegments[ctx.messageId] = segments;
      try {
        await ctx.chatService.updateMessage(
          ctx.messageId,
          reasoningSegmentsJson: ReasoningStateManager.serializeSegments(segments),
        );
      } catch (_) {}
    }
  }

  /// 构建错误显示内容
  static String buildErrorDisplayContent(String fullContent, String errorMessage) {
    return fullContent.isNotEmpty ? fullContent : errorMessage;
  }

  /// 处理流式内容更新 (用于 streaming 模式)
  static Future<void> handleStreamingContentUpdate(
    StreamContext ctx, {
    required void Function(String content, String? tokenUsageJson) updateMessage,
    required Future<void> Function(String content, String? tokenUsageJson) persistMessage,
    required void Function() scheduleScroll,
  }) async {
    final tokenUsageJson = buildTokenUsageJson(ctx);

    if (ctx.isMounted() && ctx.isCurrentConversation()) {
      updateMessage(ctx.fullContent, tokenUsageJson);
    }

    await persistMessage(ctx.fullContent, tokenUsageJson);
    scheduleScroll();
  }
}
