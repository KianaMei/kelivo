import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/services/api/models/chat_stream_chunk.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/models/token_usage.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/utils/gemini_thought_signatures.dart';
import '../../chat/widgets/message/message_models.dart';
import '../state/reasoning_state.dart';
import 'streaming_content_notifier.dart';

export 'streaming_content_notifier.dart';

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

  // 流式性能优化: StreamingContentNotifier (可选)
  // 当提供时，使用轻量级 ValueNotifier 替代全局 setState()
  final StreamingContentNotifier? streamingNotifier;

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
    this.streamingNotifier,
  });

  String get messageId => assistantMessage.id;

  /// 使用轻量级通知（如果可用）或回退到全局 setState
  void notifyStreamingUpdate() {
    if (streamingNotifier != null && isMounted() && isCurrentConversation()) {
      // 使用 ValueNotifier 只重建流式消息 widget
      final tokenUsageJson = ChatStreamHandler.buildTokenUsageJson(this);
      streamingNotifier!.updateContent(messageId, fullContent, totalTokens, tokenUsageJson: tokenUsageJson);
    }
    // 注意: 不再调用 notifyUI() 因为会触发全局重建
  }

  /// 通知推理内容更新
  void notifyReasoningUpdate() {
    if (streamingNotifier != null && isMounted() && isCurrentConversation()) {
      final r = reasoning[messageId];
      streamingNotifier!.updateReasoning(
        messageId,
        reasoningText: r?.text,
        reasoningStartAt: r?.startAt,
        reasoningFinishedAt: r?.finishedAt,
      );
    }
  }

  /// 通知工具部件更新
  void notifyToolPartsUpdate() {
    if (streamingNotifier != null && isMounted() && isCurrentConversation()) {
      streamingNotifier!.notifyToolPartsUpdated(messageId);
    } else if (isMounted() && isCurrentConversation()) {
      notifyUI();  // 回退到全局更新
    }
  }
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
    // Tool call/result chunks can arrive out-of-order (e.g. builtin web search).
    // If we keep the "last" one, a later placeholder can overwrite a completed result.
    // Merge by id, prefer non-empty content, and keep the first occurrence order.
    final indexById = <String, int>{};
    final out = <Map<String, dynamic>>[];

    for (final raw in events) {
      final e = raw.map((k, v) => MapEntry(k.toString(), v));
      final id = (e['id'] ?? '').toString();
      if (id.isEmpty) {
        out.add(e);
        continue;
      }

      final idx = indexById[id];
      if (idx == null) {
        indexById[id] = out.length;
        out.add(e);
        continue;
      }

      final prev = out[idx];
      final merged = Map<String, dynamic>.from(prev);

      final name = (e['name'] ?? '').toString();
      if (name.isNotEmpty) merged['name'] = name;

      final args = e['arguments'];
      if (args is Map && args.isNotEmpty) merged['arguments'] = args;

      final prevContent = (prev['content'] ?? '').toString();
      final nextContent = (e['content'] ?? '').toString();
      if (nextContent.isNotEmpty) {
        merged['content'] = e['content'];
      } else if (prevContent.isNotEmpty) {
        merged['content'] = prev['content'];
      } else {
        merged['content'] = e['content'] ?? prev['content'];
      }

      out[idx] = merged;
    }

    return out;
  }

  /// 去重 ToolUIPart 列表
  static List<ToolUIPart> dedupeToolPartsList(List<ToolUIPart> parts) {
    // Same rationale as dedupeToolEvents: merge placeholders + results by id.
    final indexById = <String, int>{};
    final out = <ToolUIPart>[];

    for (final p in parts) {
      if (p.id.isEmpty) {
        out.add(p);
        continue;
      }

      final idx = indexById[p.id];
      if (idx == null) {
        indexById[p.id] = out.length;
        out.add(p);
        continue;
      }

      final prev = out[idx];
      final content = (p.content?.isNotEmpty == true) ? p.content : prev.content;
      final hasContent = (content?.isNotEmpty == true);
      out[idx] = ToolUIPart(
        id: prev.id,
        toolName: prev.toolName.isNotEmpty ? prev.toolName : p.toolName,
        arguments: p.arguments.isNotEmpty ? p.arguments : prev.arguments,
        content: content,
        loading: hasContent ? false : (prev.loading && p.loading),
      );
    }

    return out;
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

      // 使用轻量级通知（优化性能）
      ctx.notifyReasoningUpdate();
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
    // 使用轻量级通知（优化性能）
    ctx.notifyToolPartsUpdate();

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
    // 使用轻量级通知（优化性能）
    ctx.notifyToolPartsUpdate();
    ctx.scrollToBottom();
  }

  /// 处理内容块
  static Future<void> handleContentChunk(StreamContext ctx, String content) async {
    if (content.isEmpty) return;

    if (ctx.firstTokenTime == null) {
      ctx.firstTokenTime = DateTime.now();
    }

    // Gemini 3 persists `thoughtSignature` metadata as HTML comments; never show it to users.
    if (GeminiThoughtSignatures.hasAny(content)) {
      final sig = GeminiThoughtSignatures.extractLast(content);
      if (sig != null && sig.isNotEmpty) {
        await ctx.chatService.setGeminiThoughtSignature(ctx.messageId, sig);
      }
      final cleaned = GeminiThoughtSignatures.stripAll(content);
      // If the chunk only carried metadata + whitespace, drop it entirely.
      if (cleaned.trim().isEmpty) return;
      ctx.fullContent += cleaned;
      return;
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
      // 使用轻量级通知（优化性能）
      ctx.notifyReasoningUpdate();
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
      // 使用轻量级通知（优化性能）
      ctx.notifyReasoningUpdate();
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
      // 使用轻量级通知（优化性能）
      ctx.notifyReasoningUpdate();
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

/// 流式内容节流管理器
///
/// 用于限制流式 UI 更新频率，从而提升性能
/// 默认节流间隔为 60ms（约 16 FPS），足够流畅且不会过度消耗资源
class StreamingThrottleManager {
  StreamingThrottleManager({
    this.throttleInterval = const Duration(milliseconds: 60),
  });

  /// 节流间隔
  final Duration throttleInterval;

  /// 每条消息的节流定时器
  final Map<String, Timer?> _throttleTimers = {};

  /// 待处理的内容
  final Map<String, String> _pendingContent = {};

  /// 待处理的 token 数量
  final Map<String, int> _pendingTokens = {};

  /// 待处理的 token usage JSON（可能随着流式更新变化）
  final Map<String, String?> _pendingTokenUsageJson = {};

  /// 调度节流更新
  ///
  /// 每次调用会更新待处理内容，但实际 UI 更新按节流间隔执行
  void scheduleUpdate(
    String messageId,
    String content,
    int totalTokens,
    StreamingContentNotifier notifier, {
    String? tokenUsageJson,
    VoidCallback? onTick,
  }) {
    _pendingContent[messageId] = content;
    _pendingTokens[messageId] = totalTokens;
    _pendingTokenUsageJson[messageId] = tokenUsageJson;

    // 如果定时器已存在，等待下次触发
    if (_throttleTimers[messageId] != null) return;

    // 立即执行一次
    notifier.updateContent(messageId, content, totalTokens, tokenUsageJson: tokenUsageJson);
    onTick?.call();

    // 创建周期性定时器
    _throttleTimers[messageId] = Timer.periodic(throttleInterval, (_) {
      final pending = _pendingContent[messageId];
      final tokens = _pendingTokens[messageId] ?? 0;
      final pendingTokenUsageJson = _pendingTokenUsageJson[messageId];
      if (pending != null) {
        notifier.updateContent(messageId, pending, tokens, tokenUsageJson: pendingTokenUsageJson);
        onTick?.call();
      }
    });
  }

  /// 清理指定消息的节流状态
  void cleanup(String messageId) {
    _throttleTimers[messageId]?.cancel();
    _throttleTimers.remove(messageId);
    _pendingContent.remove(messageId);
    _pendingTokens.remove(messageId);
    _pendingTokenUsageJson.remove(messageId);
  }

  /// 清理所有节流状态
  void clear() {
    for (final timer in _throttleTimers.values) {
      timer?.cancel();
    }
    _throttleTimers.clear();
    _pendingContent.clear();
    _pendingTokens.clear();
    _pendingTokenUsageJson.clear();
  }

  /// 释放资源
  void dispose() {
    clear();
  }
}
