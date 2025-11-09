# UI 取舍决策记录

**决策时间：** 2025-11-08
**决策原则：** 保留本地所有功能 + 选择性采用上游 UI

---

## 决策总览

| 组件 | 上游实现 | 本地实现 | 最终决策 | 理由 |
|------|----------|----------|----------|------|
| 桌面端主页布局 | 侧边栏 Tabs（会话/主题切换） | 现有布局 | **本地** | 先不管，保持现状 |
| 模型选择器 | 桌面对话框样式 | Tab化 + 移动端滑动 | **混合** | 本地逻辑 + 上游位置 |
| 助手管理页面 | 标签和分组功能 | 助手计数 + Delete 按钮 | **本地** | 上游功能还没搞懂 |
| 聊天输入栏 | 拖放文件上传 | 相机拍摄按钮 | **合并** | 两个功能都保留 |
| 消息渲染 | Markdown WebView + HTML 预览 | 表情包渲染 + 文字选择 | **合并** | 全部功能集成 |
| TTS 实现 | ElevenLabs TTS | Windows stub | **不动** | 暂时保持现状 |
| 设置页面 | 重构的桌面设置页 | 现有设置 + SSL 跳过 | **本地** | 保留现有实现 |

---

## 详细决策说明

### 1. 桌面端主页布局

**上游实现：**
- 侧边栏 Tabs（会话视图 / 主题视图切换）
- 现代化导航体验
- 可能的性能优化

**本地实现：**
- 现有桌面布局
- 用户已经熟悉

**决策：** ✅ **本地**

**理由：**
- 用户明确表示"先不管，按照我的"
- 现有布局稳定，用户熟悉
- 上游侧边栏 Tabs 功能可以后续单独评估

**实施方案：**
```bash
# 完全保留本地 desktop_home_page.dart
# 上游代码记录到 gitmerge/ 备用

cp lib/desktop/desktop_home_page.dart gitmerge/local_desktop_home_page.dart
git show upstream/master:lib/desktop/desktop_home_page.dart > gitmerge/upstream_desktop_home_page.dart

# 不进行合并，保持本地文件不变
```

---

### 2. 模型选择器

**上游实现：**
- 桌面端：对话框从上方弹出（不会挡住聊天内容）
- 统一的对话框样式

**本地实现：**
- 核心逻辑：Tab 化供应商切换
- 移动端：底部弹出 + 左右滑动
- Windows 端：底部弹出（会挡住内容）

**决策：** 🔄 **混合**（本地选择器逻辑 + 上游对话框位置）

**理由：**
- 用户需求："模型选择器本身，按照我的，但是显示位置按照他的"
- 本地的 Tab 化和滑动功能要保留
- 改进 Windows 端的弹出位置（从底部改为 Dialog 居中）
- 移动端保持底部弹出

**实施方案：**

```dart
// 1. 抽离核心逻辑（本地）
class ModelSelectorCore extends StatelessWidget {
  // Tab 化供应商切换
  // 移动端左右滑动
  // 供应商头像显示
  // 模型列表
}

// 2. 平台包装器
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

**测试验证：**
- [ ] Windows: Dialog 居中显示，不挡住聊天内容
- [ ] macOS/Linux: Dialog 居中显示
- [ ] Android: 底部弹出
- [ ] iOS: 底部弹出
- [ ] Tab 切换正常
- [ ] 左右滑动正常（移动端）
- [ ] 供应商头像正常显示

---

### 3. 助手管理页面

**上游实现：**
- 标签和分组功能
- 更强大的组织能力

**本地实现：**
- 每个分支助手计数显示
- Delete 按钮集成到操作栏
- 助手头像同步

**决策：** ✅ **本地**

**理由：**
- 用户明确表示"目前先保留我的，他的我还没搞懂呢"
- 本地功能稳定可用
- 上游标签分组功能可以后续评估并集成

**实施方案：**
```bash
# 完全保留本地 assistant_provider.dart
# 上游代码记录备用

cp lib/core/providers/assistant_provider.dart gitmerge/local_assistant_provider.dart
git show upstream/master:lib/core/providers/assistant_provider.dart > gitmerge/upstream_assistant_provider.dart

# 在代码中添加 TODO 注释
```

```dart
// lib/core/providers/assistant_provider.dart
class AssistantProvider extends ChangeNotifier {
  // 完全保留本地实现：
  // - 头像同步
  // - 助手计数显示
  // - Delete 按钮集成

  // TODO: 后续评估并集成上游的标签分组功能
  // 上游代码参考：gitmerge/upstream_assistant_provider.dart
  // void addTag(String assistantId, String tag) { ... }
  // void removeTag(String assistantId, String tag) { ... }
  // List<String> getTags(String assistantId) { ... }
}
```

---

### 4. 聊天输入栏

**上游实现：**
- 拖放文件上传（DragTarget）
- 更现代的交互方式

**本地实现：**
- 相机拍摄按钮（Android + Windows）
- 附件选择按钮

**决策：** ✅ **合并**（两个功能都保留）

**理由：**
- 用户明确要求"合并"
- 拖放和相机功能不冲突
- 提供更多的输入方式

**实施方案：**

```dart
class ChatInputBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DragTarget<List<File>>(  // 上游：拖放支持
      onAccept: (files) => _handleDraggedFiles(files),
      onWillAccept: (data) => data != null,
      builder: (context, candidateData, rejectedData) {
        // 拖放时的视觉反馈
        final isDragging = candidateData.isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            border: isDragging ? Border.all(color: Colors.blue, width: 2) : null,
          ),
          child: Row(
            children: [
              // 1. 相机按钮（本地）
              if (Platform.isAndroid || Platform.isWindows)
                IconButton(
                  icon: Icon(Icons.camera_alt),
                  tooltip: 'Camera',
                  onPressed: _openCamera,
                ),

              // 2. 附件按钮（原有）
              IconButton(
                icon: Icon(Icons.attach_file),
                tooltip: 'Attach file',
                onPressed: _pickFile,
              ),

              // 3. 文本输入框
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: isDragging
                      ? 'Drop files here'
                      : 'Type a message...',
                  ),
                  onSubmitted: _sendMessage,
                ),
              ),

              // 4. 发送按钮
              IconButton(
                icon: Icon(Icons.send),
                onPressed: _canSend ? _sendMessage : null,
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleDraggedFiles(List<File> files) {
    // 处理拖放的文件
    for (final file in files) {
      _attachFile(file);
    }
  }

  void _openCamera() async {
    // 本地相机功能
    final image = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CameraPage()),
    );
    if (image != null) {
      _attachFile(image);
    }
  }
}
```

**测试验证：**
- [ ] Windows: 拖放文件正常
- [ ] Windows: 相机按钮正常
- [ ] Android: 拖放文件正常
- [ ] Android: 相机按钮正常
- [ ] macOS/Linux: 拖放文件正常
- [ ] 附件选择正常
- [ ] 文本输入正常
- [ ] 发送正常

---

### 5. 消息渲染

**上游实现：**
- Markdown WebView 预览（更完整的渲染）
- HTML 代码块预览
- 代码块滚动优化

**本地实现：**
- 表情包渲染（自定义标记 `[[sticker:id]]`）
- 文字选择功能（SelectableText）
- Token 显示（输入/输出）

**决策：** ✅ **合并**（全部功能集成）

**理由：**
- 用户明确要求"消息渲染也是合并"
- 所有渲染功能都有价值
- 可以通过优先级控制渲染逻辑

**实施方案：**

```dart
class ChatMessageWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 消息内容（渲染优先级）
        _buildMessageContent(message),

        // 消息底部（时间 + Token）
        _buildMessageFooter(message),
      ],
    );
  }

  Widget _buildMessageContent(ChatMessage message) {
    // 优先级 1：表情包（本地）
    if (message.content.contains('[[sticker:')) {
      return StickerRenderer(
        message: message,
        enableSelection: true,  // 支持长按查看原始内容
      );
    }

    // 优先级 2：Markdown/HTML（上游）
    if (message.hasMarkdown || message.hasHtml) {
      return MarkdownWebView(
        content: message.content,
        enableTextSelection: true,  // 本地：文字选择功能
        enableCodeBlockScroll: true,  // 上游：代码块滚动
      );
    }

    // 优先级 3：普通文本（保留选择功能）
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
          // 时间戳
          Text(
            formatTime(message.createdAt),
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),

          SizedBox(width: 8),

          // Token 显示（本地功能）
          if (message.role == 'assistant') ...[
            if (message.inputTokens != null)
              Chip(
                label: Text('In: ${message.inputTokens}'),
                avatar: Icon(Icons.input, size: 14),
                visualDensity: VisualDensity.compact,
              ),
            SizedBox(width: 4),
            if (message.outputTokens != null)
              Chip(
                label: Text('Out: ${message.outputTokens}'),
                avatar: Icon(Icons.output, size: 14),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ],
      ),
    );
  }
}
```

**测试验证：**
- [ ] 表情包正常显示
- [ ] 表情包支持长按查看原始内容
- [ ] Markdown 预览正常
- [ ] HTML 预览正常
- [ ] 代码块滚动正常
- [ ] 文字选择正常（普通文本）
- [ ] 文字选择正常（Markdown 内容）
- [ ] Token 显示正常（输入 + 输出）
- [ ] 时间戳显示正常

---

### 6. TTS 实现

**上游实现：**
- ElevenLabs TTS（高质量语音合成）
- 网络 TTS 服务支持
- flutter_tts 本地化（vendor 目录）

**本地实现：**
- Windows stub 实现（禁用 TTS）
- 避免 NUGET.EXE 依赖问题

**决策：** ⏸️ **不动**（暂时保持现状）

**理由：**
- 用户明确表示"tts我没有 暂时啥也别动"
- 避免引入复杂的依赖问题
- TTS 功能非核心，可以后续单独集成

**实施方案：**
```bash
# 完全不修改 TTS 相关代码
# 上游 TTS 代码记录备用

git show upstream/master:lib/core/providers/tts_provider.dart > gitmerge/upstream_tts_provider.dart

# 保持本地 stub 实现不变
```

```dart
// lib/core/providers/tts_provider.dart
// 保持现有的 stub 实现

// TODO: 后续评估集成上游的 ElevenLabs TTS
// 上游代码参考：gitmerge/upstream_tts_provider.dart
```

---

### 7. 设置页面

**上游实现：**
- 重构的桌面设置页
- 可能的布局优化

**本地实现：**
- 现有设置页面布局
- SSL 证书验证跳过选项
- 用户熟悉的结构

**决策：** ✅ **本地**（暂时保留现有实现）

**理由：**
- 用户明确要求"暂时保留我的"
- 本地的 SSL 跳过选项必须保留
- 设置页面稳定可用

**实施方案：**
```bash
# 完全保留本地 desktop_settings_page.dart
cp lib/desktop/desktop_settings_page.dart gitmerge/local_desktop_settings_page.dart
git show upstream/master:lib/desktop/desktop_settings_page.dart > gitmerge/upstream_desktop_settings_page.dart

# 保持本地文件不变
```

```dart
// lib/desktop/desktop_settings_page.dart
// 完全保留本地实现

// 确保 SSL 证书跳过选项存在
class DesktopSettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // ... 其他设置 ...

        // SSL 证书验证跳过（本地功能，必须保留）
        SwitchListTile(
          title: Text('Skip SSL certificate verification'),
          subtitle: Text('Use for self-signed certificates'),
          value: settings.skipSslVerification,
          onChanged: (value) {
            settings.setSkipSslVerification(value);
          },
        ),

        // TODO: 后续评估上游的设置页面优化
        // 上游代码参考：gitmerge/upstream_desktop_settings_page.dart
      ],
    );
  }
}
```

---

## 测试验证总清单

### 桌面端（Windows）

**模型选择器：**
- [ ] Dialog 居中显示（不挡住聊天内容）
- [ ] Tab 切换供应商正常
- [ ] 供应商头像正常显示
- [ ] 模型列表正常显示

**聊天输入栏：**
- [ ] 拖放文件正常
- [ ] 相机按钮正常
- [ ] 附件按钮正常
- [ ] 文本输入正常

**消息渲染：**
- [ ] 表情包显示正常
- [ ] Markdown 预览正常
- [ ] HTML 预览正常
- [ ] 代码块滚动正常
- [ ] 文字选择正常
- [ ] Token 显示正常（输入 + 输出）

**布局：**
- [ ] 桌面主页保持本地样式
- [ ] 设置页面保持本地样式
- [ ] SSL 跳过选项存在

### 移动端（Android）

**模型选择器：**
- [ ] 底部弹出
- [ ] 左右滑动切换供应商
- [ ] Tab 切换正常
- [ ] 供应商头像正常显示

**聊天输入栏：**
- [ ] 拖放文件正常（如果支持）
- [ ] 相机按钮正常
- [ ] 相机拍摄正常
- [ ] 附件按钮正常

**消息渲染：**
- [ ] 表情包显示正常
- [ ] Markdown 预览正常
- [ ] HTML 预览正常
- [ ] 文字选择正常
- [ ] Token 显示正常（tap/long-press 提示）

---

## 后续评估清单

以下上游功能暂时未集成，可以后续单独评估：

1. **桌面侧边栏 Tabs**
   - 上游代码：gitmerge/upstream_desktop_home_page.dart
   - 评估时机：稳定后，用户反馈需要时

2. **助手标签和分组**
   - 上游代码：gitmerge/upstream_assistant_provider.dart
   - 评估时机：用户理解上游功能后

3. **ElevenLabs TTS**
   - 上游代码：gitmerge/upstream_tts_provider.dart
   - 评估时机：解决 Windows 依赖问题后

4. **设置页面重构**
   - 上游代码：gitmerge/upstream_desktop_settings_page.dart
   - 评估时机：稳定后，发现明显优势时

---

## 变更日志

| 日期 | 变更内容 | 理由 |
|------|----------|------|
| 2025-11-08 | 初始决策 | 用户明确 UI 取舍要求 |

---

**决策确认：** ✅ 已与用户确认所有 UI 取舍决策
