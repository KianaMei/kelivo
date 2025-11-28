import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import 'message/assistant_message_renderer.dart';
import 'message/message_models.dart';
import 'message/tool_call_item.dart';
import 'message/user_message_renderer.dart';

export 'message/message_models.dart' show ToolUIPart, ReasoningSegment;

class ChatMessageWidget extends StatefulWidget {
  final ChatMessage message;
  final Widget? modelIcon;
  final bool showModelIcon;
  final bool useAssistantAvatar;
  final String? assistantName;
  final String? assistantAvatar;
  final bool showUserAvatar;
  final bool showTokenStats;
  final VoidCallback? onRegenerate;
  final VoidCallback? onResend;
  final VoidCallback? onCopy;
  final VoidCallback? onTranslate;
  final VoidCallback? onSpeak;
  final VoidCallback? onMore;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final int? versionIndex;
  final int? versionCount;
  final VoidCallback? onPrevVersion;
  final VoidCallback? onNextVersion;
  final String? reasoningText;
  final bool reasoningExpanded;
  final bool reasoningLoading;
  final DateTime? reasoningStartAt;
  final DateTime? reasoningFinishedAt;
  final VoidCallback? onToggleReasoning;
  final List<ReasoningSegment>? reasoningSegments;
  final bool translationExpanded;
  final VoidCallback? onToggleTranslation;
  final List<ToolUIPart>? toolParts;
  final List<ChatMessage>? allMessages;
  final Map<String, List<ToolUIPart>>? allToolParts;

  const ChatMessageWidget({
    super.key,
    required this.message,
    this.modelIcon,
    this.showModelIcon = true,
    this.useAssistantAvatar = false,
    this.assistantName,
    this.assistantAvatar,
    this.showUserAvatar = true,
    this.showTokenStats = true,
    this.onRegenerate,
    this.onResend,
    this.onCopy,
    this.onTranslate,
    this.onSpeak,
    this.onMore,
    this.onEdit,
    this.onDelete,
    this.versionIndex,
    this.versionCount,
    this.onPrevVersion,
    this.onNextVersion,
    this.reasoningText,
    this.reasoningExpanded = false,
    this.reasoningLoading = false,
    this.reasoningStartAt,
    this.reasoningFinishedAt,
    this.onToggleReasoning,
    this.reasoningSegments,
    this.translationExpanded = true,
    this.onToggleTranslation,
    this.toolParts,
    this.allMessages,
    this.allToolParts,
  });

  @override
  State<ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<ChatMessageWidget> {
  static final RegExp THINKING_REGEX = RegExp(
    r"<think>([\s\S]*?)(?:</think>|$)",
    dotAll: true,
  );
  
  late final Ticker _ticker = Ticker((_) {
    if (mounted && _tickActive) setState(() {});
  });
  
  bool _tickActive = false;
  bool? _inlineThinkExpanded;
  bool _inlineThinkManuallyToggled = false;
  bool _inlineThinkWasLoading = false;

  @override
  void initState() {
    super.initState();
    _syncTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyAutoCollapseInlineThinkIfFinished(oldWidget: null);
    });
  }

  @override
  void didUpdateWidget(covariant ChatMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
    _applyAutoCollapseInlineThinkIfFinished(oldWidget: oldWidget);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final loading = widget.reasoningStartAt != null && widget.reasoningFinishedAt == null;
    _tickActive = loading;
    if (loading) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
    }
  }

  void _applyAutoCollapseInlineThinkIfFinished({ChatMessageWidget? oldWidget}) {
    if (!mounted) return;
    
    final newExtracted = THINKING_REGEX
        .allMatches(widget.message.content)
        .map((m) => (m.group(1) ?? '').trim())
        .where((s) => s.isNotEmpty)
        .join('\n\n');
    final usingInlineThinkNew =
        (widget.reasoningText == null || widget.reasoningText!.isEmpty) &&
        newExtracted.isNotEmpty;
    final loadingNew =
        usingInlineThinkNew &&
        widget.message.isStreaming &&
        !widget.message.content.contains('</think>');

    bool loadingOld = false;
    if (oldWidget != null) {
      final oldExtracted = THINKING_REGEX
          .allMatches(oldWidget.message.content)
          .map((m) => (m.group(1) ?? '').trim())
          .where((s) => s.isNotEmpty)
          .join('\n\n');
      final usingInlineThinkOld =
          (oldWidget.reasoningText == null || oldWidget.reasoningText!.isEmpty) &&
          oldExtracted.isNotEmpty;
      loadingOld =
          usingInlineThinkOld &&
          oldWidget.message.isStreaming &&
          !oldWidget.message.content.contains('</think>');
    }

    _inlineThinkWasLoading = loadingNew;

    final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
    final finishedNow = usingInlineThinkNew && !loadingNew;
    final justFinished = oldWidget != null ? (loadingOld && finishedNow) : finishedNow;

    if (autoCollapse && finishedNow && justFinished) {
      if (!_inlineThinkManuallyToggled || _inlineThinkExpanded == null) {
        if (mounted) setState(() => _inlineThinkExpanded = false);
        return;
      }
    }

    if (oldWidget == null &&
        usingInlineThinkNew &&
        !loadingNew &&
        _inlineThinkExpanded == null) {
      if (autoCollapse) {
        if (mounted) setState(() => _inlineThinkExpanded = false);
      } else {
        if (mounted) setState(() => _inlineThinkExpanded = true);
      }
    }
  }

  static void _log(String message) {}

  Widget _buildToolMessage() {
    String toolName = 'tool';
    Map<String, dynamic> args = const {};
    String result = '';
    try {
      final obj = jsonDecode(widget.message.content) as Map<String, dynamic>;
      toolName = (obj['tool'] ?? 'tool').toString();
      final a = obj['arguments'];
      if (a is Map<String, dynamic>) args = a;
      result = (obj['result'] ?? '').toString();
    } catch (_) {}

    final part = ToolUIPart(
      id: widget.message.id,
      toolName: toolName,
      arguments: args,
      content: result,
      loading: false,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ToolCallItem(part: part),
    );
  }

  void _handleCitationTap(String id) async {
    final l10n = AppLocalizations.of(context)!;
    _log('[Citation UI] Tapped citation with id: $id');

    if (widget.allToolParts != null && widget.allToolParts!.isNotEmpty) {
      bool found = false;
      for (final entry in widget.allToolParts!.entries) {
        if (found) break;
        final toolPartsForMessage = entry.value;
        if (toolPartsForMessage.isEmpty) continue;

        for (final part in toolPartsForMessage) {
          if (found) break;
          if ((part.toolName == 'search_web' || part.toolName == 'builtin_search') &&
              (part.content?.isNotEmpty ?? false)) {
            try {
              final obj = jsonDecode(part.content!) as Map<String, dynamic>;
              final items = (obj['items'] as List? ?? []).whereType<Map<String, dynamic>>().toList();

              for (final item in items) {
                final itemId = item['id']?.toString() ?? '';
                if (itemId == id) {
                  final url = item['url']?.toString();
                  if (url != null && url.isNotEmpty) {
                    try {
                      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      if (!ok && context.mounted) {
                        showAppSnackBar(context, message: l10n.chatMessageWidgetCannotOpenUrl(url), type: NotificationType.error);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        showAppSnackBar(context, message: l10n.chatMessageWidgetOpenLinkError, type: NotificationType.error);
                      }
                    }
                    found = true;
                    break;
                  }
                }
              }
            } catch (e) {}
          }
        }
      }
      if (found) return;
    }

    final items = _latestSearchItems();
    final match = items.cast<Map<String, dynamic>?>().firstWhere(
      (e) => (e?['id']?.toString() ?? '') == id,
      orElse: () => null,
    );
    final url = match?['url']?.toString();

    if (url != null && url.isNotEmpty) {
      try {
        final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) {
          showAppSnackBar(context, message: l10n.chatMessageWidgetCannotOpenUrl(url), type: NotificationType.error);
        }
      } catch (_) {
        if (context.mounted) {
          showAppSnackBar(context, message: l10n.chatMessageWidgetOpenLinkError, type: NotificationType.error);
        }
      }
    } else {
      if (context.mounted) {
        showAppSnackBar(context, message: l10n.chatMessageWidgetCitationNotFound, type: NotificationType.warning);
      }
    }
  }

  List<Map<String, dynamic>> _latestSearchItems() {
    final parts = widget.toolParts ?? const <ToolUIPart>[];
    for (int i = parts.length - 1; i >= 0; i--) {
      final p = parts[i];
      if ((p.toolName == 'search_web' || p.toolName == 'builtin_search') &&
          (p.content?.isNotEmpty ?? false)) {
        try {
          final obj = jsonDecode(p.content!) as Map<String, dynamic>;
          final arr = obj['items'] as List? ?? const <dynamic>[];
          final items = [
            for (final it in arr)
              if (it is Map) it.cast<String, dynamic>(),
          ];
          return items;
        } catch (e) {
          return const <Map<String, dynamic>>[];
        }
      }
    }
    return const <Map<String, dynamic>>[];
  }

  void _showCitationsSheet(List<Map<String, dynamic>> items) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
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
            heightFactor: 0.5,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.book_outlined, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.chatMessageWidgetCitationsTitle(items.length),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < items.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () async {
                                  final url = items[i]['url']?.toString();
                                  if (url != null && url.isNotEmpty) {
                                    try {
                                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                    } catch (_) {}
                                  }
                                },
                                child: Text(
                                  items[i]['title']?.toString() ?? items[i]['url']?.toString() ?? '',
                                  style: TextStyle(color: cs.primary),
                                ),
                              ),
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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    
    if (widget.message.role == 'user') {
      return UserMessageRenderer(
        message: widget.message,
        showUserAvatar: widget.showUserAvatar,
        showUserActions: settings.showUserMessageActions,
        showVersionSwitcher: (widget.versionCount ?? 1) > 1,
        versionIndex: widget.versionIndex,
        versionCount: widget.versionCount,
        onPrevVersion: widget.onPrevVersion,
        onNextVersion: widget.onNextVersion,
        onCopy: widget.onCopy,
        onResend: widget.onResend,
        onMore: widget.onMore,
        onEdit: widget.onEdit,
        onDelete: widget.onDelete,
      );
    }
    
    if (widget.message.role == 'tool') return _buildToolMessage();
    
    final extractedThinking = THINKING_REGEX
        .allMatches(widget.message.content)
        .map((m) => (m.group(1) ?? '').trim())
        .where((s) => s.isNotEmpty)
        .join('\n\n');
    final contentWithoutThink = extractedThinking.isNotEmpty
        ? widget.message.content.replaceAll(THINKING_REGEX, '').trim()
        : widget.message.content;
    final usingInlineThink =
        (widget.reasoningText == null || widget.reasoningText!.isEmpty) &&
        extractedThinking.isNotEmpty;
    
    return AssistantMessageRenderer(
      message: widget.message,
      modelIcon: widget.modelIcon,
      showModelIcon: widget.showModelIcon,
      useAssistantAvatar: widget.useAssistantAvatar,
      assistantName: widget.assistantName,
      assistantAvatar: widget.assistantAvatar,
      showTokenStats: widget.showTokenStats,
      translationExpanded: widget.translationExpanded,
      onToggleTranslation: widget.onToggleTranslation,
      reasoningText: widget.reasoningText,
      reasoningExpanded: widget.reasoningExpanded,
      reasoningLoading: widget.reasoningLoading,
      reasoningStartAt: widget.reasoningStartAt,
      reasoningFinishedAt: widget.reasoningFinishedAt,
      onToggleReasoning: widget.onToggleReasoning,
      reasoningSegments: widget.reasoningSegments,
      toolParts: widget.toolParts,
      latestSearchItems: _latestSearchItems(),
      onShowCitations: () => _showCitationsSheet(_latestSearchItems()),
      onCitationTap: (id) => _handleCitationTap(id),
      usingInlineThink: usingInlineThink,
      inlineThinkExpanded: _inlineThinkExpanded,
      onToggleInlineThink: () {
        setState(() {
          _inlineThinkExpanded = !(_inlineThinkExpanded ?? true);
          _inlineThinkManuallyToggled = true;
        });
      },
      extractedThinking: extractedThinking,
      contentWithoutThink: contentWithoutThink,
      onRegenerate: widget.onRegenerate,
      onCopy: widget.onCopy,
      onTranslate: widget.onTranslate,
      onSpeak: widget.onSpeak,
      onDelete: widget.onDelete,
      onMore: widget.onMore,
      versionIndex: widget.versionIndex,
      versionCount: widget.versionCount,
      onPrevVersion: widget.onPrevVersion,
      onNextVersion: widget.onNextVersion,
    );
  }
}
