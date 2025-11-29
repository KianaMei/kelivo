import '../../../core/models/chat_message.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/services/chat/document_text_extractor.dart';

/// 聊天消息处理器 - 封装 API 消息准备逻辑
///
/// 从 home_page.dart 的 _sendMessage 和 _regenerateAtMessage 提取的共享逻辑。
/// 主要职责:
/// - 准备 API 消息 (文档内联、OCR、消息模板)
/// - 构建工具定义 (搜索、贴纸、记忆、MCP)
/// - 工具参数清理
class ChatMessageHandler {
  ChatMessageHandler._();

  /// 解析原始消息内容，提取文本、图片路径和文档附件
  static ChatInputData parseMessageContent(String rawContent) {
    final imagePaths = <String>[];
    final documents = <DocumentAttachment>[];

    // Extract image paths: [image:/path/to/image.jpg]
    final imageRegex = RegExp(r'\[image:([^\]]+)\]');
    for (final match in imageRegex.allMatches(rawContent)) {
      final path = match.group(1)?.trim();
      if (path != null && path.isNotEmpty) {
        imagePaths.add(path);
      }
    }

    // Extract document attachments: [file:path|fileName|mime]
    final docRegex = RegExp(r'\[file:([^|]+)\|([^|]+)\|([^\]]+)\]');
    for (final match in docRegex.allMatches(rawContent)) {
      final path = match.group(1)?.trim() ?? '';
      final fileName = match.group(2)?.trim() ?? '';
      final mime = match.group(3)?.trim() ?? '';
      if (path.isNotEmpty) {
        documents.add(DocumentAttachment(path: path, fileName: fileName, mime: mime));
      }
    }

    // Clean text content by removing markers
    String cleanText = rawContent
        .replaceAll(imageRegex, '')
        .replaceAll(docRegex, '')
        .trim();

    return ChatInputData(
      text: cleanText,
      imagePaths: imagePaths,
      documents: documents,
    );
  }

  /// 折叠消息版本 - 只保留每个 groupId 的选定版本
  ///
  /// [messages] - 消息列表
  /// [versionSelections] - 版本选择映射 (groupId -> 选中的索引)
  static List<ChatMessage> collapseVersions(
    List<ChatMessage> messages,
    Map<String, int> versionSelections,
  ) {
    final Map<String, List<ChatMessage>> byGroup = <String, List<ChatMessage>>{};
    final List<String> order = <String>[];

    for (final m in messages) {
      final gid = m.groupId ?? m.id;
      final list = byGroup.putIfAbsent(gid, () {
        order.add(gid);
        return <ChatMessage>[];
      });
      list.add(m);
    }

    // 按版本排序
    for (final e in byGroup.entries) {
      e.value.sort((a, b) => a.version.compareTo(b.version));
    }

    // 选择版本
    final out = <ChatMessage>[];
    for (final gid in order) {
      final vers = byGroup[gid]!;
      final sel = versionSelections[gid];
      final idx = (sel != null && sel >= 0 && sel < vers.length)
          ? sel
          : (vers.length - 1);
      out.add(vers[idx]);
    }

    return out;
  }

  /// 准备基础 API 消息列表
  ///
  /// [messages] - 原始消息列表
  /// [truncateIndex] - 截断索引，-1 表示不截断
  /// [versionSelections] - 版本选择映射
  static List<Map<String, dynamic>> prepareBaseApiMessages({
    required List<ChatMessage> messages,
    required int truncateIndex,
    required Map<String, int> versionSelections,
  }) {
    // 应用截断
    final List<ChatMessage> sourceAll = (truncateIndex >= 0 && truncateIndex <= messages.length)
        ? messages.sublist(truncateIndex)
        : List.of(messages);

    // 折叠版本
    final List<ChatMessage> source = collapseVersions(sourceAll, versionSelections);

    // 转换为 API 格式
    return source
        .where((m) => m.content.isNotEmpty)
        .map((m) => <String, dynamic>{
              'role': m.role == 'assistant' ? 'assistant' : 'user',
              'content': m.content,
            })
        .toList();
  }

  /// 读取文档内容 (带缓存)
  static Future<String?> readDocumentCached(
    DocumentAttachment doc,
    Map<String, String?> cache,
  ) async {
    // 跳过视频文件
    if (doc.mime.toLowerCase().startsWith('video/')) return null;

    if (cache.containsKey(doc.path)) {
      return cache[doc.path];
    }

    try {
      final text = await DocumentTextExtractor.extract(path: doc.path, mime: doc.mime);
      cache[doc.path] = text;
      return text;
    } catch (_) {
      cache[doc.path] = null;
      return null;
    }
  }

  /// 包装 OCR 文本块
  static String wrapOcrBlock(String text) {
    return '<image_file_ocr>\n$text\n</image_file_ocr>';
  }

  /// 包装文档内容块
  static String wrapDocumentBlock(String fileName, String content) {
    return '<document name="$fileName">\n$content\n</document>';
  }
}
