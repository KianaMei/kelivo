# 本地功能保留清单 - KianaMei/kelivo

**创建时间：** 2025-11-08
**本地仓库：** https://github.com/KianaMei/kelivo
**领先上游：** 139 commits

---

## 一、概览

### 1.1 本地特色功能分类

| 类别 | 功能数量 | 保留优先级 |
|------|----------|-----------|
| 核心功能 | 8+ | ⭐⭐⭐⭐⭐ |
| UI 增强 | 6+ | ⭐⭐⭐⭐⭐ |
| 平台特性 | 5+ | ⭐⭐⭐⭐ |
| 工具集成 | 3+ | ⭐⭐⭐⭐ |
| 配置选项 | 4+ | ⭐⭐⭐ |

### 1.2 合并成功标准

合并完成后，以下所有功能必须正常运行：
- [x] 表情包工具系统
- [x] Token 多轮追踪与统计
- [x] 供应商自定义头像（跨平台同步）
- [x] 模型选择器 Tab 化
- [x] SSL 证书验证跳过
- [x] 相机拍摄页面（Android + Windows）
- [x] 鼠标侧键返回（Windows）
- [x] 工具调用循环限制
- [x] Token 显示 UI
- [x] 文件选择器增强

---

## 二、核心功能（最高优先级）

### 2.1 表情包工具系统

**功能描述：**
使用自定义标记 `[[sticker:id]]` 在对话中发送和显示表情包（nachoneko 系列）。

**关键文件：**
```
lib/features/sticker/
├── sticker_renderer.dart        # 表情包渲染器
├── sticker_picker.dart           # 表情包选择器
├── sticker_tool.dart             # MCP 工具定义
└── assets/
    └── stickers/
        └── nachoneko/            # 表情包资源
```

**数据模型：**
```dart
// lib/core/models/chat_message.dart
class ChatMessage {
  // 本地新增字段
  @HiveField(10) final String? sticker;  // 表情包 ID
}
```

**渲染逻辑：**
```dart
// lib/features/sticker/sticker_renderer.dart
class StickerRenderer extends StatelessWidget {
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final stickerId = _extractStickerId(message.content);

    if (stickerId != null) {
      return Image.asset(
        'assets/stickers/nachoneko/$stickerId.png',
        width: 200,
        height: 200,
      );
    }

    // 降级显示原始文本
    return SelectableText(message.content);
  }

  String? _extractStickerId(String content) {
    final regex = RegExp(r'\[\[sticker:(\w+)\]\]');
    final match = regex.firstMatch(content);
    return match?.group(1);
  }
}
```

**MCP 工具集成：**
```dart
// lib/features/sticker/sticker_tool.dart
class StickerTool {
  static const String name = 'nachoneko_sticker';

  static Map<String, dynamic> getToolDefinition() {
    return {
      'name': name,
      'description': 'Send a cute Nachoneko sticker',
      'parameters': {
        'type': 'object',
        'properties': {
          'sticker_id': {
            'type': 'string',
            'enum': [
              'nachoneko_happy',
              'nachoneko_sad',
              'nachoneko_angry',
              'nachoneko_surprised',
              // ... 更多表情包
            ],
            'description': 'The sticker ID to send',
          },
        },
        'required': ['sticker_id'],
      },
    };
  }

  static String execute(Map<String, dynamic> args) {
    final stickerId = args['sticker_id'] as String;
    return '[[sticker:$stickerId]]';
  }
}
```

**测试验证清单：**
- [ ] 表情包正常显示（Android + Windows）
- [ ] 表情包选择器正常弹出
- [ ] MCP 工具调用正常（模型能发送表情包）
- [ ] 表情包资源正确打包到发布版本
- [ ] 长按表情包显示原始标记（调试功能）
- [ ] 与上游 Markdown 渲染不冲突

**保留优先级：** ⭐⭐⭐⭐⭐ **最高优先级**

**合并注意事项：**
- 在消息渲染优先级中，表情包检测必须在 Markdown 检测之前
- 确保 assets/stickers/ 目录在 pubspec.yaml 中正确声明
- 与上游的 WebView 渲染器隔离（不要在 WebView 中渲染表情包）

---

### 2.2 Token 多轮追踪与统计

**功能描述：**
在聊天消息中显示输入 token 和输出 token，支持桌面端 hover 提示和移动端 tap 显示。

**关键文件：**
```
lib/features/chat/widgets/chat_message_widget.dart  # Token 显示 UI
lib/features/token_stats/                            # Token 统计卡片（如果存在）
lib/core/services/api/chat_api_service.dart          # Token 提取逻辑
```

**数据模型：**
```dart
// lib/core/models/chat_message.dart
class ChatMessage {
  // 本地新增字段
  @HiveField(11) final int? inputTokens;   // 输入 token 数量
  @HiveField(12) final int? outputTokens;  // 输出 token 数量
}
```

**API 提取逻辑：**
```dart
// lib/core/services/api/chat_api_service.dart
StreamTransformer<Map<String, dynamic>, Map<String, dynamic>>
    get _extractTokenUsageTransformer {
  return StreamTransformer.fromHandlers(
    handleData: (data, sink) {
      // 提取 usage 字段（OpenAI/Anthropic 格式）
      if (data['usage'] != null) {
        final usage = data['usage'];
        _currentMessage.inputTokens = usage['prompt_tokens'];
        _currentMessage.outputTokens = usage['completion_tokens'];
      }

      // 提取 usageMetadata 字段（Gemini 格式）
      if (data['usageMetadata'] != null) {
        final usage = data['usageMetadata'];
        _currentMessage.inputTokens = usage['promptTokenCount'];
        _currentMessage.outputTokens = usage['candidatesTokenCount'];
      }

      sink.add(data);
    },
  );
}
```

**UI 显示逻辑：**
```dart
// lib/features/chat/widgets/chat_message_widget.dart
Widget _buildMessageFooter(ChatMessage message) {
  return Row(
    children: [
      // 时间戳
      Text(formatTime(message.createdAt)),

      Spacer(),

      // Token 显示（仅 assistant 消息）
      if (message.role == 'assistant') ...[
        if (message.inputTokens != null)
          _buildTokenChip('In', message.inputTokens!, Icons.input, Colors.blue.shade50),
        SizedBox(width: 4),
        if (message.outputTokens != null)
          _buildTokenChip('Out', message.outputTokens!, Icons.output, Colors.green.shade50),
      ],
    ],
  );
}

Widget _buildTokenChip(String label, int value, IconData icon, Color color) {
  final chip = Chip(
    label: Text('$label: $value'),
    avatar: Icon(icon, size: 14),
    backgroundColor: color,
    visualDensity: VisualDensity.compact,
  );

  // 桌面端：Tooltip hover 提示
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return Tooltip(
      message: '$label Tokens: $value',
      child: chip,
    );
  }

  // 移动端：GestureDetector tap 提示
  return GestureDetector(
    onTap: () => _showTokenDetails(label, value),
    child: chip,
  );
}
```

**统计卡片（可选）：**
```dart
// lib/features/token_stats/token_stats_card.dart
class TokenStatsCard extends StatelessWidget {
  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final totalInput = conversation.messages
        .where((m) => m.inputTokens != null)
        .fold(0, (sum, m) => sum + m.inputTokens!);

    final totalOutput = conversation.messages
        .where((m) => m.outputTokens != null)
        .fold(0, (sum, m) => sum + m.outputTokens!);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Token Statistics',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat('Input', totalInput, Icons.input),
                _buildStat('Output', totalOutput, Icons.output),
                _buildStat('Total', totalInput + totalOutput, Icons.analytics),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, int value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 32),
        SizedBox(height: 4),
        Text(
          value.toString(),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 12)),
      ],
    );
  }
}
```

**测试验证清单：**
- [ ] OpenAI API token 正确提取
- [ ] Gemini API token 正确提取（usageMetadata）
- [ ] Anthropic API token 正确提取
- [ ] Token Chip 正常显示（输入 + 输出）
- [ ] 桌面端 Tooltip hover 正常
- [ ] 移动端 tap 提示正常
- [ ] Token 统计卡片正确计算累计值
- [ ] 与上游消息元数据不冲突

**保留优先级：** ⭐⭐⭐⭐⭐ **最高优先级**

**合并注意事项：**
- 必须在 Response API 合并中保留 Token 提取逻辑（见 CONFLICT_CRITICAL.md 2.4）
- UI 组件必须在上游消息渲染架构中保留位置
- 支持多种 API 格式（OpenAI、Gemini、Anthropic）

---

### 2.3 工具调用循环限制

**功能描述：**
防止模型陷入无限工具调用循环，默认限制 5 轮。

**关键文件：**
```
lib/core/services/api/chat_api_service.dart
lib/core/providers/settings_provider.dart
```

**实现逻辑：**
```dart
// lib/core/services/api/chat_api_service.dart
class ChatApiService {
  static const int defaultMaxToolCallLoops = 5;

  Future<void> handleConversationWithTools(Conversation conv) async {
    final maxLoops = SettingsProvider().maxToolCallLoops ?? defaultMaxToolCallLoops;
    int loopCount = 0;
    bool hasToolCalls = true;

    while (hasToolCalls && loopCount < maxLoops) {
      // 发送消息
      final responseStream = sendMessage(...);

      ChatResponse? finalResponse;
      await for (final response in responseStream) {
        finalResponse = response;
      }

      // 检查工具调用
      hasToolCalls = finalResponse?.toolCalls?.isNotEmpty ?? false;

      if (hasToolCalls) {
        // 执行工具
        final toolResults = await _executeToolCalls(finalResponse!.toolCalls!);

        // 添加工具结果
        await _addToolResultMessages(conv, toolResults);

        loopCount++;
      }
    }

    // 循环限制警告
    if (loopCount >= maxLoops) {
      await _handleToolLoopLimitReached(conv, maxLoops);
    }
  }

  Future<void> _handleToolLoopLimitReached(Conversation conv, int limit) async {
    print('Warning: Tool call loop limit reached ($limit) for conversation ${conv.id}');

    // 添加系统消息
    final warningMessage = ChatMessage(
      id: Uuid().v4(),
      conversationId: conv.id,
      role: 'system',
      content: 'Tool call loop limit reached ($limit rounds). Stopping to prevent infinite loops.',
      createdAt: DateTime.now(),
    );

    await ChatService.saveMessage(warningMessage);
  }
}
```

**配置选项：**
```dart
// lib/core/providers/settings_provider.dart
class SettingsProvider extends ChangeNotifier {
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

**设置 UI：**
```dart
// lib/desktop/desktop_settings_page.dart 或 lib/features/settings/
ListTile(
  title: Text('Max Tool Call Loops'),
  subtitle: Text('Prevent infinite tool call loops (1-20)'),
  trailing: SizedBox(
    width: 80,
    child: TextField(
      controller: _maxLoopsController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        hintText: '5',
      ),
      onSubmitted: (value) {
        final intValue = int.tryParse(value);
        if (intValue != null) {
          settings.setMaxToolCallLoops(intValue);
        }
      },
    ),
  ),
),
```

**测试验证清单：**
- [ ] 单次工具调用正常执行
- [ ] 多轮工具调用正常执行（2-3 轮）
- [ ] 第 6 轮停止（默认限制 5）
- [ ] 系统消息正确显示警告
- [ ] 配置选项正确保存和加载
- [ ] 超出范围值（<1 或 >20）拒绝

**保留优先级：** ⭐⭐⭐⭐⭐ **最高优先级**

**合并注意事项：**
- 必须集成到上游的 Response API 架构中（见 CONFLICT_CRITICAL.md 2.4）
- 确保配置选项持久化存储

---

## 三、UI 增强功能

### 3.1 供应商自定义头像（跨平台同步）

**功能描述：**
为每个 AI 供应商（OpenAI、Gemini、Anthropic 等）设置自定义头像，支持跨平台同步（通过 WebDAV 备份恢复）。

**关键文件：**
```
lib/utils/provider_avatar_manager.dart
lib/core/services/backup/data_sync.dart
lib/features/provider/widgets/provider_avatar.dart
```

**实现逻辑：**
```dart
// lib/utils/provider_avatar_manager.dart
class ProviderAvatarManager {
  static const String avatarsPath = 'avatars/providers';

  static Future<String> getAvatarDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory('${appDir.path}/$avatarsPath');

    if (!await avatarsDir.exists()) {
      await avatarsDir.create(recursive: true);
    }

    return avatarsDir.path;
  }

  static Future<File?> getProviderAvatar(String providerId) async {
    final avatarsDir = await getAvatarDirectory();
    final avatarFile = File('$avatarsDir/$providerId.png');

    if (await avatarFile.exists()) {
      return avatarFile;
    }

    return null;
  }

  static Future<void> setProviderAvatar(String providerId, File imageFile) async {
    final avatarsDir = await getAvatarDirectory();
    final targetFile = File('$avatarsDir/$providerId.png');

    // 复制头像文件
    await imageFile.copy(targetFile.path);
  }

  static Future<void> deleteProviderAvatar(String providerId) async {
    final avatarFile = await getProviderAvatar(providerId);
    if (avatarFile != null && await avatarFile.exists()) {
      await avatarFile.delete();
    }
  }
}
```

**备份集成：**
```dart
// lib/core/services/backup/data_sync.dart
class DataSync {
  Future<void> backup() async {
    // ... 其他备份逻辑 ...

    // 备份供应商头像
    await _backupProviderAvatars();
  }

  Future<void> _backupProviderAvatars() async {
    final avatarsDir = await ProviderAvatarManager.getAvatarDirectory();
    final dir = Directory(avatarsDir);

    if (await dir.exists()) {
      final files = dir.listSync();

      for (final file in files) {
        if (file is File) {
          final fileName = path.basename(file.path);
          // 统一路径分隔符（使用正斜杠）
          final remotePath = 'avatars/providers/$fileName';

          await _uploadToWebDAV(remotePath, file);
        }
      }
    }
  }

  Future<void> restore() async {
    // ... 其他恢复逻辑 ...

    // 恢复供应商头像
    await _restoreProviderAvatars();
  }

  Future<void> _restoreProviderAvatars() async {
    final avatarsDir = await ProviderAvatarManager.getAvatarDirectory();

    // 列出 WebDAV 上的头像文件
    final remoteFiles = await _listWebDAVFiles('avatars/providers/');

    for (final remoteFile in remoteFiles) {
      final fileName = path.basename(remoteFile);
      final localFile = File('$avatarsDir/$fileName');

      // 下载头像
      await _downloadFromWebDAV(remoteFile, localFile);
    }
  }
}
```

**UI 组件：**
```dart
// lib/features/provider/widgets/provider_avatar.dart
class ProviderAvatar extends StatelessWidget {
  final String providerId;
  final double size;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: ProviderAvatarManager.getProviderAvatar(providerId),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          // 显示自定义头像
          return CircleAvatar(
            radius: size / 2,
            backgroundImage: FileImage(snapshot.data!),
          );
        }

        // 显示默认头像（供应商 Logo）
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: _getProviderColor(providerId),
          child: Text(
            _getProviderInitials(providerId),
            style: TextStyle(
              fontSize: size / 2,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}
```

**测试验证清单：**
- [ ] 上传自定义头像正常（图片选择器）
- [ ] 头像正常显示在聊天消息中
- [ ] 头像正常显示在供应商列表中
- [ ] 删除头像正常（恢复默认）
- [ ] Windows 备份头像正常
- [ ] Android 恢复头像正常（跨平台）
- [ ] 路径分隔符正确处理（Windows \ vs Linux /）

**保留优先级：** ⭐⭐⭐⭐⭐ **最高优先级**

**合并注意事项：**
- 保留 `avatars/providers/` 路径方案（已测试跨平台）
- 在备份系统中集成头像备份逻辑
- 确保路径统一处理（normalizePath）

---

### 3.2 模型选择器 Tab 化

**功能描述：**
模型选择器支持 Tab 切换供应商，移动端支持左右滑动。

**用户决策：** 🔄 **混合方案**（见 UI_DECISIONS.md 第2节）
- 本地逻辑：Tab 化供应商切换 + 移动端滑动
- 上游位置：桌面端 Dialog 居中显示（不挡住聊天内容）

**关键文件：**
```
lib/features/model/widgets/model_selector_core.dart  # 核心逻辑
lib/features/model/widgets/model_selector.dart        # 平台包装器
```

**核心逻辑（保留）：**
```dart
// lib/features/model/widgets/model_selector_core.dart
class ModelSelectorCore extends StatefulWidget {
  @override
  _ModelSelectorCoreState createState() => _ModelSelectorCoreState();
}

class _ModelSelectorCoreState extends State<ModelSelectorCore>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    final providers = context.read<ModelProvider>().providers;

    _tabController = TabController(length: providers.length, vsync: this);
    _pageController = PageController();

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _pageController.animateToPage(
          _tabController.index,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final providers = context.watch<ModelProvider>().providers;

    return Column(
      children: [
        // Tab 栏（供应商切换）
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: providers.map((provider) {
            return Tab(
              child: Row(
                children: [
                  ProviderAvatar(providerId: provider.id, size: 24),
                  SizedBox(width: 8),
                  Text(provider.name),
                ],
              ),
            );
          }).toList(),
        ),

        SizedBox(height: 8),

        // 模型列表（可左右滑动）
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: providers.length,
            onPageChanged: (index) {
              _tabController.animateTo(index);
            },
            itemBuilder: (context, index) {
              return _buildModelList(providers[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModelList(Provider provider) {
    return ListView.builder(
      itemCount: provider.models.length,
      itemBuilder: (context, index) {
        final model = provider.models[index];
        return ListTile(
          title: Text(model.name),
          subtitle: Text(model.description ?? ''),
          onTap: () {
            context.read<ModelProvider>().selectModel(model);
            Navigator.pop(context);
          },
        );
      },
    );
  }
}
```

**平台包装器（采用上游位置）：**
```dart
// lib/features/model/widgets/model_selector.dart
class ModelSelector {
  static void show(BuildContext context) {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // 桌面端：Dialog 居中显示（上游位置）
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 600,
            height: 500,
            child: ModelSelectorCore(),  // 本地逻辑
          ),
        ),
      );
    } else {
      // 移动端：底部弹出（本地位置）
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: ModelSelectorCore(),  // 本地逻辑
        ),
      );
    }
  }
}
```

**测试验证清单：**
- [ ] Windows: Dialog 居中显示（不挡住聊天内容）
- [ ] Android: 底部弹出
- [ ] Tab 切换供应商正常
- [ ] 左右滑动切换供应商正常（移动端）
- [ ] 供应商头像正常显示
- [ ] 模型列表正常显示
- [ ] 选择模型后 Dialog/BottomSheet 关闭

**保留优先级：** ⭐⭐⭐⭐⭐ **最高优先级**

**合并注意事项：**
- 保留本地的 Tab 化逻辑（ModelSelectorCore）
- 采用上游的对话框位置（桌面端 Dialog 居中）
- 确保供应商头像集成正常

---

### 3.3 文字选择功能

**功能描述：**
聊天消息支持文字选择（SelectableText），方便复制。

**关键文件：**
```
lib/features/chat/widgets/chat_message_widget.dart
```

**实现逻辑：**
```dart
// 普通文本消息使用 SelectableText
Widget _buildPlainTextMessage(ChatMessage message) {
  return SelectableText(
    message.content,
    style: TextStyle(fontSize: 16),
  );
}

// Markdown 渲染器也启用文字选择
Widget _buildMarkdownMessage(ChatMessage message) {
  return MarkdownWebView(
    content: message.content,
    enableTextSelection: true,  // 本地功能
  );
}
```

**测试验证清单：**
- [ ] 普通文本消息可选择
- [ ] Markdown 消息可选择（WebView 内）
- [ ] 代码块可选择
- [ ] 表情包消息长按显示原始文本（可选择）

**保留优先级：** ⭐⭐⭐⭐ **高优先级**

**合并注意事项：**
- 在上游 Markdown WebView 中启用 enableTextSelection
- 确保所有文本内容都可选择

---

### 3.4 鼠标侧键返回（Windows）

**功能描述：**
Windows 桌面端支持鼠标侧键（前进/后退）导航。

**关键文件：**
```
lib/desktop/desktop_home_page.dart
```

**实现逻辑：**
```dart
// lib/desktop/desktop_home_page.dart
class DesktopHomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKey: (event) {
        // 检测鼠标侧键
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.browserBack) {
            // 返回上一页
            Navigator.maybePop(context);
          } else if (event.logicalKey == LogicalKeyboardKey.browserForward) {
            // 前进（如果有历史）
            // ...
          }
        }
      },
      child: Scaffold(
        // ... 桌面布局 ...
      ),
    );
  }
}
```

**测试验证清单：**
- [ ] Windows: 鼠标侧键后退正常
- [ ] Windows: 鼠标侧键前进正常（如果有历史）
- [ ] 不影响移动端（无鼠标侧键）

**保留优先级：** ⭐⭐⭐ **中优先级**

**合并注意事项：**
- 保留桌面布局实现（见 UI_DECISIONS.md 第1节）
- 确保 RawKeyboardListener 不被移除

---

## 四、平台特性

### 4.1 相机拍摄页面（Android + Windows）

**功能描述：**
Android 和 Windows 支持直接打开相机拍摄照片并发送。

**关键文件：**
```
lib/features/camera/camera_page.dart
lib/features/home/widgets/chat_input_bar.dart
```

**依赖：**
```yaml
dependencies:
  camera: ^0.10.5             # Android/iOS 相机
  camera_windows: ^0.2.1      # Windows 相机
```

**实现逻辑：**
```dart
// lib/features/camera/camera_page.dart
class CameraPage extends StatefulWidget {
  @override
  _CameraPageState createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();

    if (_cameras != null && _cameras!.isNotEmpty) {
      // 使用后置摄像头（索引 0）
      _controller = CameraController(
        _cameras![0],
        ResolutionPreset.high,
      );

      await _controller!.initialize();
      setState(() {});
    }
  }

  Future<void> _takePicture() async {
    if (_controller != null && _controller!.value.isInitialized) {
      final image = await _controller!.takePicture();
      Navigator.pop(context, File(image.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Camera')),
      body: CameraPreview(_controller!),
      floatingActionButton: FloatingActionButton(
        onPressed: _takePicture,
        child: Icon(Icons.camera),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
```

**聊天输入栏集成：**
```dart
// lib/features/home/widgets/chat_input_bar.dart
Row(
  children: [
    // 相机按钮（仅 Android + Windows）
    if (Platform.isAndroid || Platform.isWindows)
      IconButton(
        icon: Icon(Icons.camera_alt),
        tooltip: 'Camera',
        onPressed: _openCamera,
      ),

    // 附件按钮
    IconButton(
      icon: Icon(Icons.attach_file),
      onPressed: _pickFile,
    ),

    // ...
  ],
)

Future<void> _openCamera() async {
  final image = await Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => CameraPage()),
  );

  if (image != null) {
    _attachFile(image);
  }
}
```

**测试验证清单：**
- [ ] Android: 相机按钮显示
- [ ] Android: 后置摄像头正常启动
- [ ] Android: 拍照正常，照片正确附加
- [ ] Windows: 相机按钮显示
- [ ] Windows: 摄像头正常启动
- [ ] Windows: 拍照正常，照片正确附加
- [ ] iOS/macOS: 相机按钮不显示（或使用系统相机）

**保留优先级：** ⭐⭐⭐⭐ **高优先级**

**合并注意事项：**
- 合并聊天输入栏时保留相机按钮（见 UI_DECISIONS.md 第4节）
- 确保 camera_windows 依赖正确配置

---

### 4.2 SSL 证书验证跳过

**功能描述：**
设置选项允许跳过 SSL 证书验证，用于自签名证书的内网服务器。

**关键文件：**
```
lib/core/services/network/ssl_helper.dart
lib/desktop/desktop_settings_page.dart
lib/core/providers/settings_provider.dart
```

**实现逻辑：**
```dart
// lib/core/services/network/ssl_helper.dart
class SslHelper {
  static HttpClient createHttpClient({bool skipSslVerification = false}) {
    final client = HttpClient();

    if (skipSslVerification) {
      client.badCertificateCallback = (cert, host, port) => true;
    }

    return client;
  }
}

// 集成到 ChatApiService
class ChatApiService {
  http.Client _createClient() {
    final skipSsl = SettingsProvider().skipSslVerification;

    if (skipSsl) {
      final httpClient = SslHelper.createHttpClient(skipSslVerification: true);
      return IOClient(httpClient);
    }

    return http.Client();
  }
}
```

**设置 UI：**
```dart
// lib/desktop/desktop_settings_page.dart
SwitchListTile(
  title: Text('Skip SSL certificate verification'),
  subtitle: Text('Use for self-signed certificates (insecure)'),
  value: settings.skipSslVerification,
  onChanged: (value) {
    settings.setSkipSslVerification(value);
  },
),
```

**配置存储：**
```dart
// lib/core/providers/settings_provider.dart
class SettingsProvider extends ChangeNotifier {
  bool _skipSslVerification = false;

  bool get skipSslVerification => _skipSslVerification;

  Future<void> setSkipSslVerification(bool value) async {
    _skipSslVerification = value;
    await _saveSettings();
    notifyListeners();
  }
}
```

**测试验证清单：**
- [ ] 设置选项存在并可切换
- [ ] 启用后能连接自签名证书服务器
- [ ] 禁用后恢复正常 SSL 验证
- [ ] 配置正确保存和加载

**保留优先级：** ⭐⭐⭐⭐ **高优先级**

**合并注意事项：**
- 保留设置页面实现（见 UI_DECISIONS.md 第7节）
- 集成到上游的 HTTP 客户端配置中

---

### 4.3 FilePicker 替代 ImagePicker

**功能描述：**
使用 file_picker 包替代 image_picker，支持更多文件类型。

**关键依赖：**
```yaml
dependencies:
  file_picker: ^6.1.1  # 本地使用
```

**实现逻辑：**
```dart
// lib/features/home/widgets/chat_input_bar.dart
Future<void> _pickFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'png', 'gif', 'pdf', 'txt', 'md'],
    allowMultiple: true,
  );

  if (result != null && result.files.isNotEmpty) {
    for (final file in result.files) {
      if (file.path != null) {
        _attachFile(File(file.path!));
      }
    }
  }
}
```

**测试验证清单：**
- [ ] 图片文件选择正常
- [ ] PDF 文件选择正常
- [ ] 文本文件选择正常
- [ ] 多文件选择正常
- [ ] 附件正确添加到消息

**保留优先级：** ⭐⭐⭐ **中优先级**

**合并注意事项：**
- 确保 file_picker 与上游依赖无冲突
- 如果上游也使用 file_picker，合并配置

---

## 五、工具集成

### 5.1 工具调用事件存储

**功能描述：**
将所有工具调用（MCP 工具、搜索工具等）记录到 Hive 数据库，用于调试和统计。

**关键文件：**
```
lib/core/models/tool_event.dart
lib/core/services/api/chat_api_service.dart
```

**数据模型：**
```dart
// lib/core/models/tool_event.dart
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

  ToolEvent({
    required this.id,
    required this.conversationId,
    required this.messageId,
    required this.toolName,
    required this.input,
    this.output,
    this.isError = false,
    required this.createdAt,
  });
}
```

**记录逻辑：**
```dart
// lib/core/services/api/chat_api_service.dart
Future<void> _logToolEvent(
  String conversationId,
  String messageId,
  ToolCall toolCall,
  ToolResult result,
) async {
  final box = await Hive.openBox<ToolEvent>('tool_events_v1');

  final event = ToolEvent(
    id: Uuid().v4(),
    conversationId: conversationId,
    messageId: messageId,
    toolName: toolCall.name,
    input: toolCall.arguments,
    output: result.content,
    isError: result.isError,
    createdAt: DateTime.now(),
  );

  await box.add(event);
}
```

**测试验证清单：**
- [ ] MCP 工具调用事件正确记录
- [ ] 搜索工具调用事件正确记录
- [ ] 工具输入参数正确记录
- [ ] 工具输出结果正确记录
- [ ] 错误标志正确设置

**保留优先级：** ⭐⭐⭐ **中优先级**

**合并注意事项：**
- typeId: 5 确保无冲突
- 在 Response API 合并中保留记录逻辑

---

### 5.2 MaxTokens 配置

**功能描述：**
允许用户配置每次请求的最大 token 数（max_tokens 参数）。

**关键文件：**
```
lib/core/providers/settings_provider.dart
lib/core/services/api/chat_api_service.dart
lib/desktop/desktop_settings_page.dart
```

**配置存储：**
```dart
// lib/core/providers/settings_provider.dart
class SettingsProvider extends ChangeNotifier {
  int _maxTokens = 4096;

  int get maxTokens => _maxTokens;

  Future<void> setMaxTokens(int value) async {
    if (value < 1 || value > 128000) {
      throw ArgumentError('Max tokens must be between 1 and 128000');
    }
    _maxTokens = value;
    await _saveSettings();
    notifyListeners();
  }
}
```

**API 集成：**
```dart
// lib/core/services/api/chat_api_service.dart
Map<String, dynamic> _buildRequest(...) {
  return {
    'model': model.id,
    'messages': messages,
    'max_tokens': SettingsProvider().maxTokens,  // 本地配置
    // ...
  };
}
```

**设置 UI：**
```dart
// lib/desktop/desktop_settings_page.dart
ListTile(
  title: Text('Max Tokens'),
  subtitle: Text('Maximum tokens per request (1-128000)'),
  trailing: SizedBox(
    width: 100,
    child: TextField(
      controller: _maxTokensController,
      keyboardType: TextInputType.number,
      onSubmitted: (value) {
        final intValue = int.tryParse(value);
        if (intValue != null) {
          settings.setMaxTokens(intValue);
        }
      },
    ),
  ),
),
```

**测试验证清单：**
- [ ] 配置选项存在并可修改
- [ ] 配置值正确应用到 API 请求
- [ ] 超出范围值拒绝
- [ ] 配置正确保存和加载

**保留优先级：** ⭐⭐⭐⭐ **高优先级**

**合并注意事项：**
- 在上游 Response API 请求构建中集成 maxTokens 参数

---

## 六、配置选项

### 6.1 HTTP 日志记录

**功能描述：**
可选的 HTTP 请求/响应日志记录，用于调试 API 问题。

**关键文件：**
```
lib/core/services/api/chat_api_service.dart
lib/core/providers/settings_provider.dart
```

**实现逻辑：**
```dart
// lib/core/services/api/chat_api_service.dart
Future<http.Response> _sendRequest(http.Request request) async {
  if (SettingsProvider().enableHttpLogging) {
    print('=== HTTP Request ===');
    print('${request.method} ${request.url}');
    print('Headers: ${request.headers}');
    print('Body: ${request.body}');
  }

  final response = await request.send();
  final responseBody = await response.stream.bytesToString();

  if (SettingsProvider().enableHttpLogging) {
    print('=== HTTP Response ===');
    print('Status: ${response.statusCode}');
    print('Body: $responseBody');
  }

  return http.Response(responseBody, response.statusCode);
}
```

**配置选项：**
```dart
// lib/core/providers/settings_provider.dart
bool _enableHttpLogging = false;

bool get enableHttpLogging => _enableHttpLogging;

Future<void> setEnableHttpLogging(bool value) async {
  _enableHttpLogging = value;
  await _saveSettings();
  notifyListeners();
}
```

**设置 UI：**
```dart
SwitchListTile(
  title: Text('Enable HTTP Logging'),
  subtitle: Text('Log API requests/responses for debugging'),
  value: settings.enableHttpLogging,
  onChanged: (value) {
    settings.setEnableHttpLogging(value);
  },
),
```

**测试验证清单：**
- [ ] 启用后日志正常输出
- [ ] 禁用后无日志输出
- [ ] 配置正确保存

**保留优先级：** ⭐⭐ **低优先级**

**合并注意事项：**
- 在上游 HTTP 客户端中集成日志逻辑

---

## 七、保留验证总清单

### 核心功能验证（必须 100% 通过）

- [ ] 表情包工具
  - [ ] 表情包正常显示
  - [ ] 表情包选择器正常
  - [ ] MCP 工具调用正常
  - [ ] 资源正确打包

- [ ] Token 追踪与统计
  - [ ] Token 正确提取（OpenAI/Gemini/Anthropic）
  - [ ] Token UI 正常显示
  - [ ] 桌面端 hover 提示正常
  - [ ] 移动端 tap 提示正常

- [ ] 工具调用循环限制
  - [ ] 循环限制生效
  - [ ] 系统消息正确显示
  - [ ] 配置选项正常

### UI 功能验证

- [ ] 供应商自定义头像
  - [ ] 上传头像正常
  - [ ] 头像显示正常
  - [ ] 跨平台同步正常

- [ ] 模型选择器 Tab 化
  - [ ] Windows Dialog 居中显示
  - [ ] Android 底部弹出
  - [ ] Tab 切换正常
  - [ ] 左右滑动正常

- [ ] 文字选择功能
  - [ ] 普通文本可选择
  - [ ] Markdown 可选择

- [ ] 鼠标侧键返回
  - [ ] Windows 鼠标侧键正常

### 平台特性验证

- [ ] 相机拍摄
  - [ ] Android 相机正常
  - [ ] Windows 相机正常

- [ ] SSL 证书跳过
  - [ ] 设置选项存在
  - [ ] 自签名证书可用

- [ ] FilePicker
  - [ ] 多种文件类型选择正常

### 工具集成验证

- [ ] 工具事件存储
  - [ ] 工具调用事件正确记录

- [ ] MaxTokens 配置
  - [ ] 配置正确应用到请求

### 跨平台验证

- [ ] Windows → Android 备份恢复
  - [ ] 对话正常恢复
  - [ ] 头像正常同步
  - [ ] 设置正常恢复

---

**文档状态：** ✅ 完成
**下一步：** 开始阶段一 - 环境准备（见 MERGE_PLAN.md）
