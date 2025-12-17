import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark-reasonable.dart';
import '../../icons/lucide_adapter.dart';
import 'snackbar.dart';
import 'code_artifacts_card.dart';

/// 显示代码查看对话框/页面
/// 
/// 桌面端：使用 Dialog 显示
/// 移动端：使用全屏页面（Navigator.push）
Future<void> showCodeViewDialog(
  BuildContext context, {
  required String code,
  required String language,
}) {
  final isDesktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);
  
  if (isDesktop) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _CodeViewDialog(code: code, language: language),
    );
  } else {
    return Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _CodeViewPage(code: code, language: language),
      ),
    );
  }
}

/// 桌面端代码查看 Dialog
class _CodeViewDialog extends StatefulWidget {
  final String code;
  final String language;

  const _CodeViewDialog({
    required this.code,
    required this.language,
  });

  @override
  State<_CodeViewDialog> createState() => _CodeViewDialogState();
}

class _CodeViewDialogState extends State<_CodeViewDialog> {
  late LanguageConfig _config;
  late ScrollController _scrollController;
  bool _showLineNumbers = true;
  bool _wordWrap = true;
  double _fontSize = 13.0;

  @override
  void initState() {
    super.initState();
    _config = LanguageConfig.getConfig(widget.language);
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) {
      showAppSnackBar(
        context,
        message: 'Copied to clipboard',
        type: NotificationType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: screenSize.width * 0.85,
        height: screenSize.height * 0.8,
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Column(
          children: [
            // Header
            _buildHeader(cs, isDark),
            
            // Toolbar
            _buildToolbar(cs),
            
            // Code content
            Expanded(child: _buildCodeView(cs, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    final lineCount = widget.code.split('\n').length;
    final charCount = widget.code.length;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _config.accentColor.withOpacity(isDark ? 0.15 : 0.1),
          cs.surface,
        ),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // 语言图标
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _config.accentColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _config.icon,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          
          // 标题和信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_config.displayName} Code',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$lineCount lines · $charCount characters',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          
          // 复制按钮
          IconButton(
            onPressed: _handleCopy,
            icon: const Icon(Lucide.Copy, size: 18),
            tooltip: 'Copy code',
          ),
          
          // 关闭按钮
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Lucide.X, size: 20),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          // 行号开关
          _ToolbarToggle(
            icon: Lucide.Hash,
            label: 'Lines',
            isActive: _showLineNumbers,
            onToggle: () => setState(() => _showLineNumbers = !_showLineNumbers),
          ),
          const SizedBox(width: 8),
          
          // 自动换行开关
          _ToolbarToggle(
            icon: Lucide.Type,
            label: 'Wrap',
            isActive: _wordWrap,
            onToggle: () => setState(() => _wordWrap = !_wordWrap),
          ),
          
          const Spacer(),
          
          // 字体大小调节
          IconButton(
            onPressed: _fontSize > 10 ? () => setState(() => _fontSize -= 1) : null,
            icon: const Icon(Lucide.Minus, size: 14),
            iconSize: 14,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            tooltip: 'Decrease font size',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${_fontSize.toInt()}px',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            onPressed: _fontSize < 24 ? () => setState(() => _fontSize += 1) : null,
            icon: const Icon(Lucide.Plus, size: 14),
            iconSize: 14,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            tooltip: 'Increase font size',
          ),
        ],
      ),
    );
  }

  Widget _buildCodeView(ColorScheme cs, bool isDark) {
    final theme = isDark ? atomOneDarkReasonableTheme : githubTheme;
    final lines = widget.code.split('\n');
    
    if (_showLineNumbers) {
      // 带行号的代码视图
      return Container(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFAFAFA),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: SingleChildScrollView(
            scrollDirection: _wordWrap ? Axis.vertical : Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 行号列
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark 
                        ? const Color(0xFF252526)
                        : const Color(0xFFF0F0F0),
                    border: Border(
                      right: BorderSide(
                        color: cs.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(lines.length, (i) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        height: _fontSize * 1.5,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: _fontSize,
                            fontFamily: 'monospace',
                            color: cs.onSurfaceVariant.withOpacity(0.5),
                            height: 1.5,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                
                // 代码内容
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: HighlightView(
                      widget.code,
                      language: widget.language.isEmpty ? 'text' : widget.language,
                      theme: theme,
                      textStyle: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: _fontSize,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // 无行号的简洁视图
      return Container(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFAFAFA),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: _wordWrap ? Axis.vertical : Axis.horizontal,
            child: HighlightView(
              widget.code,
              language: widget.language.isEmpty ? 'text' : widget.language,
              theme: theme,
              textStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: _fontSize,
                height: 1.5,
              ),
            ),
          ),
        ),
      );
    }
  }
}

/// 移动端代码查看页面
class _CodeViewPage extends StatefulWidget {
  final String code;
  final String language;

  const _CodeViewPage({
    required this.code,
    required this.language,
  });

  @override
  State<_CodeViewPage> createState() => _CodeViewPageState();
}

class _CodeViewPageState extends State<_CodeViewPage> {
  late LanguageConfig _config;
  double _fontSize = 13.0;

  @override
  void initState() {
    super.initState();
    _config = LanguageConfig.getConfig(widget.language);
  }

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) {
      showAppSnackBar(
        context,
        message: 'Copied to clipboard',
        type: NotificationType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = isDark ? atomOneDarkReasonableTheme : githubTheme;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _config.accentColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                _config.icon,
                size: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Text(_config.displayName),
          ],
        ),
        actions: [
          // 字体大小
          IconButton(
            onPressed: _fontSize > 10 ? () => setState(() => _fontSize -= 1) : null,
            icon: const Icon(Lucide.Minus, size: 16),
          ),
          IconButton(
            onPressed: _fontSize < 20 ? () => setState(() => _fontSize += 1) : null,
            icon: const Icon(Lucide.Plus, size: 16),
          ),
          // 复制
          IconButton(
            onPressed: _handleCopy,
            icon: const Icon(Lucide.Copy, size: 18),
          ),
        ],
      ),
      body: Container(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFAFAFA),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: HighlightView(
            widget.code,
            language: widget.language.isEmpty ? 'text' : widget.language,
            theme: theme,
            textStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: _fontSize,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// 工具栏切换按钮
class _ToolbarToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onToggle;

  const _ToolbarToggle({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Material(
      color: isActive ? cs.primary.withOpacity(0.15) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
