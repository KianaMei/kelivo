import 'dart:convert';

/// 推理数据模型 - 存储单个消息的推理状态
class ReasoningData {
  String text = '';
  DateTime? startAt;
  DateTime? finishedAt;
  bool expanded = false;

  ReasoningData();

  ReasoningData.fromMessage({
    required String reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
  }) {
    text = reasoningText;
    startAt = reasoningStartAt;
    finishedAt = reasoningFinishedAt;
    expanded = false;
  }
}

/// 推理段落数据模型 - 支持混合渲染的分段推理
class ReasoningSegmentData {
  String text = '';
  DateTime? startAt;
  DateTime? finishedAt;
  bool expanded = true;
  int toolStartIndex = 0;

  ReasoningSegmentData();

  Map<String, dynamic> toJson() => {
    'text': text,
    'startAt': startAt?.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'expanded': expanded,
    'toolStartIndex': toolStartIndex,
  };

  factory ReasoningSegmentData.fromJson(Map<String, dynamic> json) {
    final s = ReasoningSegmentData();
    s.text = json['text'] ?? '';
    s.startAt = json['startAt'] != null ? DateTime.parse(json['startAt']) : null;
    s.finishedAt = json['finishedAt'] != null ? DateTime.parse(json['finishedAt']) : null;
    s.expanded = json['expanded'] ?? false;
    s.toolStartIndex = (json['toolStartIndex'] as int?) ?? 0;
    return s;
  }
}

/// 推理状态管理器 - 封装推理相关的状态和操作
class ReasoningStateManager {
  /// 每个消息的推理状态
  final Map<String, ReasoningData> reasoning = {};

  /// 每个消息的推理段落（用于混合渲染）
  final Map<String, List<ReasoningSegmentData>> segments = {};

  /// 内联 think 标签缓冲区
  final Map<String, String> inlineThinkBuffer = {};

  /// 是否正在处理内联 think 标签
  final Map<String, bool> inInlineThink = {};

  /// 序列化推理段落为 JSON 字符串
  static String serializeSegments(List<ReasoningSegmentData> segments) {
    return jsonEncode(segments.map((s) => s.toJson()).toList());
  }

  /// 反序列化 JSON 字符串为推理段落列表
  static List<ReasoningSegmentData> deserializeSegments(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((item) => ReasoningSegmentData.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 检查是否启用推理功能
  /// Supports both new effort level constants and legacy positive values
  static bool isReasoningEnabled(int? budget) {
    if (budget == null) return true; // treat null as default/auto -> enabled
    if (budget == -1) return true; // auto
    if (budget == 0) return false;  // off
    // New effort level constants: -10 (minimal), -20 (low), -30 (medium), -40 (high)
    if (budget == -10 || budget == -20 || budget == -30 || budget == -40) return true;
    // Legacy positive values
    return budget >= 1024;
  }

  /// 检查是否应该使用内联 think 段落
  bool shouldUseInlineThinkSegments(String messageId, String content, bool hasNativeReasoning) {
    if (hasNativeReasoning) return false;
    return content.contains('<think>') || (inInlineThink[messageId] ?? false);
  }

  /// 处理内联 <think> 标签
  /// [messageId] - 消息 ID
  /// [newContent] - 新增的内容
  /// [getToolPartsCount] - 获取工具部件数量的回调
  /// [autoCollapse] - 是否自动折叠
  void processInlineThinkTag({
    required String messageId,
    required String newContent,
    required int Function() getToolPartsCount,
    required bool autoCollapse,
  }) {
    if (newContent.isEmpty) return;

    final inThink = inInlineThink[messageId] ?? false;
    var buffer = inlineThinkBuffer[messageId] ?? '';
    var remaining = newContent;

    while (remaining.isNotEmpty) {
      if (inThink || inInlineThink[messageId] == true) {
        // Currently inside <think> block, look for </think>
        final endIndex = remaining.indexOf('</think>');
        if (endIndex == -1) {
          buffer += remaining;
          inlineThinkBuffer[messageId] = buffer;
          remaining = '';
        } else {
          buffer += remaining.substring(0, endIndex);
          remaining = remaining.substring(endIndex + '</think>'.length);

          if (buffer.trim().isNotEmpty) {
            final segs = segments[messageId] ?? <ReasoningSegmentData>[];
            final toolCount = getToolPartsCount();

            if (segs.isEmpty) {
              final seg = ReasoningSegmentData();
              seg.text = buffer.trim();
              seg.startAt = DateTime.now();
              seg.expanded = true;
              seg.toolStartIndex = toolCount;
              segs.add(seg);
            } else {
              final lastSeg = segs.last;
              if (lastSeg.finishedAt != null && toolCount > lastSeg.toolStartIndex) {
                final seg = ReasoningSegmentData();
                seg.text = buffer.trim();
                seg.startAt = DateTime.now();
                seg.expanded = true;
                seg.toolStartIndex = toolCount;
                segs.add(seg);
              } else if (lastSeg.finishedAt == null) {
                lastSeg.text += '\n\n' + buffer.trim();
              } else {
                lastSeg.text += '\n\n' + buffer.trim();
                lastSeg.finishedAt = null;
              }
            }

            if (segs.isNotEmpty) {
              segs.last.finishedAt = DateTime.now();
              if (autoCollapse) {
                segs.last.expanded = false;
              }
            }

            segments[messageId] = segs;
          }

          buffer = '';
          inlineThinkBuffer[messageId] = buffer;
          inInlineThink[messageId] = false;
        }
      } else {
        // Not inside <think> block, look for <think>
        final startIndex = remaining.indexOf('<think>');
        if (startIndex == -1) {
          remaining = '';
        } else {
          remaining = remaining.substring(startIndex + '<think>'.length);
          inInlineThink[messageId] = true;
        }
      }
    }
  }

  /// 清理指定消息的推理状态
  void removeMessage(String messageId) {
    reasoning.remove(messageId);
    segments.remove(messageId);
    inlineThinkBuffer.remove(messageId);
    inInlineThink.remove(messageId);
  }

  /// 清理所有状态
  void clear() {
    reasoning.clear();
    segments.clear();
    inlineThinkBuffer.clear();
    inInlineThink.clear();
  }
}
