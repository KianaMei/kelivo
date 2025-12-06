import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart' show GptMarkdownConfig;
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark-reasonable.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import '../../icons/lucide_adapter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import '../../features/chat/pages/image_viewer_page.dart';
import 'snackbar.dart';
import 'mermaid_bridge.dart';
import 'export_capture_scope.dart';
import 'mermaid_image_cache.dart';
import 'package:kelivo/l10n/app_localizations.dart';
import 'package:kelivo/theme/theme_factory.dart' show kDefaultFontFamilyFallback;
import 'package:provider/provider.dart';
import '../../core/providers/settings_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'html_artifacts_card.dart';
import 'html_preview_dialog.dart';
import 'code_artifacts_card.dart';
import 'code_runtime_templates.dart';

/// gpt_markdown with custom code block highlight and inline code styling.
class MarkdownWithCodeHighlight extends StatelessWidget {
  const MarkdownWithCodeHighlight({
    super.key,
    required this.text,
    this.onCitationTap,
    this.baseStyle,
    this.isStreaming = false, // Streaming state for special code blocks
  });

  final String text;
  final void Function(String id)? onCitationTap;
  final TextStyle? baseStyle; // optional override for base markdown text style
  final bool isStreaming; // Whether the message is currently streaming

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final imageUrls = _extractImageUrls(text);

    final normalized = _preprocessFences(text);
    // Base text style (can be overridden by caller)
    final baseTextStyle = (baseStyle ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
      fontSize: baseStyle?.fontSize ?? 15.5,
      height: baseStyle?.height ?? 1.55,
      letterSpacing: baseStyle?.letterSpacing ?? (_isZh(context) ? 0.0 : 0.05),
      color: null,
    );

    // Replace default components and add our own where needed
    final components = List<MarkdownComponent>.from(MarkdownComponent.globalComponents);
    final hrIdx = components.indexWhere((c) => c is HrLine);
    if (hrIdx != -1) components[hrIdx] = SoftHrLine();
    final bqIdx = components.indexWhere((c) => c is BlockQuote);
    if (bqIdx != -1) components[bqIdx] = ModernBlockQuote();
    final cbIdx = components.indexWhere((c) => c is CheckBoxMd);
    if (cbIdx != -1) components[cbIdx] = ModernCheckBoxMd();
    final rbIdx = components.indexWhere((c) => c is RadioButtonMd);
    if (rbIdx != -1) components[rbIdx] = ModernRadioMd();
    // Remove default FencedCodeBlock if exists (we'll replace with our custom one)
    components.removeWhere((c) {
      final typeName = c.runtimeType.toString();
      return typeName.contains('FencedCode') || typeName.contains('CodeBlock');
    });
    // Prepend custom renderers in priority order (fence first)
    components.insert(0, LabelValueLineMd());
    // Conditionally add LaTeX/math renderers
    if (settings.enableMathRendering) {
      // Block-level LaTeX (e.g., $$...$$ or \[...\])
      components.insert(0, LatexBlockScrollableMd());
      // Inline LaTeX: $...$ and \(...\)
      if (settings.enableDollarLatex) {
        components.insert(0, InlineLatexParenScrollableMd());
        components.insert(0, InlineLatexDollarScrollableMd());
      } else {
        // Only \(...\) inline
        components.insert(0, InlineLatexParenScrollableMd());
      }
    }
    components.insert(0, AtxHeadingMd());
    // Wrap FencedCodeBlockMd to provide streaming context
    components.insert(0, FencedCodeBlockMd(fullText: text, isStreaming: isStreaming));
    final markdownConfig = GptMarkdownConfig(
      textDirection: Directionality.of(context),
      style: baseTextStyle,
      followLinkColor: true,
      onLinkTap: (url, title) => _handleLinkTap(context, url),
      components: components,
      imageBuilder: (ctx, url) {
        // Check if this is a sticker
        final isSticker = url.startsWith('sticker://');

        final imgs = imageUrls.isNotEmpty ? imageUrls : [url];
        final idx = imgs.indexOf(url);
        final initial = idx >= 0 ? idx : 0;
        final provider = _imageProviderFor(url);

        // For stickers, render with size based on settings
        if (isSticker) {
          // Get sticker size from settings: 0=small(48), 1=medium(85), 2=large(120)
          final stickerSize = ctx.read<SettingsProvider>().stickerSize;
          final double size = switch (stickerSize) {
            0 => 48.0,
            2 => 120.0,
            _ => 85.0, // default medium
          };
          if (provider == null) return const SizedBox.shrink();
          
          // Wrap in GestureDetector for tap to view large in a popup
          return GestureDetector(
            onTap: () => _showStickerPopup(ctx, provider),
            child: Image(
              image: provider,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => Icon(Icons.broken_image, size: size),
            ),
          );
        }

        // For regular images, use the original logic with viewer
        return GestureDetector(
          onTap: () {
            Navigator.of(ctx).push(PageRouteBuilder(
              pageBuilder: (_, __, ___) => ImageViewerPage(images: imgs, initialIndex: initial),
              transitionDuration: const Duration(milliseconds: 360),
              reverseTransitionDuration: const Duration(milliseconds: 280),
              transitionsBuilder: (context, anim, sec, child) {
                final curved = CurvedAnimation(
                  parent: anim,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.02),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                );
              },
            ));
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final media = MediaQuery.of(context);
              final screenW = media.size.width;
              final bounded = constraints.hasBoundedWidth && constraints.maxWidth.isFinite;
              // Clamp to viewport width to satisfy Image size assertions
              final double w = (bounded ? constraints.maxWidth : screenW).clamp(0.0, screenW);
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: (provider == null)
                    ? const SizedBox.shrink()
                    : Image(
                  image: provider,
                  width: w,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Icon(Icons.broken_image),
                ),
              );
            },
          ),
        );
      },
      linkBuilder: (ctx, span, url, style) {
        final label = span.toPlainText().trim();
        // Special handling: [citation](index:id)
        if (label.toLowerCase() == 'citation') {
          final parts = url.split(':');
          if (parts.length == 2) {
            final indexText = parts[0].trim();
            final id = parts[1].trim();
            final cs = Theme.of(ctx).colorScheme;
            return GestureDetector(
              onTap: () {
                if (onCitationTap != null && id.isNotEmpty) {
                  onCitationTap!(id);
                } else {
                  // Fallback: do nothing
                }
              },
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  indexText,
                  style: const TextStyle(fontSize: 12, height: 1.0),
                ),
              ),
            );
          }
        }
        // Default link appearance
        final cs = Theme.of(ctx).colorScheme;
        return Text(
          span.toPlainText(),
          style: style.copyWith(
            color: cs.primary,
            decoration: TextDecoration.none,
          ),
          textAlign: TextAlign.start,
          textScaler: MediaQuery.of(ctx).textScaler,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        );
      },
      orderedListBuilder: (ctx, no, child, cfg) {
        final style = (cfg.style ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w400, // normal weight
        );
        return Directionality(
          textDirection: cfg.textDirection,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textBaseline: TextBaseline.alphabetic,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 6, end: 6),
                child: Text("$no.", style: style),
              ),
              Flexible(child: child),
            ],
          ),
        );
      },
      tableBuilder: (ctx, rows, style, cfg) {
        final cs = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final borderColor = cs.outlineVariant.withOpacity(isDark ? 0.22 : 0.28);
        final headerBg = Color.alphaBlend(
          cs.primary.withOpacity(isDark ? 0.14 : 0.08),
          cs.surface,
        );
        final headerStyle = (style).copyWith(fontWeight: FontWeight.w600, color: cs.onSurface);
        final cellStyle = (style).copyWith(color: cs.onSurface);

        int maxCol = 0;
        for (final r in rows) {
          if (r.fields.length > maxCol) maxCol = r.fields.length;
        }

        final bool isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

        Widget cell(String text, TextAlign align, {bool header = false, bool lastCol = false, bool lastRow = false}) {
          final innerCfg = cfg.copyWith(style: header ? headerStyle : cellStyle);
          final children = MarkdownComponent.generate(ctx, text, innerCfg, true);
          final Widget rich = isDesktop
              ? SelectableText.rich(
                  TextSpan(style: header ? headerStyle : cellStyle, children: children),
                  textAlign: align,
                  maxLines: null,
                )
              : RichText(
                  text: TextSpan(style: header ? headerStyle : cellStyle, children: children),
                  textAlign: align,
                  softWrap: true,
                  maxLines: null,
                  overflow: TextOverflow.visible,
                  textWidthBasis: TextWidthBasis.parent,
                );
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Align(
              alignment: () {
                switch (align) {
                  case TextAlign.center:
                    return Alignment.center;
                  case TextAlign.right:
                    return Alignment.centerRight;
                  default:
                    return Alignment.centerLeft;
                }
              }(),
              child: rich,
            ),
          );
        }

        if (!isDesktop) {
          final table = Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder(
              horizontalInside: BorderSide(color: borderColor, width: 0.5),
              verticalInside: BorderSide(color: borderColor, width: 0.5),
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              if (rows.isNotEmpty)
                TableRow(
                  decoration: BoxDecoration(color: headerBg),
                  children: List.generate(maxCol, (i) {
                    final f = i < rows.first.fields.length ? rows.first.fields[i] : null;
                    final txt = f?.data ?? '';
                    final align = f?.alignment ?? TextAlign.left;
                    return cell(txt, align, header: true, lastCol: i == maxCol - 1, lastRow: false);
                  }),
                ),
              for (int r = 1; r < rows.length; r++)
                TableRow(
                  children: List.generate(maxCol, (c) {
                    final f = c < rows[r].fields.length ? rows[r].fields[c] : null;
                    final txt = f?.data ?? '';
                    final align = f?.alignment ?? TextAlign.left;
                    return cell(txt, align, lastCol: c == maxCol - 1, lastRow: r == rows.length - 1);
                  }),
                ),
            ],
          );

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              primary: false,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: cs.onSurface),
                    child: table,
                  ),
                ),
              ),
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final columnWidths = <int, TableColumnWidth>{
              for (int i = 0; i < maxCol; i++) i: const FlexColumnWidth(),
            };

            final table = Table(
              defaultColumnWidth: const FlexColumnWidth(),
              columnWidths: columnWidths,
              border: TableBorder(
                horizontalInside: BorderSide(color: borderColor, width: 0.5),
                verticalInside: BorderSide(color: borderColor, width: 0.5),
              ),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                if (rows.isNotEmpty)
                  TableRow(
                    decoration: BoxDecoration(color: headerBg),
                    children: List.generate(maxCol, (i) {
                      final f = i < rows.first.fields.length ? rows.first.fields[i] : null;
                      final txt = f?.data ?? '';
                      final align = f?.alignment ?? TextAlign.left;
                      return cell(txt, align, header: true, lastCol: i == maxCol - 1, lastRow: false);
                    }),
                  ),
                for (int r = 1; r < rows.length; r++)
                  TableRow(
                    children: List.generate(maxCol, (c) {
                      final f = c < rows[r].fields.length ? rows[r].fields[c] : null;
                      final txt = f?.data ?? '';
                      final align = f?.alignment ?? TextAlign.left;
                      return cell(txt, align, lastCol: c == maxCol - 1, lastRow: r == rows.length - 1);
                    }),
                  ),
              ],
            );

            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: 0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: cs.onSurface),
                  child: table,
                ),
              ),
            );
          },
        );
      },
      // Inline `code` styling via highlightBuilder in gpt_markdown
      highlightBuilder: (ctx, inline, style) {
        final cs = Theme.of(ctx).colorScheme;
        final softened = _softBreakInline(inline);
        return Text(
          softened,
          style: MarkdownWithCodeHighlight._codeStyleBase(ctx, size: 13, height: 1.4)
              .copyWith(color: cs.onSurface),
          softWrap: true,
          overflow: TextOverflow.visible,
        );
      },
    );

    return ClipRRect(
      child: _SelectableMarkdownBody(
        markdownContext: context,
        text: normalized,
        config: markdownConfig,
      ),
    );
  }

  static bool _isZh(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return locale.languageCode.toLowerCase().startsWith('zh');
  }

  static String _preprocessFences(String input) {
    // Convert custom sticker tokens like [STICKER:nachoneko:26] into
    // markdown image syntax using a custom sticker scheme.
    final re = RegExp(r'\[STICKER:([a-zA-Z0-9_]+):(\d{1,3})\]', caseSensitive: false);
    return input.replaceAllMapped(re, (m) {
      final pack = m.group(1)!;
      final id = m.group(2)!;
      return '![sticker](sticker://$pack/$id)';
    });
  }

  static List<String> _extractImageUrls(String input) {
    final re = RegExp(r'(https?:\/\/[^\s)]+|file:[^\s)]+|data:image\/[^\s)]+|sticker:\/\/[^\s)]+)', caseSensitive: false);
    return re.allMatches(input).map((m) => m.group(0)!).toList();
  }

  static String _softBreakInline(String s) {
    return s.replaceAll('\n', ' ');
  }

  static Map<String, TextStyle> _transparentBgTheme(Map<String, TextStyle> base) {
    final root = (base['root'] ?? const TextStyle()).copyWith(backgroundColor: Colors.transparent);
    return {...base, 'root': root};
  }

  static String? _normalizeLanguage(String lang) {
    final l = lang.trim().toLowerCase();
    if (l.isEmpty) return null;
    switch (l) {
      case 'js':
      case 'javascript':
      case 'node':
      case 'nodejs':
        return 'javascript';
      case 'ts':
      case 'typescript':
        return 'typescript';
      case 'shell':
      case 'bash':
      case 'sh':
        return 'bash';
      case 'py':
      case 'python':
        return 'python';
      case 'dart':
        return 'dart';
      case 'json':
        return 'json';
      case 'yml':
      case 'yaml':
        return 'yaml';
      case 'md':
      case 'markdown':
        return 'markdown';
      default:
        return l;
    }
  }

  static String _displayLanguage(BuildContext ctx, String lang) {
    final n = _normalizeLanguage(lang) ?? 'text';
    return n;
  }

  /// Show sticker in a simple popup dialog
  static void _showStickerPopup(BuildContext context, ImageProvider provider) {
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    
    if (isDesktop) {
      // Desktop: Simple centered dialog
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (ctx) => GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280, maxHeight: 280),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Image(
                  image: provider,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 120),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      // Mobile: Bottom sheet style popup
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Image(
                image: provider,
                width: 200,
                height: 200,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 120),
              ),
            ],
          ),
        ),
      );
    }
  }

  static ImageProvider? _imageProviderFor(String src) {
    try {
      final uri = Uri.parse(src);
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return NetworkImage(src);
      }
      if (uri.scheme == 'file') {
        return FileImage(File(uri.toFilePath()));
      }
      if (uri.scheme == 'sticker') {
        final pack = uri.host;
        String id = '';
        if (uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty) {
          id = uri.pathSegments.first;
        } else {
          final auth = uri.authority; // fallback for sticker://pack:26 legacy
          final parts = auth.split(':');
          if (parts.length == 2) id = parts[1];
        }
        if (pack.isNotEmpty && id.isNotEmpty) {
          return AssetImage('assets/stickers/$pack/$id.webp');
        }
      }
    } catch (_) {
    }
    if (Platform.isWindows && RegExp(r'^[a-zA-Z]:\\').hasMatch(src)) {
      return FileImage(File(src));
    }
    return null;
  }

  static TextStyle _codeStyleBase(BuildContext ctx, {double size = 13, double height = 1.5}) {
    final base = TextStyle(fontSize: size, height: height);
    final sp = Provider.of<SettingsProvider>(ctx, listen: false);
    final fam = sp.codeFontFamily;
    if (fam == null || fam.isEmpty) {
      return base.copyWith(fontFamily: 'monospace');
    }
    if (sp.codeFontIsGoogle) {
      try {
        return GoogleFonts.getFont(fam, textStyle: base);
      } catch (_) {
        return base.copyWith(fontFamily: fam);
      }
    }
    return base.copyWith(fontFamily: fam);
  }

  static Future<void> _handleLinkTap(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        message: 'Failed to open link: $url',
        type: NotificationType.error,
      );
    }
  }
}

class _CollapsibleCodeBlock extends StatefulWidget {
  final String language;
  final String code;
  const _CollapsibleCodeBlock({required this.language, required this.code});

  @override
  State<_CollapsibleCodeBlock> createState() => _CollapsibleCodeBlockState();
}

class _CollapsibleCodeBlockState extends State<_CollapsibleCodeBlock> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use theme-tinted surfaces so headers follow the current theme color.
    final Color bodyBg = Color.alphaBlend(
      cs.primary.withOpacity(isDark ? 0.06 : 0.03),
      cs.surface,
    );
    final Color headerBg = Color.alphaBlend(
      cs.primary.withOpacity(isDark ? 0.16 : 0.10),
      cs.surface,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      // Clip children to the same radius so they don't overpaint corners
      clipBehavior: Clip.antiAlias,
      // Draw the border on top so it remains visible at corners
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
          // Header layout: language (left) + copy action (icon + label) + expand/collapse icon
          Material(
            color: headerBg,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              splashColor: Platform.isIOS ? Colors.transparent : null,
              highlightColor: Platform.isIOS ? Colors.transparent : null,
              hoverColor: Platform.isIOS ? Colors.transparent : null,
              overlayColor: Platform.isIOS ? const MaterialStatePropertyAll(Colors.transparent) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border(
                    // Show divider only when expanded
                    bottom: _expanded
                        ? BorderSide(color: cs.outlineVariant.withOpacity(0.28), width: 1.0)
                        : BorderSide.none,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 2),
                    Text(
                      MarkdownWithCodeHighlight._displayLanguage(context, widget.language),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        height: 1.0,
                      ),
                    ),
                    const Spacer(),
                    // Copy action: icon + label ("复制"/localized)
                    InkWell(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: widget.code));
                        if (mounted) {
                          showAppSnackBar(
                            context,
                            message: AppLocalizations.of(context)!.chatMessageWidgetCopiedToClipboard,
                            type: NotificationType.success,
                          );
                        }
                      },
                      splashColor: Platform.isIOS ? Colors.transparent : null,
                      highlightColor: Platform.isIOS ? Colors.transparent : null,
                      hoverColor: Platform.isIOS ? Colors.transparent : null,
                      overlayColor: Platform.isIOS ? const MaterialStatePropertyAll(Colors.transparent) : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              Lucide.Copy,
                              size: 14,
                              color: cs.onSurface.withOpacity(0.6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              AppLocalizations.of(context)!.shareProviderSheetCopyButton,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0.0, // right -> down
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Lucide.ChevronRight,
                        size: 16,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(
                sizeFactor: anim,
                axisAlignment: -1.0,
                child: child,
              ),
            ),
            child: _expanded
                ? Container(
                    key: const ValueKey('code-expanded'),
                    width: double.infinity,
                    color: bodyBg,
                    padding: const EdgeInsets.fromLTRB(10, 6, 6, 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      child: _SelectableHighlightView(
                        widget.code,
                        language: MarkdownWithCodeHighlight._normalizeLanguage(widget.language) ?? 'plaintext',
                        theme: MarkdownWithCodeHighlight._transparentBgTheme(
                          isDark ? atomOneDarkReasonableTheme : githubTheme,
                        ),
                        padding: EdgeInsets.zero,
                        textStyle: MarkdownWithCodeHighlight._codeStyleBase(context, size: 13, height: 1.5),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('code-collapsed')),
          ),
          ],
      ),
    );
  }
}

class _MermaidBlock extends StatefulWidget {
  final String code;
  const _MermaidBlock({required this.code});

  @override
  State<_MermaidBlock> createState() => _MermaidBlockState();
}

class _MermaidBlockState extends State<_MermaidBlock> {
  bool _expanded = true;
  // Stable key to avoid frequent WebView recreation across rebuilds
  final GlobalKey _mermaidViewKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use theme-tinted surfaces so headers follow the current theme color.
    final Color bodyBg = Color.alphaBlend(
      cs.primary.withOpacity(isDark ? 0.06 : 0.03),
      cs.surface,
    );
    final Color headerBg = Color.alphaBlend(
      cs.primary.withOpacity(isDark ? 0.16 : 0.10),
      cs.surface,
    );

    // Build theme variables mapping for Mermaid from Material ColorScheme
    String hex(Color c) {
      final v = c.value & 0xFFFFFFFF;
      final r = (v >> 16) & 0xFF;
      final g = (v >> 8) & 0xFF;
      final b = v & 0xFF;
      return '#'
          '${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();
    }

    final themeVars = <String, String>{
      'primaryColor': hex(cs.primary),
      'primaryTextColor': hex(cs.onPrimary),
      'primaryBorderColor': hex(cs.primary),
      'secondaryColor': hex(cs.secondary),
      'secondaryTextColor': hex(cs.onSecondary),
      'secondaryBorderColor': hex(cs.secondary),
      'tertiaryColor': hex(cs.tertiary),
      'tertiaryTextColor': hex(cs.onTertiary),
      'tertiaryBorderColor': hex(cs.tertiary),
      'background': hex(cs.background),
      'mainBkg': hex(cs.primaryContainer),
      'secondBkg': hex(cs.secondaryContainer),
      'lineColor': hex(cs.onBackground),
      'textColor': hex(cs.onBackground),
      'nodeBkg': hex(cs.surface),
      'nodeBorder': hex(cs.primary),
      'clusterBkg': hex(cs.surface),
      'clusterBorder': hex(cs.primary),
      'actorBorder': hex(cs.primary),
      'actorBkg': hex(cs.surface),
      'actorTextColor': hex(cs.onBackground),
      'actorLineColor': hex(cs.primary),
      'taskBorderColor': hex(cs.primary),
      'taskBkgColor': hex(cs.primary),
      'taskTextLightColor': hex(cs.onPrimary),
      'taskTextDarkColor': hex(cs.onBackground),
      'labelColor': hex(cs.onBackground),
      'errorBkgColor': hex(cs.error),
      'errorTextColor': hex(cs.onError),
    };

    final exporting = ExportCaptureScope.of(context);
    final handle = exporting ? null : createMermaidView(widget.code, isDark, themeVars: themeVars, viewKey: _mermaidViewKey);
    final Widget? mermaidView = () {
      if (exporting) {
        final bytes = MermaidImageCache.get(widget.code);
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(bytes, fit: BoxFit.contain);
        }
        return null;
      } else {
        return handle?.widget;
      }
    }();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
          // Header: left label (mermaid), right actions (copy label + export + chevron)
          Material(
            color: headerBg,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              splashColor: Platform.isIOS ? Colors.transparent : null,
              highlightColor: Platform.isIOS ? Colors.transparent : null,
              hoverColor: Platform.isIOS ? Colors.transparent : null,
              overlayColor: Platform.isIOS ? const MaterialStatePropertyAll(Colors.transparent) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border(
                    // Show divider only when expanded
                    bottom: _expanded
                        ? BorderSide(color: cs.outlineVariant.withOpacity(0.28), width: 1.0)
                        : BorderSide.none,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 2),
                    Text(
                      'mermaid',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        height: 1.0,
                      ),
                    ),
                    const Spacer(),
                    if (!ExportCaptureScope.of(context)) ...[
                      // Copy action
                      InkWell(
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: widget.code));
                          if (mounted) {
                            showAppSnackBar(
                              context,
                              message: AppLocalizations.of(context)!.chatMessageWidgetCopiedToClipboard,
                              type: NotificationType.success,
                            );
                          }
                        },
                        splashColor: Platform.isIOS ? Colors.transparent : null,
                        highlightColor: Platform.isIOS ? Colors.transparent : null,
                        hoverColor: Platform.isIOS ? Colors.transparent : null,
                        overlayColor: Platform.isIOS ? const MaterialStatePropertyAll(Colors.transparent) : null,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                Lucide.Copy,
                                size: 14,
                                color: cs.onSurface.withOpacity(0.6),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                AppLocalizations.of(context)!.shareProviderSheetCopyButton,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withOpacity(0.6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (handle != null) ...[
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () async {
                            final ok = await handle.exportPng();
                            if (!mounted) return;
                            if (!ok) {
                              final l10n = AppLocalizations.of(context)!;
                              showAppSnackBar(
                                context,
                                message: l10n.mermaidExportFailed,
                                type: NotificationType.error,
                              );
                            }
                          },
                          splashColor: Platform.isIOS ? Colors.transparent : null,
                          highlightColor: Platform.isIOS ? Colors.transparent : null,
                          hoverColor: Platform.isIOS ? Colors.transparent : null,
                          overlayColor: Platform.isIOS ? const MaterialStatePropertyAll(Colors.transparent) : null,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Lucide.Download,
                              size: 14,
                              color: cs.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _expanded ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Lucide.ChevronRight,
                          size: 16,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(
                sizeFactor: anim,
                axisAlignment: -1.0,
                child: child,
              ),
            ),
            child: _expanded
                ? Container(
                    key: const ValueKey('mermaid-expanded'),
                    width: double.infinity,
                    color: bodyBg,
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (mermaidView != null) ...[
                          SizedBox(
                            width: double.infinity,
                            child: mermaidView,
                          ),
                        ] else ...[
                          // Fallback: show raw code and a preview button (opens browser)
                          SizedBox(
                            width: double.infinity,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: _SelectableHighlightView(
                                widget.code,
                                language: 'plaintext',
                                theme: MarkdownWithCodeHighlight._transparentBgTheme(
                                  Theme.of(context).brightness == Brightness.dark
                                      ? atomOneDarkReasonableTheme
                                      : githubTheme,
                                ),
                                padding: EdgeInsets.zero,
                                textStyle: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                          if (!ExportCaptureScope.of(context)) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _openMermaidPreviewInBrowser(
                                    context, widget.code,
                                    Theme.of(context).brightness == Brightness.dark),
                                icon: Icon(Lucide.Eye, size: 16),
                                label:
                                    Text(AppLocalizations.of(context)!.mermaidPreviewOpen),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('mermaid-collapsed')),
          ),
        ],
      ),
    );
  }

  Future<void> _openMermaidPreviewInBrowser(BuildContext context, String code, bool dark) async {
    final htmlStr = _buildMermaidHtml(code, dark);
    final uri = Uri.dataFromString(htmlStr, mimeType: 'text/html', encoding: utf8);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.mermaidPreviewOpenFailed,
        type: NotificationType.error,
      );
    }
  }

  String _buildMermaidHtml(String code, bool dark) {
    final bg = dark ? '#111111' : '#ffffff';
    final fg = dark ? '#eaeaea' : '#222222';
    final escaped = code
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes, maximum-scale=5.0">
    <title>Mermaid Preview</title>
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
    <style>
      body{ margin:0; padding:12px; background:${bg}; color:${fg}; }
      .wrap{ max-width: 1000px; margin: 0 auto; }
      .mermaid{ text-align:center; }
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="mermaid">${escaped}</div>
    </div>
    <script>
      mermaid.initialize({ startOnLoad:false, theme: '${dark ? 'dark' : 'default'}', securityLevel:'loose' });
      mermaid.run({ querySelector: '.mermaid' });
    </script>
  </body>
</html>
''';
  }
}

// Full-width horizontal rule with softer color
class SoftHrLine extends BlockMd {
  @override
  String get expString => (r"^\s*(?:-{3,}|⸻)\s*$");

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.outlineVariant.withOpacity(0.4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: double.infinity,
        height: 1,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

// Robust fenced code block that takes precedence over other blocks
class FencedCodeBlockMd extends BlockMd {
  final String fullText;
  final bool isStreaming;

  FencedCodeBlockMd({this.fullText = '', this.isStreaming = false});

  @override
  // Match ```lang\n...\n``` at line starts. Non-greedy to stop at first closing fence.
  // More tolerant: optional whitespace before/after closing fence
  String get expString => (r"^\s*```([^\n`]*)\s*\n([\s\S]*?)\n```\s*$");

  /// 检测当前代码块是否处于流式生成中（未闭合）
  bool _detectStreamingState(String lang) {
    if (!isStreaming || fullText.isEmpty) return false;
    
    // 检测 ```html 是否有配对的 ```
    final openPattern = '```$lang';
    final openCount = openPattern.allMatches(fullText).length;
    final closeCount = '```'.allMatches(fullText).length;
    
    // 如果 ```html 出现次数多于总的 ``` 闭合次数，说明有未闭合的
    return closeCount < openCount * 2;
  }

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final m = exp.firstMatch(text);
    if (m == null) return const SizedBox.shrink();
    final lang = (m.group(1) ?? '').trim();
    final code = (m.group(2) ?? '');
    final langLower = lang.toLowerCase();
    
    // Special handling for Mermaid diagrams
    if (langLower == 'mermaid') {
      return _MermaidBlock(code: code);
    }
    
    // Check if this is a previewable frontend code (HTML, JSX, TSX, Vue, React)
    final isHtml = langLower == 'html';
    final runtimeType = CodeRuntimeTemplates.detectType(langLower);
    final canPreview = isHtml || runtimeType != null;
    
    return CodeArtifactsCard(
      code: code,
      language: lang,
      isStreaming: _detectStreamingState(langLower),
      canRenderPreview: canPreview,
      onPreview: canPreview ? () async {
        if (isHtml) {
          // Plain HTML - direct preview
          showHtmlPreviewDialog(context, code);
        } else if (runtimeType != null) {
          // Frontend code - generate HTML with runtime and preview
          // Use async version to support local cache
          final html = await CodeRuntimeTemplates.generateHtmlAsync(
            code: code,
            type: runtimeType,
            useTailwind: true,
            useLucide: false,
            preferLocalCache: true,
          );
          if (context.mounted) {
            showHtmlPreviewDialog(context, html);
          }
        }
      } : null,
    );
  }
}

/// Scrollable LaTeX block to prevent overflow when equations are very wide
class LatexBlockScrollableMd extends BlockMd {
  @override
  // Match either $$...$$ or \[...\] as standalone block
  String get expString => (r"^(?:\s*\$\$([\s\S]*?)\$\$\s*|\s*\\\[([\s\S]*?)\\\]\s*)$");

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final m = exp.firstMatch(text.trim());
    if (m == null) return const SizedBox.shrink();
    final body = ((m.group(1) ?? m.group(2) ?? '')).trim();
    if (body.isEmpty) return const SizedBox.shrink();

    final math = Math.tex(
      body,
      textStyle: (config.style ?? const TextStyle()),
    );
    // Wrap in horizontal scroll to avoid overflow; no extra background
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            child: math,
          );
        },
      ),
    );
  }
}

/// Inline LaTeX `$...$` rendered in a horizontally scrollable bubble to avoid line overflow
class InlineLatexScrollableMd extends InlineMd {
  @override
  // Match single-dollar $...$ or \(...\) inline math (avoid $$ block)
  RegExp get exp => RegExp(r"(?:(?<!\$)\$([^\$\n]+?)\$(?!\$)|\\\(([^\n]+?)\\\))");

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final m = exp.firstMatch(text);
    if (m == null) return TextSpan(text: text, style: config.style);
    final body = ((m.group(1) ?? m.group(2) ?? '')).trim();
    if (body.isEmpty) return TextSpan(text: text, style: config.style);
    final math = Math.tex(
      body,
      mathStyle: MathStyle.text,
      textStyle: () {
        final base = (config.style ?? const TextStyle());
        final baseSize = base.fontSize ?? 15.5;
        // Slightly enlarge inline math for readability
        return base.copyWith(fontSize: baseSize * 1.2);
      }(),
    );
    // Wrap in horizontal scroll to prevent line overflow; no extra background
    final w = LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          primary: false,
          child: math,
        );
      },
    );

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: w,
    );
  }
}

/// Inline LaTeX for dollar delimiters only: `$...$`
class InlineLatexDollarScrollableMd extends InlineMd {
  @override
  RegExp get exp => RegExp(r"(?:(?<!\$)\$([^\$\n]+?)\$(?!\$))");

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final m = exp.firstMatch(text);
    if (m == null) return TextSpan(text: text, style: config.style);
    final body = (m.group(1) ?? '').trim();
    if (body.isEmpty) return TextSpan(text: text, style: config.style);
    final math = Math.tex(
      body,
      mathStyle: MathStyle.text,
      textStyle: () {
        final base = (config.style ?? const TextStyle());
        final baseSize = base.fontSize ?? 15.5;
        return base.copyWith(fontSize: baseSize * 1.2);
      }(),
    );
    final w = LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          primary: false,
          child: math,
        );
      },
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: w,
    );
  }
}

/// Inline LaTeX for parenthesis delimiters only: `\(...\)`
class InlineLatexParenScrollableMd extends InlineMd {
  @override
  RegExp get exp => RegExp(r"(?:\\\(([^\n]+?)\\\))");

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final m = exp.firstMatch(text);
    if (m == null) return TextSpan(text: text, style: config.style);
    final body = (m.group(1) ?? '').trim();
    if (body.isEmpty) return TextSpan(text: text, style: config.style);
    final math = Math.tex(
      body,
      mathStyle: MathStyle.text,
      textStyle: () {
        final base = (config.style ?? const TextStyle());
        final baseSize = base.fontSize ?? 15.5;
        return base.copyWith(fontSize: baseSize * 1.2);
      }(),
    );
    final w = LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          primary: false,
          child: math,
        );
      },
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: w,
    );
  }
}

// Balanced ATX-style headings (#, ##, ###, …) with consistent spacing and typography
class AtxHeadingMd extends BlockMd {
  @override
  // Restrict heading content to a single line to avoid swallowing
  // subsequent blocks (e.g., fenced code) when the engine builds
  // the regex with dotAll=true. Using [^\n]+ keeps it line-bound.
  String get expString => (r"^\s{0,3}(#{1,6})\s+([^\n]+?)(?:\s+#+\s*)?$");

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final m = exp.firstMatch(text.trim());
    if (m == null) return const SizedBox.shrink();
    final hashes = m.group(1) ?? '#';
    final raw = (m.group(2) ?? '').trim();
    final lvl = hashes.length;
    final level = lvl < 1 ? 1 : (lvl > 6 ? 6 : lvl);

    final innerCfg = config.copyWith(style: const TextStyle());
    final inner = TextSpan(children: MarkdownComponent.generate(context, raw, innerCfg, true));
    final style = _headingTextStyle(context, config, level);
    // Increase top spacing to ensure headings are visually separated from preceding content
    // This prevents headings from appearing inline with regular text (especially in reasoning blocks)
    final top = switch (level) { 1 => 16.0, 2 => 14.0, 3 => 12.0, _ => 10.0 };
    final bottom = switch (level) { 1 => 8.0, 2 => 6.0, 3 => 5.0, _ => 4.0 };

    // Use Column to ensure block-level rendering (prevents inline display with preceding text)
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            text: TextSpan(style: style, children: [inner]),
            textScaler: MediaQuery.of(context).textScaler,
            textAlign: TextAlign.start,
          ),
        ],
      ),
    );
  }

  TextStyle _headingTextStyle(BuildContext ctx, GptMarkdownConfig cfg, int level) {
    final t = Theme.of(ctx).textTheme;
    final cs = Theme.of(ctx).colorScheme;
    final isZh = MarkdownWithCodeHighlight._isZh(ctx);
    // Start from Material styles but tighten sizes for balance with body text
    TextStyle base;
    // Explicit sizes ensure visible contrast over the body (16.0)
    switch (level) {
      case 1:
        base = const TextStyle(fontSize: 24);
        break;
      case 2:
        base = const TextStyle(fontSize: 20);
        break;
      case 3:
        base = const TextStyle(fontSize: 18);
        break;
      case 4:
        base = const TextStyle(fontSize: 16);
        break;
      case 5:
        base = const TextStyle(fontSize: 15);
        break;
      default:
        base = const TextStyle(fontSize: 14);
    }
    final weight = switch (level) { 1 => FontWeight.w700, 2 => FontWeight.w600, 3 => FontWeight.w600, _ => FontWeight.w500 };
    final ls = switch (level) { 1 => isZh ? 0.0 : 0.1, 2 => isZh ? 0.0 : 0.08, _ => isZh ? 0.0 : 0.05 };
    final h = switch (level) { 1 => 1.25, 2 => 1.3, _ => 1.35 };
    return base.copyWith(
      fontWeight: weight,
      height: h,
      letterSpacing: ls,
      color: cs.onSurface,
      fontFamilyFallback: kDefaultFontFamilyFallback,
    );
  }
}

// Setext-style headings (underlines with === or ---)
class SetextHeadingMd extends BlockMd {
  @override
  String get expString => (r"^(.+?)\n(=+|-+)\s*$");

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final m = exp.firstMatch(text.trimRight());
    if (m == null) return const SizedBox.shrink();
    final title = (m.group(1) ?? '').trim();
    final underline = (m.group(2) ?? '').trim();
    final level = underline.startsWith('=') ? 1 : 2;

    final innerCfg = config.copyWith(style: const TextStyle());
    final inner = TextSpan(children: MarkdownComponent.generate(context, title, innerCfg, true));
    final style = AtxHeadingMd()._headingTextStyle(context, config, level);
    // Match the spacing used in ATX headings for consistency
    final top = level == 1 ? 16.0 : 14.0;
    final bottom = level == 1 ? 8.0 : 6.0;

    // Use Column to ensure block-level rendering (prevents inline display with preceding text)
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            text: TextSpan(style: style, children: [inner]),
            textScaler: MediaQuery.of(context).textScaler,
            textAlign: TextAlign.start,
          ),
        ],
      ),
    );
  }
}

// Label-value strong lines like "**作者:** 张三" should not render as heading-sized text
class LabelValueLineMd extends InlineMd {
  @override
  bool get inline => false;

  @override
  // Match either "**标签:** 值" (冒号在加粗内) 或 "**标签**: 值"（冒号在加粗外），支持全角/半角冒号
  RegExp get exp => RegExp(r"(?:(?:^|\n)\*\*([^*]+?)\*\*\s*:\s*.+$)", multiLine: true);

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text);
    if (match == null) return TextSpan(text: text, style: config.style);
    final label = (match.group(1) ?? '').trim();
    // Note: list item markers are stripped by the list renderer before
    // this runs, so a list line like "- **Label**: value [citation](1:abc)"
    // becomes "**Label**: value [citation](1:abc)", which we intentionally
    // match here.

    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    // Inherit base markdown style (letterSpacing/height) to keep visual consistency
    final base = (config.style ?? t.bodyMedium ?? const TextStyle(fontSize: 14));
    final labelStyle = base.copyWith(
      fontWeight: FontWeight.w500,
      color: cs.onSurface,
    );
    final valueStyle = base.copyWith(
      fontWeight: FontWeight.w400,
      color: cs.onSurface.withOpacity(0.92),
    );
       // Split into label/value while preserving the rest of the line
    final colonIndex = text.indexOf(':');
    final prefix = text.substring(0, colonIndex + 1);
    final value = text.substring(colonIndex + 1).trim();
    // Parse the value part as markdown so links/citations render correctly
    final valueChildren = MarkdownComponent.generate(
      context,
      value,
      config.copyWith(style: valueStyle),
      true,
    );

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: RichText(
          text: TextSpan(children: [
            TextSpan(text: prefix.replaceAll('**', ''), style: labelStyle),
            const TextSpan(text: ' '),
            ...valueChildren,
          ]),
          textScaler: MediaQuery.of(context).textScaler,
        ),
      ),
    );
  }
}

// Modern, app-styled block quote with soft background and accent border
class ModernBlockQuote extends InlineMd {
  @override
  bool get inline => false;

  @override
  RegExp get exp => RegExp(
    r"^[ \t]*>[^\n]*(?:\n[ \t]*>[^\n]*)*",
    multiLine: true,
  );

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text);
    final m = match?[0] ?? '';
    final sb = StringBuffer();
    for (final line in m.split('\n')) {
      if (RegExp(r'^\ *>').hasMatch(line)) {
        var sub = line.trimLeft();
        sub = sub.substring(1); // remove '>'
        if (sub.startsWith(' ')) sub = sub.substring(1);
        sb.writeln(sub);
      } else {
        sb.writeln(line);
      }
    }
    final data = sb.toString().trim();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = cs.primaryContainer.withOpacity(isDark ? 0.18 : 0.12);
    final accent = cs.primary.withOpacity(isDark ? 0.90 : 0.80);

    final inner = TextSpan(children: MarkdownComponent.generate(context, data, config, true));
    final child = Directionality(
      textDirection: config.textDirection,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: config.getRich(inner),
        ),
      ),
    );

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: child,
    );
  }
}

// Modern task checkbox: square with subtle border, primary check on done
class ModernCheckBoxMd extends BlockMd {
  @override
  String get expString => (r"\[((?:\x|\ ))\]\ (\S[^\n]*?)$");

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text.trim());
    final checked = (match?[1] == 'x');
    final content = match?[2] ?? '';
    final cs = Theme.of(context).colorScheme;

    final contentStyle = (config.style ?? const TextStyle()).copyWith(
      decoration: checked ? TextDecoration.lineThrough : null,
      color: (config.style?.color ?? cs.onSurface).withOpacity(checked ? 0.75 : 1.0),
    );

    final child = MdWidget(
      context,
      content,
      false,
      config: config.copyWith(style: contentStyle),
    );

    return Directionality(
      textDirection: config.textDirection,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textBaseline: TextBaseline.alphabetic,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, end: 8),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.8), width: 1),
                color: checked ? cs.primary.withOpacity(0.12) : Colors.transparent,
              ),
              child: checked
                  ? Icon(Icons.check, size: 14, color: cs.primary)
                  : null,
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

// Modern radio (optional): circle with primary dot when selected
class ModernRadioMd extends BlockMd {
  @override
  String get expString => (r"\(((?:\x|\ ))\)\ (\S[^\n]*)$");

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text.trim());
    final selected = (match?[1] == 'x');
    final content = match?[2] ?? '';
    final cs = Theme.of(context).colorScheme;

    final contentStyle = (config.style ?? const TextStyle()).copyWith(
      color: (config.style?.color ?? cs.onSurface).withOpacity(selected ? 0.95 : 1.0),
    );

    final child = MdWidget(
      context,
      content,
      false,
      config: config.copyWith(style: contentStyle),
    );

    return Directionality(
      textDirection: config.textDirection,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textBaseline: TextBaseline.alphabetic,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, end: 8),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.8), width: 1),
              ),
              child: selected
                  ? Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              )
                  : null,
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }

  static TextStyle _codeStyleBase(BuildContext ctx, {double size = 13, double height = 1.5}) {
    final base = TextStyle(fontSize: size, height: height);
    final sp = Provider.of<SettingsProvider>(ctx, listen: false);
    final fam = sp.codeFontFamily;
    if (fam == null || fam.isEmpty) {
      return base.copyWith(fontFamily: 'monospace');
    }
    if (sp.codeFontIsGoogle) {
      try { return GoogleFonts.getFont(fam, textStyle: base); } catch (_) { return base.copyWith(fontFamily: fam); }
    }
    return base.copyWith(fontFamily: fam);
  }
}

class _SelectableMarkdownBody extends StatefulWidget {
  const _SelectableMarkdownBody({
    required this.markdownContext,
    required this.text,
    required this.config,
    this.includeGlobalComponents = true,
  });

  final BuildContext markdownContext;
  final String text;
  final GptMarkdownConfig config;
  final bool includeGlobalComponents;

  @override
  State<_SelectableMarkdownBody> createState() => _SelectableMarkdownBodyState();
}

class _SelectableMarkdownBodyState extends State<_SelectableMarkdownBody> {
  late List<InlineSpan> _spans;

  @override
  void initState() {
    super.initState();
    _spans = _generateSpans();
  }

  @override
  void didUpdateWidget(covariant _SelectableMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.includeGlobalComponents != widget.includeGlobalComponents ||
        oldWidget.markdownContext != widget.markdownContext ||
        !oldWidget.config.isSame(widget.config)) {
      _spans = _generateSpans();
    }
  }

  List<InlineSpan> _generateSpans() {
    return MarkdownComponent.generate(
      widget.markdownContext,
      widget.text,
      widget.config,
      widget.includeGlobalComponents,
    );
  }

  @override
  Widget build(BuildContext context) {
    final span = TextSpan(style: widget.config.style, children: _spans);
    final bool isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    
    // Desktop: Use SelectionArea + Text.rich for proper text and WidgetSpan selection
    // Wrap in ExcludeSemantics to avoid Windows accessibility crashes
    // Mobile: Use SelectableText.rich (long-press selection works fine)
    if (isDesktop) {
      return ExcludeSemantics(
        child: SelectionArea(
          child: Text.rich(
            span,
            textDirection: widget.config.textDirection,
            textAlign: widget.config.textAlign ?? TextAlign.start,
            textScaler: widget.config.textScaler ?? TextScaler.noScaling,
            maxLines: widget.config.maxLines,
            softWrap: true,
            overflow: TextOverflow.clip,
          ),
        ),
      );
    }
    
    return SelectableText.rich(
      span,
      textDirection: widget.config.textDirection,
      textAlign: widget.config.textAlign,
      textScaler: widget.config.textScaler,
      maxLines: widget.config.maxLines,
    );
  }
}

class _SelectableHighlightView extends StatelessWidget {
  _SelectableHighlightView(
    String input, {
    this.language,
    this.theme = const {},
    this.padding,
    this.textStyle,
    int tabSize = 8,
  }) : source = input.replaceAll('\t', ' ' * tabSize);

  final String source;
  final String? language;
  final Map<String, TextStyle> theme;
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;
  static const _rootKey = 'root';
  static const _defaultFontColor = Color(0xff000000);
  static const _defaultBackgroundColor = Color(0xffffffff);
  static const _defaultFontFamily = 'monospace';

  List<TextSpan> _convert(List<Node> nodes) {
    final spans = <TextSpan>[];
    var currentSpans = spans;
    final stack = <List<TextSpan>>[];

    void traverse(Node node) {
      if (node.value != null) {
        currentSpans.add(
          node.className == null
              ? TextSpan(text: node.value)
              : TextSpan(text: node.value, style: theme[node.className!]),
        );
      } else if (node.children != null && node.children!.isNotEmpty) {
        final tmp = <TextSpan>[];
        currentSpans.add(TextSpan(children: tmp, style: node.className == null ? null : theme[node.className!]));
        stack.add(currentSpans);
        currentSpans = tmp;
        for (final child in node.children!) {
          traverse(child);
          if (child == node.children!.last) {
            currentSpans = stack.isEmpty ? spans : stack.removeLast();
          }
        }
      }
    }

    for (final node in nodes) {
      traverse(node);
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    var baseStyle = TextStyle(
      fontFamily: _defaultFontFamily,
      color: theme[_rootKey]?.color ?? _defaultFontColor,
    );
    if (textStyle != null) {
      baseStyle = baseStyle.merge(textStyle);
    }

    final parsed = highlight.parse(source, language: language).nodes ?? const <Node>[];
    return Container(
      color: theme[_rootKey]?.backgroundColor ?? _defaultBackgroundColor,
      padding: padding,
      child: SelectableText.rich(
        TextSpan(style: baseStyle, children: _convert(parsed)),
        maxLines: null,
        scrollPhysics: const NeverScrollableScrollPhysics(),
        textWidthBasis: TextWidthBasis.longestLine,
      ),
    );
  }
}
