import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:markdown_quill/markdown_quill.dart';
import '../../../icons/lucide_adapter.dart';

/// 富文本聊天输入组件
/// 
/// 类似 LobeChat 风格的简洁富文本编辑器：
/// - 默认隐藏工具栏，点击展开
/// - 支持代码块、粗体、斜体
/// - 深浅主题自适应
class RichChatInput extends StatefulWidget {
  const RichChatInput({
    super.key,
    this.onSend,
    this.focusNode,
    this.hintText,
    this.minLines = 1,
    this.maxLines = 8,
    this.readOnly = false,
    this.showToolbar = false,
  });

  final Function(String plainText)? onSend;
  final FocusNode? focusNode;
  final String? hintText;
  final int minLines;
  final int maxLines;
  final bool readOnly;
  final bool showToolbar;

  @override
  State<RichChatInput> createState() => RichChatInputState();
}

class RichChatInputState extends State<RichChatInput> {
  late QuillController _controller;
  late FocusNode _editorFocusNode;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = QuillController.basic();
    _editorFocusNode = widget.focusNode ?? FocusNode();

    // 监听文档变化
    _controller.addListener(_onDocumentChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onDocumentChange);
    _controller.dispose();
    _scrollController.dispose();
    if (widget.focusNode == null) {
      _editorFocusNode.dispose();
    }
    super.dispose();
  }

  void _onDocumentChange() {
    setState(() {});
  }

  /// 获取纯文本内容
  String get plainText => _controller.document.toPlainText().trim();

  /// 获取 Markdown 格式内容
  String get markdown {
    final delta = _controller.document.toDelta();
    final converter = DeltaToMarkdown();
    return converter.convert(delta).trim();
  }

  /// 检查是否为空
  bool get isEmpty => _controller.document.isEmpty();

  /// 清空内容
  void clear() {
    _controller.clear();
  }

  /// 插入文本
  void insertText(String text) {
    final index = _controller.selection.baseOffset;
    _controller.document.insert(index, text);
  }

  /// 处理发送
  void _handleSend() {
    final text = plainText;
    if (text.isEmpty) return;
    widget.onSend?.call(text);
    clear();
  }

  /// 切换行内样式 (粗体、斜体等)
  void _toggleInlineStyle(Attribute attr) {
    final style = _controller.getSelectionStyle();
    if (style.containsKey(attr.key)) {
      _controller.formatSelection(Attribute.clone(attr, null));
    } else {
      _controller.formatSelection(attr);
    }
  }

  /// 切换块级样式 (列表、引用等)
  void _toggleBlockAttribute(Attribute attr) {
    final style = _controller.getSelectionStyle();
    final current = style.attributes[attr.key];
    if (current?.value == attr.value) {
      // 已经是这个样式，取消它
      _controller.formatSelection(Attribute.clone(attr, null));
    } else {
      // 应用新样式
      _controller.formatSelection(attr);
    }
  }

  /// 检查列表类型是否激活
  bool _isListActive(String listType) {
    final style = _controller.getSelectionStyle();
    final listAttr = style.attributes[Attribute.list.key];
    return listAttr?.value == listType;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 工具栏 - 单行可滚动，不折叠
        _buildToolbar(context, isDark, cs),
        const SizedBox(height: 4),
        // 编辑器
        _buildEditor(context, isDark, cs),
      ],
    );
  }

  /// 工具栏 - 单行可滚动
  Widget _buildToolbar(BuildContext context, bool isDark, ColorScheme cs) {
    final style = _controller.getSelectionStyle();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          // 粗体
          _ToolbarButton(
            icon: Lucide.Bold,
            tooltip: '粗体',
            isActive: style.containsKey(Attribute.bold.key),
            onTap: () => _toggleInlineStyle(Attribute.bold),
            isDark: isDark,
          ),
          // 斜体
          _ToolbarButton(
            icon: Lucide.Italic,
            tooltip: '斜体',
            isActive: style.containsKey(Attribute.italic.key),
            onTap: () => _toggleInlineStyle(Attribute.italic),
            isDark: isDark,
          ),
          // 下划线
          _ToolbarButton(
            icon: Lucide.Underline,
            tooltip: '下划线',
            isActive: style.containsKey(Attribute.underline.key),
            onTap: () => _toggleInlineStyle(Attribute.underline),
            isDark: isDark,
          ),
          // 删除线
          _ToolbarButton(
            icon: Lucide.Strikethrough,
            tooltip: '删除线',
            isActive: style.containsKey(Attribute.strikeThrough.key),
            onTap: () => _toggleInlineStyle(Attribute.strikeThrough),
            isDark: isDark,
          ),
          // 行内代码
          _ToolbarButton(
            icon: Lucide.Code,
            tooltip: '行内代码',
            isActive: style.containsKey(Attribute.inlineCode.key),
            onTap: () => _toggleInlineStyle(Attribute.inlineCode),
            isDark: isDark,
          ),
          _buildDivider(isDark),
          // 标题 H1
          _ToolbarButton(
            icon: Lucide.Heading1,
            tooltip: '标题 1',
            isActive: style.attributes[Attribute.header.key]?.value == 1,
            onTap: () => _toggleBlockAttribute(Attribute.h1),
            isDark: isDark,
          ),
          // 标题 H2
          _ToolbarButton(
            icon: Lucide.Heading2,
            tooltip: '标题 2',
            isActive: style.attributes[Attribute.header.key]?.value == 2,
            onTap: () => _toggleBlockAttribute(Attribute.h2),
            isDark: isDark,
          ),
          // 标题 H3
          _ToolbarButton(
            icon: Lucide.Heading3,
            tooltip: '标题 3',
            isActive: style.attributes[Attribute.header.key]?.value == 3,
            onTap: () => _toggleBlockAttribute(Attribute.h3),
            isDark: isDark,
          ),
          _buildDivider(isDark),
          // 代码块
          _ToolbarButton(
            icon: Lucide.FileCode,
            tooltip: '代码块',
            isActive: style.containsKey(Attribute.codeBlock.key),
            onTap: () => _toggleBlockAttribute(Attribute.codeBlock),
            isDark: isDark,
          ),
          // 引用
          _ToolbarButton(
            icon: Lucide.Quote,
            tooltip: '引用',
            isActive: style.containsKey(Attribute.blockQuote.key),
            onTap: () => _toggleBlockAttribute(Attribute.blockQuote),
            isDark: isDark,
          ),
          _buildDivider(isDark),
          // 无序列表
          _ToolbarButton(
            icon: Lucide.List,
            tooltip: '无序列表',
            isActive: _isListActive('bullet'),
            onTap: () => _toggleBlockAttribute(Attribute.ul),
            isDark: isDark,
          ),
          // 有序列表
          _ToolbarButton(
            icon: Lucide.ListOrdered,
            tooltip: '有序列表',
            isActive: _isListActive('ordered'),
            onTap: () => _toggleBlockAttribute(Attribute.ol),
            isDark: isDark,
          ),
          // 任务列表
          _ToolbarButton(
            icon: Lucide.ListTodo,
            tooltip: '任务列表',
            isActive: _isListActive('unchecked'),
            onTap: () => _toggleBlockAttribute(Attribute.unchecked),
            isDark: isDark,
          ),
          _buildDivider(isDark),
          // 链接
          _ToolbarButton(
            icon: Lucide.Link,
            tooltip: '插入链接',
            isActive: style.containsKey(Attribute.link.key),
            onTap: () => _showLinkDialog(context),
            isDark: isDark,
          ),
          // 清除格式
          _ToolbarButton(
            icon: Lucide.RemoveFormatting,
            tooltip: '清除格式',
            onTap: () {
              final attrs = _controller.getSelectionStyle().attributes;
              for (final attr in attrs.values) {
                _controller.formatSelection(Attribute.clone(attr, null));
              }
            },
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(width: 1, height: 20, color: isDark ? Colors.white24 : Colors.black12),
    );
  }

  /// 显示链接输入对话框
  void _showLinkDialog(BuildContext context) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('插入链接'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'https://example.com',
            labelText: 'URL',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final url = textController.text.trim();
              if (url.isNotEmpty) {
                _controller.formatSelection(LinkAttribute(url));
              }
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context, bool isDark, ColorScheme cs) {
    return Container(
      constraints: BoxConstraints(
        minHeight: 24.0 * widget.minLines + 16,
        maxHeight: 24.0 * widget.maxLines + 16,
      ),
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: QuillEditor(
          controller: _controller,
          focusNode: _editorFocusNode,
          scrollController: _scrollController,
          config: QuillEditorConfig(
            placeholder: widget.hintText ?? '输入消息...',
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            expands: false,
            autoFocus: false,
            scrollable: true,
            customStyles: _getCustomStyles(context, isDark),
            // 支持图片、视频等嵌入内容
            embedBuilders: FlutterQuillEmbeds.editorBuilders(),
          ),
        ),
      ),
    );
  }

  /// 处理键盘事件: Enter 发送, Shift+Enter 换行
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;

    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    if (isShiftPressed) {
      // Shift+Enter: 插入换行，让 QuillEditor 处理
      return KeyEventResult.ignored;
    } else {
      // Enter: 发送消息
      final text = plainText;
      if (text.isNotEmpty) {
        widget.onSend?.call(text);
        clear();
      }
      return KeyEventResult.handled;
    }
  }

  DefaultStyles _getCustomStyles(BuildContext context, bool isDark) {
    final baseStyle = TextStyle(
      fontSize: 15,
      height: 1.5,
      color: isDark ? Colors.white : Colors.black87,
    );

    return DefaultStyles(
      paragraph: DefaultTextBlockStyle(
        baseStyle,
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(0, 0),
        const VerticalSpacing(0, 0),
        null,
      ),
      code: DefaultTextBlockStyle(
        TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: isDark ? Colors.greenAccent : Colors.green.shade800,
          backgroundColor: isDark 
              ? Colors.black.withOpacity(0.3) 
              : Colors.grey.withOpacity(0.1),
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(8, 8),
        const VerticalSpacing(0, 0),
        BoxDecoration(
          color: isDark 
              ? Colors.black.withOpacity(0.3) 
              : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      h1: DefaultTextBlockStyle(
        baseStyle.copyWith(fontSize: 24, fontWeight: FontWeight.bold),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(16, 8),
        const VerticalSpacing(0, 0),
        null,
      ),
      h2: DefaultTextBlockStyle(
        baseStyle.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(12, 6),
        const VerticalSpacing(0, 0),
        null,
      ),
      h3: DefaultTextBlockStyle(
        baseStyle.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(8, 4),
        const VerticalSpacing(0, 0),
        null,
      ),
      bold: const TextStyle(fontWeight: FontWeight.bold),
      italic: const TextStyle(fontStyle: FontStyle.italic),
      inlineCode: InlineCodeStyle(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          color: isDark ? Colors.amber : Colors.deepOrange,
          backgroundColor: isDark 
              ? Colors.amber.withOpacity(0.2) 
              : Colors.orange.withOpacity(0.15),
        ),
        backgroundColor: isDark 
            ? Colors.amber.withOpacity(0.2) 
            : Colors.orange.withOpacity(0.15),
        radius: const Radius.circular(4),
      ),
      lists: DefaultListBlockStyle(
        baseStyle,
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(4, 4),
        const VerticalSpacing(0, 0),
        null,
        null,
      ),
      quote: DefaultTextBlockStyle(
        baseStyle.copyWith(
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          fontStyle: FontStyle.italic,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(8, 8),
        const VerticalSpacing(0, 0),
        BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              width: 3,
            ),
          ),
        ),
      ),
    );
  }
}

/// 工具栏按钮
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.isDark,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDark;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? cs.primary.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive
                ? cs.primary
                : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      ),
    );
  }
}
