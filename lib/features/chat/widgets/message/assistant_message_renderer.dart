import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/models/chat_message.dart';
import '../../../../core/providers/assistant_provider.dart';
import '../../../../core/providers/model_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/providers/tts_provider.dart';
import '../../../../desktop/menu_anchor.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/animated_loading_text.dart';
import '../../../../shared/widgets/markdown_with_highlight.dart';
import '../../../../shared/widgets/snackbar.dart';
import '../../../../shared/widgets/typing_indicator.dart';
import '../../../../utils/avatar_cache.dart';
import '../../../../utils/local_image_provider.dart';
import '../../../../utils/platform_utils.dart';
import '../../../../utils/safe_tooltip.dart';
import 'message_models.dart';
import 'message_parts.dart';
import 'reasoning_section.dart';
import 'tool_call_item.dart';

class AssistantMessageRenderer extends StatefulWidget {
  final ChatMessage message;
  final Widget? modelIcon;
  final bool showModelIcon;
  final bool useAssistantAvatar;
  final String? assistantName;
  final String? assistantAvatar;
  final bool showTokenStats;
  final bool translationExpanded;
  final VoidCallback? onToggleTranslation;
  final String? reasoningText;
  final bool reasoningExpanded;
  final bool reasoningLoading;
  final DateTime? reasoningStartAt;
  final DateTime? reasoningFinishedAt;
  final VoidCallback? onToggleReasoning;
  final List<ReasoningSegment>? reasoningSegments;
  final List<ToolUIPart>? toolParts;
  final List<Map<String, dynamic>> latestSearchItems;
  final VoidCallback? onShowCitations;
  final Function(String)? onCitationTap;
  final bool usingInlineThink;
  final bool? inlineThinkExpanded;
  final VoidCallback? onToggleInlineThink;
  final String extractedThinking;
  final String contentWithoutThink;
  final VoidCallback? onRegenerate;
  final VoidCallback? onCopy;
  final VoidCallback? onTranslate;
  final VoidCallback? onSpeak;
  final VoidCallback? onDelete;
  final VoidCallback? onMore;
  final VoidCallback? onMentionReAnswer;
  final int? versionIndex;
  final int? versionCount;
  final VoidCallback? onPrevVersion;
  final VoidCallback? onNextVersion;
  final bool isGenerating;

  const AssistantMessageRenderer({
    super.key,
    required this.message,
    this.modelIcon,
    this.showModelIcon = true,
    this.useAssistantAvatar = false,
    this.assistantName,
    this.assistantAvatar,
    this.showTokenStats = true,
    this.translationExpanded = false,
    this.onToggleTranslation,
    this.reasoningText,
    this.reasoningExpanded = false,
    this.reasoningLoading = false,
    this.reasoningStartAt,
    this.reasoningFinishedAt,
    this.onToggleReasoning,
    this.reasoningSegments,
    this.toolParts,
    this.latestSearchItems = const [],
    this.onShowCitations,
    this.onCitationTap,
    this.usingInlineThink = false,
    this.inlineThinkExpanded,
    this.onToggleInlineThink,
    this.extractedThinking = '',
    this.contentWithoutThink = '',
    this.onRegenerate,
    this.onCopy,
    this.onTranslate,
    this.onSpeak,
    this.onDelete,
    this.onMore,
    this.onMentionReAnswer,
    this.versionIndex,
    this.versionCount,
    this.onPrevVersion,
    this.onNextVersion,
    this.isGenerating = false,
  });

  @override
  State<AssistantMessageRenderer> createState() => _AssistantMessageRendererState();
}

class _AssistantMessageRendererState extends State<AssistantMessageRenderer> {
  static final DateFormat _dateFormat = DateFormat('HH:mm');

  String _resolveModelDisplayName(SettingsProvider settings) {
    final modelId = widget.message.modelId;
    if (modelId == null || modelId.trim().isEmpty) return 'AI Assistant';

    String? providerName;
    String? modelName;

    final providerId = widget.message.providerId;
    if (providerId != null && providerId.isNotEmpty) {
      try {
        final cfg = settings.getProviderConfig(providerId);
        providerName = cfg.name.trim().isNotEmpty ? cfg.name : null;
        final ov = cfg.modelOverrides[modelId] as Map?;
        modelName = (ov?['name'] as String?)?.trim();
      } catch (_) {}
    }

    if (modelName == null || modelName.isEmpty) {
      final inferred = ModelRegistry.infer(ModelInfo(id: modelId, displayName: modelId));
      modelName = inferred.displayName.trim();
      if (modelName.isEmpty) modelName = modelId;
    }

    if (providerName != null && providerName.isNotEmpty) {
      return '$modelName | $providerName';
    }
    return modelName;
  }

  Widget _buildAssistantAvatar(ColorScheme cs) {
    final av = (widget.assistantAvatar ?? '').trim();
    if (av.isNotEmpty) {
      if (av.startsWith('http')) {
        return FutureBuilder<String?>(
          future: AvatarCache.getPath(av),
          builder: (ctx, snap) {
            final p = snap.data;
            if (p != null && !kIsWeb && PlatformUtils.fileExistsSync(p)) {
              return ClipOval(child: Image(image: localFileImage(p), width: 32, height: 32, fit: BoxFit.cover));
            }
            if (p != null && kIsWeb && p.startsWith('data:')) {
              return ClipOval(child: Image.network(p, width: 32, height: 32, fit: BoxFit.cover));
            }
            return ClipOval(
              child: Image.network(av, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _assistantInitial(cs)),
            );
          },
        );
      }
      if (!kIsWeb && (av.startsWith('/') || av.contains(':') || av.contains('/'))) {
        return FutureBuilder<String?>(
          future: AssistantProvider.resolveToAbsolutePath(av),
          builder: (ctx, snap) {
            if (!snap.hasData || snap.data == null) return _assistantInitial(cs);
            if (!PlatformUtils.fileExistsSync(snap.data!)) return _assistantInitial(cs);
            return ClipOval(
              child: Image(image: localFileImage(snap.data!), width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _assistantInitial(cs)),
            );
          },
        );
      }
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: cs.primary.withOpacity(0.1), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(av.characters.take(1).toString(), style: const TextStyle(fontSize: 18)),
      );
    }
    return _assistantInitial(cs);
  }

  Widget _assistantInitial(ColorScheme cs) {
    final name = (widget.assistantName ?? '').trim();
    final ch = name.isNotEmpty ? name.characters.first.toUpperCase() : 'A';
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: cs.primary.withOpacity(0.1), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(ch, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
    );
  }

  Widget _wrapAssistantBubble(BuildContext context, SettingsProvider settings, Widget child) {
    final opacity = settings.chatMessageBubbleOpacity.clamp(0.0, 1.0);
    if (opacity <= 0.0001) return child;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = settings.chatMessageBackgroundStyle;
    final radius = BorderRadius.circular(16);

    Color bg;
    double blur = 0;
    switch (style) {
      case ChatMessageBackgroundStyle.frosted:
        bg = Colors.white.withOpacity(opacity * (isDark ? 0.12 : 0.70));
        blur = 6 + 10 * opacity;
        break;
      case ChatMessageBackgroundStyle.solid:
        bg = cs.surfaceVariant.withOpacity(opacity);
        blur = 0;
        break;
      case ChatMessageBackgroundStyle.defaultStyle:
      default:
        bg = cs.surface.withOpacity(opacity * (isDark ? 0.20 : 0.16));
        blur = 0;
    }

    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: cs.outlineVariant.withOpacity(opacity * 0.25), width: 1),
      ),
      child: child,
    );

    if (blur <= 0) return box;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: box),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final isDesktop = !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 10 : 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(cs, settings),
          const SizedBox(height: 8),
          Builder(
            builder: (ctx) => _wrapAssistantBubble(ctx, settings, _buildContent(cs, l10n, settings)),
          ),
          if (widget.latestSearchItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            SourcesSummaryCard(count: widget.latestSearchItems.length, onTap: widget.onShowCitations ?? () {}),
          ],
          if (!widget.message.isStreaming) _buildActions(cs, l10n),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, SettingsProvider settings) {
    return Row(
      children: [
        if (widget.useAssistantAvatar) ...[
          _buildAssistantAvatar(cs),
          const SizedBox(width: 8),
        ] else if (widget.showModelIcon) ...[
          widget.modelIcon ??
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: cs.secondary.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(Lucide.Bot, size: 18, color: cs.secondary),
              ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (settings.showModelNameTimestamp)
                Text(
                  _resolveModelDisplayName(settings),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface.withOpacity(0.7)),
                ),
              _buildTokenStats(cs, settings),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTokenStats(ColorScheme cs, SettingsProvider settings) {
    final List<Widget> rowChildren = [];
    
    if (settings.showModelNameTimestamp) {
      rowChildren.add(
        Text(_dateFormat.format(widget.message.timestamp), style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
      );
    }
    
    if (widget.showTokenStats) {
      final tokenUsage = widget.message.tokenUsage;
      if (tokenUsage != null) {
        if (rowChildren.isNotEmpty) rowChildren.add(const SizedBox(width: 8));
        rowChildren.add(_buildTokenDisplay(cs, tokenUsage));
      } else if (widget.message.totalTokens != null) {
        if (rowChildren.isNotEmpty) rowChildren.add(const SizedBox(width: 8));
        rowChildren.add(
          Text('${widget.message.totalTokens} tokens', style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
        );
      }
    }
    
    return rowChildren.isNotEmpty ? Row(children: rowChildren) : const SizedBox.shrink();
  }

  Widget _buildTokenDisplay(ColorScheme cs, dynamic tokenUsage) {
    final List<String> tokenParts = [];
    tokenParts.add('${tokenUsage.promptTokens}↓');
    tokenParts.add('${tokenUsage.completionTokens}↑');
    if (tokenUsage.thoughtTokens > 0) tokenParts.add('${tokenUsage.thoughtTokens}💭');
    if (tokenUsage.cachedTokens > 0) tokenParts.add('${tokenUsage.cachedTokens}♻');
    
    try {
      if (widget.message.tokenUsageJson != null) {
        final json = jsonDecode(widget.message.tokenUsageJson!) as Map<String, dynamic>;
        final tokenSpeed = json['token_speed'] as num?;
        final timeFirstTokenMs = json['time_first_token_millsec'] as int?;
        if (tokenSpeed != null && tokenSpeed > 0) tokenParts.add('${tokenSpeed.toStringAsFixed(1)}tok/s');
        if (timeFirstTokenMs != null && timeFirstTokenMs > 0) tokenParts.add('${timeFirstTokenMs}ms⚡');
      }
    } catch (_) {}
    
    final tooltipLines = _buildTooltipLines(tokenUsage);
    
    return TokenUsageDisplay(
      tokenText: tokenParts.join(' '),
      tooltipLines: tooltipLines,
      hasCache: tokenUsage.cachedTokens > 0,
      colorScheme: cs,
      rounds: tokenUsage.rounds,
    );
  }

  List<String> _buildTooltipLines(dynamic tokenUsage) {
    final List<String> lines = [];
    
    if (tokenUsage.rounds != null && tokenUsage.rounds!.length > 1) {
      for (int i = 0; i < tokenUsage.rounds!.length; i++) {
        final round = tokenUsage.rounds![i];
        lines.add('第 ${i + 1} 轮:');
        lines.add('  输入: ${round['promptTokens'] ?? 0}');
        lines.add('  输出: ${round['completionTokens'] ?? 0}');
        if ((round['thoughtTokens'] ?? 0) > 0) lines.add('  思考: ${round['thoughtTokens']}');
        if ((round['cachedTokens'] ?? 0) > 0) lines.add('  缓存: ${round['cachedTokens']}');
      }
      lines.add('---');
      lines.add('总计:');
    }
    
    lines.add('输入: ${tokenUsage.promptTokens}');
    lines.add('输出: ${tokenUsage.completionTokens}');
    if (tokenUsage.thoughtTokens > 0) lines.add('思考: ${tokenUsage.thoughtTokens}');
    if (tokenUsage.cachedTokens > 0) lines.add('缓存: ${tokenUsage.cachedTokens}');
    lines.add('总计: ${tokenUsage.totalTokens}');
    
    try {
      if (widget.message.tokenUsageJson != null) {
        final json = jsonDecode(widget.message.tokenUsageJson!) as Map<String, dynamic>;
        final timeFirstTokenMs = json['time_first_token_millsec'] as int?;
        final tokenSpeed = json['token_speed'] as num?;
        if (timeFirstTokenMs != null || tokenSpeed != null) {
          lines.add('---');
          if (timeFirstTokenMs != null && timeFirstTokenMs > 0) lines.add('首字: ${timeFirstTokenMs}ms');
          if (tokenSpeed != null && tokenSpeed > 0) lines.add('速度: ${tokenSpeed.toStringAsFixed(1)} tok/s');
        }
      }
    } catch (_) {}
    
    return lines;
  }

  Widget _buildContent(ColorScheme cs, AppLocalizations l10n, SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.reasoningSegments != null && widget.reasoningSegments!.isNotEmpty)
          ..._buildMixedContent(settings)
        else
          ..._buildLegacyContent(settings),
        _buildMainContent(cs, l10n),
      ],
    );
  }

  List<Widget> _buildMixedContent(SettingsProvider settings) {
    final List<Widget> mixedContent = [];
    final tools = widget.toolParts ?? const <ToolUIPart>[];
    final segments = widget.reasoningSegments!;

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.text.isNotEmpty) {
        mixedContent.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ReasoningSection(
              text: seg.text,
              expanded: seg.expanded,
              loading: seg.loading,
              startAt: seg.startAt,
              finishedAt: seg.finishedAt,
              onToggle: seg.onToggle,
            ),
          ),
        );
      }

      int start = seg.toolStartIndex;
      final int end = (i < segments.length - 1) ? segments[i + 1].toolStartIndex : tools.length;
      if (start < 0) start = 0;
      if (start > tools.length) start = tools.length;
      final int clampedEnd = end.clamp(start, tools.length);

      for (int k = start; k < clampedEnd; k++) {
        if (tools[k].toolName == 'builtin_search') continue;
        if (tools[k].toolName == 'get_sticker' && !settings.showStickerToolUI) continue;
        mixedContent.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: ToolCallItem(part: tools[k])));
      }
    }

    return mixedContent;
  }

  List<Widget> _buildLegacyContent(SettingsProvider settings) {
    final hasProvidedReasoning = (widget.reasoningText != null && widget.reasoningText!.isNotEmpty) || widget.reasoningLoading;
    final effectiveReasoningText =
        (widget.reasoningText != null && widget.reasoningText!.isNotEmpty) ? widget.reasoningText! : widget.extractedThinking;
    final shouldShowReasoning = hasProvidedReasoning || effectiveReasoningText.isNotEmpty;

    final List<Widget> content = [];

    if (shouldShowReasoning) {
      final effectiveExpanded = widget.usingInlineThink ? (widget.inlineThinkExpanded ?? true) : widget.reasoningExpanded;
      final collapsedNow = widget.usingInlineThink && (widget.inlineThinkExpanded == false);
      final effectiveLoading = widget.usingInlineThink
          ? (widget.message.isStreaming && !widget.message.content.contains('</think>') && !collapsedNow)
          : (widget.reasoningFinishedAt == null);

      content.add(
        ReasoningSection(
          text: effectiveReasoningText,
          expanded: effectiveExpanded,
          loading: effectiveLoading,
          startAt: widget.usingInlineThink ? null : widget.reasoningStartAt,
          finishedAt: widget.usingInlineThink ? null : widget.reasoningFinishedAt,
          onToggle: widget.usingInlineThink ? widget.onToggleInlineThink : widget.onToggleReasoning,
        ),
      );
      content.add(const SizedBox(height: 8));
    }

    if ((widget.toolParts ?? const <ToolUIPart>[])
        .where((p) => p.toolName != 'builtin_search' && (p.toolName != 'get_sticker' || settings.showStickerToolUI))
        .isNotEmpty) {
      content.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widget.toolParts!
              .where((p) => p.toolName != 'builtin_search' && (p.toolName != 'get_sticker' || settings.showStickerToolUI))
              .map((p) => Padding(padding: const EdgeInsets.only(bottom: 8), child: ToolCallItem(part: p)))
              .toList(),
        ),
      );
      content.add(const SizedBox(height: 8));
    }

    return content;
  }

  Widget _buildMainContent(ColorScheme cs, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      child: widget.message.isStreaming && widget.contentWithoutThink.isEmpty
          ? AnimatedLoadingText(
              text: l10n.chatMessageWidgetThinking,
              textStyle: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.6), fontStyle: FontStyle.italic),
              dotSize: 8,
              dotGap: 3,
              style: LoadingTextStyle.modern,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 15.7, height: 1.5),
                  child: MarkdownWithCodeHighlight(
                    text: widget.contentWithoutThink,
                    onCitationTap: widget.onCitationTap,
                    isStreaming: widget.message.role == 'assistant' && widget.message.isStreaming,
                  ),
                ),
                if (widget.message.isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: DotsTypingIndicator(color: cs.primary, dotSize: 7, gap: 3),
                  ),
                if (widget.message.translation != null && widget.message.translation!.isNotEmpty)
                  _buildTranslation(cs, l10n),
              ],
            ),
    );
  }

  Widget _buildTranslation(ColorScheme cs, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.30),
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: const Cubic(0.2, 0.8, 0.2, 1),
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: widget.onToggleTranslation,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Lucide.Languages, size: 16, color: cs.secondary),
                      const SizedBox(width: 6),
                      Text(l10n.chatMessageWidgetTranslation, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.secondary)),
                      const Spacer(),
                      Icon(widget.translationExpanded ? Lucide.ChevronDown : Lucide.ChevronRight, size: 18, color: cs.secondary),
                    ],
                  ),
                ),
              ),
              if (widget.translationExpanded) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                  child: widget.message.translation == l10n.chatMessageWidgetTranslating
                      ? Row(
                          children: [
                            const LoadingIndicator(),
                            const SizedBox(width: 8),
                            Text(l10n.chatMessageWidgetTranslating, style: TextStyle(fontSize: 15.5, color: cs.onSurface.withOpacity(0.5), fontStyle: FontStyle.italic)),
                          ],
                        )
                      : DefaultTextStyle.merge(
                          style: const TextStyle(fontSize: 15.5, height: 1.4),
                          child: MarkdownWithCodeHighlight(text: widget.message.translation!, onCitationTap: widget.onCitationTap, isStreaming: false),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(ColorScheme cs, AppLocalizations l10n) {
    // Hide most actions while generating, only show copy and branch selector
    if (widget.isGenerating) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Lucide.Copy, size: 16),
              onPressed: widget.onCopy ?? () {
                Clipboard.setData(ClipboardData(text: widget.message.content));
                showAppSnackBar(context, message: l10n.chatMessageWidgetCopiedToClipboard, type: NotificationType.success);
              },
              visualDensity: VisualDensity.compact,
              iconSize: 16,
            ),
            if ((widget.versionCount ?? 1) > 1) ...[
              const SizedBox(width: 6),
              BranchSelector(
                index: widget.versionIndex ?? 0,
                total: widget.versionCount ?? 1,
                onPrev: widget.onPrevVersion,
                onNext: widget.onNextVersion,
              ),
            ],
          ],
        ),
      );
    }
    
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Lucide.Copy, size: 16),
            onPressed: widget.onCopy ?? () {
              Clipboard.setData(ClipboardData(text: widget.message.content));
              showAppSnackBar(context, message: l10n.chatMessageWidgetCopiedToClipboard, type: NotificationType.success);
            },
            visualDensity: VisualDensity.compact,
            iconSize: 16,
          ),
          IconButton(
            icon: Icon(Lucide.RefreshCw, size: 16),
            onPressed: widget.onRegenerate,
            tooltip: safeTooltipMessage(l10n.chatMessageWidgetRegenerateTooltip),
            visualDensity: VisualDensity.compact,
            iconSize: 16,
          ),
          IconButton(
            icon: Icon(Lucide.AtSign, size: 16),
            onPressed: widget.onMentionReAnswer,
            tooltip: safeTooltipMessage('@'),
            visualDensity: VisualDensity.compact,
            iconSize: 16,
          ),
          Consumer<TtsProvider>(
            builder: (context, tts, _) => IconButton(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
                child: Icon(tts.isSpeaking ? Lucide.CircleStop : Lucide.Volume2, key: ValueKey(tts.isSpeaking), size: 16),
              ),
              onPressed: widget.onSpeak,
              tooltip: safeTooltipMessage(tts.isSpeaking ? l10n.chatMessageWidgetStopTooltip : l10n.chatMessageWidgetSpeakTooltip),
              visualDensity: VisualDensity.compact,
              iconSize: 16,
            ),
          ),
          IconButton(
            icon: Icon(Lucide.Languages, size: 16),
            onPressed: widget.onTranslate,
            tooltip: safeTooltipMessage(l10n.chatMessageWidgetTranslateTooltip),
            visualDensity: VisualDensity.compact,
            iconSize: 16,
          ),
          IconButton(
            icon: Icon(Lucide.Trash2, size: 16),
            onPressed: widget.onDelete,
            tooltip: safeTooltipMessage(l10n.homePageDelete),
            visualDensity: VisualDensity.compact,
            iconSize: 16,
          ),
          Builder(
            builder: (btnContext) => IconButton(
              icon: Icon(Lucide.Ellipsis, size: 16),
              onPressed: widget.onMore == null
                  ? null
                  : () {
                      final renderBox = btnContext.findRenderObject() as RenderBox?;
                      if (renderBox != null) {
                        final offset = renderBox.localToGlobal(Offset.zero);
                        final size = renderBox.size;
                        DesktopMenuAnchor.setPosition(Offset(offset.dx + size.width, offset.dy + size.height / 2));
                      }
                      widget.onMore!();
                    },
              tooltip: safeTooltipMessage(l10n.chatMessageWidgetMoreTooltip),
              visualDensity: VisualDensity.compact,
              iconSize: 16,
            ),
          ),
          if ((widget.versionCount ?? 1) > 1) ...[
            const SizedBox(width: 6),
            BranchSelector(
              index: widget.versionIndex ?? 0,
              total: widget.versionCount ?? 1,
              onPrev: widget.onPrevVersion,
              onNext: widget.onNextVersion,
            ),
          ],
        ],
      ),
    );
  }
}
