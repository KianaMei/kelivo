import '../../../core/models/chat_message.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/assistant_memory.dart';
import '../../../core/models/token_usage.dart';
import '../../../core/services/chat/document_text_extractor.dart';
import '../../../core/providers/memory_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/utils/tool_schema_sanitizer.dart';

/// 聊天消息处理器 - 封装 API 消息准备逻辑
///
/// 从 home_page.dart 的 _sendMessage 和 _regenerateAtMessage 提取的共享逻辑。
/// 主要职责:
/// - 准备 API 消息 (文档内联、OCR、消息模板)
/// - 构建工具定义 (搜索、贴纸、记忆、MCP)
/// - 工具参数清理
class ChatMessageHandler {
  ChatMessageHandler._();

  /// 记忆工具定义 - 静态常量
  static const List<Map<String, dynamic>> memoryToolDefinitions = [
    {
      'type': 'function',
      'function': {
        'name': 'create_memory',
        'description': 'create a memory record',
        'parameters': {
          'type': 'object',
          'properties': {
            'content': {'type': 'string', 'description': 'The content of the memory record'}
          },
          'required': ['content']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'edit_memory',
        'description': 'update a memory record',
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {'type': 'integer', 'description': 'The id of the memory record'},
            'content': {'type': 'string', 'description': 'The content of the memory record'}
          },
          'required': ['id', 'content']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_memory',
        'description': 'delete a memory record',
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {'type': 'integer', 'description': 'The id of the memory record'}
          },
          'required': ['id']
        }
      }
    },
  ];

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
    final result = <Map<String, dynamic>>[];

    for (final m in source) {
      if (m.content.isEmpty) continue;

      final role = m.role == 'assistant' ? 'assistant' : 'user';
      result.add({
        'role': role,
        'content': m.content,
      });
    }

    return result;
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

  /// 追加内容到系统消息
  ///
  /// 如果 apiMessages 已有系统消息，则追加到现有内容后面
  /// 否则插入新的系统消息到列表开头
  static void appendToSystemMessage(
    List<Map<String, dynamic>> apiMessages,
    String content,
  ) {
    if (content.trim().isEmpty) return;

    if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
      apiMessages[0]['content'] =
          ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + content;
    } else {
      apiMessages.insert(0, {'role': 'system', 'content': content});
    }
  }

  /// 构建 Assistant 自定义请求覆盖 (headers/body)
  ///
  /// 从 Assistant 的 customHeaders 和 customBody 配置构建 API 请求覆盖
  static ({Map<String, String>? headers, Map<String, dynamic>? body}) buildAssistantOverrides(
    Assistant? assistant,
  ) {
    Map<String, String>? headers;
    Map<String, dynamic>? body;

    if ((assistant?.customHeaders.isNotEmpty ?? false)) {
      headers = {
        for (final e in assistant!.customHeaders)
          if ((e['name'] ?? '').trim().isNotEmpty)
            (e['name']!.trim()): (e['value'] ?? '')
      };
      if (headers.isEmpty) headers = null;
    }

    if ((assistant?.customBody.isNotEmpty ?? false)) {
      body = {
        for (final e in assistant!.customBody)
          if ((e['key'] ?? '').trim().isNotEmpty)
            (e['key']!.trim()): (e['value'] ?? '')
      };
      if (body.isEmpty) body = null;
    }

    return (headers: headers, body: body);
  }

  /// 处理记忆工具回调
  ///
  /// 返回工具调用结果，如果不是记忆工具返回 null
  static Future<String?> handleMemoryToolCall({
    required String toolName,
    required Map<String, dynamic> args,
    required MemoryProvider memoryProvider,
    required String assistantId,
  }) async {
    try {
      if (toolName == 'create_memory') {
        final content = (args['content'] ?? '').toString();
        if (content.isEmpty) return '';
        final m = await memoryProvider.add(assistantId: assistantId, content: content);
        return m.content;
      } else if (toolName == 'edit_memory') {
        final id = (args['id'] as num?)?.toInt() ?? -1;
        final content = (args['content'] ?? '').toString();
        if (id <= 0 || content.isEmpty) return '';
        final m = await memoryProvider.update(id: id, content: content);
        return m?.content ?? '';
      } else if (toolName == 'delete_memory') {
        final id = (args['id'] as num?)?.toInt() ?? -1;
        if (id <= 0) return '';
        final ok = await memoryProvider.delete(id: id);
        return ok ? 'deleted' : '';
      }
    } catch (_) {}
    return null; // Not a memory tool
  }

  /// 构建单个 MCP 工具的 API 定义
  ///
  /// 将 MCP 服务器提供的工具配置转换为 OpenAI 兼容的 function calling 格式
  static Map<String, dynamic> buildMcpToolDefinition(
    McpToolConfig tool,
    ProviderKind providerKind,
  ) {
    // Build base schema from server-provided schema or param specs
    Map<String, dynamic> baseSchema;
    if (tool.schema != null && tool.schema!.isNotEmpty) {
      baseSchema = Map<String, dynamic>.from(tool.schema!);
    } else {
      final props = <String, dynamic>{
        for (final p in tool.params) p.name: {'type': (p.type ?? 'string')}
      };
      final required = [for (final p in tool.params.where((e) => e.required)) p.name];
      baseSchema = {
        'type': 'object',
        'properties': props,
        if (required.isNotEmpty) 'required': required,
      };
    }

    // Sanitize schema for the target provider
    final sanitized = ToolSchemaSanitizer.sanitizeForProvider(baseSchema, providerKind);

    return {
      'type': 'function',
      'function': {
        'name': tool.name,
        if ((tool.description ?? '').isNotEmpty) 'description': tool.description,
        'parameters': sanitized,
      }
    };
  }

  /// 估算或修复 Token 使用量
  ///
  /// 当 API 未返回 token 使用信息，或返回的 promptTokens/completionTokens 为 0 时，
  /// 使用字符数 / 4 的近似公式进行估算
  static TokenUsage? estimateOrFixTokenUsage({
    required TokenUsage? usage,
    required List<Map<String, dynamic>> apiMessages,
    required String processedContent,
  }) {
    TokenUsage? effectiveUsage = usage;

    if (effectiveUsage == null && (processedContent.isNotEmpty || apiMessages.isNotEmpty)) {
      // Estimate input tokens from sent messages
      final promptChars = apiMessages.fold<int>(
        0,
        (acc, m) => acc + ((m['content'] ?? '').toString().length),
      );
      final approxPromptTokens = (promptChars / 4).round();
      // Estimate output tokens from received content
      final approxCompletionTokens = (processedContent.length / 4).round();
      effectiveUsage = TokenUsage(
        promptTokens: approxPromptTokens,
        completionTokens: approxCompletionTokens,
        totalTokens: approxPromptTokens + approxCompletionTokens,
      );
    } else if (effectiveUsage != null &&
        (effectiveUsage.promptTokens == 0 || effectiveUsage.completionTokens == 0)) {
      // Fix missing tokens: API returned usage but some token counts are 0
      var fixedPromptTokens = effectiveUsage.promptTokens;
      var fixedCompletionTokens = effectiveUsage.completionTokens;

      // Fix promptTokens if 0
      if (fixedPromptTokens == 0 && apiMessages.isNotEmpty) {
        final promptChars = apiMessages.fold<int>(
          0,
          (acc, m) => acc + ((m['content'] ?? '').toString().length),
        );
        fixedPromptTokens = (promptChars / 4).round();
      }

      // Fix completionTokens if 0
      if (fixedCompletionTokens == 0 && processedContent.isNotEmpty) {
        fixedCompletionTokens = (processedContent.length / 4).round();
      }

      effectiveUsage = TokenUsage(
        promptTokens: fixedPromptTokens,
        completionTokens: fixedCompletionTokens,
        cachedTokens: effectiveUsage.cachedTokens,
        thoughtTokens: effectiveUsage.thoughtTokens,
        totalTokens: fixedPromptTokens +
            fixedCompletionTokens +
            effectiveUsage.cachedTokens +
            effectiveUsage.thoughtTokens,
        rounds: effectiveUsage.rounds,
      );
    }

    return effectiveUsage;
  }

  /// Memory 工具使用指南常量
  static const String _memoryToolGuide = '''
## Memory Tool
你是一个无状态的大模型，你无法存储记忆，因此为了记住信息，你需要使用**记忆工具**。
你可以使用 `create_memory`, `edit_memory`, `delete_memory` 工具创建、更新或删除记忆。
- 如果记忆中没有相关信息，请使用 create_memory 创建一条新的记录。
- 如果已有相关记录，请使用 edit_memory 更新内容。
- 若记忆过时或无用，请使用 delete_memory 删除。
这些记忆会自动包含在未来的对话上下文中，在<memories>标签内。
请勿在记忆中存储敏感信息，敏感信息包括：用户的民族、宗教信仰、性取向、政治观点及党派归属、性生活、犯罪记录等。
在与用户聊天过程中，你可以像一个私人秘书一样**主动的**记录用户相关的信息到记忆里，包括但不限于：
- 用户昵称/姓名
- 年龄/性别/兴趣爱好
- 计划事项等
- 聊天风格偏好
- 工作相关
- 首次聊天时间
- ...
请主动调用工具记录，而不是需要用户请求。
记忆如果包含日期信息，请包含在内，请使用绝对时间格式，并且当前时间是 {currentTime}。
无需告知用户你已更改记忆记录，也不要在对话中直接显示记忆内容，除非用户主动请求。
相似或相关的记忆应合并为一条记录，而不要重复记录，过时记录应删除。
你可以在和用户闲聊的时候暗示用户你能记住东西。
''';

  /// 构建 Memory 系统提示词
  ///
  /// [memories] - 该 assistant 的所有记忆记录
  /// 返回完整的 memory 提示词字符串，包含记忆列表和工具使用指南
  static String buildMemoriesPrompt(List<AssistantMemory> memories) {
    final buf = StringBuffer();
    buf.writeln('## Memories');
    buf.writeln('These are memories that you can reference in the future conversations.');
    buf.writeln('<memories>');
    for (final m in memories) {
      buf.writeln('<record>');
      buf.writeln('<id>${m.id}</id>');
      buf.writeln('<content>${m.content}</content>');
      buf.writeln('</record>');
    }
    buf.writeln('</memories>');
    // 替换时间占位符
    final guide = _memoryToolGuide.replaceAll('{currentTime}', DateTime.now().toIso8601String());
    buf.write(guide);
    return buf.toString();
  }

  /// 构建 Recent Chats 系统提示词
  ///
  /// [chatTitles] - 最近对话的标题列表
  /// 返回完整的最近对话提示词字符串
  static String buildRecentChatsPrompt(List<String> chatTitles) {
    if (chatTitles.isEmpty) return '';
    final sb = StringBuffer();
    sb.writeln('## 最近的对话');
    sb.writeln('这是用户最近的一些对话，你可以参考这些对话了解用户偏好。');
    sb.writeln('<recent_chats>');
    for (final t in chatTitles) {
      sb.writeln('<conversation>');
      sb.writeln('  <title>$t</title>');
      sb.writeln('</conversation>');
    }
    sb.writeln('</recent_chats>');
    return sb.toString();
  }
}
