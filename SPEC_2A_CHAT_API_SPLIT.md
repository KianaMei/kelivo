# Phase 2A: ChatApiService 拆分规格

## 目标

将 `chat_api_service.dart` (4373行) 拆分为模块化的 Provider Adapter 架构。

---

## 当前文件结构

```
lib/core/services/api/
├── chat_api_service.dart      (4373行 - 待拆分)
├── chat_stream_pipeline.dart  (332行)
├── adapters/
│   └── chat_provider_adapter.dart (32行 - 接口已定义)
└── models/
    └── chat_stream_event.dart (245行)
```

---

## 流式方法分析

| 方法 | 行范围 | 行数 | Provider |
|------|--------|------|----------|
| `_sendOpenAIStream` | 1004-3480 | ~2476 | OpenAI/兼容API |
| `_sendClaudeStream` | 3483-3820 | ~337 | Anthropic Claude |
| `_sendGoogleStream` | 3822-4373 | ~551 | Google Gemini/Vertex |
| `_sendPromptToolUseStream` | 812-1001 | ~190 | 模拟工具调用 |

---

## 共享依赖项

### 配置辅助方法 (需保留在主文件或提取到工具类)
- `_apiModelId(config, modelId)` - 获取上游模型ID
- `_effectiveApiKey(config)` - 获取有效API密钥
- `_effectiveModelInfo(config, modelId)` - 获取模型信息
- `_customHeaders(config, modelId)` - 获取自定义请求头
- `_customBody(config, modelId)` - 获取自定义请求体
- `_builtInTools(config, modelId)` - 获取内置工具列表
- `_parseOverrideValue(value)` - 解析覆盖值

### 文件/编码辅助方法
- `_mimeFromPath(path)` - 从文件路径推断MIME类型
- `_encodeBase64File(path, withPrefix)` - 编码文件为Base64

### 已提取到横切模块的工具
- `MimeUtils` - MIME类型处理
- `ModelCapabilities` - 模型能力检测
- `ToolSchemaSanitizer` - Schema清洗

---

## 拆分策略

### 策略A: Part文件拆分 (推荐)

保持 `ChatApiService` 为单一类，使用 Dart `part` 指令将方法分散到多个文件：

```dart
// chat_api_service.dart
part 'adapters/openai_stream.dart';
part 'adapters/claude_stream.dart';
part 'adapters/google_stream.dart';
part 'adapters/prompt_tool_stream.dart';
```

**优点:**
- 最小化改动
- 保持所有私有方法访问权限
- 无需修改调用方

**缺点:**
- 仍是一个逻辑类
- 不支持多态/依赖注入

### 策略B: Adapter类 + 工具类

1. 创建 `ChatApiHelper` 工具类，包含所有共享辅助方法
2. 每个 Provider 创建独立的 Adapter 类实现 `ChatProviderAdapter` 接口
3. 主服务类通过 Provider 类型选择对应 Adapter

**优点:**
- 真正的模块化
- 支持测试和扩展
- 职责分离

**缺点:**
- 需要大量重构
- 需要处理跨类访问

---

## 详细拆分计划

### Step 1: 创建辅助工具类

```
lib/core/services/api/
├── helpers/
│   ├── chat_api_helper.dart    (配置辅助方法)
│   └── file_encoder.dart       (文件编码辅助)
```

提取方法：
- `apiModelId()` - 公开静态方法
- `effectiveApiKey()` - 公开静态方法
- `effectiveModelInfo()` - 公开静态方法
- `customHeaders()` - 公开静态方法
- `customBody()` - 公开静态方法
- `builtInTools()` - 公开静态方法
- `mimeFromPath()` - 使用 MimeUtils
- `encodeBase64File()` - 公开静态方法

### Step 2: 创建 Provider Adapters

```
lib/core/services/api/adapters/
├── chat_provider_adapter.dart  (接口 - 已存在)
├── openai_adapter.dart         (~800行)
├── claude_adapter.dart         (~350行)
├── google_adapter.dart         (~550行)
└── prompt_tool_adapter.dart    (~200行)
```

### Step 3: 更新主服务类

```dart
// chat_api_service.dart (~500行)
class ChatApiService {
  static Stream<ChatStreamChunk> sendMessageStream(...) async* {
    final adapter = _getAdapter(kind);
    yield* adapter.stream(...);
  }
  
  static ChatProviderAdapter _getAdapter(ProviderKind kind) {
    switch (kind) {
      case ProviderKind.openai: return OpenAIAdapter();
      case ProviderKind.claude: return ClaudeAdapter();
      case ProviderKind.google: return GoogleAdapter();
      default: throw UnsupportedError('Unknown provider: $kind');
    }
  }
}
```

---

## 预期结果

| 文件 | 预计行数 |
|------|----------|
| `chat_api_service.dart` | ~500 |
| `helpers/chat_api_helper.dart` | ~300 |
| `adapters/openai_adapter.dart` | ~800 |
| `adapters/claude_adapter.dart` | ~350 |
| `adapters/google_adapter.dart` | ~550 |
| `adapters/prompt_tool_adapter.dart` | ~200 |

**总计:** ~2700行 (原4373行的~62%)

---

## 执行顺序

1. [ ] 创建 `helpers/chat_api_helper.dart` - 提取配置辅助方法
2. [ ] 创建 `adapters/claude_adapter.dart` - 最小的adapter
3. [ ] 创建 `adapters/google_adapter.dart` - 中等复杂度
4. [ ] 创建 `adapters/openai_adapter.dart` - 最复杂
5. [ ] 创建 `adapters/prompt_tool_adapter.dart` - 依赖其他adapter
6. [ ] 更新主服务类使用adapters
7. [ ] 删除主文件中的冗余代码
8. [ ] 验证编译和功能

---

## 风险与注意事项

1. **Tool Loop 逻辑**: OpenAI adapter 包含复杂的工具循环逻辑，需要仔细处理
2. **SSE 解析差异**: 每个 Provider 的 SSE 格式不同，需要保持现有解析逻辑
3. **Token 统计**: 需要正确传递和累加 Token 使用量
4. **错误处理**: 保持现有的错误处理和重试逻辑
5. **向后兼容**: 确保 `sendMessageStream` 接口不变
