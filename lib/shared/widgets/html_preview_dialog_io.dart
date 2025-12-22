// IO implementation (mobile/desktop)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../icons/lucide_adapter.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark-reasonable.dart';
import 'code_artifacts_card.dart' show LanguageConfig;
import 'snackbar.dart';

// Platform-specific WebView imports
import 'package:webview_flutter/webview_flutter.dart' if (dart.library.html) 'package:webview_flutter_web/webview_flutter_web.dart';
import 'package:webview_windows/webview_windows.dart' as winweb;

/// 显示 HTML 预览对话框/页面（保留向后兼容）
Future<void> showHtmlPreviewDialog(BuildContext context, String html) {
  return showCodePreviewDialog(
    context,
    code: html,
    language: 'html',
    canRenderPreview: true,
    previewHtml: html,
  );
}

/// 显示通用代码预览对话框
///
/// [code] - 原始代码
/// [language] - 语言类型
/// [canRenderPreview] - 是否支持渲染预览
/// [previewHtml] - 用于预览的 HTML（仅当 canRenderPreview=true 时需要）
Future<void> showCodePreviewDialog(
  BuildContext context, {
  required String code,
  required String language,
  required bool canRenderPreview,
  String? previewHtml,
}) {
  final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  if (isDesktop) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _CodePreviewDialog(
        code: code,
        language: language,
        canRenderPreview: canRenderPreview,
        previewHtml: previewHtml ?? code,
      ),
    );
  } else {
    return Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _CodePreviewPage(
          code: code,
          language: language,
          canRenderPreview: canRenderPreview,
          previewHtml: previewHtml ?? code,
        ),
      ),
    );
  }
}

/// 视图模式枚举
enum _ViewMode { split, code, preview }

/// 桌面端通用代码预览 Dialog
class _CodePreviewDialog extends StatefulWidget {
  final String code;
  final String language;
  final bool canRenderPreview;
  final String previewHtml;

  const _CodePreviewDialog({
    required this.code,
    required this.language,
    required this.canRenderPreview,
    required this.previewHtml,
  });

  @override
  State<_CodePreviewDialog> createState() => _CodePreviewDialogState();
}

class _CodePreviewDialogState extends State<_CodePreviewDialog> {
  late _ViewMode _viewMode;
  late LanguageConfig _config;
  winweb.WebviewController? _winCtrl;
  WebViewController? _flutterCtrl;
  bool _isLoading = true;
  double _fontSize = 13.0;
  bool _wordWrap = false;

  @override
  void initState() {
    super.initState();
    _config = LanguageConfig.getConfig(widget.language);
    // 可预览时默认显示预览，否则只显示源码
    _viewMode = widget.canRenderPreview ? _ViewMode.preview : _ViewMode.code;
    if (widget.canRenderPreview) {
      _initWebView();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _initWebView() async {
    if (Platform.isWindows) {
      _winCtrl = winweb.WebviewController();
      await _winCtrl!.initialize();
      await _winCtrl!.loadStringContent(widget.previewHtml);
    } else {
      _flutterCtrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (url) {
              setState(() => _isLoading = false);
            },
          ),
        )
        ..loadHtmlString(widget.previewHtml);
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _winCtrl?.dispose();
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
    final screenSize = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: screenSize.width * 0.9,
          height: screenSize.height * 0.85,
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            children: [
              // Header
              _buildHeader(cs, isDark),

              // Toolbar (仅源码模式显示)
              if (_viewMode == _ViewMode.code || _viewMode == _ViewMode.split)
                _buildToolbar(cs),

              // Content
              Expanded(child: _buildContent(cs, isDark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    final lineCount = widget.code.split('\n').length;
    final charCount = widget.code.length;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHighest : cs.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          // 语言图标
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _config.accentColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(_config.icon, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 10),

          // 语言名称
          Text(
            _config.displayName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),

          // 分隔点
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('·', style: TextStyle(color: cs.onSurfaceVariant)),
          ),

          // 行数和字符数
          Text(
            '$lineCount lines · $charCount chars',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),

          const Spacer(),

          // 视图模式切换（仅当可预览时显示）
          if (widget.canRenderPreview) ...[
            _CompactModeSwitch(
              viewMode: _viewMode,
              onChanged: (mode) => setState(() => _viewMode = mode),
            ),
            const SizedBox(width: 8),
          ],

          // 复制按钮
          _HeaderIconButton(
            icon: Lucide.Copy,
            tooltip: '复制',
            onPressed: _handleCopy,
          ),

          // 关闭按钮
          _HeaderIconButton(
            icon: Lucide.X,
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? cs.surface : cs.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2)),
        ),
      ),
      child: Row(
        children: [
          // 自动换行开关
          _MiniToggle(
            label: '换行',
            isActive: _wordWrap,
            onTap: () => setState(() => _wordWrap = !_wordWrap),
          ),

          const Spacer(),

          // 字体大小调节
          _MiniIconButton(
            icon: Lucide.Minus,
            onPressed: _fontSize > 10 ? () => setState(() => _fontSize -= 1) : null,
          ),
          Container(
            width: 36,
            alignment: Alignment.center,
            child: Text(
              '${_fontSize.toInt()}',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ),
          _MiniIconButton(
            icon: Lucide.Plus,
            onPressed: _fontSize < 20 ? () => setState(() => _fontSize += 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, bool isDark) {
    // 不可预览时始终显示源码
    if (!widget.canRenderPreview) {
      return _buildCodeView(cs, isDark);
    }

    switch (_viewMode) {
      case _ViewMode.split:
        return Row(
          children: [
            Expanded(child: _buildCodeView(cs, isDark)),
            Container(
              width: 1,
              color: cs.outlineVariant.withOpacity(0.5),
            ),
            Expanded(child: _buildWebView(cs)),
          ],
        );
      case _ViewMode.code:
        return _buildCodeView(cs, isDark);
      case _ViewMode.preview:
        return _buildWebView(cs);
    }
  }

  Widget _buildCodeView(ColorScheme cs, bool isDark) {
    final theme = isDark ? atomOneDarkReasonableTheme : githubTheme;
    final lines = widget.code.split('\n');
    final lineNumberWidth = '${lines.length}'.length * 10.0 + 24;

    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFAFAFA),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行号列
          Container(
            width: lineNumberWidth,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF252526) : const Color(0xFFEEEEEE),
              border: Border(
                right: BorderSide(
                  color: isDark ? const Color(0xFF3C3C3C) : const Color(0xFFDDDDDD),
                ),
              ),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: List.generate(lines.length, (i) {
                    return Container(
                      height: _fontSize * 1.6,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: _fontSize,
                          fontFamily: 'JetBrains Mono, Consolas, monospace',
                          color: isDark
                              ? const Color(0xFF858585)
                              : const Color(0xFF999999),
                          height: 1.6,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),

          // 代码内容（可选择）
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: _wordWrap ? Axis.vertical : Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: HighlightView(
                      widget.code,
                      language: widget.language.isEmpty ? 'text' : widget.language,
                      theme: theme,
                      textStyle: TextStyle(
                        fontFamily: 'JetBrains Mono, Consolas, monospace',
                        fontSize: _fontSize,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView(ColorScheme cs) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: cs.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading preview...',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Platform.isWindows
          ? (_winCtrl != null
              ? winweb.Webview(_winCtrl!)
              : const Center(child: Text('WebView not available')))
          : (_flutterCtrl != null
              ? WebViewWidget(controller: _flutterCtrl!)
              : const Center(child: Text('WebView not available'))),
    );
  }
}

/// Header 图标按钮（紧凑）
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// 紧凑的视图模式切换
class _CompactModeSwitch extends StatelessWidget {
  final _ViewMode viewMode;
  final ValueChanged<_ViewMode> onChanged;

  const _CompactModeSwitch({
    required this.viewMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: isDark ? cs.surface : cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeTab(
            icon: Lucide.Columns2,
            isActive: viewMode == _ViewMode.split,
            onTap: () => onChanged(_ViewMode.split),
          ),
          _ModeTab(
            icon: Lucide.Code,
            isActive: viewMode == _ViewMode.code,
            onTap: () => onChanged(_ViewMode.code),
          ),
          _ModeTab(
            icon: Lucide.Eye,
            isActive: viewMode == _ViewMode.preview,
            onTap: () => onChanged(_ViewMode.preview),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeTab({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 28,
        decoration: BoxDecoration(
          color: isActive ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(
          icon,
          size: 14,
          color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 迷你开关
class _MiniToggle extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _MiniToggle({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? cs.primary.withOpacity(0.3) : cs.outlineVariant.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 迷你图标按钮
class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _MiniIconButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 12,
          color: onPressed != null ? cs.onSurfaceVariant : cs.onSurfaceVariant.withOpacity(0.3),
        ),
      ),
    );
  }
}

/// 移动端通用代码预览页面
class _CodePreviewPage extends StatefulWidget {
  final String code;
  final String language;
  final bool canRenderPreview;
  final String previewHtml;

  const _CodePreviewPage({
    required this.code,
    required this.language,
    required this.canRenderPreview,
    required this.previewHtml,
  });

  @override
  State<_CodePreviewPage> createState() => _CodePreviewPageState();
}

class _CodePreviewPageState extends State<_CodePreviewPage> {
  late _ViewMode _viewMode;
  late LanguageConfig _config;
  WebViewController? _controller;
  bool _isLoading = true;
  double _fontSize = 13.0;

  @override
  void initState() {
    super.initState();
    _config = LanguageConfig.getConfig(widget.language);
    // 可预览时默认显示预览，否则只显示源码
    _viewMode = widget.canRenderPreview ? _ViewMode.preview : _ViewMode.code;
    if (widget.canRenderPreview) {
      _initWebView();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _initWebView() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadHtmlString(widget.previewHtml);
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _config.accentColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: _config.accentColor.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                _config.icon,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _config.displayName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${widget.code.split('\n').length} lines',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // 字体大小调节
          if (_viewMode == _ViewMode.code) ...[
            IconButton(
              icon: const Icon(Lucide.Minus, size: 18),
              onPressed: _fontSize > 10 ? () => setState(() => _fontSize -= 1) : null,
              tooltip: '缩小',
            ),
            IconButton(
              icon: const Icon(Lucide.Plus, size: 18),
              onPressed: _fontSize < 20 ? () => setState(() => _fontSize += 1) : null,
              tooltip: '放大',
            ),
          ],
          // 复制按钮
          IconButton(
            icon: const Icon(Lucide.Copy, size: 18),
            onPressed: _handleCopy,
            tooltip: '复制',
          ),
          // 视图模式切换按钮（仅当可预览时显示）
          if (widget.canRenderPreview)
            IconButton(
              icon: Icon(
                _viewMode == _ViewMode.code ? Lucide.Eye : Lucide.Code,
                size: 18,
              ),
              onPressed: () {
                setState(() {
                  _viewMode = _viewMode == _ViewMode.code
                      ? _ViewMode.preview
                      : _ViewMode.code;
                });
              },
              tooltip: _viewMode == _ViewMode.code ? '预览' : '源码',
            ),
        ],
      ),
      body: _viewMode == _ViewMode.code
          ? _buildCodeView(cs, isDark)
          : _buildWebView(cs),
    );
  }

  Widget _buildCodeView(ColorScheme cs, bool isDark) {
    final theme = isDark ? atomOneDarkReasonableTheme : githubTheme;
    final lines = widget.code.split('\n');
    final lineNumberWidth = '${lines.length}'.length * 10.0 + 24;

    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFAFAFA),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行号列
          Container(
            width: lineNumberWidth,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF252526) : const Color(0xFFEEEEEE),
              border: Border(
                right: BorderSide(
                  color: isDark ? const Color(0xFF3C3C3C) : const Color(0xFFDDDDDD),
                ),
              ),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: List.generate(lines.length, (i) {
                    return Container(
                      height: _fontSize * 1.6,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: _fontSize,
                          fontFamily: 'JetBrains Mono, Consolas, monospace',
                          color: isDark
                              ? const Color(0xFF858585)
                              : const Color(0xFF999999),
                          height: 1.6,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),

          // 代码内容（可选择）
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: HighlightView(
                      widget.code,
                      language: widget.language.isEmpty ? 'text' : widget.language,
                      theme: theme,
                      textStyle: TextStyle(
                        fontFamily: 'JetBrains Mono, Consolas, monospace',
                        fontSize: _fontSize,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView(ColorScheme cs) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: cs.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading preview...',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: _controller != null
          ? WebViewWidget(controller: _controller!)
          : const Center(child: Text('WebView not available')),
    );
  }
}
