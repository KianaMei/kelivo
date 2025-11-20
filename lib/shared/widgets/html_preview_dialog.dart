import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../icons/lucide_adapter.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark-reasonable.dart';

// Platform-specific WebView imports
import 'package:webview_flutter/webview_flutter.dart' if (dart.library.html) 'package:webview_flutter_web/webview_flutter_web.dart';
import 'package:webview_windows/webview_windows.dart' as winweb;

/// 显示 HTML 预览对话框/页面
/// 
/// 桌面端：使用 Dialog 显示
/// 移动端：使用全屏页面（Navigator.push）
Future<void> showHtmlPreviewDialog(BuildContext context, String html) {
  final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  
  if (isDesktop) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _HtmlPreviewDialog(html: html),
    );
  } else {
    return Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _HtmlPreviewPage(html: html),
      ),
    );
  }
}

/// 视图模式枚举
enum _ViewMode { split, code, preview }

/// 桌面端预览 Dialog
class _HtmlPreviewDialog extends StatefulWidget {
  final String html;

  const _HtmlPreviewDialog({required this.html});

  @override
  State<_HtmlPreviewDialog> createState() => _HtmlPreviewDialogState();
}

class _HtmlPreviewDialogState extends State<_HtmlPreviewDialog> {
  _ViewMode _viewMode = _ViewMode.preview; // 默认只显示预览
  winweb.WebviewController? _winCtrl;
  WebViewController? _flutterCtrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    if (Platform.isWindows) {
      _winCtrl = winweb.WebviewController();
      await _winCtrl!.initialize();
      await _winCtrl!.loadStringContent(widget.html);
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
        ..loadHtmlString(widget.html);
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;
    
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: screenSize.width * 0.9,
        height: screenSize.height * 0.85,
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Column(
          children: [
            // Header: 标题 + 视图切换按钮 + 关闭按钮
            _buildHeader(cs),
            
            // Content: 根据视图模式显示
            Expanded(child: _buildContent(cs)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // 标题
          Expanded(
            child: Text(
              'HTML Preview',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
          ),
          
          // 视图模式切换按钮
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ViewButton(
                  icon: Lucide.Columns2,
                  label: 'Split',
                  isActive: _viewMode == _ViewMode.split,
                  onPressed: () => setState(() => _viewMode = _ViewMode.split),
                ),
                const SizedBox(width: 4),
                _ViewButton(
                  icon: Lucide.Code,
                  label: 'Code',
                  isActive: _viewMode == _ViewMode.code,
                  onPressed: () => setState(() => _viewMode = _ViewMode.code),
                ),
                const SizedBox(width: 4),
                _ViewButton(
                  icon: Lucide.Eye,
                  label: 'Preview',
                  isActive: _viewMode == _ViewMode.preview,
                  onPressed: () => setState(() => _viewMode = _ViewMode.preview),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 12),
          
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

  Widget _buildContent(ColorScheme cs) {
    switch (_viewMode) {
      case _ViewMode.split:
        return Row(
          children: [
            Expanded(child: _buildCodeView(cs)),
            VerticalDivider(width: 1, color: cs.outlineVariant),
            Expanded(child: _buildWebView(cs)),
          ],
        );
      case _ViewMode.code:
        return _buildCodeView(cs);
      case _ViewMode.preview:
        return _buildWebView(cs);
    }
  }

  Widget _buildCodeView(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      color: cs.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: HighlightView(
          widget.html,
          language: 'html',
          theme: isDark ? atomOneDarkReasonableTheme : githubTheme,
          padding: const EdgeInsets.all(12),
          textStyle: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildWebView(ColorScheme cs) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Loading preview...',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
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

/// 移动端全屏预览页面
class _HtmlPreviewPage extends StatefulWidget {
  final String html;

  const _HtmlPreviewPage({required this.html});

  @override
  State<_HtmlPreviewPage> createState() => _HtmlPreviewPageState();
}

class _HtmlPreviewPageState extends State<_HtmlPreviewPage> {
  _ViewMode _viewMode = _ViewMode.preview;
  WebViewController? _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
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
      ..loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('HTML Preview'),
        actions: [
          // 视图模式切换按钮（简化版）
          IconButton(
            icon: Icon(
              _viewMode == _ViewMode.code ? Lucide.Eye : Lucide.Code,
            ),
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == _ViewMode.code
                    ? _ViewMode.preview
                    : _ViewMode.code;
              });
            },
            tooltip: _viewMode == _ViewMode.code ? 'Preview' : 'Code',
          ),
        ],
      ),
      body: _viewMode == _ViewMode.code
          ? _buildCodeView(cs)
          : _buildWebView(cs),
    );
  }

  Widget _buildCodeView(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: HighlightView(
        widget.html,
        language: 'html',
        theme: isDark ? atomOneDarkReasonableTheme : githubTheme,
        padding: const EdgeInsets.all(12),
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildWebView(ColorScheme cs) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Loading preview...',
              style: TextStyle(color: cs.onSurfaceVariant),
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

/// 视图切换按钮组件
class _ViewButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  const _ViewButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Material(
      color: isActive ? cs.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
