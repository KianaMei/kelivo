# RikkaHub vs Kelivo 引用系统实现对比总结

## ✅ 已实现的功能

### 1. 引用追踪系统

**两个项目都已实现了从搜索结果到 LLM 生成文本的引用链接机制。**

#### RikkaHub 实现路径

```
搜索工具执行 → ToolResult (包含 search_web) 
  ↓
MessagePart.ToolResult 存储搜索 items（每个 item 有唯一 id）
  ↓
LLM 生成 Markdown 包含 [citation](id) 格式
  ↓
MarkdownBlock 处理器识别 citation 并渲染为可点击链接
  ↓
handleClickCitation(citationId) 根据 id 查找 URL 并打开
```

**核心代码：** 
- `ChatMessage.kt` 第 261-277 行：`handleClickCitation()` 从 ToolResult 中查找 id 匹配的搜索项
- `Markdown.kt` 第 196 行：`onClickCitation` 回调处理引用点击

#### Kelivo 实现路径

```
搜索工具执行 → ToolUIPart (toolName='search_web' 或 'builtin_search')
  ↓
part.content 包含 JSON，其中 items 数组每项都有 id 和 url
  ↓
MarkdownWithCodeHighlight.linkBuilder 识别 [citation](index:id) 格式
  ↓
解析 URL 格式 "index:id"，提取 id
  ↓
_handleCitationTap(id) 在 _latestSearchItems() 中查找匹配项
  ↓
通过 launchUrl() 打开搜索结果 URL
```

**核心代码：**
- `chat_message_widget.dart` 第 1260-1297 行：`_handleCitationTap()` 处理引用点击
- `chat_message_widget.dart` 第 1300-1319 行：`_latestSearchItems()` 提取最新搜索结果
- `markdown_with_highlight.dart` 第 141-189 行：`linkBuilder` 识别 citation 格式

### 2. 引用 UI 展示

#### RikkaHub

**方式1：Markdown 内联显示**
- Markdown 中 `[citation](id)` 自动转换为蓝色下划线链接
- 点击直接打开对应 URL

**方式2：底部引用列表**
```kotlin
// MessagePartsBlock 中处理 annotations
if (annotations.isNotEmpty()) {
    // 可折叠的引用列表
    // 每条引用显示：
    // - Favicon
    // - 标题 (urlDecode 处理)
    // - 链接 (LinkAnnotation.Url)
    // - 序号 (index + 1)
}
```
位置：`ChatMessage.kt` 第 365-419 行

#### Kelivo

**方式1：Markdown 内联引用标记**
```dart
// 圆形数字标记，如 ① ② ③
Container(
  width: 20, height: 20,
  decoration: BoxDecoration(
    color: cs.primary.withOpacity(0.20),
    borderRadius: BorderRadius.circular(10),
  ),
  child: Text(indexText),  // 显示 "0", "1", "2" 等
)
```
位置：`markdown_with_highlight.dart` 第 158-171 行

**方式2：顶部来源汇总卡片**
- `_SourcesSummaryCard` 显示 "Sources (N)"
- 点击打开底部 Sheet

**方式3：完整引用列表 Sheet**
- `_showCitationsSheet()` 显示完整引用列表
- 包含标题、URL 和链接

### 3. 搜索结果中的唯一标识

#### 前端生成

**RikkaHub (Kotlin)**
- 每个搜索结果 item 包含 `id` 字段
- 存储在 ToolResult 的 JSON 中
- 通过 `item.jsonObject["id"]?.jsonPrimitive?.content` 访问

**Kelivo (Dart)**
- 每个搜索结果 item 包含 `id` 字段  
- 存储在 ToolUIPart 的 content JSON 中
- 通过 `it['id']?.toString()` 访问

#### 后端生成

**搜索服务** (`search/` 模块 或 `lib/core/services/search/`)
- 各搜索 API（Exa, Tavily, Bing 等）返回的结果都包含唯一标识
- 例如 Exa API 返回 `id` 字段
- 被转换为 SearchResult → SearchResultItem.id

### 4. Markdown 渲染中的引用处理

#### RikkaHub

**Markdown 解析器：** IntelliJ Markdown Parser + GFM 扩展
- 递归遍历 AST 树
- 识别所有 Markdown 元素类型
- 对于链接节点，检查 `[citation](id)` 格式
- 通过 `onClickCitation` 回调触发打开

**特性：**
- 支持完整的 GFM 功能
- 代码块内容不被处理
- 支持表格、strikethrough 等

#### Kelivo

**Markdown 库：** gpt_markdown + flutter_markdown
- 自定义 `linkBuilder` 处理所有链接
- 检查 link text == "citation"
- URL 格式 `"index:id"` 用来传递信息
- 自定义渲染圆形标记按钮

**特性：**
- 轻量级实现
- 易于自定义样式
- 支持 LaTeX、代码高亮等

## ⚠️ 未实现的功能

### 1. 结果去重 (Result Deduplication)

**问题：**
- 多次搜索或多个搜索工具可能返回相同 URL
- 没有机制合并重复项

**改进建议：**
```dart
// 示例：按 URL 去重
List<SearchResultItem> deduplicateResults(List<SearchResultItem> items) {
  final Map<String, SearchResultItem> urlMap = {};
  for (final item in items) {
    if (!urlMap.containsKey(item.url)) {
      urlMap[item.url] = item;
    }
  }
  return urlMap.values.toList();
}
```

### 2. 结果排序 (Result Ranking)

**问题：**
- 搜索结果按原始顺序显示
- 没有相关性、重要性或时效性排序

**改进建议：**
```kotlin
// RikkaHub 示例
data class SearchResultItem(
    val title: String,
    val url: String,
    val text: String,
    val id: String,
    val relevanceScore: Float? = null,  // 新增
    val publishDate: Long? = null       // 新增
)

fun rankResults(items: List<SearchResultItem>): List<SearchResultItem> {
    return items.sortedByDescending { it.relevanceScore }
}
```

### 3. 网页爬取增强 (Kelivo)

**问题：**
- Kelivo 仅返回搜索摘要
- RikkaHub 支持 `scrape()` 获取完整网页内容

**改进建议：**
```dart
// Kelivo 可添加爬取功能
class SearchServiceWithScraping<T extends SearchServiceOptions> {
    Future<ScrapedResult> scrape({
        required String url,
        required ScrapingOptions options,
    }) async {
        // 使用 http 获取网页
        // 使用 html 或 xpath 解析内容
        // 返回 ScrapedResult(content, metadata)
    }
}
```

## 🔍 关键实现细节对比

| 功能 | RikkaHub | Kelivo |
|------|---------|--------|
| **引用格式** | `[citation](id)` | `[citation](index:id)` |
| **ID 来源** | 搜索 API 原生 id | 搜索 API 原生 id |
| **提取方式** | 遍历 messages 中所有 ToolResult | `_latestSearchItems()` 获取最新搜索 |
| **存储位置** | UIMessageAnnotation.UrlCitation | widget.toolParts 中的 ToolUIPart |
| **UI 样式** | 蓝色链接 + 可折叠底部列表 | 圆形标记 + 汇总卡片 + 详情 Sheet |
| **点击处理** | ClickableText + onClick 回调 | GestureDetector + onCitationTap |
| **URL 打开** | context.openUrl() | launchUrl() |

## 💡 最佳实践建议

### 1. 增强引用元数据

当前两个项目的搜索结果中的 `id` 都是原生的（如 UUID 或 API ID）。

**建议添加：**
```dart
class SearchResultItem {
  String id;           // ✅ 已有
  String title;        // ✅ 已有
  String url;          // ✅ 已有
  String text;         // ✅ 已有
  
  // 建议添加：
  String source;       // 搜索引擎来源 (Exa, Tavily, Bing 等)
  double? confidence;  // 相关性分数 (0-1)
  DateTime? fetchedAt; // 获取时间
  int? position;       // 在搜索结果中的位置
}
```

### 2. 集成引用到 LLM Prompt

**建议：** 在 AI provider 中将搜索结果作为系统提示的上下文

```kotlin
// RikkaHub
val systemPrompt = buildString {
    append(originalPrompt)
    if (searchResults.isNotEmpty()) {
        append("\n\n## Available Search Results\n")
        searchResults.forEachIndexed { idx, result ->
            append("[${idx}] ${result.title}\n")
            append("URL: ${result.url}\n")
            append("Content: ${result.text}\n\n")
        }
        append("Reference format: [0], [1], etc.")
    }
}
```

### 3. 统计引用使用情况

**建议：** 追踪哪些搜索结果被实际引用

```dart
// 用于分析和改进搜索质量
class CitationStats {
  String resultId;
  int clickCount;      // 用户点击次数
  bool wasReferencedByAI; // LLM 是否引用
  DateTime lastAccessed;
}
```

## 总结

✅ **已实现：**
- 搜索结果的唯一标识（id）
- Markdown 中的引用格式解析
- 点击链接打开搜索结果
- 引用的 UI 展示

⚠️ **可以优化：**
- 结果去重（按 URL 或内容相似度）
- 结果排序（按相关性、时效性）
- 网页内容爬取（Kelivo）
- 引用统计和分析

两个项目的实现思路一致，都利用搜索工具返回的 JSON 结果中的 `id` 字段建立引用链接。差异主要在 UI 呈现方式和 Markdown 格式约定。
