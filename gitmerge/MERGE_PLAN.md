# 上游合并完整计划 - 100%功能保留版

**创建时间：** 2025-11-08
**目标：** 合并 Chevey339/kelivo upstream/master，保留本地所有功能 + 集成上游所有功能
**预计耗时：** 3-6周（根据投入时间）

---

## 一、合并概况

### 1.1 基本数据
- **分叉点：** `25b13c3 feat: add desktop settings page`
- **本地领先：** 139 commits (origin/master)
- **上游领先：** 223 commits (upstream/master)
- **文件变更：** 743 个文件修改（154,877 行新增，10,836 行删除）

### 1.2 UI 决策原则
详见 [UI_DECISIONS.md](./UI_DECISIONS.md)

- ✅ 桌面端布局 → **本地**
- 🔄 模型选择器 → **混合**（本地逻辑 + 上游对话框位置）
- ✅ 助手管理 → **本地**（暂时）
- ✅ 聊天输入栏 → **合并**（拖放 + 相机）
- ✅ 消息渲染 → **合并**（WebView + HTML + 表情包 + 选择）
- ⏸️ TTS → **不动**（暂时跳过）
- ✅ 设置页面 → **本地**

### 1.3 关键冲突区域
详见 [CONFLICT_CRITICAL.md](./CONFLICT_CRITICAL.md)

**高风险：**
- Token 显示逻辑（本地大量 UI 修改）
- Response API 工具调用（本地重写了流程）
- Hive 数据模型（双方可能添加字段）
- 聊天消息渲染（表情包 vs Markdown/HTML）

**中风险：**
- 依赖冲突（pubspec.yaml）
- 备份系统（头像路径处理）
- Provider 状态管理

---

## 二、执行阶段

### 阶段一：环境准备（30分钟）

#### 1.1 创建工作分支
```bash
cd c:\mycode\kelivo
git checkout -b merge/upstream-full-features
git tag backup-pre-merge-$(date +%Y%m%d)
```

#### 1.2 确认远程仓库
```bash
git remote -v
# origin: https://github.com/KianaMei/kelivo.git
# upstream: https://github.com/Chevey339/kelivo.git

git fetch origin
git fetch upstream
```

#### 1.3 创建文档目录
已创建 gitmerge/ 目录及以下文档：
- ✅ MERGE_PLAN.md (本文档)
- ✅ UI_DECISIONS.md
- ✅ CONFLICT_CRITICAL.md
- ✅ UPSTREAM_ANALYSIS.md
- ✅ LOCAL_FEATURES.md

---

### 阶段二：数据模型层统一（关键！2-3天）

#### 2.1 Hive 模型对比

**目标文件：**
- `lib/core/models/chat_message.dart`
- `lib/core/models/conversation.dart`

**执行步骤：**

1. **导出双方字段定义**
   ```bash
   # 本地版本
   git show HEAD:lib/core/models/chat_message.dart > gitmerge/local_chat_message.dart

   # 上游版本
   git show upstream/master:lib/core/models/chat_message.dart > gitmerge/upstream_chat_message.dart

   # 对比
   code --diff gitmerge/local_chat_message.dart gitmerge/upstream_chat_message.dart
   ```

2. **识别字段差异**
   - 本地可能新增：`sticker` 字段、`inputTokens`/`outputTokens` 字段
   - 上游可能新增：`tools`、`citations`、`metadata` 字段

3. **合并策略**
   ```dart
   @HiveType(typeId: 1)  // 保持 typeId 不变
   class ChatMessage {
     // 原有字段
     @HiveField(0) final String id;
     @HiveField(1) final String conversationId;
     @HiveField(2) final String role;
     @HiveField(3) final String content;

     // 本地新增字段（nullable）
     @HiveField(10) final String? sticker;
     @HiveField(11) final int? inputTokens;
     @HiveField(12) final int? outputTokens;

     // 上游新增字段（nullable）
     @HiveField(20) final List<Tool>? tools;
     @HiveField(21) final List<Citation>? citations;
     @HiveField(22) final Map<String, dynamic>? metadata;

     // 添加版本号用于迁移检测
     @HiveField(99) final int? schemaVersion;  // 当前版本：2
   }
   ```

4. **typeId 检查**
   ```bash
   # 搜索所有 @HiveType 确保无冲突
   grep -r "@HiveType" lib/core/models/
   ```

#### 2.2 数据迁移测试

**创建测试脚本：**
```dart
// test/hive_migration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('Hive Migration Tests', () {
    test('旧版消息能被新模型解析', () async {
      // 1. 创建旧版消息
      final oldMessage = ChatMessage(
        id: 'test',
        content: '测试消息',
        // 不包含新字段
      );

      // 2. 序列化
      final box = await Hive.openBox('test');
      await box.put('msg', oldMessage);

      // 3. 读取并验证
      final retrieved = box.get('msg') as ChatMessage;
      expect(retrieved.id, 'test');
      expect(retrieved.sticker, isNull);  // 新字段应为 null
      expect(retrieved.tools, isNull);
    });

    test('包含表情包的消息正常存储', () {
      // 测试本地新字段
    });

    test('包含工具调用的消息正常存储', () {
      // 测试上游新字段
    });
  });
}
```

**执行测试：**
```bash
flutter test test/hive_migration_test.dart
```

#### 2.3 重新生成适配器
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

#### 2.4 验证现有数据
```bash
# 备份现有数据库
cp -r ~/.local/share/kelivo/hive_boxes gitmerge/backup_hive_$(date +%Y%m%d)

# 或 Windows:
cp -r $env:APPDATA\kelivo\hive_boxes gitmerge\backup_hive_$(Get-Date -Format yyyyMMdd)
```

**检查点：**
- [ ] 所有字段都添加了 @HiveField 注解
- [ ] typeId 无冲突
- [ ] .g.dart 文件成功生成
- [ ] 测试通过
- [ ] 现有数据已备份

---

### 阶段三：依赖统一（1天）

#### 3.1 合并 pubspec.yaml

**执行步骤：**

1. **查看双方差异**
   ```bash
   git diff upstream/master HEAD -- pubspec.yaml
   ```

2. **手动合并依赖**

   **保留双方依赖：**
   ```yaml
   dependencies:
     # 上游新增
     super_clipboard: ^0.8.0  # 剪贴板增强
     camera: ^0.10.5  # 相机（上游版本）
     pdfx: ^2.5.0  # Syncfusion PDF
     webview_flutter: ^4.4.2  # WebView 支持

     # 本地新增
     camera_windows: ^0.2.1  # Windows 相机
     file_picker: ^6.1.1  # 文件选择器（替代 image_picker）

     # 冲突解决
     # 如果 camera 版本冲突，选择更高版本
     # 保留 camera_windows（平台特定）
   ```

3. **特殊处理的依赖**
   ```yaml
   # TTS - 暂时不动（根据用户要求）
   flutter_tts: ^3.8.3  # 保持现状

   # MCP
   # 如果上游升级了 mcp_client，跟随上游版本

   # HTTP
   # 确保 http/dio 版本与双方兼容
   ```

#### 3.2 解决版本冲突
```bash
flutter pub get

# 如果有冲突：
flutter pub upgrade --major-versions
# 手动选择兼容版本
```

#### 3.3 验证编译
```bash
flutter pub outdated  # 检查依赖健康度
flutter analyze  # 静态分析
```

**检查点：**
- [ ] 所有依赖成功解析
- [ ] 无版本冲突警告
- [ ] flutter analyze 无错误
- [ ] Android 编译通过（flutter build apk --debug）
- [ ] Windows 编译通过（flutter build windows --debug）

---

### 阶段四：核心架构层合并（高风险！3-5天）

详见 [CONFLICT_CRITICAL.md](./CONFLICT_CRITICAL.md) 的详细策略。

#### 4.1 API 服务层
**文件：** `lib/core/services/api/chat_api_service.dart`

**策略：** 采用上游 Response API 架构 + 移植本地功能

**合并步骤：**

1. **保存本地版本**
   ```bash
   cp lib/core/services/api/chat_api_service.dart gitmerge/local_chat_api_service.dart
   ```

2. **Cherry-pick 上游 Response API 架构**
   ```bash
   # 找到上游重构 Response API 的提交
   git log upstream/master --oneline --grep="Response API"

   # Cherry-pick（可能需要解决冲突）
   git cherry-pick <commit-sha>
   ```

3. **移植本地功能**

   **本地特有功能需要保留：**
   - ✅ MaxTokens 配置
   - ✅ 工具调用循环限制
   - ✅ Token 统计（输入/输出）
   - ✅ HTTP 日志记录
   - ✅ SSL 证书跳过选项

   **集成位置：**
   ```dart
   class ChatApiService {
     // 上游的 Response API 基础架构
     Future<Stream<ChatResponse>> sendMessage(...) async {
       // 1. 构建请求（集成本地的 MaxTokens）
       final request = buildRequest(
         messages: messages,
         maxTokens: settings.maxTokens,  // 本地功能
       );

       // 2. 发送请求（集成本地的 SSL 选项）
       final response = await _httpClient.post(
         url,
         ...
         // 本地的 SSL 跳过逻辑
       );

       // 3. 处理流式响应（集成本地的 Token 统计）
       return response.stream.transform(
         _tokenTrackingTransformer,  // 本地功能
       ).transform(
         _toolCallLimitTransformer,  // 本地功能
       );
     }
   }
   ```

4. **测试验证**
   ```dart
   // test/chat_api_service_test.dart
   test('MaxTokens 配置生效', () {
     // 验证请求包含 maxTokens 参数
   });

   test('Token 统计准确', () {
     // 验证输入/输出 token 计算
   });

   test('工具调用循环限制', () {
     // 验证超过限制后停止
   });
   ```

#### 4.2 聊天服务层
**文件：** `lib/core/services/chat/chat_service.dart`

**冲突点：**
- 上游：可能调整了数据库操作逻辑、消息存储流程
- 本地：Token 追踪、表情包消息处理、工具调用记录

**策略：**

1. **对比差异**
   ```bash
   git diff upstream/master HEAD -- lib/core/services/chat/chat_service.dart
   ```

2. **合并逻辑**
   ```dart
   class ChatService {
     // 保存消息（合并双方逻辑）
     Future<void> saveMessage(ChatMessage message) async {
       // 上游：基础存储逻辑
       await _saveToHive(message);

       // 本地：Token 统计
       if (message.inputTokens != null || message.outputTokens != null) {
         await _updateTokenStats(message);
       }

       // 本地：表情包处理
       if (message.sticker != null) {
         await _cacheStickerResource(message.sticker!);
       }

       // 上游：工具调用存储
       if (message.tools != null) {
         await _saveToolCalls(message.tools!);
       }
     }
   }
   ```

#### 4.3 Provider 层
**文件：**
- `lib/core/providers/assistant_provider.dart`
- `lib/core/providers/model_provider.dart`

**策略：** 保留本地实现，暂不集成上游标签分组

```dart
// assistant_provider.dart
class AssistantProvider extends ChangeNotifier {
  // 完全保留本地实现：
  // - 头像同步
  // - 助手计数显示
  // - Delete 按钮集成

  // 上游的标签分组功能暂时注释掉，留待后续集成
  // TODO: 集成上游的标签分组功能
  // void addTag(String assistantId, String tag) { ... }
}
```

**检查点：**
- [ ] chat_api_service.dart 编译通过
- [ ] MaxTokens 功能正常
- [ ] Token 统计正常
- [ ] 工具调用限制正常
- [ ] chat_service.dart 编译通过
- [ ] 消息存储正常（包含表情包和工具调用）
- [ ] Provider 层无破坏性变更

---

### 阶段五：UI 组件合并（按决策！5-7天）

#### 5.1 模型选择器改造（混合方案）

**目标：** 本地选择器逻辑 + 上游对话框位置

**实现步骤：**

1. **抽离核心逻辑**
   ```dart
   // lib/features/model/widgets/model_selector_core.dart
   class ModelSelectorCore extends StatelessWidget {
     // 本地的 Tab 化供应商切换逻辑
     // 移动端左右滑动
     // 供应商头像显示
   }
   ```

2. **创建平台包装器**
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
           builder: (context) => ModelSelectorCore(),
         );
       }
     }
   }
   ```

3. **测试验证**
   - [ ] Windows: Dialog 居中显示
   - [ ] Android: 底部弹出
   - [ ] Tab 切换正常
   - [ ] 左右滑动正常（移动端）
   - [ ] 供应商头像正常显示

#### 5.2 聊天输入栏（合并拖放 + 相机）

**文件：** `lib/features/home/widgets/chat_input_bar.dart`

**实现：**

1. **查看上游拖放实现**
   ```bash
   git show upstream/master:lib/features/home/widgets/chat_input_bar.dart > gitmerge/upstream_chat_input_bar.dart
   ```

2. **合并代码**
   ```dart
   class ChatInputBar extends StatelessWidget {
     @override
     Widget build(BuildContext context) {
       return DragTarget<List<File>>(  // 上游的拖放
         onAccept: (files) {
           _handleDraggedFiles(files);
         },
         builder: (context, candidateData, rejectedData) {
           return Row(
             children: [
               // 1. 相机按钮（本地）
               if (Platform.isAndroid || Platform.isWindows)
                 IconButton(
                   icon: Icon(Icons.camera_alt),
                   onPressed: _openCamera,
                 ),

               // 2. 附件按钮（原有）
               IconButton(
                 icon: Icon(Icons.attach_file),
                 onPressed: _pickFile,
               ),

               // 3. 文本输入框
               Expanded(child: TextField(...)),

               // 4. 发送按钮
               IconButton(
                 icon: Icon(Icons.send),
                 onPressed: _sendMessage,
               ),
             ],
           );
         },
       );
     }
   }
   ```

3. **测试验证**
   - [ ] 拖放文件正常
   - [ ] 相机拍摄正常
   - [ ] 附件选择正常
   - [ ] 文本输入正常

#### 5.3 消息渲染（全功能集成）

**文件：** `lib/features/chat/widgets/chat_message_widget.dart`

**实现：**

1. **渲染优先级**
   ```dart
   Widget _buildMessageContent(ChatMessage message) {
     // 优先级 1：表情包（本地）
     if (message.content.contains('[[sticker:')) {
       return StickerRenderer(
         message: message,
         enableSelection: true,  // 本地的文字选择
       );
     }

     // 优先级 2：Markdown/HTML（上游）
     if (message.hasMarkdown || message.hasHtml) {
       return MarkdownWebView(
         content: message.content,
         enableTextSelection: true,  // 本地功能
       );
     }

     // 优先级 3：普通文本（保留选择）
     return SelectableText(
       message.content,
       // 本地的文字选择功能
     );
   }
   ```

2. **Token 显示集成（本地功能）**
   ```dart
   Widget _buildMessageFooter(ChatMessage message) {
     return Row(
       children: [
         // 时间戳
         Text(formatTime(message.createdAt)),

         // Token 显示（本地）
         if (message.role == 'assistant')
           Row(
             children: [
               if (message.inputTokens != null)
                 Chip(
                   label: Text('In: ${message.inputTokens}'),
                   avatar: Icon(Icons.input, size: 16),
                 ),
               if (message.outputTokens != null)
                 Chip(
                   label: Text('Out: ${message.outputTokens}'),
                   avatar: Icon(Icons.output, size: 16),
                 ),
             ],
           ),
       ],
     );
   }
   ```

3. **测试验证**
   - [ ] 表情包正常显示
   - [ ] Markdown 预览正常
   - [ ] HTML 预览正常
   - [ ] 文字选择正常
   - [ ] Token 显示正常

#### 5.4 桌面端布局（保留本地）

**文件：** `lib/desktop/desktop_home_page.dart`

**策略：** 完全保留本地实现

```bash
# 记录上游侧边栏 Tabs 代码备用
git show upstream/master:lib/desktop/desktop_home_page.dart > gitmerge/upstream_desktop_home_page.dart

# 保持本地文件不变
```

#### 5.5 设置页面（保留本地）

**文件：** `lib/desktop/desktop_settings_page.dart`

**策略：** 保留本地的 SSL 证书跳过选项和布局

```dart
// 完全保留本地实现
// 上游的重构代码记录到 gitmerge/ 备用
```

**检查点：**
- [ ] 模型选择器：Windows Dialog / Android 底部弹出
- [ ] 聊天输入栏：拖放 + 相机 + 附件
- [ ] 消息渲染：表情包 + Markdown + HTML + 选择
- [ ] Token 显示：输入/输出 token 正常显示
- [ ] 桌面布局：保持本地不变
- [ ] 设置页面：SSL 选项存在

---

### 阶段六：功能层合并（逐个集成！5-7天）

#### 6.1 上游独立功能（直接移植）

##### 6.1.1 SOCKS5 代理
```bash
# Cherry-pick 上游代理功能
git log upstream/master --oneline --grep="proxy" --grep="SOCKS5"
git cherry-pick <commit-sha>

# 手动解决冲突（如果有）
```

**集成点：**
- 添加到设置页面
- 集成到 HTTP 客户端配置

##### 6.1.2 内置 MCP fetch 工具
```bash
git log upstream/master --oneline --grep="MCP" --grep="fetch"
git cherry-pick <commit-sha>
```

**集成点：**
- 添加到 McpProvider
- 在 MCP 服务器列表显示

##### 6.1.3 Markdown WebView 预览
```bash
git log upstream/master --oneline --grep="Markdown" --grep="WebView"
git cherry-pick <commit-sha>
```

**集成点：**
- 已在阶段五集成到消息渲染

##### 6.1.4 HTML 代码块预览
```bash
git log upstream/master --oneline --grep="HTML" --grep="preview"
git cherry-pick <commit-sha>
```

##### 6.1.5 super_clipboard 支持
```bash
git log upstream/master --oneline --grep="clipboard"
git cherry-pick <commit-sha>
```

**集成点：**
- 图片复制粘贴功能
- 添加到聊天输入栏

##### 6.1.6 Android 后台对话
```bash
git log upstream/master --oneline --grep="background" --grep="notification"
git cherry-pick <commit-sha>
```

**集成点：**
- Android 后台服务
- 通知国际化

#### 6.2 本地独有功能（确保保留）

##### 6.2.1 表情包工具
**文件：** `lib/features/sticker/`

**检查：**
- [ ] 文件完整存在
- [ ] 渲染逻辑正常
- [ ] 与上游消息渲染兼容

##### 6.2.2 Token 多轮追踪
**文件：** `lib/features/token_stats/`

**检查：**
- [ ] 统计卡片 UI 正常
- [ ] 与上游 Response API 集成
- [ ] hover 提示正常
- [ ] 移动端 tap/long-press 正常

##### 6.2.3 供应商头像同步
**文件：** `lib/utils/provider_avatar_manager.dart`

**检查：**
- [ ] 头像上传正常
- [ ] 跨平台同步正常
- [ ] 备份恢复包含头像

##### 6.2.4 相机拍摄页面
**文件：** `lib/features/camera/`

**检查：**
- [ ] Android 后摄正常
- [ ] Windows 摄像头正常
- [ ] 权限处理正常

##### 6.2.5 SSL 证书跳过
**文件：** `lib/core/services/network/ssl_helper.dart`

**检查：**
- [ ] 设置选项存在
- [ ] 集成到 HTTP 客户端
- [ ] 自签名证书可用

**检查点：**
- [ ] 所有上游功能成功集成
- [ ] 所有本地功能正常运行
- [ ] 无功能缺失
- [ ] 无破坏性变更

---

### 阶段七：备份系统整合（2-3天）

#### 7.1 头像路径统一

**文件：** `lib/core/services/backup/data_sync.dart`

**策略：** 采用本地的 `avatars/providers/` 方案（已测试跨平台）

```dart
class DataSync {
  // 供应商头像路径
  static const String providerAvatarsPath = 'avatars/providers';

  // 助手头像路径
  static const String assistantAvatarsPath = 'avatars/assistants';

  // 备份时包含头像
  Future<void> backup() async {
    // ...
    await _backupAvatars();  // 本地逻辑
    // ...
  }

  // 恢复时同步头像
  Future<void> restore() async {
    // ...
    await _restoreAvatars();  // 本地逻辑
    // ...
  }
}
```

#### 7.2 WebDAV 同步增强

**合并上游改进（如果有）：**
- 错误处理优化
- 进度提示
- 增量备份

**检查点：**
- [ ] 备份包含所有头像
- [ ] 恢复正常同步头像
- [ ] 跨平台测试（Windows → Android）
- [ ] 路径分隔符正确

---

### 阶段八：构建系统合并（1-2天）

#### 8.1 GitHub Actions 工作流

**文件：** `.github/workflows/`

**策略：** 保留本地 Android/Windows 构建，添加上游 Linux/macOS（可选）

```yaml
# .github/workflows/build.yml
name: Build Multi-platform

on:
  push:
    branches: [master]
  pull_request:

jobs:
  build-android:
    # 保留本地配置

  build-windows:
    # 保留本地配置

  build-linux:
    # 添加上游配置（可选）

  build-macos:
    # 添加上游配置（可选）
```

#### 8.2 构建脚本

**文件：** `scripts/`

**策略：**
- 保留本地的 `build_windows.ps1`
- 添加上游的 Inno Setup 脚本（Windows 安装程序）
- 添加上游的 Linux 打包脚本（AppImage/DEB/RPM）

**检查点：**
- [ ] Android 构建正常
- [ ] Windows 构建正常
- [ ] Inno Setup 安装程序生成（可选）
- [ ] GitHub Actions 运行正常

---

### 阶段九：测试验证（3-5天）

#### 9.1 数据完整性测试

**测试场景：**

1. **加载现有对话**
   ```dart
   test('现有对话正常加载', () async {
     // 使用备份的数据库
     // 验证所有对话能被加载
     // 特别关注包含表情包的消息
   });
   ```

2. **发送新消息**
   ```dart
   test('新消息正常发送', () async {
     // 测试上游 Response API
     // 验证 Token 统计
     // 验证工具调用
   });
   ```

3. **工具调用测试**
   - MCP 工具
   - 搜索工具
   - 表情包工具
   - 内置 fetch 工具（上游）

4. **Token 统计测试**
   - 输入 token 准确
   - 输出 token 准确
   - 多轮对话累计
   - UI 显示正确

5. **备份恢复测试**
   ```bash
   # Windows → Android
   # 1. Windows 备份
   # 2. 上传 WebDAV
   # 3. Android 恢复
   # 4. 验证：对话、头像、设置
   ```

#### 9.2 UI 功能测试

**桌面端（Windows）：**
- [ ] 模型选择器：Dialog 居中显示
- [ ] 聊天输入栏：拖放文件上传
- [ ] 聊天输入栏：相机按钮正常
- [ ] 消息渲染：表情包显示
- [ ] 消息渲染：Markdown 预览
- [ ] 消息渲染：HTML 预览
- [ ] 消息渲染：文字选择
- [ ] Token 显示：输入/输出 token
- [ ] Token 统计卡片：hover 提示
- [ ] 鼠标侧键返回：正常工作
- [ ] 桌面布局：保持本地样式

**移动端（Android）：**
- [ ] 模型选择器：底部弹出
- [ ] 模型选择器：左右滑动切换供应商
- [ ] 聊天输入栏：相机拍摄
- [ ] 聊天输入栏：附件选择
- [ ] 消息渲染：表情包显示
- [ ] 消息渲染：Markdown/HTML 预览
- [ ] Token 显示：tap/long-press 提示
- [ ] 供应商头像：正常显示
- [ ] 助手管理：计数显示
- [ ] 助手管理：删除按钮

#### 9.3 功能兼容性测试

**上游新功能：**
- [ ] SOCKS5 代理：配置并连接
- [ ] 内置 MCP fetch 工具：调用成功
- [ ] Markdown WebView 预览：渲染正常
- [ ] HTML 代码块预览：显示正常
- [ ] super_clipboard：图片复制粘贴
- [ ] Android 后台对话：通知正常

**本地新功能：**
- [ ] 表情包工具：发送和显示
- [ ] Token 多轮追踪：统计准确
- [ ] 供应商头像同步：跨平台正常
- [ ] SSL 证书跳过：自签名证书可用
- [ ] 相机拍摄：Android + Windows
- [ ] 鼠标侧键返回：Windows
- [ ] FilePicker：文件选择正常

#### 9.4 构建测试

```bash
# Android Release
flutter build apk --release
# 验证：
# - APK 大小合理（< 50MB）
# - 安装正常
# - 运行无崩溃
# - 所有功能正常

# Windows Release
flutter build windows --release
# 验证：
# - 构建成功
# - 运行正常
# - TTS stub 正常
# - 相机功能正常

# Web（如果保留）
flutter build web --release
```

#### 9.5 回归测试清单

- [ ] 现有对话能否正常加载（包含表情包）
- [ ] 发送消息是否正常（测试 Response API）
- [ ] 工具调用是否正常（MCP + 搜索 + 表情包）
- [ ] Token 统计是否准确（输入 + 输出）
- [ ] 备份恢复是否正常（包含头像）
- [ ] 跨平台同步是否正常（Windows ↔ Android）
- [ ] 助手管理是否正常（计数 + 删除）
- [ ] 供应商管理是否正常（头像 + 拖拽）
- [ ] 模型选择器是否正常（Desktop Dialog / Mobile BottomSheet）
- [ ] 消息渲染是否正常（表情包 + Markdown + HTML + 选择）
- [ ] SSL 证书跳过是否正常
- [ ] 相机拍摄是否正常
- [ ] 鼠标侧键返回是否正常（Windows）

**所有测试必须通过才能进入下一阶段！**

---

### 阶段十：文档更新（1天）

#### 10.1 更新项目文档

**CLAUDE.md**
```markdown
## 合并说明

本项目已合并上游 Chevey339/kelivo 的所有功能，同时保留本地所有特色功能。

### 上游集成功能
- SOCKS5 代理支持
- 内置 MCP fetch 工具
- Markdown WebView 预览
- HTML 代码块预览
- super_clipboard 支持
- Android 后台对话生成

### 本地特色功能
- 表情包工具（nachoneko）
- Token 多轮追踪与统计
- 供应商自定义头像（跨平台同步）
- 模型选择器 Tab 化（移动端左右滑动）
- SSL 证书验证跳过
- 相机拍摄页面（Android + Windows）
- 鼠标侧键返回（Windows）
```

**README.md**
```markdown
## Features

### Chat & Messaging
- 多供应商支持（OpenAI、Gemini、Anthropic 等）
- 表情包工具（本地特色）
- Markdown/HTML 预览（上游集成）
- 文字选择功能（本地特色）
- Token 统计面板（本地特色）

### Desktop Features
- 自定义模型选择器（Dialog 样式）
- 鼠标侧键返回（本地特色）
- 拖放文件上传（上游集成）

### Mobile Features
- 模型选择器左右滑动（本地特色）
- 相机拍摄功能（本地特色）

### Network & Sync
- SOCKS5 代理支持（上游集成）
- SSL 证书跳过（本地特色）
- 供应商头像跨平台同步（本地特色）
```

#### 10.2 创建迁移指南

**gitmerge/MIGRATION_GUIDE.md**
```markdown
# 用户迁移指南

## 从旧版本升级

### 数据兼容性
- ✅ 所有现有对话自动迁移
- ✅ 表情包消息正常显示
- ✅ Token 统计数据保留
- ✅ 供应商头像自动同步

### 新功能启用
1. SOCKS5 代理：设置 → 网络 → 代理配置
2. 内置 MCP 工具：MCP 服务器列表自动显示
3. Markdown 预览：自动启用（发送包含 Markdown 的消息）

### 已知问题
- 暂无

### 回滚方案
如果遇到问题，可以回退到备份标签：
\`\`\`bash
git checkout backup-pre-merge-YYYYMMDD
\`\`\`
```

---

### 阶段十一：发布（1天）

#### 11.1 最终检查

```bash
# 1. 工作区状态
git status
# 应该只显示合并后的修改，无未跟踪文件

# 2. 提交历史
git log --oneline --graph -30
# 检查提交信息清晰

# 3. 差异统计
git diff upstream/master --stat
# 确认所有修改都是预期的

# 4. 代码质量
flutter analyze
# 应该无错误

# 5. 测试覆盖
flutter test
# 所有测试通过
```

#### 11.2 整理提交历史（可选）

```bash
# 如果提交过于琐碎，可以压缩
git rebase -i HEAD~50

# 合并相关的 fix 提交
# 保持主要功能提交独立
```

#### 11.3 推送到远程

```bash
# 推送合并分支
git push origin merge/upstream-full-features

# 创建 Draft PR 自我审查
gh pr create \
  --draft \
  --title "Merge upstream - 100% features preserved" \
  --body "$(cat gitmerge/MERGE_PLAN.md)"
```

#### 11.4 代码审查（自我审查）

在 GitHub PR 页面逐文件检查：
- [ ] 数据模型修改正确
- [ ] API 服务层集成完整
- [ ] UI 组件按决策实现
- [ ] 本地功能全部保留
- [ ] 上游功能全部集成
- [ ] 无意外删除的代码
- [ ] 无遗留的 TODO/FIXME

#### 11.5 合并到 master

```bash
# 确认 PR 自我审查通过
gh pr ready  # 标记为 Ready for review

# 合并（--no-ff 保留分支历史）
git checkout master
git merge --no-ff merge/upstream-full-features

# 推送
git push origin master
```

#### 11.6 打标签发布

```bash
# 打版本标签
git tag -a v1.2.0-full-merge -m "Merge upstream - All features preserved"
git push origin v1.2.0-full-merge

# 发布到 GitHub Releases
gh release create v1.2.0-full-merge \
  --title "v1.2.0 - Upstream Full Merge" \
  --notes "$(cat << 'EOF'
# v1.2.0 - 上游完整合并

## 📦 合并说明
成功合并上游 Chevey339/kelivo 的所有功能（223 commits），同时保留本地所有特色功能（139 commits）。

## ✨ 新增功能（上游）
- SOCKS5 代理支持
- 内置 MCP fetch 工具
- Markdown WebView 预览
- HTML 代码块预览
- super_clipboard 图片复制粘贴
- Android 后台对话生成

## 🎨 保留功能（本地特色）
- 表情包工具系统
- Token 多轮追踪与统计面板
- 供应商自定义头像（跨平台同步）
- 模型选择器 Tab 化（移动端左右滑动）
- SSL 证书验证跳过
- 相机拍摄页面（Android + Windows）
- 鼠标侧键返回（Windows）

## 📊 统计
- 合并提交：362 commits
- 文件变更：743 files
- 代码行数：+154,877 / -10,836

## ⚠️ 重要提示
- 首次运行会自动迁移数据
- 所有现有对话和设置都会保留
- 如有问题，可回退到 backup-pre-merge-* 标签

## 📝 详细文档
- [合并计划](https://github.com/KianaMei/kelivo/blob/master/gitmerge/MERGE_PLAN.md)
- [迁移指南](https://github.com/KianaMei/kelivo/blob/master/gitmerge/MIGRATION_GUIDE.md)
EOF
)"
```

#### 11.7 构建发布包

```bash
# Android APK
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk kelivo-v1.2.0-android.apk

# Windows Portable
flutter build windows --release
# 打包成 ZIP
Compress-Archive -Path build/windows/runner/Release/* -DestinationPath kelivo-v1.2.0-windows-portable.zip

# 上传到 Release
gh release upload v1.2.0-full-merge \
  kelivo-v1.2.0-android.apk \
  kelivo-v1.2.0-windows-portable.zip
```

#### 11.8 监控用户反馈

发布后监控：
- GitHub Issues（新问题）
- GitHub Discussions（用户反馈）
- Discord 频道（实时反馈）

准备快速修复（hotfix）分支应对紧急问题。

---

## 三、关键风险控制

### 风险点 1：Hive 数据模型不兼容
**影响：** 用户数据可能无法读取，应用崩溃

**缓解措施：**
1. 阶段二必须100%完成并测试
2. 编写完整的迁移测试脚本
3. 提供回滚方案（备份标签 + 数据库备份）
4. 添加版本检测逻辑，旧数据自动升级

**回滚计划：**
```bash
# 如果数据模型有问题
git checkout backup-pre-merge-YYYYMMDD
# 恢复用户数据库
cp gitmerge/backup_hive_YYYYMMDD/* ~/.local/share/kelivo/hive_boxes/
```

### 风险点 2：API 架构冲突
**影响：** 对话生成失败，工具调用异常

**缓解措施：**
1. 优先采用上游 Response API 架构（更规范）
2. 逐步移植本地功能（MaxTokens、循环限制、Token 统计）
3. 每个功能独立测试
4. 保留本地原始代码备份（gitmerge/local_*.dart）

**回滚计划：**
```bash
# 如果 API 层有问题
cp gitmerge/local_chat_api_service.dart lib/core/services/api/chat_api_service.dart
flutter pub run build_runner build
```

### 风险点 3：依赖冲突
**影响：** 编译失败，运行时崩溃

**缓解措施：**
1. 优先选择更高版本的依赖
2. 测试所有平台编译（Android + Windows + Web）
3. 准备降级方案（记录可用的版本组合）
4. 使用 `flutter pub outdated` 检查依赖健康度

**回滚计划：**
```bash
# 如果依赖有问题
git checkout HEAD~1 -- pubspec.yaml pubspec.lock
flutter pub get
```

### 风险点 4：UI 渲染冲突
**影响：** 消息显示异常，表情包或 Markdown 渲染失败

**缓解措施：**
1. 使用类型检测分流渲染逻辑
2. 优先级明确：表情包 > Markdown > 普通文本
3. 渐进式集成，每个渲染器独立测试
4. 保留降级渲染（如果新渲染器失败，回退到纯文本）

**回滚计划：**
```bash
# 如果渲染有问题
cp gitmerge/local_chat_message_widget.dart lib/features/chat/widgets/chat_message_widget.dart
```

---

## 四、预计时间表

### 快速通道（有经验，全职投入）

| 阶段 | 耗时 | 累计 |
|------|------|------|
| 阶段一：环境准备 | 0.5天 | 0.5天 |
| 阶段二：数据模型统一 | 2天 | 2.5天 |
| 阶段三：依赖统一 | 1天 | 3.5天 |
| 阶段四：核心架构合并 | 3天 | 6.5天 |
| 阶段五：UI 组件合并 | 5天 | 11.5天 |
| 阶段六：功能层合并 | 5天 | 16.5天 |
| 阶段七：备份系统整合 | 2天 | 18.5天 |
| 阶段八：构建系统合并 | 1天 | 19.5天 |
| 阶段九：测试验证 | 3天 | 22.5天 |
| 阶段十：文档更新 | 1天 | 23.5天 |
| 阶段十一：发布 | 1天 | 24.5天 |

**总计：约 3-4 周（全职）**

### 稳健通道（兼职，充分测试）

| 阶段 | 耗时 | 累计 |
|------|------|------|
| 阶段一：环境准备 | 1天 | 1天 |
| 阶段二：数据模型统一 | 3天 | 4天 |
| 阶段三：依赖统一 | 1天 | 5天 |
| 阶段四：核心架构合并 | 5天 | 10天 |
| 阶段五：UI 组件合并 | 7天 | 17天 |
| 阶段六：功能层合并 | 7天 | 24天 |
| 阶段七：备份系统整合 | 3天 | 27天 |
| 阶段八：构建系统合并 | 2天 | 29天 |
| 阶段九：测试验证 | 5天 | 34天 |
| 阶段十：文档更新 | 1天 | 35天 |
| 阶段十一：发布 | 1天 | 36天 |

**总计：约 5-6 周（兼职）**

---

## 五、成功标准

合并完成的标准（所有项必须满足）：

### 功能完整性
- [x] 所有本地功能正常运行
- [x] 所有上游功能正常运行
- [x] 无功能缺失或降级

### 数据完整性
- [x] 现有用户数据无损迁移
- [x] 表情包消息正常显示
- [x] Token 统计数据保留
- [x] 工具调用历史保留

### 跨平台兼容性
- [x] 备份恢复跨平台兼容（Windows ↔ Android）
- [x] 供应商头像同步正常
- [x] 助手头像同步正常

### 构建成功
- [x] Android Release 构建成功
- [x] Windows Release 构建成功
- [x] Web 构建成功（如果保留）

### 测试通过
- [x] 单元测试全部通过
- [x] 集成测试全部通过
- [x] UI 功能测试全部通过
- [x] 回归测试全部通过

### 文档完整
- [x] CLAUDE.md 更新
- [x] README.md 更新
- [x] MIGRATION_GUIDE.md 完成
- [x] CHANGELOG.md 更新

### 发布就绪
- [x] 版本标签打好
- [x] GitHub Release 创建
- [x] 发布包上传
- [x] 用户反馈渠道准备好

---

## 六、下一步行动

现在立即开始：

### 立即执行（今天）
1. ✅ 创建工作分支 `merge/upstream-full-features`
2. ✅ 打备份标签
3. ✅ 阅读所有 gitmerge/ 文档
4. ⏳ 开始阶段二：数据模型对比

### 本周完成
- [ ] 阶段二：数据模型统一（2-3天）
- [ ] 阶段三：依赖统一（1天）
- [ ] 开始阶段四：API 服务层

### 下周目标
- [ ] 完成阶段四：核心架构合并
- [ ] 开始阶段五：UI 组件合并

### 月度目标
- [ ] 完成所有功能合并
- [ ] 通过所有测试
- [ ] 准备发布

---

## 七、支持与反馈

### 问题追踪
- 所有合并过程中的问题记录到：`gitmerge/merge_issues.md`
- 冲突解决日志：`gitmerge/conflict_resolution.md`

### 定期检查点
每周五回顾：
- 本周完成的阶段
- 遇到的问题和解决方案
- 下周计划

### 紧急停止条件
如果出现以下情况，立即停止并回滚：
- 用户数据损坏无法恢复
- 核心功能完全失效
- 编译错误无法解决超过 2 天

---

**准备好了吗？让我们开始这个大工程吧！** 🚀
