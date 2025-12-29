import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/widgets/chat_message_widget.dart';
import '../../chat/widgets/message_more_sheet.dart';
import '../state/reasoning_state.dart';
import '../services/streaming_content_notifier.dart';
import 'home_helper_widgets.dart';
import '../../../shared/widgets/ios_checkbox.dart';

/// Data class for translation UI state (extracted from home_page.dart)
class TranslationUiState {
  bool expanded = true;
}

/// Callback types for message list view actions
typedef OnVersionChange = Future<void> Function(String groupId, int version);
typedef OnRegenerateMessage = void Function(ChatMessage message);
typedef OnResendMessage = void Function(ChatMessage message);
typedef OnTranslateMessage = void Function(ChatMessage message);
typedef OnEditMessage = void Function(ChatMessage message);
typedef OnDeleteMessage = Future<void> Function(ChatMessage message, Map<String, List<ChatMessage>> byGroup);
typedef OnForkConversation = Future<void> Function(ChatMessage message);
typedef OnShareMessage = void Function(int messageIndex, List<ChatMessage> messages);
typedef OnSpeakMessage = Future<void> Function(ChatMessage message);

/// Widget that displays the chat message list.
///
/// This widget extracts the ListView.builder logic from HomePageState
/// to reduce coupling and improve maintainability.
class MessageListView extends StatelessWidget {
  const MessageListView({
    super.key,
    required this.scrollController,
    required this.messages,
    required this.versionSelections,
    required this.currentConversation,
    required this.messageKeys,
    required this.reasoning,
    required this.translations,
    required this.selecting,
    required this.selectedItems,
    required this.toolParts,
    required this.streamingNotifier,
    this.onVersionChange,
    this.onRegenerateMessage,
    this.onResendMessage,
    this.onTranslateMessage,
    this.onEditMessage,
    this.onDeleteMessage,
    this.onForkConversation,
    this.onShareMessage,
    this.onSpeakMessage,
    this.onToggleSelection,
    this.onToggleReasoning,
    this.onToggleTranslation,
    this.onToggleReasoningSegment,
    this.onMentionReAnswer,
    this.onSend,
    this.reasoningSegments,
    this.clearContextLabel,
    this.pinnedStreamingMessageId,
    this.isPinnedIndicatorActive = false,
  });

  final ScrollController scrollController;
  final List<ChatMessage> messages;
  final Map<String, int> versionSelections;
  final Conversation? currentConversation;
  final Map<String, GlobalKey> messageKeys;
  final Map<String, ReasoningData> reasoning;
  final Map<String, TranslationUiState> translations;
  final Map<String, List<dynamic>> toolParts; 
  final bool selecting;
  final Set<String> selectedItems;
  final StreamingContentNotifier streamingNotifier;

  // Callbacks
  final OnVersionChange? onVersionChange;
  final OnRegenerateMessage? onRegenerateMessage;
  final OnResendMessage? onResendMessage;
  final OnTranslateMessage? onTranslateMessage;
  final OnEditMessage? onEditMessage;
  final OnDeleteMessage? onDeleteMessage;
  final OnForkConversation? onForkConversation;
  final OnShareMessage? onShareMessage;
  final OnSpeakMessage? onSpeakMessage;
  final void Function(String messageId, bool selected)? onToggleSelection;
  final void Function(String messageId)? onToggleReasoning;
  final void Function(String messageId)? onToggleTranslation;
  final void Function(String messageId, int segmentIndex)? onToggleReasoningSegment;
  final void Function(ChatMessage message)? onMentionReAnswer;
  final ValueChanged<String>? onSend;

  final Map<String, List<ReasoningSegmentData>>? reasoningSegments;
  final String? clearContextLabel;
  final String? pinnedStreamingMessageId;
  final bool isPinnedIndicatorActive;

  /// Collapse message versions to show only selected version per group.
  List<ChatMessage> _collapseVersions(List<ChatMessage> items) {
    final Map<String, List<ChatMessage>> byGroup = <String, List<ChatMessage>>{};
    final List<String> order = <String>[];
    for (final m in items) {
      final gid = (m.groupId ?? m.id);
      final list = byGroup.putIfAbsent(gid, () {
        order.add(gid);
        return <ChatMessage>[];
      });
      list.add(m);
    }
    for (final e in byGroup.entries) {
      e.value.sort((a, b) => a.version.compareTo(b.version));
    }
    final out = <ChatMessage>[];
    for (final gid in order) {
      final vers = byGroup[gid]!;
      final sel = versionSelections[gid];
      final idx = (sel != null && sel >= 0 && sel < vers.length) ? sel : (vers.length - 1);
      out.add(vers[idx]);
    }
    return out;
  }

  /// Group messages by their group ID for version navigation.
  Map<String, List<ChatMessage>> _groupMessages(List<ChatMessage> items) {
    final Map<String, List<ChatMessage>> byGroup = <String, List<ChatMessage>>{};
    for (final m in items) {
      final gid = (m.groupId ?? m.id);
      byGroup.putIfAbsent(gid, () => <ChatMessage>[]).add(m);
    }
    return byGroup;
  }

  /// Build the context divider widget shown at truncate position.
  Widget _buildContextDivider(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final label = clearContextLabel ?? l10n.homePageClearContext;
    return Row(
      children: [
        Expanded(child: Divider(color: cs.outlineVariant.withOpacity(0.6), height: 1, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
        ),
        Expanded(child: Divider(color: cs.outlineVariant.withOpacity(0.6), height: 1, thickness: 1)),
      ],
    );
  }

  GlobalKey _keyForMessage(String id) => messageKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'msg:$id'));

  @override
  Widget build(BuildContext context) {
    final collapsedMessages = _collapseVersions(messages);
    final byGroup = _groupMessages(messages);

    final int truncRaw = currentConversation?.truncateIndex ?? -1;
    int truncCollapsed = -1;
    if (truncRaw > 0) {
      final seen = <String>{};
      final int limit = truncRaw < messages.length ? truncRaw : messages.length;
      int count = 0;
      for (int i = 0; i < limit; i++) {
        final gid0 = (messages[i].groupId ?? messages[i].id);
        if (seen.add(gid0)) count++;
      }
      truncCollapsed = count - 1;
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      itemCount: collapsedMessages.length,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemBuilder: (context, index) {
        if (index < 0 || index >= collapsedMessages.length) {
          return const SizedBox.shrink();
        }
        return _buildMessageItem(
          context,
          index: index,
          messages: collapsedMessages,
          byGroup: byGroup,
          truncCollapsed: truncCollapsed,
        );
      },
    );
  }

  Widget _buildMessageItem(
    BuildContext context, {
    required int index,
    required List<ChatMessage> messages,
    required Map<String, List<ChatMessage>> byGroup,
    required int truncCollapsed,
  }) {
    final message = messages[index];
    final r = reasoning[message.id];
    final t = translations[message.id];
    final assistant = context.watch<AssistantProvider>().currentAssistant;
    final useAssist = assistant?.useAssistantAvatar == true;
    final showDivider = truncCollapsed >= 0 && index == truncCollapsed;
    final gid = (message.groupId ?? message.id);
    final vers = (byGroup[gid] ?? const <ChatMessage>[]).toList()..sort((a, b) => a.version.compareTo(b.version));
    int selectedIdx = versionSelections[gid] ?? (vers.isNotEmpty ? vers.length - 1 : 0);
    final total = vers.length;
    if (selectedIdx < 0) selectedIdx = 0;
    if (total > 0 && selectedIdx > total - 1) selectedIdx = total - 1;
    final showMsgNav = context.watch<SettingsProvider>().showMessageNavButtons;
    final effectiveTotal = showMsgNav ? total : 1;
    final effectiveIndex = showMsgNav ? selectedIdx : 0;

    final isStreaming = message.isStreaming &&
        message.role == 'assistant' &&
        streamingNotifier.hasNotifier(message.id);

    return Column(
      key: _keyForMessage(message.id),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selecting && (message.role == 'user' || message.role == 'assistant'))
              Padding(
                padding: const EdgeInsets.only(left: 10, right: 6),
                child: IosCheckbox(
                  value: selectedItems.contains(message.id),
                  onChanged: (v) {
                    onToggleSelection?.call(message.id, v ?? false);
                  },
                ),
              ),
            Expanded(
              child: Builder(
                builder: (context) {
                  final textScale = MediaQuery.textScaleFactorOf(context);
                  final chatScale = context.watch<SettingsProvider>().chatFontScale;
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaleFactor: textScale * chatScale,
                    ),
                    child: isStreaming
                        ? _buildStreamingMessageWidget(
                            context,
                            message: message,
                            index: index,
                            messages: messages,
                            byGroup: byGroup,
                            r: r,
                            t: t,
                            useAssist: useAssist,
                            assistant: assistant,
                            showMsgNav: showMsgNav,
                            gid: gid,
                            selectedIdx: selectedIdx,
                            total: total,
                            effectiveIndex: effectiveIndex,
                            effectiveTotal: effectiveTotal,
                          )
                        : _buildChatMessageWidget(
                            context,
                            message: message,
                            index: index,
                            messages: messages,
                            byGroup: byGroup,
                            r: r,
                            t: t,
                            useAssist: useAssist,
                            assistant: assistant,
                            showMsgNav: showMsgNav,
                            gid: gid,
                            selectedIdx: selectedIdx,
                            total: total,
                            effectiveIndex: effectiveIndex,
                            effectiveTotal: effectiveTotal,
                          ),
                  );
                },
              ),
            ),
          ],
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4, left: 24, right: 24),
            child: _buildContextDivider(context),
          ),
      ],
    );
  }

  Widget _buildStreamingMessageWidget(
    BuildContext context, {
    required ChatMessage message,
    required int index,
    required List<ChatMessage> messages,
    required Map<String, List<ChatMessage>> byGroup,
    required ReasoningData? r,
    required TranslationUiState? t,
    required bool useAssist,
    required dynamic assistant,
    required bool showMsgNav,
    required String gid,
    required int selectedIdx,
    required int total,
    required int effectiveIndex,
    required int effectiveTotal,
  }) {
    return ValueListenableBuilder<StreamingContentData>(
      valueListenable: streamingNotifier.getNotifier(message.id),
      builder: (context, data, child) {
        final displayContent = data.content.isNotEmpty ? data.content : message.content;
        final streamingMessage = message.copyWith(
          content: displayContent,
          tokenUsageJson: data.tokenUsageJson,
        );

        ReasoningData? streamingReasoning = r;
        final rText = data.reasoningText;
        if (rText != null && rText.isNotEmpty) {
           if (r != null) {
              r.text = rText;
              r.startAt = data.reasoningStartAt;
              if (data.reasoningFinishedAt != null) {
                r.finishedAt = data.reasoningFinishedAt;
              }
              streamingReasoning = r;
           } else {
              streamingReasoning = ReasoningData()
                ..text = rText
                ..startAt = data.reasoningStartAt
                ..finishedAt = data.reasoningFinishedAt
                ..expanded = false;
           }
        }

        return RepaintBoundary(
          child: _buildChatMessageWidget(
            context,
            message: streamingMessage,
            index: index,
            messages: messages,
            byGroup: byGroup,
            r: streamingReasoning,
            t: t,
            useAssist: useAssist,
            assistant: assistant,
            showMsgNav: showMsgNav,
            gid: gid,
            selectedIdx: selectedIdx,
            total: total,
            effectiveIndex: effectiveIndex,
            effectiveTotal: effectiveTotal,
          ),
        );
      },
    );
  }

  Widget _buildChatMessageWidget(
    BuildContext context, {
    required ChatMessage message,
    required int index,
    required List<ChatMessage> messages,
    required Map<String, List<ChatMessage>> byGroup,
    required ReasoningData? r,
    required TranslationUiState? t,
    required bool useAssist,
    required dynamic assistant,
    required bool showMsgNav,
    required String gid,
    required int selectedIdx,
    required int total,
    required int effectiveIndex,
    required int effectiveTotal,
  }) {
    return ChatMessageWidget(
      message: message,
      allMessages: messages,
      allToolParts: toolParts as Map<String, List<ToolUIPart>>?,
      toolParts: (message.role == 'assistant') ? (toolParts[message.id] as List<ToolUIPart>?) : null,
      versionIndex: effectiveIndex,
      versionCount: effectiveTotal,
      onPrevVersion: (showMsgNav && selectedIdx > 0)
          ? () => onVersionChange?.call(gid, selectedIdx - 1)
          : null,
      onNextVersion: (showMsgNav && selectedIdx < total - 1)
          ? () => onVersionChange?.call(gid, selectedIdx + 1)
          : null,
      modelIcon: (!useAssist && message.role == 'assistant' && message.providerId != null && message.modelId != null)
          ? CurrentModelIcon(providerKey: message.providerId, modelId: message.modelId, size: 30)
          : null,
      showModelIcon: useAssist ? false : context.watch<SettingsProvider>().showModelIcon,
      useAssistantAvatar: useAssist && message.role == 'assistant',
      assistantName: useAssist ? (assistant?.name ?? 'Assistant') : null,
      assistantAvatar: useAssist ? (assistant?.avatar ?? '') : null,
      showUserAvatar: context.watch<SettingsProvider>().showUserAvatar,
      showTokenStats: context.watch<SettingsProvider>().showTokenStats,
      reasoningText: (message.role == 'assistant') ? (r?.text ?? '') : null,
      reasoningExpanded: (message.role == 'assistant') ? (r?.expanded ?? false) : false,
      reasoningLoading: (message.role == 'assistant') ? (r?.finishedAt == null && (r?.text.isNotEmpty == true)) : false,
      reasoningStartAt: (message.role == 'assistant') ? r?.startAt : null,
      reasoningFinishedAt: (message.role == 'assistant') ? r?.finishedAt : null,
      onToggleReasoning: (message.role == 'assistant' && r != null)
          ? () => onToggleReasoning?.call(message.id)
          : null,
      translationExpanded: t?.expanded ?? true,
      onToggleTranslation: (message.translation != null && message.translation!.isNotEmpty && t != null)
          ? () => onToggleTranslation?.call(message.id)
          : null,
      onRegenerate: message.role == 'assistant' ? () => onRegenerateMessage?.call(message) : null,
      onResend: message.role == 'user' ? () => onResendMessage?.call(message) : null,
      onTranslate: message.role == 'assistant' ? () => onTranslateMessage?.call(message) : null,
      onSpeak: message.role == 'assistant' ? () => onSpeakMessage?.call(message) : null,
      onMentionReAnswer: message.role == 'assistant' ? () => onMentionReAnswer?.call(message) : null,
      onEdit: (message.role == 'user' || message.role == 'assistant')
          ? () => onEditMessage?.call(message)
          : null,
      onDelete: () => onDeleteMessage?.call(message, byGroup),
      onMore: () async {
        final action = await showMessageMoreSheet(context, message);
        if (action == MessageMoreAction.delete) {
          await onDeleteMessage?.call(message, byGroup);
        } else if (action == MessageMoreAction.edit) {
          onEditMessage?.call(message);
        } else if (action == MessageMoreAction.fork) {
          await onForkConversation?.call(message);
        } else if (action == MessageMoreAction.share) {
          onShareMessage?.call(index, messages);
        }
      },
      reasoningSegments: message.role == 'assistant'
          ? _buildReasoningSegments(message.id)
          : null,
    );
  }

  List<ReasoningSegment>? _buildReasoningSegments(String messageId) {
    final segments = reasoningSegments?[messageId];
    if (segments == null || segments.isEmpty) return null;
    return segments.asMap().entries.map((entry) {
      final idx = entry.key;
      final s = entry.value;
      return ReasoningSegment(
        text: s.text,
        expanded: s.expanded,
        loading: s.finishedAt == null && s.text.isNotEmpty,
        startAt: s.startAt,
        finishedAt: s.finishedAt,
        onToggle: () => onToggleReasoningSegment?.call(messageId, idx),
        toolStartIndex: s.toolStartIndex,
      );
    }).toList();
  }
}
