import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/snackbar.dart';
import 'message_models.dart';

/// Tool call/result display card.
///
/// Shows MCP tool invocations with their arguments and results.
/// Tapping the card opens a detailed view:
/// - Desktop: Dialog
/// - Mobile: Bottom sheet
class ToolCallItem extends StatelessWidget {
  const ToolCallItem({super.key, required this.part});

  final ToolUIPart part;

  IconData _iconFor(String name) {
    switch (name) {
      case 'create_memory':
      case 'edit_memory':
        return Lucide.Library;
      case 'delete_memory':
        return Lucide.Trash2;
      case 'search_web':
        return Lucide.Earth;
      case 'builtin_search':
        return Lucide.Search;
      default:
        return Lucide.Wrench;
    }
  }

  String _titleFor(
    BuildContext context,
    String name,
    Map<String, dynamic> args, {
    required bool isResult,
  }) {
    final l10n = AppLocalizations.of(context)!;
    switch (name) {
      case 'create_memory':
        return l10n.chatMessageWidgetCreateMemory;
      case 'edit_memory':
        return l10n.chatMessageWidgetEditMemory;
      case 'delete_memory':
        return l10n.chatMessageWidgetDeleteMemory;
      case 'search_web':
        final q = (args['query'] ?? '').toString();
        return l10n.chatMessageWidgetWebSearch(q);
      case 'builtin_search':
        return l10n.chatMessageWidgetBuiltinSearch;
      default:
        return isResult
            ? l10n.chatMessageWidgetToolResult(name)
            : l10n.chatMessageWidgetToolCall(name);
    }
  }

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = cs.primaryContainer.withOpacity(isDark ? 0.25 : 0.30);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDetail(context),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: part.loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            cs.primary,
                          ),
                        ),
                      )
                    : Icon(
                        _iconFor(part.toolName),
                        size: 18,
                        color: cs.secondary,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleFor(
                        context,
                        part.toolName,
                        part.arguments,
                        isResult: !part.loading,
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    if (_isDesktop) {
      _showDesktopDialog(context);
    } else {
      _showMobileSheet(context);
    }
  }

  /// Desktop: Dialog
  void _showDesktopDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ToolDetailDialog(
        part: part,
        iconFor: _iconFor,
        titleFor: _titleFor,
      ),
    );
  }

  /// Mobile: bottom sheet
  void _showMobileSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final argsPretty = const JsonEncoder.withIndent('  ').convert(part.arguments);
    final resultText = (part.content ?? '').isNotEmpty
        ? part.content!
        : l10n.chatMessageWidgetNoResultYet;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.7,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        _iconFor(part.toolName),
                        size: 18,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _titleFor(
                            context,
                            part.toolName,
                            part.arguments,
                            isResult: !part.loading,
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.chatMessageWidgetArguments,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white10
                                  : const Color(0xFFF7F7F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: cs.outlineVariant.withOpacity(0.2),
                              ),
                            ),
                            child: SelectableText(
                              argsPretty,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.chatMessageWidgetResult,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _ResultContentWidget(
                            resultText: resultText,
                            toolName: part.toolName,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Desktop Dialog for tool details
class _ToolDetailDialog extends StatelessWidget {
  const _ToolDetailDialog({
    required this.part,
    required this.iconFor,
    required this.titleFor,
  });

  final ToolUIPart part;
  final IconData Function(String) iconFor;
  final String Function(BuildContext, String, Map<String, dynamic>, {required bool isResult}) titleFor;

  Future<void> _copyToClipboard(BuildContext context, String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: '$label copied',
        type: NotificationType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final screenSize = MediaQuery.of(context).size;

    final argsPretty = const JsonEncoder.withIndent('  ').convert(part.arguments);
    final resultText = (part.content ?? '').isNotEmpty
        ? part.content!
        : l10n.chatMessageWidgetNoResultYet;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: screenSize.width * 0.55,
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(isDark ? 0.15 : 0.10),
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      iconFor(part.toolName),
                      size: 16,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      titleFor(context, part.toolName, part.arguments, isResult: !part.loading),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Lucide.X, size: 18, color: cs.onSurface.withOpacity(0.7)),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Arguments section
                    Row(
                      children: [
                        Text(
                          l10n.chatMessageWidgetArguments,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => _copyToClipboard(context, argsPretty, 'Arguments'),
                          icon: Icon(Lucide.Copy, size: 14, color: cs.onSurface.withOpacity(0.5)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          visualDensity: VisualDensity.compact,
                          tooltip: '复制参数',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
                      ),
                      child: SelectableText(
                        argsPretty,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: cs.onSurface.withOpacity(0.85),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Result section
                    Row(
                      children: [
                        Text(
                          l10n.chatMessageWidgetResult,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => _copyToClipboard(context, resultText, 'Result'),
                          icon: Icon(Lucide.Copy, size: 14, color: cs.onSurface.withOpacity(0.5)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          visualDensity: VisualDensity.compact,
                          tooltip: '复制结果',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _ResultContentWidget(
                      resultText: resultText,
                      toolName: part.toolName,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Smart result content widget that formats JSON and search results
class _ResultContentWidget extends StatelessWidget {
  const _ResultContentWidget({
    required this.resultText,
    required this.toolName,
  });

  final String resultText;
  final String toolName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Try to parse as JSON
    final parsed = _tryParseJson(resultText);

    if (parsed != null) {
      // Check if it's search results format
      final searchItems = _extractSearchItems(parsed);
      if (searchItems != null && searchItems.isNotEmpty) {
        return _SearchResultsList(items: searchItems);
      }

      // Otherwise, show formatted JSON
      final prettyJson = const JsonEncoder.withIndent('  ').convert(parsed);
      return _JsonCodeBlock(json: prettyJson);
    }

    // Fallback: plain text
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: SelectableText(
        resultText,
        style: TextStyle(
          fontSize: 12,
          color: cs.onSurface.withOpacity(0.85),
        ),
      ),
    );
  }

  dynamic _tryParseJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>>? _extractSearchItems(dynamic json) {
    if (json is Map<String, dynamic>) {
      // Direct items array
      if (json['items'] is List) {
        return (json['items'] as List).whereType<Map<String, dynamic>>().toList();
      }
      // Results array (some search APIs)
      if (json['results'] is List) {
        return (json['results'] as List).whereType<Map<String, dynamic>>().toList();
      }
      // Data.items pattern
      if (json['data'] is Map && json['data']['items'] is List) {
        return (json['data']['items'] as List).whereType<Map<String, dynamic>>().toList();
      }
    }
    // Direct array of items
    if (json is List && json.isNotEmpty && json.first is Map) {
      final first = json.first as Map;
      if (first.containsKey('title') || first.containsKey('url') || first.containsKey('text')) {
        return json.whereType<Map<String, dynamic>>().toList();
      }
    }
    return null;
  }
}

/// Formatted JSON code block
class _JsonCodeBlock extends StatelessWidget {
  const _JsonCodeBlock({required this.json});

  final String json;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: SelectableText(
        json,
        style: TextStyle(
          fontSize: 11.5,
          fontFamily: 'monospace',
          color: cs.onSurface.withOpacity(0.9),
          height: 1.4,
        ),
      ),
    );
  }
}

/// Search results list view
class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          _SearchResultCard(item: items[i], index: i + 1),
          if (i < items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Single search result card
class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.item, required this.index});

  final Map<String, dynamic> item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final title = (item['title'] ?? item['name'] ?? '').toString().trim();
    final url = (item['url'] ?? item['link'] ?? '').toString().trim();
    final text = (item['text'] ?? item['snippet'] ?? item['description'] ?? item['content'] ?? '').toString().trim();

    // Extract domain from URL
    String domain = '';
    try {
      if (url.isNotEmpty) {
        final uri = Uri.parse(url);
        domain = uri.host.replaceFirst('www.', '');
      }
    } catch (_) {}

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row with index
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (domain.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Lucide.Globe, size: 11, color: cs.onSurface.withOpacity(0.4)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              domain,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (url.isNotEmpty)
                IconButton(
                  onPressed: () => _openUrl(url),
                  icon: Icon(Lucide.ExternalLink, size: 14, color: cs.primary.withOpacity(0.7)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  visualDensity: VisualDensity.compact,
                  tooltip: '打开链接',
                ),
            ],
          ),
          // Content/snippet
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withOpacity(0.7),
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}
