# 常用模式和最佳实践

- Token Usage 显示优化：
- 统一显示格式：只有多轮（rounds.length > 1）时显示分轮详情，单轮或无 rounds 数据都显示统一格式
- 主显示区：始终显示聚合的 token 数（如 548↓ 3235↑ 91.7tok/s）
- Tooltip 显示规则：
  * 多轮：显示每轮详情 + 总计
  * 单轮/无轮：直接显示总计
- 修改文件：lib/features/chat/widgets/chat_message_widget.dart（第1101-1171行，第3229-3254行）
- rounds 数据来源：API 响应中的多轮对话或工具调用的 token 统计
- Token Usage Display 卡片美化优化：
- 宽度自适应：使用 IntrinsicWidth 让卡片紧贴内容宽度，避免右侧留白
- 替换 Divider 为 Container：避免 Divider 撑开宽度，实现真正的自适应
- 毛玻璃效果：BackdropFilter + blur(10, 10) + surface.withOpacity(0.85)
- 圆角优化：从 8px 增加到 12px
- 阴影增强：blurRadius 从 8 增加到 12，offset (0, 4)
- 边框柔和化：使用 outlineVariant.withOpacity(0.4)
- 行高优化：Text height 1.2，padding 微调
- 移动端和桌面端通用
- 修改文件：lib/features/chat/widgets/chat_message_widget.dart（第3181-3273行，添加 dart:ui import）
- ## Phase 1A: ChatMessageWidget 重构完成

### 文件结构
```
lib/features/chat/widgets/
├── chat_message_widget.dart (orchestrator, ~165行)
└── message/
    ├── message_parts.dart (SharedComponents: ShimmerEffect, Marquee, BranchSelector, TokenUsageDisplay, CitationWidgets)
    ├── tool_call_item.dart (ToolUIPart, ToolCallItem)
    ├── reasoning_section.dart (ReasoningSegment, ReasoningSection)
    ├── user_message_renderer.dart (UserMessageRenderer)
    └── assistant_message_renderer.dart (AssistantMessageRenderer)
```

### 关键设计
1. **Orchestrator 模式**: ChatMessageWidget 保持原接口，内部根据 message.role 分发到 UserMessageRenderer 或 AssistantMessageRenderer
2. **向后兼容**: 通过 export 语句重新导出 ToolUIPart 和 ReasoningSegment，home_page.dart 无需修改导入
3. **Provider 传递**: settings、userProvider 通过 context.watch 获取后传入 Renderer

### Spec 文档位置
docs/SPEC_1A_MESSAGE_SPLIT.md

### 分支
refactor/chat-message-split
