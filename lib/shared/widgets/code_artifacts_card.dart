import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:simple_icons/simple_icons.dart';
import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import 'snackbar.dart';
import '../../utils/text_file_exporter.dart';

/// 语言配置：图标和显示名
class LanguageConfig {
  final IconData icon;
  final String displayName;
  final Color accentColor;
  
  const LanguageConfig({
    required this.icon,
    required this.displayName,
    required this.accentColor,
  });
  
  static LanguageConfig getConfig(String language) {
    final lang = language.toLowerCase();
    
    // 语言配置映射 - 使用 Simple Icons 品牌图标 + Lucide 通用图标
    final configs = <String, LanguageConfig>{
      // Web
      'html': LanguageConfig(
        icon: SimpleIcons.html5,
        displayName: 'HTML',
        accentColor: const Color(0xFFE44D26),
      ),
      'css': LanguageConfig(
        icon: SimpleIcons.css3,
        displayName: 'CSS',
        accentColor: const Color(0xFF264DE4),
      ),
      'scss': LanguageConfig(
        icon: SimpleIcons.sass,
        displayName: 'SCSS',
        accentColor: const Color(0xFFCC6699),
      ),
      'sass': LanguageConfig(
        icon: SimpleIcons.sass,
        displayName: 'Sass',
        accentColor: const Color(0xFFCC6699),
      ),
      'less': LanguageConfig(
        icon: SimpleIcons.less,
        displayName: 'Less',
        accentColor: const Color(0xFF1D365D),
      ),
      
      // JavaScript 系列
      'javascript': LanguageConfig(
        icon: SimpleIcons.javascript,
        displayName: 'JavaScript',
        accentColor: const Color(0xFFF7DF1E),
      ),
      'js': LanguageConfig(
        icon: SimpleIcons.javascript,
        displayName: 'JavaScript',
        accentColor: const Color(0xFFF7DF1E),
      ),
      'jsx': LanguageConfig(
        icon: SimpleIcons.react,
        displayName: 'JSX',
        accentColor: const Color(0xFF61DAFB),
      ),
      'typescript': LanguageConfig(
        icon: SimpleIcons.typescript,
        displayName: 'TypeScript',
        accentColor: const Color(0xFF3178C6),
      ),
      'ts': LanguageConfig(
        icon: SimpleIcons.typescript,
        displayName: 'TypeScript',
        accentColor: const Color(0xFF3178C6),
      ),
      'tsx': LanguageConfig(
        icon: SimpleIcons.react,
        displayName: 'TSX',
        accentColor: const Color(0xFF61DAFB),
      ),
      'react': LanguageConfig(
        icon: SimpleIcons.react,
        displayName: 'React',
        accentColor: const Color(0xFF61DAFB),
      ),
      'vue': LanguageConfig(
        icon: SimpleIcons.vuedotjs,
        displayName: 'Vue',
        accentColor: const Color(0xFF4FC08D),
      ),
      'svelte': LanguageConfig(
        icon: SimpleIcons.svelte,
        displayName: 'Svelte',
        accentColor: const Color(0xFFFF3E00),
      ),
      'angular': LanguageConfig(
        icon: SimpleIcons.angular,
        displayName: 'Angular',
        accentColor: const Color(0xFFDD0031),
      ),
      'node': LanguageConfig(
        icon: SimpleIcons.nodedotjs,
        displayName: 'Node.js',
        accentColor: const Color(0xFF339933),
      ),
      
      // 编程语言
      'python': LanguageConfig(
        icon: SimpleIcons.python,
        displayName: 'Python',
        accentColor: const Color(0xFF3776AB),
      ),
      'py': LanguageConfig(
        icon: SimpleIcons.python,
        displayName: 'Python',
        accentColor: const Color(0xFF3776AB),
      ),
      'dart': LanguageConfig(
        icon: SimpleIcons.dart,
        displayName: 'Dart',
        accentColor: const Color(0xFF0175C2),
      ),
      'flutter': LanguageConfig(
        icon: SimpleIcons.flutter,
        displayName: 'Flutter',
        accentColor: const Color(0xFF02569B),
      ),
      'java': LanguageConfig(
        icon: Lucide.FileCode, // Simple Icons 没有 Java
        displayName: 'Java',
        accentColor: const Color(0xFFB07219),
      ),
      'kotlin': LanguageConfig(
        icon: SimpleIcons.kotlin,
        displayName: 'Kotlin',
        accentColor: const Color(0xFF7F52FF),
      ),
      'swift': LanguageConfig(
        icon: SimpleIcons.swift,
        displayName: 'Swift',
        accentColor: const Color(0xFFFA7343),
      ),
      'rust': LanguageConfig(
        icon: SimpleIcons.rust,
        displayName: 'Rust',
        accentColor: const Color(0xFF000000),
      ),
      'go': LanguageConfig(
        icon: SimpleIcons.go,
        displayName: 'Go',
        accentColor: const Color(0xFF00ADD8),
      ),
      'golang': LanguageConfig(
        icon: SimpleIcons.go,
        displayName: 'Go',
        accentColor: const Color(0xFF00ADD8),
      ),
      'c': LanguageConfig(
        icon: SimpleIcons.c,
        displayName: 'C',
        accentColor: const Color(0xFFA8B9CC),
      ),
      'cpp': LanguageConfig(
        icon: SimpleIcons.cplusplus,
        displayName: 'C++',
        accentColor: const Color(0xFF00599C),
      ),
      'c++': LanguageConfig(
        icon: SimpleIcons.cplusplus,
        displayName: 'C++',
        accentColor: const Color(0xFF00599C),
      ),
      'csharp': LanguageConfig(
        icon: Lucide.FileCode, // Simple Icons 没有 C#
        displayName: 'C#',
        accentColor: const Color(0xFF239120),
      ),
      'cs': LanguageConfig(
        icon: Lucide.FileCode, // Simple Icons 没有 C#
        displayName: 'C#',
        accentColor: const Color(0xFF239120),
      ),
      'php': LanguageConfig(
        icon: SimpleIcons.php,
        displayName: 'PHP',
        accentColor: const Color(0xFF777BB4),
      ),
      'ruby': LanguageConfig(
        icon: SimpleIcons.ruby,
        displayName: 'Ruby',
        accentColor: const Color(0xFFCC342D),
      ),
      'r': LanguageConfig(
        icon: SimpleIcons.r,
        displayName: 'R',
        accentColor: const Color(0xFF276DC3),
      ),
      'lua': LanguageConfig(
        icon: SimpleIcons.lua,
        displayName: 'Lua',
        accentColor: const Color(0xFF2C2D72),
      ),
      'perl': LanguageConfig(
        icon: SimpleIcons.perl,
        displayName: 'Perl',
        accentColor: const Color(0xFF39457E),
      ),
      'haskell': LanguageConfig(
        icon: SimpleIcons.haskell,
        displayName: 'Haskell',
        accentColor: const Color(0xFF5D4F85),
      ),
      'scala': LanguageConfig(
        icon: SimpleIcons.scala,
        displayName: 'Scala',
        accentColor: const Color(0xFFDC322F),
      ),
      'elixir': LanguageConfig(
        icon: SimpleIcons.elixir,
        displayName: 'Elixir',
        accentColor: const Color(0xFF4B275F),
      ),
      'clojure': LanguageConfig(
        icon: SimpleIcons.clojure,
        displayName: 'Clojure',
        accentColor: const Color(0xFF5881D8),
      ),
      'erlang': LanguageConfig(
        icon: SimpleIcons.erlang,
        displayName: 'Erlang',
        accentColor: const Color(0xFFA90533),
      ),
      'zig': LanguageConfig(
        icon: SimpleIcons.zig,
        displayName: 'Zig',
        accentColor: const Color(0xFFF7A41D),
      ),
      
      // 数据格式
      'json': LanguageConfig(
        icon: SimpleIcons.json,
        displayName: 'JSON',
        accentColor: const Color(0xFF000000),
      ),
      'yaml': LanguageConfig(
        icon: SimpleIcons.yaml,
        displayName: 'YAML',
        accentColor: const Color(0xFFCB171E),
      ),
      'yml': LanguageConfig(
        icon: SimpleIcons.yaml,
        displayName: 'YAML',
        accentColor: const Color(0xFFCB171E),
      ),
      'xml': LanguageConfig(
        icon: Lucide.FileCode,
        displayName: 'XML',
        accentColor: const Color(0xFF0060AC),
      ),
      'toml': LanguageConfig(
        icon: SimpleIcons.toml,
        displayName: 'TOML',
        accentColor: const Color(0xFF9C4121),
      ),
      
      // Markdown
      'markdown': LanguageConfig(
        icon: SimpleIcons.markdown,
        displayName: 'Markdown',
        accentColor: const Color(0xFF000000),
      ),
      'md': LanguageConfig(
        icon: SimpleIcons.markdown,
        displayName: 'Markdown',
        accentColor: const Color(0xFF000000),
      ),
      
      // 数据库
      'sql': LanguageConfig(
        icon: Lucide.Database,
        displayName: 'SQL',
        accentColor: const Color(0xFFE38C00),
      ),
      'mysql': LanguageConfig(
        icon: SimpleIcons.mysql,
        displayName: 'MySQL',
        accentColor: const Color(0xFF4479A1),
      ),
      'postgresql': LanguageConfig(
        icon: SimpleIcons.postgresql,
        displayName: 'PostgreSQL',
        accentColor: const Color(0xFF4169E1),
      ),
      'mongodb': LanguageConfig(
        icon: SimpleIcons.mongodb,
        displayName: 'MongoDB',
        accentColor: const Color(0xFF47A248),
      ),
      'redis': LanguageConfig(
        icon: SimpleIcons.redis,
        displayName: 'Redis',
        accentColor: const Color(0xFFDC382D),
      ),
      
      // Shell
      'shell': LanguageConfig(
        icon: SimpleIcons.gnubash,
        displayName: 'Shell',
        accentColor: const Color(0xFF4EAA25),
      ),
      'bash': LanguageConfig(
        icon: SimpleIcons.gnubash,
        displayName: 'Bash',
        accentColor: const Color(0xFF4EAA25),
      ),
      'sh': LanguageConfig(
        icon: SimpleIcons.gnubash,
        displayName: 'Shell',
        accentColor: const Color(0xFF4EAA25),
      ),
      'zsh': LanguageConfig(
        icon: SimpleIcons.zsh,
        displayName: 'Zsh',
        accentColor: const Color(0xFFF15A24),
      ),
      'powershell': LanguageConfig(
        icon: SimpleIcons.gnubash, // PowerShell 使用 bash 图标作为替代
        displayName: 'PowerShell',
        accentColor: const Color(0xFF5391FE),
      ),
      'fish': LanguageConfig(
        icon: Lucide.Terminal,
        displayName: 'Fish',
        accentColor: const Color(0xFF4AAE46),
      ),
      
      // DevOps
      'dockerfile': LanguageConfig(
        icon: SimpleIcons.docker,
        displayName: 'Dockerfile',
        accentColor: const Color(0xFF2496ED),
      ),
      'docker': LanguageConfig(
        icon: SimpleIcons.docker,
        displayName: 'Docker',
        accentColor: const Color(0xFF2496ED),
      ),
      'kubernetes': LanguageConfig(
        icon: SimpleIcons.kubernetes,
        displayName: 'Kubernetes',
        accentColor: const Color(0xFF326CE5),
      ),
      'terraform': LanguageConfig(
        icon: SimpleIcons.terraform,
        displayName: 'Terraform',
        accentColor: const Color(0xFF7B42BC),
      ),
      'nginx': LanguageConfig(
        icon: SimpleIcons.nginx,
        displayName: 'Nginx',
        accentColor: const Color(0xFF009639),
      ),
      
      // API
      'graphql': LanguageConfig(
        icon: SimpleIcons.graphql,
        displayName: 'GraphQL',
        accentColor: const Color(0xFFE10098),
      ),
      'protobuf': LanguageConfig(
        icon: Lucide.FileCode,
        displayName: 'Protobuf',
        accentColor: const Color(0xFF4285F4),
      ),
      
      // 其他
      'regex': LanguageConfig(
        icon: Lucide.Regex,
        displayName: 'Regex',
        accentColor: const Color(0xFF000000),
      ),
      'latex': LanguageConfig(
        icon: SimpleIcons.latex,
        displayName: 'LaTeX',
        accentColor: const Color(0xFF008080),
      ),
      'tex': LanguageConfig(
        icon: SimpleIcons.latex,
        displayName: 'TeX',
        accentColor: const Color(0xFF008080),
      ),
      'vim': LanguageConfig(
        icon: SimpleIcons.vim,
        displayName: 'Vim',
        accentColor: const Color(0xFF019733),
      ),
      'git': LanguageConfig(
        icon: SimpleIcons.git,
        displayName: 'Git',
        accentColor: const Color(0xFFF05032),
      ),
    };
    
    return configs[lang] ?? LanguageConfig(
      icon: Lucide.Code,
      displayName: lang.isNotEmpty ? lang.toUpperCase() : 'CODE',
      accentColor: const Color(0xFF6366F1),
    );
  }
}

/// Code Artifacts Card - 通用代码块卡片
/// 
/// 功能：
/// 1. 流式生成时显示终端效果（最后3行代码 + 闪烁光标）
/// 2. 生成完成显示操作按钮
/// 3. 支持所有语言，根据语言显示不同图标和颜色
class CodeArtifactsCard extends StatefulWidget {
  final String code;
  final String language;
  final bool isStreaming;
  final VoidCallback? onPreview;
  final bool canRenderPreview; // 是否支持渲染预览（如 HTML）

  const CodeArtifactsCard({
    super.key,
    required this.code,
    required this.language,
    this.isStreaming = false,
    this.onPreview,
    this.canRenderPreview = false,
  });

  @override
  State<CodeArtifactsCard> createState() => _CodeArtifactsCardState();
}

class _CodeArtifactsCardState extends State<CodeArtifactsCard> {
  late LanguageConfig _config;
  
  @override
  void initState() {
    super.initState();
    _config = LanguageConfig.getConfig(widget.language);
  }
  
  @override
  void didUpdateWidget(covariant CodeArtifactsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      _config = LanguageConfig.getConfig(widget.language);
    }
  }

  /// 提取标题（HTML 从 <title>，其他用语言名）
  String _extractTitle() {
    if (widget.language.toLowerCase() == 'html') {
      final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false)
          .firstMatch(widget.code);
      if (titleMatch != null && titleMatch.group(1)!.trim().isNotEmpty) {
        return titleMatch.group(1)!.trim();
      }
    }
    return '${_config.displayName} Code';
  }

  /// 获取文件扩展名
  String _getFileExtension() {
    final lang = widget.language.toLowerCase();
    const extensions = {
      'javascript': 'js',
      'typescript': 'ts',
      'python': 'py',
      'csharp': 'cs',
      'c++': 'cpp',
      'markdown': 'md',
      'shell': 'sh',
      'powershell': 'ps1',
    };
    return extensions[lang] ?? lang;
  }

  /// 下载代码文件
  Future<void> _handleDownload() async {
    try {
      final ext = _getFileExtension();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'code_$timestamp.$ext';
      final saved = await saveTextToDocuments(fileName: fileName, content: widget.code);
      
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

  /// 复制代码到剪贴板
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

  /// 在外部打开（仅 HTML）
  Future<void> _handleOpenExternal() async {
    if (widget.language.toLowerCase() != 'html') return;
    
    try {
      await openHtmlExternally(htmlContent: widget.code);
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
    final lines = widget.code.split('\n');
    final start = lines.length > n ? lines.length - n : 0;
    return lines.skip(start).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _extractTitle();
    final hasContent = widget.code.trim().isNotEmpty;
    final isHtml = widget.language.toLowerCase() == 'html';

    // 主题色：流式时橙色，完成时使用语言颜色
    final iconGradient = widget.isStreaming
        ? const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              _config.accentColor,
              HSLColor.fromColor(_config.accentColor)
                  .withLightness(
                    (HSLColor.fromColor(_config.accentColor).lightness - 0.1)
                        .clamp(0.0, 1.0),
                  )
                  .toColor(),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    final headerBg = Color.alphaBlend(
      _config.accentColor.withOpacity(isDark ? 0.12 : 0.08),
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
                            : _config.accentColor).withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.isStreaming ? Lucide.Sparkles : _config.icon,
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
                              _config.displayName,
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
                    icon: Icon(isHtml ? Lucide.Eye : Lucide.Code, size: 16),
                    label: Text(isHtml ? l10n.codeCardPreview : l10n.codeCardView),
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
                    icon: Icon(
                      widget.canRenderPreview ? Lucide.Eye : Lucide.Code,
                      size: 14,
                    ),
                    label: Text(widget.canRenderPreview ? l10n.codeCardPreview : l10n.codeCardView),
                  ),
                  TextButton.icon(
                    onPressed: hasContent ? _handleCopy : null,
                    icon: const Icon(Lucide.Copy, size: 14),
                    label: Text(l10n.codeCardCopy),
                  ),
                  if (isHtml)
                    TextButton.icon(
                      onPressed: hasContent ? _handleOpenExternal : null,
                      icon: const Icon(Lucide.ExternalLink, size: 14),
                      label: Text(l10n.codeCardOpen),
                    ),
                  TextButton.icon(
                    onPressed: hasContent ? _handleDownload : null,
                    icon: const Icon(Lucide.Download, size: 14),
                    label: Text(l10n.codeCardDownload),
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
