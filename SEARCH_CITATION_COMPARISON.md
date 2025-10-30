# RikkaHub vs Kelivo 搜索和引用机制对比分析

## 项目概述

| 维度 | RikkaHub | Kelivo |
|------|---------|--------|
| **框架** | Android (Kotlin) | Flutter (Dart) |
| **用途** | 原生 Android LLM 聊天客户端 | 跨平台（Web/Desktop/Mobile） |
| **搜索能力** | 集成搜索服务模块 | 集成搜索服务模块 |
| **引用处理** | 搜索结果集成但无专门引用系统 | 搜索结果集成但无专门引用系统 |

## 架构对比

### 1. 搜索服务架构

#### RikkaHub (Android/Kotlin)

**文件结构：**
```
search/
├── src/main/java/me/rerere/search/
│   ├── SearchService.kt          # 基类接口
│   ├── ExaSearchService.kt        # Exa 实现
│   ├── TavilySearchService.kt     # Tavily 实现
│   ├── BingSearchService.kt       # Bing 实现
│   ├── ... (其他服务)
│   └── providers/                 # 所有搜索提供商
└── src/test/...                  # 单元测试
```

**核心设计：**
```kotlin
abstract class SearchService<T : SearchServiceOptions> {
    val name: String
    val parameters: InputSchema?
    val scrapingParameters: InputSchema?
    
    @Composable
    fun Description()
    
    suspend fun search(
        params: JsonObject,
        commonOptions: SearchCommonOptions,
        serviceOptions: T
    ): Result<SearchResult>
    
    suspend fun scrape(
        params: JsonObject,
        commonOptions: SearchCommonOptions,
        serviceOptions: T
    ): Result<ScrapedResult>
}
```

**关键特性：**
- 支持异步 `suspend` 函数（协程）
- Result<T> 错误处理包装
- 同时支持搜索和网页爬取功能
- 使用 OkHttp 客户端（已配置 30s 超时）

#### Kelivo (Flutter/Dart)

**文件结构：**
```
lib/core/services/search/
├── search_service.dart           # 基类和工厂
├── search_tool_service.dart      # 搜索工具服务
├── providers/
│   ├── exa_search_service.dart
│   ├── tavily_search_service.dart
│   ├── bing_search_service.dart
│   └── ... (其他提供商)
└── lib/features/search/
    ├── pages/search_services_page.dart
    └── widgets/search_settings_sheet.dart
```

**核心设计：**
```dart
abstract class SearchService<T extends SearchServiceOptions> {
    String get name;
    
    Widget description(BuildContext context);
    
    Future<SearchResult> search({
        required String query,
        required SearchCommonOptions commonOptions,
        required T serviceOptions,
    });
}

class SearchResult {
    String? answer;
    List<SearchResultItem> items;
    
    Map<String, dynamic> toJson();
    factory SearchResult.fromJson(Map<String, dynamic>);
}

class SearchResultItem {
    String title;
    String url;
    String text;
    String? id;
    int? index;
    
    Map<String, dynamic> toJson();
    factory SearchResultItem.fromJson(Map<String, dynamic>);
}
```

**关键特性：**
- 使用 `Future<T>` 异步模式
- 直接抛出异常（无 Result 包装）
- 仅支持搜索功能（无爬取功能）
- 序列化/反序列化内置支持
- 返回 UI Widget 描述（BuildContext 敏感）

### 2. 搜索结果数据模型

#### RikkaHub

```kotlin
data class SearchResult(
    val answer: String?,
    val items: List<SearchResultItem>
)

data class SearchResultItem(
    val title: String,
    val url: String,
    val text: String
)

data class ScrapedResult(
    val urls: List<ScrapedResultUrl>
)

data class ScrapedResultUrl(
    val url: String,
    val content: String,
    val metadata: Metadata? // title, description, language
)

data class SearchCommonOptions(
    val resultSize: Int = 10,
    val timeout: Long = 30_000  // ms
)
```

#### Kelivo

```dart
class SearchResult {
    String? answer;
    List<SearchResultItem> items;
    
    // JSON 序列化方法包含
}

class SearchResultItem {
    String title;
    String url;
    String text;
    String? id;
    int? index;
    
    // JSON 序列化方法包含
}

class SearchCommonOptions {
    final int resultSize; // default: 10
    final int timeout;    // default: 5000 ms
}
```

**区别：**
- RikkaHub: 额外提供 `ScrapedResult` 用于网页内容爬取，metadata 包含标题/描述/语言
- Kelivo: SearchResultItem 包含可选的 `id` 和 `index`，便于结果追踪

### 3. 搜索提供商实现对比

#### Exa 搜索服务 - RikkaHub (Kotlin)

```kotlin
class ExaSearchService : SearchService<ExaOptions> {
    override val name = "Exa"
    
    override val parameters: InputSchema? = InputSchema(
        fields = listOf(
            InputSchema.Field("query", "string", "search keyword")
        )
    )
    
    override suspend fun search(
        params: JsonObject,
        commonOptions: SearchCommonOptions,
        serviceOptions: ExaOptions
    ): Result<SearchResult> = runCatching {
        val query = params["query"].asString
        val body = JsonObject().apply {
            addProperty("query", query)
            addProperty("numResults", commonOptions.resultSize)
            addProperty("contents", JsonObject().apply {
                addProperty("text", true)
            })
        }
        
        val request = Request.Builder()
            .url("https://api.exa.ai/search")
            .post(body.toString().toRequestBody())
            .addHeader("Authorization", "Bearer ${serviceOptions.apiKey}")
            .build()
            
        val response = httpClient.newCall(request).await()
        
        return@runCatching when {
            response.isSuccessful -> {
                val data = json.decodeFromString<ExaData>(response.body?.string() ?: "")
                SearchResult(
                    answer = null,
                    items = data.results.map { result ->
                        SearchResultItem(
                            title = result.title,
                            url = result.url,
                            text = result.text
                        )
                    }
                )
            }
            else -> throw Exception("response failed #${response.code}")
        }
    }
}
```

**特性：**
- 使用 `runCatching` 包装异常为 `Result`
- JsonObject 构建请求体
- OkHttp 的 `newCall().await()` 协程扩展
- 响应解析使用 kotlinx.serialization

#### Exa 搜索服务 - Kelivo (Dart)

```dart
class ExaSearchService extends SearchService<ExaOptions> {
  @override
  String get name => 'Exa';
  
  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(l10n.searchProviderExaDescription);
  }
  
  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required ExaOptions serviceOptions,
  }) async {
    try {
      final body = jsonEncode({
        'query': query,
        'numResults': commonOptions.resultSize,
        'contents': {
          'text': true,
        },
      });
      
      final response = await http.post(
        Uri.parse('https://api.exa.ai/search'),
        headers: {
          'Authorization': 'Bearer ${serviceOptions.apiKey}',
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(Duration(milliseconds: commonOptions.timeout));
      
      if (response.statusCode != 200) {
        throw Exception('API request failed: ${response.statusCode}');
      }
      
      final data = jsonDecode(response.body);
      final results = (data['results'] as List).map((item) {
        return SearchResultItem(
          title: item['title'] ?? '',
          url: item['url'] ?? '',
          text: item['text'] ?? '',
        );
      }).toList();
      
      return SearchResult(items: results);
    } catch (e) {
      throw Exception('Exa search failed: $e');
    }
  }
}
```

**特性：**
- 直接使用 try-catch 异常处理
- `jsonEncode` 构建请求体
- 使用标准 `http` 包
- 内置 `.timeout()` 控制
- 直接抛出异常（调用方需处理）

## 搜索与引用机制对比

### 当前实现

| 特性 | RikkaHub | Kelivo |
|------|---------|--------|
| **搜索集成** | ✓ 完整模块化 | ✓ 完整模块化 |
| **引用系统** | ✓ 已实现 | ✓ 已实现 |
| **Citation追踪** | ✓ 已实现 | ✓ 已实现 |
| **来源标注** | ✓ 搜索结果包含唯一 ID | ✓ 搜索结果包含唯一 ID |
| **结果去重** | ✗ 无 | ✗ 无 |
| **结果排序** | ✗ 无 | ✗ 无 |
| **引用渲染** | ✓ 可点击链接到搜索结果 | ✓ 可点击链接到搜索结果 |
| **引用提取** | ✓ 从搜索工具结果自动提取 | ✓ 从搜索工具结果自动提取 |

### 已实现的引用机制详情

#### RikkaHub (Kotlin/Compose)

**引用提取和存储：**
```kotlin
// 搜索结果存储在 ToolResult 中
// ChatMessage.kt 第 261-277 行
fun handleClickCitation(citationId: String) {
    messages.forEach { message ->
        message.parts.forEach { part ->
            if (part is UIMessagePart.ToolResult && part.toolName == "search_web") {
                val items = part.content.jsonObject["items"]?.jsonArray ?: return@forEach
                items.forEach { item ->
                    val id = item.jsonObject["id"]?.jsonPrimitive?.content ?: return@forEach
                    val url = item.jsonObject["url"]?.jsonPrimitive?.content ?: return@forEach
                    if (citationId == id) {
                        context.openUrl(url)
                        return
                    }
                }
            }
        }
    }
}
```

**引用显示系统：**
- 使用 `UIMessageAnnotation.UrlCitation` 类型
- 在消息底部显示可折叠的引用列表
- 每条引用显示 favicon、标题和链接（第 365-419 行）
- Markdown 中 `[citation](id)` 格式被自动解析为可点击链接

#### Kelivo (Flutter/Dart)

**引用提取和存储：**
```dart
// chat_message_widget.dart 第 1260-1319 行
void _handleCitationTap(String id) async {
  final items = _latestSearchItems();
  final match = items.cast<Map<String, dynamic>?>().firstWhere(
    (e) => (e?['id']?.toString() ?? '') == id,
    orElse: () => null,
  );
  final url = match?['url']?.toString();
  if (url != null && url.isNotEmpty) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

List<Map<String, dynamic>> _latestSearchItems() {
  // 从工具结果中提取搜索 items
  final parts = widget.toolParts ?? const <ToolUIPart>[];
  for (int i = parts.length - 1; i >= 0; i--) {
    final p = parts[i];
    if ((p.toolName == 'search_web' || p.toolName == 'builtin_search')) {
      final obj = jsonDecode(p.content!) as Map<String, dynamic>;
      return (obj['items'] as List).cast<Map<String, dynamic>>();
    }
  }
  return const <Map<String, dynamic>>[];
}
```

**引用渲染系统：**
```dart
// markdown_with_highlight.dart 第 141-189 行
// 特殊处理 [citation](index:id) 格式
linkBuilder: (ctx, span, url, style) {
  if (span.toPlainText().trim().toLowerCase() == 'citation') {
    final parts = url.split(':');
    if (parts.length == 2) {
      final indexText = parts[0].trim();  // 显示的数字
      final id = parts[1].trim();         // 搜索结果 ID
      return GestureDetector(
        onTap: () => onCitationTap?.call(id),
        child: Container(
          // 圆形引用标记
          width: 20, height: 20,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(indexText),
        ),
      );
    }
  }
}
```

**引用汇总显示：**
- `_SourcesSummaryCard` 显示来源数量（第 1179-1186 行）
- 点击展开 `_showCitationsSheet()` 显示完整列表（第 1321-1360 行）

### 当前存在的问题

1. **结果去重** - 未实现
   - 搜索结果可能包含重复的 URL 或内容
   - 没有基于 URL 或内容相似度的去重机制

2. **结果排序** - 未实现
   - 搜索结果按原始顺序显示
   - 缺乏相关性、重要性或时效性排序

3. **网页爬取差异**
   - RikkaHub: 支持 `scrape()` 获取全文内容和 metadata
   - Kelivo: 不支持爬取，仅返回摘要

## 未实现的功能及改进建议

### 建议方案

#### 1. 扩展数据模型

**RikkaHub (Kotlin):**
```kotlin
data class SearchResult(
    val answer: String?,
    val items: List<SearchResultItem>,
    val metadata: SearchMetadata? = null
)

data class SearchResultItem(
    val id: String,  // 新增：唯一标识符
    val title: String,
    val url: String,
    val text: String,
    val source: String? = null,  // 新增：来源名称
    val confidence: Float? = null  // 新增：置信度
)

data class SearchMetadata(
    val query: String,
    val provider: String,
    val timestamp: Long,
    val totalResults: Int
)
```

**Kelivo (Dart):**
```dart
class SearchResult {
    String? answer;
    List<SearchResultItem> items;
    SearchMetadata? metadata;  // 新增
}

class SearchResultItem {
    String id;  // 新增
    String title;
    String url;
    String text;
    String? source;  // 新增
    double? confidence;  // 新增
}

class SearchMetadata {
    String query;
    String provider;
    DateTime timestamp;
    int totalResults;
}
```

#### 2. 在 LLM 响应中集成引用

**方案：在 AI Provider 中处理搜索结果上下文**

RikkaHub (Kotlin):
```kotlin
// 在 OpenAIProvider 或其他 AI provider 中
suspend fun chatWithSearch(
    messages: List<Message>,
    searchResult: SearchResult?,
    options: ChatCompletionOptions
): Flow<String> {
    // 构建上下文，在 system prompt 中包含搜索结果
    val systemPrompt = buildString {
        append(options.systemPrompt)
        if (searchResult != null) {
            append("\n\n### 搜索结果:\n")
            searchResult.items.forEachIndexed { index, item ->
                append("[$index] ${item.title}\n")
                append("URL: ${item.url}\n")
                append("内容: ${item.text}\n\n")
            }
            append("引用格式: [来源1][来源2]")
        }
    }
    
    // 继续正常的 API 调用...
}
```

Kelivo (Dart):
```dart
// 在 AI provider 中
Future<String> chatWithSearch({
    required List<Message> messages,
    required SearchResult? searchResult,
    required ChatCompletionOptions options,
}) async {
    String systemPrompt = options.systemPrompt;
    
    if (searchResult != null) {
        systemPrompt += '\n\n### 搜索结果:\n';
        for (int i = 0; i < searchResult.items.length; i++) {
            final item = searchResult.items[i];
            systemPrompt += '[$i] ${item.title}\n';
            systemPrompt += 'URL: ${item.url}\n';
            systemPrompt += '内容: ${item.text}\n\n';
        }
        systemPrompt += '引用格式: [来源1][来源2]';
    }
    
    // 继续正常的 API 调用...
}
```

#### 3. 实现引用解析和渲染

**方案：在 UI 层解析和展示引用**

RikkaHub (Kotlin/Compose):
```kotlin
@Composable
fun ChatMessageWithCitations(
    message: String,
    citations: List<SearchResultItem>
) {
    val citationPattern = """\[(\d+)\]""".toRegex()
    
    AnnotatedString.Builder().apply {
        var lastIndex = 0
        citationPattern.findAll(message).forEach { match ->
            // 添加普通文本
            append(message.substring(lastIndex, match.range.first))
            
            // 添加引用链接
            val citationIndex = match.groupValues[1].toInt()
            if (citationIndex < citations.size) {
                val citation = citations[citationIndex]
                pushStringAnnotation(
                    tag = "citation",
                    annotation = citation.url
                )
                withStyle(SpanStyle(color = Color.Blue)) {
                    append("[${citation.title}]")
                }
                pop()
            }
            
            lastIndex = match.range.last + 1
        }
        append(message.substring(lastIndex))
        
        ClickableText(
            text = toAnnotatedString(),
            onClick = { offset ->
                getStringAnnotations("citation", offset, offset)
                    .firstOrNull()?.let { annotation ->
                        // 打开 URL
                    }
            }
        )
    }.build()
}
```

Kelivo (Flutter):
```dart
Widget buildCitationsText(
  String text,
  List<SearchResultItem> citations,
) {
  final citationPattern = RegExp(r'\[(\d+)\]');
  
  List<InlineSpan> spans = [];
  int lastIndex = 0;
  
  for (var match in citationPattern.allMatches(text)) {
    // 添加普通文本
    spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
    
    // 添加引用链接
    final citationIndex = int.parse(match.group(1)!);
    if (citationIndex < citations.length) {
      final citation = citations[citationIndex];
      spans.add(
        TextSpan(
          text: '[${citation.title}]',
          style: const TextStyle(color: Colors.blue),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              // 打开 URL
              launchUrl(Uri.parse(citation.url));
            },
        ),
      );
    }
    
    lastIndex = match.end;
  }
  
  spans.add(TextSpan(text: text.substring(lastIndex)));
  
  return RichText(text: TextSpan(children: spans));
}
```

## 实现建议优先级

| 优先级 | 功能 | 工作量 | 效果 |
|--------|------|--------|------|
| **高** | 搜索结果唯一 ID 和元数据 | 低 | 高 - 支持引用追踪 |
| **高** | AI 提示词中包含搜索结果 | 低 | 高 - 增强 LLM 上下文 |
| **中** | 引用解析和渲染 | 中 | 中 - 改进用户体验 |
| **中** | 网页爬取（Kelivo） | 高 | 中 - 获取完整内容 |
| **低** | 结果去重和排序 | 中 | 低 - 提升结果质量 |

## 总结

**RikkaHub** 作为参考项目的优势：
- ✓ 更完整的搜索抽象（支持网页爬取）
- ✓ 更强的错误处理（Result 模式）
- ✓ 更详细的 metadata 支持

**Kelivo** 当前的优势：
- ✓ 跨平台支持（Flutter）
- ✓ 内置 JSON 序列化
- ✓ SearchResultItem 包含 id/index 字段（未充分利用）

**改进方向**：两个项目可以继续优化：
1. ✅ 搜索结果唯一标识系统（已实现）
2. ✅ 引用解析和交互式渲染（已实现）  
3. ⚠️ 结果去重和排序（可选优化）
4. ⚠️ 网页爬取增强（Kelivo 可考虑）
