# 关键冲突区域 - 详细分析与解决方案

**创建时间：** 2025-11-08
**目的：** 识别高风险冲突区域，制定精确的合并策略

---

## 一、Token 显示修改（本地重点功能）

### 1.1 冲突描述

**用户反馈：**
> "我不是对聊天界面显示修改了很多（比如显示输入输出token）"

**本地修改范围：**
- 聊天消息界面显示输入 token 和输出 token
- Token 统计面板（可能包含 hover 提示、点击展开等交互）
- 多轮对话的累计 token 追踪
- 桌面端和移动端的不同展示方式

**上游可能的修改：**
- 消息渲染架构可能重构（Markdown WebView、HTML 预览）
- 消息底部元数据显示（时间戳、编辑状态等）
- 消息组件的布局结构

**冲突风险：** 🔴 **高风险** - UI 组件结构冲突可能导致 Token 显示功能丢失

---

### 1.2 本地 Token 显示实现分析

**需要保留的关键文件/代码：**

#### 数据模型层
```dart
// lib/core/models/chat_message.dart
class ChatMessage {
  // 本地新增字段（必须保留）
  final int? inputTokens;   // 输入 token 数量
  final int? outputTokens;  // 输出 token 数量

  // Hive 字段映射
  @HiveField(11) final int? inputTokens;
  @HiveField(12) final int? outputTokens;
}
```

#### API 服务层
```dart
// lib/core/services/api/chat_api_service.dart
// 本地修改：在流式响应中提取 token 信息

Future<Stream<ChatResponse>> sendMessage(...) async {
  // 本地逻辑：解析响应中的 usage 字段
  return response.stream.transform(
    StreamTransformer.fromHandlers(
      handleData: (data, sink) {
        // 提取 usage.prompt_tokens 和 usage.completion_tokens
        if (data['usage'] != null) {
          final usage = data['usage'];
          message.inputTokens = usage['prompt_tokens'];
          message.outputTokens = usage['completion_tokens'];
        }
        sink.add(data);
      },
    ),
  );
}
```

#### UI 显示层
```dart
// lib/features/chat/widgets/chat_message_widget.dart
// 本地修改：消息底部显示 Token 信息

Widget _buildMessageFooter(ChatMessage message) {
  return Row(
    children: [
      // 时间戳
      Text(formatTime(message.createdAt)),

      SizedBox(width: 8),

      // Token 显示（本地功能）
      if (message.role == 'assistant') ...[
        if (message.inputTokens != null)
          Chip(
            label: Text('In: ${message.inputTokens}'),
            avatar: Icon(Icons.input, size: 16),
            backgroundColor: Colors.blue.shade100,
            visualDensity: VisualDensity.compact,
          ),
        SizedBox(width: 4),
        if (message.outputTokens != null)
          Chip(
            label: Text('Out: ${message.outputTokens}'),
            avatar: Icon(Icons.output, size: 16),
            backgroundColor: Colors.green.shade100,
            visualDensity: VisualDensity.compact,
          ),
      ],
    ],
  );
}
```

#### 统计面板（如果存在）
```dart
// lib/features/token_stats/ 或类似目录
// 本地可能有的 Token 统计卡片组件

class TokenStatsCard extends StatelessWidget {
  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final totalInputTokens = conversation.messages
        .where((m) => m.inputTokens != null)
        .fold(0, (sum, m) => sum + m.inputTokens!);

    final totalOutputTokens = conversation.messages
        .where((m) => m.outputTokens != null)
        .fold(0, (sum, m) => sum + m.outputTokens!);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Total Input Tokens: $totalInputTokens'),
            Text('Total Output Tokens: $totalOutputTokens'),
            Text('Total: ${totalInputTokens + totalOutputTokens}'),
          ],
        ),
      ),
    );
  }
}
```

---

### 1.3 上游消息渲染变更分析

**需要调查的上游文件：**
```bash
# 查看上游的消息渲染组件
git show upstream/master:lib/features/chat/widgets/chat_message_widget.dart

# 查看上游的消息模型
git show upstream/master:lib/core/models/chat_message.dart

# 查看上游的 API 服务
git show upstream/master:lib/core/services/api/chat_api_service.dart
```

**预期上游修改：**
1. 可能添加了 Markdown WebView 渲染
2. 可能添加了 HTML 代码块预览
3. 可能调整了消息底部的元数据显示区域
4. 可能重构了消息组件的布局结构

---

### 1.4 合并策略

#### 策略 A：保留本地 UI 结构，添加上游渲染功能

**步骤：**

1. **数据模型合并（优先级最高）**
   ```dart
   // 合并后的 ChatMessage
   @HiveType(typeId: 1)
   class ChatMessage {
     // 原有字段
     @HiveField(0) final String id;
     @HiveField(1) final String content;
     @HiveField(2) final String role;

     // 本地新增（必须保留）
     @HiveField(11) final int? inputTokens;
     @HiveField(12) final int? outputTokens;

     // 上游新增（必须集成）
     @HiveField(20) final List<Tool>? tools;
     @HiveField(21) final bool? hasMarkdown;
     @HiveField(22) final bool? hasHtml;
   }
   ```

2. **API 服务层合并**
   ```dart
   // 采用上游的 Response API 架构
   // 在流式响应处理中集成本地的 Token 提取逻辑

   class ChatApiService {
     Future<Stream<ChatResponse>> sendMessage(...) async {
       // 上游的 Response API 基础架构
       final response = await _httpClient.post(...);

       // 本地的 Token 提取 Transformer
       return response.stream
           .transform(_parseResponseTransformer)  // 上游
           .transform(_extractTokenUsageTransformer)  // 本地新增
           .transform(_handleToolCallsTransformer);  // 上游
     }

     // 本地新增：Token 提取转换器
     StreamTransformer<Map<String, dynamic>, Map<String, dynamic>>
         get _extractTokenUsageTransformer {
       return StreamTransformer.fromHandlers(
         handleData: (data, sink) {
           // 提取 usage 字段
           if (data['usage'] != null) {
             final usage = data['usage'];
             _currentMessage.inputTokens = usage['prompt_tokens'];
             _currentMessage.outputTokens = usage['completion_tokens'];
           }
           sink.add(data);
         },
       );
     }
   }
   ```

3. **UI 组件合并（关键！）**
   ```dart
   // lib/features/chat/widgets/chat_message_widget.dart

   class ChatMessageWidget extends StatelessWidget {
     final ChatMessage message;

     @override
     Widget build(BuildContext context) {
       return Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           // 消息头部（头像、名称）
           _buildMessageHeader(message),

           SizedBox(height: 8),

           // 消息内容（合并上游渲染 + 本地表情包）
           _buildMessageContent(message),

           SizedBox(height: 4),

           // 消息底部（本地 Token 显示 + 上游元数据）
           _buildMessageFooter(message),
         ],
       );
     }

     Widget _buildMessageContent(ChatMessage message) {
       // 优先级 1：本地表情包
       if (message.content.contains('[[sticker:')) {
         return StickerRenderer(message: message);
       }

       // 优先级 2：上游 Markdown/HTML
       if (message.hasMarkdown == true || message.hasHtml == true) {
         return MarkdownWebView(
           content: message.content,
           enableTextSelection: true,  // 保留本地的文字选择
         );
       }

       // 优先级 3：普通文本
       return SelectableText(
         message.content,
         style: TextStyle(fontSize: 16),
       );
     }

     Widget _buildMessageFooter(ChatMessage message) {
       return Padding(
         padding: EdgeInsets.only(top: 4),
         child: Row(
           children: [
             // 时间戳（原有）
             Text(
               formatTime(message.createdAt),
               style: TextStyle(fontSize: 12, color: Colors.grey),
             ),

             SizedBox(width: 8),

             // 上游可能的元数据（编辑状态等）
             if (message.isEdited == true)
               Chip(
                 label: Text('Edited'),
                 visualDensity: VisualDensity.compact,
               ),

             Spacer(),

             // 本地 Token 显示（必须保留！）
             if (message.role == 'assistant') ...[
               if (message.inputTokens != null)
                 Tooltip(
                   message: 'Input Tokens',
                   child: Chip(
                     label: Text('In: ${message.inputTokens}'),
                     avatar: Icon(Icons.input, size: 14),
                     backgroundColor: Colors.blue.shade50,
                     visualDensity: VisualDensity.compact,
                   ),
                 ),
               SizedBox(width: 4),
               if (message.outputTokens != null)
                 Tooltip(
                   message: 'Output Tokens',
                   child: Chip(
                     label: Text('Out: ${message.outputTokens}'),
                     avatar: Icon(Icons.output, size: 14),
                     backgroundColor: Colors.green.shade50,
                     visualDensity: VisualDensity.compact,
                   ),
                 ),
             ],
           ],
         ),
       );
     }
   }
   ```

4. **平台差异处理**
   ```dart
   // 桌面端：使用 Tooltip hover 提示
   // 移动端：使用 tap/long-press 显示详情

   Widget _buildTokenChip(String label, int? value, IconData icon, Color color) {
     if (value == null) return SizedBox.shrink();

     final chip = Chip(
       label: Text('$label: $value'),
       avatar: Icon(icon, size: 14),
       backgroundColor: color,
       visualDensity: VisualDensity.compact,
     );

     // 桌面端：添加 Tooltip
     if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
       return Tooltip(
         message: '$label Tokens: $value\nClick for details',
         child: chip,
       );
     }

     // 移动端：添加 tap 手势
     return GestureDetector(
       onTap: () => _showTokenDetails(label, value),
       child: chip,
     );
   }
   ```

---

### 1.5 测试验证清单

**数据层测试：**
- [ ] inputTokens 字段正确存储到 Hive
- [ ] outputTokens 字段正确存储到 Hive
- [ ] 旧消息（无 token 字段）能正常读取（nullable 保证）
- [ ] 新消息（有 token 字段）能正常读取

**API 层测试：**
- [ ] OpenAI API 响应的 usage 字段正确提取
- [ ] Gemini API 响应的 usageMetadata 字段正确提取
- [ ] Anthropic API 响应的 usage 字段正确提取
- [ ] 流式响应结束时 token 数据正确写入消息

**UI 层测试（桌面端）：**
- [ ] Token Chip 正常显示（输入 + 输出）
- [ ] Tooltip hover 提示正常
- [ ] Chip 样式正确（颜色、图标、大小）
- [ ] 不挡住其他消息元素

**UI 层测试（移动端）：**
- [ ] Token Chip 正常显示（输入 + 输出）
- [ ] tap/long-press 提示正常
- [ ] 小屏幕下不换行错乱
- [ ] 与上游新增元数据不冲突

**集成测试：**
- [ ] 与表情包渲染不冲突
- [ ] 与 Markdown WebView 渲染不冲突
- [ ] 与 HTML 预览不冲突
- [ ] 与工具调用显示不冲突

---

## 二、Response API 工具调用修改（本地核心逻辑）

### 2.1 冲突描述

**用户反馈：**
> "我关于请求本身response的调用工具的也修了啊！这个肯定也有冲突 都要保留我自己的内容哦"

**本地修改范围：**
- Response API 工具调用流程（可能添加了循环限制、错误处理等）
- 工具调用结果的格式化和展示
- 多轮工具调用的管理（防止无限循环）
- 工具调用事件的存储和追踪

**上游可能的修改：**
- Response API 架构重构（统一的 Response 处理）
- 工具调用格式标准化
- MCP 工具集成方式变更
- 工具结果的 markdown 格式化

**冲突风险：** 🔴 **高风险** - 核心业务逻辑冲突，可能导致工具调用完全失效

---

### 2.2 本地工具调用实现分析

**需要保留的关键代码：**

#### 工具调用循环限制
```dart
// lib/core/services/api/chat_api_service.dart
// 本地可能添加的循环限制逻辑

class ChatApiService {
  static const int maxToolCallLoops = 5;  // 本地配置

  Future<void> handleConversation(Conversation conv) async {
    int loopCount = 0;
    bool hasToolCalls = true;

    while (hasToolCalls && loopCount < maxToolCallLoops) {
      final response = await sendMessage(...);

      // 检查是否有工具调用
      hasToolCalls = response.toolCalls?.isNotEmpty ?? false;

      if (hasToolCalls) {
        // 执行工具调用
        final toolResults = await _executeToolCalls(response.toolCalls!);

        // 将工具结果添加到消息历史
        await _addToolResultMessages(conv, toolResults);

        loopCount++;
      }
    }

    // 本地逻辑：如果超过限制，记录警告
    if (loopCount >= maxToolCallLoops) {
      print('Warning: Tool call loop limit reached ($maxToolCallLoops)');
      // 可能添加用户提示
    }
  }
}
```

#### 工具调用错误处理
```dart
// 本地可能添加的错误处理逻辑

Future<List<ToolResult>> _executeToolCalls(List<ToolCall> toolCalls) async {
  final results = <ToolResult>[];

  for (final toolCall in toolCalls) {
    try {
      // 执行工具
      final result = await _executeSingleTool(toolCall);
      results.add(result);

      // 本地逻辑：记录工具调用事件
      await _logToolEvent(toolCall, result);

    } catch (e, stackTrace) {
      // 本地逻辑：捕获错误，返回错误信息给模型
      final errorResult = ToolResult(
        toolCallId: toolCall.id,
        content: 'Error executing tool: $e',
        isError: true,
      );
      results.add(errorResult);

      // 本地逻辑：记录错误日志
      print('Tool execution error: $e\n$stackTrace');
    }
  }

  return results;
}
```

#### 工具调用事件存储
```dart
// lib/core/models/tool_event.dart
// 本地可能添加的工具事件模型

@HiveType(typeId: 5)
class ToolEvent {
  @HiveField(0) final String id;
  @HiveField(1) final String conversationId;
  @HiveField(2) final String messageId;
  @HiveField(3) final String toolName;
  @HiveField(4) final Map<String, dynamic> input;
  @HiveField(5) final String? output;
  @HiveField(6) final bool isError;
  @HiveField(7) final DateTime createdAt;

  // 本地逻辑：用于调试和统计
}
```

#### 工具结果格式化
```dart
// 本地可能的工具结果格式化逻辑

String _formatToolResult(ToolResult result) {
  if (result.isError) {
    return '''
**Tool Execution Error**
Tool: ${result.toolName}
Error: ${result.content}
''';
  }

  return '''
**Tool Result: ${result.toolName}**
${result.content}
''';
}
```

---

### 2.3 上游 Response API 架构分析

**需要调查的上游文件：**
```bash
# 查看上游的 Response API 架构
git show upstream/master:lib/core/services/api/chat_api_service.dart

# 查看上游的工具调用模型
git show upstream/master:lib/core/models/tool_call.dart

# 查看上游的 MCP 工具服务
git show upstream/master:lib/core/services/mcp/mcp_tool_service.dart

# 查看工具调用相关的提交
git log upstream/master --oneline --grep="tool" --grep="Response API"
```

**预期上游修改：**
1. 可能统一了 Response 对象（包含 message、toolCalls、usage）
2. 可能重构了工具调用流程（更模块化）
3. 可能添加了工具调用的类型定义
4. 可能优化了流式响应中的工具调用处理

---

### 2.4 合并策略

#### 策略 B：采用上游架构，移植本地逻辑

**步骤：**

1. **采用上游的 Response API 基础架构**
   ```dart
   // 上游的 Response 对象（保留）
   class ChatResponse {
     final String? messageId;
     final String? content;
     final List<ToolCall>? toolCalls;
     final Usage? usage;  // 包含 token 信息
     final bool isComplete;
   }
   ```

2. **在上游架构中集成本地的循环限制**
   ```dart
   // 合并后的 chat_api_service.dart

   class ChatApiService {
     // 本地配置（保留）
     static const int maxToolCallLoops = 5;

     // 上游的 Response API 方法（保留）
     Future<Stream<ChatResponse>> sendMessage(...) async {
       // 上游的请求构建逻辑
       final request = _buildRequest(...);

       // 上游的 HTTP 请求
       final response = await _httpClient.post(...);

       // 上游的流式响应解析
       return response.stream.transform(_parseResponseTransformer);
     }

     // 本地的工具调用管理逻辑（保留并增强）
     Future<void> handleConversationWithTools(Conversation conv) async {
       int loopCount = 0;
       bool hasToolCalls = true;

       while (hasToolCalls && loopCount < maxToolCallLoops) {
         // 发送消息（使用上游的 sendMessage）
         final responseStream = sendMessage(
           messages: conv.messages,
           tools: conv.enabledTools,  // 本地逻辑
         );

         ChatResponse? finalResponse;
         await for (final response in responseStream) {
           finalResponse = response;

           // 流式更新 UI（上游逻辑）
           _updateStreamingMessage(response);
         }

         // 检查工具调用（上游数据 + 本地逻辑）
         hasToolCalls = finalResponse?.toolCalls?.isNotEmpty ?? false;

         if (hasToolCalls) {
           // 执行工具（本地逻辑 + 本地错误处理）
           final toolResults = await _executeToolCallsWithErrorHandling(
             finalResponse!.toolCalls!,
           );

           // 添加工具结果到消息历史（上游格式）
           await _addToolResultMessages(conv, toolResults);

           // 本地逻辑：记录工具调用事件
           await _logToolEvents(conv.id, finalResponse.messageId, toolResults);

           loopCount++;
         }
       }

       // 本地逻辑：循环限制警告
       if (loopCount >= maxToolCallLoops) {
         await _handleToolLoopLimitReached(conv);
       }
     }

     // 本地新增：带错误处理的工具执行
     Future<List<ToolResult>> _executeToolCallsWithErrorHandling(
       List<ToolCall> toolCalls,
     ) async {
       final results = <ToolResult>[];

       for (final toolCall in toolCalls) {
         try {
           // 使用上游的工具执行逻辑
           final result = await McpToolService.executeTool(toolCall);
           results.add(result);

         } catch (e, stackTrace) {
           // 本地逻辑：错误捕获和格式化
           final errorResult = ToolResult(
             toolCallId: toolCall.id,
             toolName: toolCall.name,
             content: 'Tool execution error: $e',
             isError: true,
           );
           results.add(errorResult);

           // 本地逻辑：错误日志
           _logError('Tool ${toolCall.name} failed', e, stackTrace);
         }
       }

       return results;
     }

     // 本地新增：工具事件记录
     Future<void> _logToolEvents(
       String conversationId,
       String? messageId,
       List<ToolResult> results,
     ) async {
       final box = await Hive.openBox<ToolEvent>('tool_events_v1');

       for (final result in results) {
         final event = ToolEvent(
           id: Uuid().v4(),
           conversationId: conversationId,
           messageId: messageId ?? '',
           toolName: result.toolName,
           input: result.input ?? {},
           output: result.content,
           isError: result.isError,
           createdAt: DateTime.now(),
         );

         await box.add(event);
       }
     }

     // 本地新增：循环限制处理
     Future<void> _handleToolLoopLimitReached(Conversation conv) async {
       // 记录警告日志
       print('Warning: Tool call loop limit reached for conversation ${conv.id}');

       // 添加系统消息提示用户
       final warningMessage = ChatMessage(
         id: Uuid().v4(),
         conversationId: conv.id,
         role: 'system',
         content: 'Tool call loop limit reached. The assistant may be stuck in a loop.',
         createdAt: DateTime.now(),
       );

       await ChatService.saveMessage(warningMessage);
     }
   }
   ```

3. **数据模型合并**
   ```dart
   // 上游的 ToolCall 模型（保留）
   class ToolCall {
     final String id;
     final String name;
     final Map<String, dynamic> arguments;
   }

   // 上游的 ToolResult 模型（保留并增强）
   class ToolResult {
     final String toolCallId;
     final String toolName;
     final String content;
     final bool isError;  // 本地新增
     final Map<String, dynamic>? input;  // 本地新增（用于调试）
   }

   // 本地的 ToolEvent 模型（保留）
   @HiveType(typeId: 5)
   class ToolEvent {
     // ... (见上文)
   }
   ```

4. **配置项集成**
   ```dart
   // lib/core/providers/settings_provider.dart

   class SettingsProvider extends ChangeNotifier {
     // 本地新增配置
     int _maxToolCallLoops = 5;

     int get maxToolCallLoops => _maxToolCallLoops;

     Future<void> setMaxToolCallLoops(int value) async {
       if (value < 1 || value > 20) {
         throw ArgumentError('Max tool call loops must be between 1 and 20');
       }
       _maxToolCallLoops = value;
       await _saveSettings();
       notifyListeners();
     }
   }
   ```

---

### 2.5 测试验证清单

**工具调用流程测试：**
- [ ] 单次工具调用正常执行
- [ ] 多轮工具调用正常执行（2-3 轮）
- [ ] 工具调用循环限制生效（第 6 轮停止）
- [ ] 工具调用错误正常捕获
- [ ] 错误信息正确返回给模型

**工具事件记录测试：**
- [ ] ToolEvent 正确存储到 Hive
- [ ] 工具输入参数正确记录
- [ ] 工具输出结果正确记录
- [ ] 错误标志正确设置

**集成测试：**
- [ ] MCP 工具调用正常（stdio/SSE/WebSocket）
- [ ] 搜索工具调用正常（Exa/Tavily/Brave）
- [ ] 内置工具调用正常（url_context 等）
- [ ] 与上游 Response API 架构兼容

**配置测试：**
- [ ] maxToolCallLoops 设置生效
- [ ] 设置持久化存储
- [ ] 超出范围值拒绝（<1 或 >20）

---

## 三、其他高风险冲突区域

### 3.1 Hive 数据模型字段冲突

**风险等级：** 🔴 **最高风险**

**冲突点：**
- ChatMessage 模型：本地添加 sticker、inputTokens、outputTokens，上游可能添加其他字段
- Conversation 模型：本地可能添加统计字段，上游可能添加分组字段
- typeId 冲突：如果双方都添加新模型，typeId 可能重复

**缓解措施：**
1. **阶段二优先处理**（见 MERGE_PLAN.md）
2. 导出双方模型定义，手动比对所有字段
3. 为新字段分配不冲突的 @HiveField 索引
4. 添加 schemaVersion 字段用于迁移检测
5. 编写数据迁移测试脚本

**回滚方案：**
```bash
# 如果数据模型有问题，立即回滚
git checkout backup-pre-merge-YYYYMMDD
cp gitmerge/backup_hive_YYYYMMDD/* ~/.local/share/kelivo/hive_boxes/
```

---

### 3.2 依赖版本冲突

**风险等级：** 🟡 **中风险**

**冲突点：**
- camera 包：本地可能使用 camera_windows，上游可能升级了 camera
- http 相关包：dio vs http 版本差异
- MCP 相关包：mcp_client 版本差异

**缓解措施：**
1. 手动合并 pubspec.yaml，保留双方依赖
2. 优先选择更高版本（兼容性更好）
3. 测试所有平台编译（Android + Windows + Web）
4. 使用 `flutter pub outdated` 检查依赖健康度

**回滚方案：**
```bash
git checkout HEAD~1 -- pubspec.yaml pubspec.lock
flutter pub get
```

---

### 3.3 供应商头像路径冲突

**风险等级：** 🟡 **中风险**

**冲突点：**
- 本地使用 `avatars/providers/` 路径
- 上游可能使用不同的路径方案
- 备份恢复时路径分隔符问题（Windows vs Linux）

**缓解措施：**
1. 保留本地的 `avatars/providers/` 方案（已测试跨平台）
2. 在备份系统中统一路径处理
3. 测试 Windows → Android 备份恢复

**代码示例：**
```dart
// lib/core/services/backup/data_sync.dart
class DataSync {
  // 统一路径格式（使用正斜杠）
  static String normalizePath(String path) {
    return path.replaceAll('\\', '/');
  }

  // 备份头像
  Future<void> _backupAvatars() async {
    final avatarsDir = await _getAvatarsDirectory();
    final files = avatarsDir.listSync(recursive: true);

    for (final file in files) {
      if (file is File) {
        // 使用相对路径和统一分隔符
        final relativePath = normalizePath(
          path.relative(file.path, from: avatarsDir.path),
        );

        await _uploadToWebDAV('avatars/$relativePath', file);
      }
    }
  }
}
```

---

## 四、冲突解决优先级

### 高优先级（必须在阶段二完成）
1. ✅ Hive 数据模型统一（ChatMessage、Conversation）
2. ✅ typeId 冲突检查
3. ✅ 数据迁移测试脚本

### 中优先级（阶段四完成）
4. ✅ Response API 工具调用逻辑合并
5. ✅ Token 提取逻辑集成
6. ✅ 工具调用循环限制移植

### 低优先级（阶段五完成）
7. ✅ Token UI 显示组件合并
8. ✅ 工具事件记录功能保留
9. ✅ 供应商头像路径统一

---

## 五、冲突检测工具

### 自动化检测脚本

```bash
#!/bin/bash
# gitmerge/detect_conflicts.sh

echo "=== Conflict Detection Tool ==="

# 1. 检测 Hive typeId 冲突
echo "Checking Hive typeId conflicts..."
git show upstream/master:lib/core/models/ | grep -E "@HiveType\(typeId:" > /tmp/upstream_typeids.txt
grep -rE "@HiveType\(typeId:" lib/core/models/ > /tmp/local_typeids.txt

if diff /tmp/upstream_typeids.txt /tmp/local_typeids.txt > /dev/null; then
  echo "✅ No typeId conflicts detected"
else
  echo "⚠️  Potential typeId conflicts:"
  diff /tmp/upstream_typeids.txt /tmp/local_typeids.txt
fi

# 2. 检测 ChatMessage 字段差异
echo ""
echo "Checking ChatMessage field differences..."
git diff upstream/master HEAD -- lib/core/models/chat_message.dart

# 3. 检测依赖冲突
echo ""
echo "Checking dependency conflicts..."
git diff upstream/master HEAD -- pubspec.yaml | grep -E "^\+|^\-" | grep -v "^+++" | grep -v "^---"

# 4. 检测 API 服务修改
echo ""
echo "Checking API service modifications..."
git log --oneline HEAD --not upstream/master -- lib/core/services/api/

echo ""
echo "=== Detection Complete ==="
```

---

## 六、测试数据准备

### 6.1 创建测试对话数据

```dart
// test/fixtures/test_conversations.dart

class TestConversations {
  // 包含 Token 的对话（测试本地功能）
  static Conversation withTokens() {
    return Conversation(
      id: 'test-conv-tokens',
      title: 'Test Conversation with Tokens',
      messages: [
        ChatMessage(
          id: 'msg-1',
          role: 'user',
          content: 'Hello',
        ),
        ChatMessage(
          id: 'msg-2',
          role: 'assistant',
          content: 'Hi there!',
          inputTokens: 120,  // 本地字段
          outputTokens: 50,   // 本地字段
        ),
      ],
    );
  }

  // 包含工具调用的对话（测试本地逻辑）
  static Conversation withToolCalls() {
    return Conversation(
      id: 'test-conv-tools',
      title: 'Test Conversation with Tool Calls',
      messages: [
        ChatMessage(
          id: 'msg-1',
          role: 'user',
          content: 'Search for Flutter tutorials',
        ),
        ChatMessage(
          id: 'msg-2',
          role: 'assistant',
          content: '',
          toolCalls: [  // 上游字段
            ToolCall(
              id: 'call-1',
              name: 'web_search',
              arguments: {'query': 'Flutter tutorials'},
            ),
          ],
        ),
        ChatMessage(
          id: 'msg-3',
          role: 'tool',
          content: 'Found 10 tutorials...',
          toolCallId: 'call-1',
        ),
        ChatMessage(
          id: 'msg-4',
          role: 'assistant',
          content: 'Here are the tutorials...',
          inputTokens: 500,  // 本地字段
          outputTokens: 300,  // 本地字段
        ),
      ],
    );
  }

  // 包含表情包的对话（测试本地功能）
  static Conversation withStickers() {
    return Conversation(
      id: 'test-conv-stickers',
      title: 'Test Conversation with Stickers',
      messages: [
        ChatMessage(
          id: 'msg-1',
          role: 'user',
          content: '[[sticker:nachoneko_happy]]',
          sticker: 'nachoneko_happy',  // 本地字段
        ),
      ],
    );
  }
}
```

---

## 七、回滚计划总结

### 紧急停止条件
立即停止并回滚如果出现：
- ❌ 用户数据损坏无法恢复
- ❌ 核心功能完全失效（无法发送消息）
- ❌ 编译错误无法解决超过 2 天

### 回滚步骤
```bash
# 1. 切回备份标签
git checkout backup-pre-merge-$(date +%Y%m%d)

# 2. 恢复用户数据库
cp gitmerge/backup_hive_$(date +%Y%m%d)/* ~/.local/share/kelivo/hive_boxes/
# Windows:
cp gitmerge\backup_hive_$(Get-Date -Format yyyyMMdd)\* $env:APPDATA\kelivo\hive_boxes\

# 3. 重新安装依赖
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs

# 4. 测试运行
flutter run -d windows --debug
```

---

**文档状态：** ✅ 初稿完成
**下一步行动：** 开始阶段二 - 数据模型对比（见 MERGE_PLAN.md）
