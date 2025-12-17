import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../icons/lucide_adapter.dart';
import 'snackbar.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/text_file_exporter.dart';

/// HTML Artifacts Card - Cherry Studio 风格的 HTML 代码块卡片
/// 
/// 功能：
/// 1. 流式生成时显示终端效果（最后3行代码 + 闪烁光标）
/// 2. 生成完成显示操作按钮：Preview、外部浏览器、下载
/// 3. 精美的卡片设计：Header + Content 区域
class HtmlArtifactsCard extends StatefulWidget {
  final String html;
  final bool isStreaming;
  final VoidCallback? onPreview;

  const HtmlArtifactsCard({
    super.key,
    required this.html,
    this.isStreaming = false,
    this.onPreview,
  });

  @override
  State<HtmlArtifactsCard> createState() => _HtmlArtifactsCardState();
}

class _HtmlArtifactsCardState extends State<HtmlArtifactsCard> {
  /// 提取 HTML 标题（从 <title> 标签）
  String _extractTitle() {
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false)
        .firstMatch(widget.html);
    if (titleMatch != null && titleMatch.group(1)!.trim().isNotEmpty) {
      return titleMatch.group(1)!.trim();
    }
    return 'HTML Artifacts';
  }

  /// 获取文件名（基于标题）
  String _getFileName() {
    final title = _extractTitle();
    // 清理标题作为文件名
    final cleaned = title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'html_artifact' : cleaned;
  }

  /// 下载 HTML 文件
  Future<void> _handleDownload() async {
    try {
      final fileName = '${_getFileName()}.html';
      final saved = await saveTextToDocuments(fileName: fileName, content: widget.html);
      
      if (mounted) {
        showAppSnackBar(
          context,
          message: kIsWeb ? 'Downloaded $fileName' : 'Saved to $saved',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Failed to save: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  /// 在外部浏览器中打开
  Future<void> _handleOpenExternal() async {
    try {
      await openHtmlExternally(htmlContent: widget.html);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Failed to open: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  /// 获取最后N行代码（用于终端显示）
  String _getLastLines(int n) {
    final lines = widget.html.split('\n');
    final start = lines.length > n ? lines.length - n : 0;
    return lines.skip(start).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _extractTitle();
    final hasContent = widget.html.trim().isNotEmpty;

    // 主题色：流式时橙色，完成时蓝色
    final iconGradient = widget.isStreaming
        ? const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    final headerBg = Color.alphaBlend(
      cs.primary.withOpacity(isDark ? 0.12 : 0.08),
      cs.surface,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Icon + Title + Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.3),
                  width: 1,
                ),
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                // 图标容器
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: iconGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (widget.isStreaming
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF3B82F6)).withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.isStreaming ? Lucide.Sparkles : Lucide.Globe,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                // 标题和徽章
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Ubuntu',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceVariant,
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Lucide.Code,
                              size: 10,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'HTML',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content: 终端效果 或 按钮区
          if (widget.isStreaming && !hasContent)
            // 加载中状态
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Generating content...',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else if (widget.isStreaming && hasContent)
            // 流式生成：终端效果
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '\$',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF00FF00) : const Color(0xFF007700),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Text(
                                _getLastLines(3),
                                style: TextStyle(
                                  color: isDark ? const Color(0xFFCCCCCC) : const Color(0xFF333333),
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                                softWrap: true,
                              ),
                            ),
                            const _BlinkingCursor(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: FilledButton.icon(
                    onPressed: hasContent ? widget.onPreview : null,
                    icon: const Icon(Lucide.Code, size: 16),
                    label: const Text('Preview'),
                  ),
                ),
              ],
            )
          else
            // 完成状态：操作按钮（响应式布局）
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: hasContent ? widget.onPreview : null,
                    icon: const Icon(Lucide.Code, size: 14),
                    label: const Text('Preview'),
                  ),
                  TextButton.icon(
                    onPressed: hasContent ? _handleOpenExternal : null,
                    icon: const Icon(Lucide.ExternalLink, size: 14),
                    label: const Text('Open'),
                  ),
                  TextButton.icon(
                    onPressed: hasContent ? _handleDownload : null,
                    icon: const Icon(Lucide.Download, size: 14),
                    label: const Text('Download'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 闪烁光标组件
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 16,
        margin: const EdgeInsets.only(left: 2),
        color: isDark ? const Color(0xFF00FF00) : const Color(0xFF007700),
      ),
    );
  }
}
