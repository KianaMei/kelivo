# Phase 1A 提取计划

## 文件拆分映射

### 源文件
`lib/features/chat/widgets/chat_message_widget.dart` (3422行)

### 目标文件结构

#### 1. message_models.dart ✅ 已完成
- ToolUIPart (行 2268-2281)
- ReasoningSegment (行 2284-2303)

#### 2. message_parts.dart - 待创建
需要提取的组件：
- _TokenUsageDisplay (行 3173-3421)
- _BranchSelector (行 2137-2188)
- _SourcesList (行 2538-2578)
- _SourceRow (行 2581-2632)
- _SourcesSummaryCard (行 2635-2677)
- _Shimmer (行 2988-3058)
- _LoadingIndicator (行 2191-2251)
- _Marquee (行 3062-3170)

#### 3. tool_call_item.dart - 待创建
- _ToolCallItem (行 2305-2536)

#### 4. reasoning_section.dart - 待创建
- _ReasoningSection (行 2697-2985)

#### 5. user_message_renderer.dart - 待创建
需要提取用户消息相关的渲染逻辑
- _ParsedUserContent (行 2253-2258)
- _DocRef (行 2260-2265)
- _buildUserMessage 方法及相关逻辑

#### 6. assistant_message_renderer.dart - 待创建
需要提取助手消息相关的渲染逻辑
- _buildAssistantMessage 方法及相关逻辑

## 提取策略

由于文件过大（3422行），采用以下策略：
1. 先创建独立的小组件文件（message_parts, tool_call_item, reasoning_section）
2. 然后创建两个大的渲染器文件（user, assistant）
3. 最后清理主文件，只保留协调逻辑

## 依赖关系

所有组件都需要导入：
- Flutter material
- 项目内的 icons/lucide_adapter
- l10n/app_localizations
- 其他必要的依赖
