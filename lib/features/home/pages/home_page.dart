import 'package:flutter/material.dart';
import '../../../utils/platform_utils.dart';
import '../state/reasoning_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import 'dart:async';
import 'dart:convert';
// Replaced flutter_zoom_drawer with a custom InteractiveDrawer
import '../../../shared/widgets/interactive_drawer.dart';
import '../../../shared/responsive/breakpoints.dart';

import '../widgets/chat_input_bar.dart';
import '../widgets/mentioned_models_chips.dart';
import '../../../core/models/chat_input_data.dart';
import '../../chat/widgets/bottom_tools_sheet.dart';
import '../widgets/side_drawer.dart';
import '../widgets/message_list_view.dart';
import '../../chat/widgets/chat_message_widget.dart';
import '../../../theme/design_tokens.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:provider/provider.dart';
import '../../../main.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/memory_provider.dart';
import '../../../core/services/chat/prompt_transformer.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/models/chat_stream_chunk.dart';
import '../../../core/services/chat/document_text_extractor.dart';
import '../../../core/services/mcp/mcp_tool_service.dart';
import '../../../core/models/token_usage.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/utils/gemini_thought_signatures.dart';
import '../../model/widgets/model_select_sheet.dart';
import '../../settings/widgets/language_select_sheet.dart';
import '../../chat/widgets/message_more_sheet.dart';
// import '../../chat/pages/message_edit_page.dart';
import '../../chat/widgets/message_edit_sheet.dart';
import '../../chat/widgets/message_export_sheet.dart';
import '../../assistant/widgets/mcp_assistant_sheet.dart';
import '../../mcp/pages/mcp_page.dart';
import '../../provider/pages/providers_page.dart';
import '../../chat/widgets/reasoning_budget_sheet.dart';
import '../../chat/widgets/max_tokens_sheet.dart';
import '../../chat/widgets/tool_loop_sheet.dart';
import '../../search/widgets/search_settings_sheet.dart';
import '../widgets/mini_map_sheet.dart';
import '../widgets/chat_mini_rail.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../desktop/search_provider_popover.dart';
import '../../../desktop/reasoning_budget_popover.dart';
import '../../../desktop/mcp_servers_popover.dart';
import '../../../desktop/max_tokens_popover.dart';
import '../../../desktop/tool_loop_popover.dart';
import '../../../desktop/mini_map_popover.dart';
import '../../../desktop/quick_phrase_popover.dart';
import '../../../utils/brand_assets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'dart:ui' as ui;
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../../../core/services/search/search_tool_service.dart';
import '../../../core/services/sticker/sticker_tool_service.dart';
import '../../../utils/markdown_media_sanitizer.dart';
import '../../../core/services/learning_mode_store.dart';
import '../../../core/services/tool_call_mode_store.dart';
import '../../../core/models/tool_call_mode.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../utils/platform_utils.dart';
import '../../../utils/local_image_provider.dart';
import '../../../core/services/upload/upload_service.dart';
import '../../../shared/animations/widgets.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../core/services/haptics.dart';
import '../../../core/models/quick_phrase.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import '../../quick_phrase/widgets/quick_phrase_menu.dart';
import '../../quick_phrase/pages/quick_phrases_page.dart';
import '../../../shared/widgets/ios_checkbox.dart';
import '../../../shared/widgets/typing_indicator.dart';
import '../../../shared/widgets/animated_loading_text.dart';
import '../widgets/home_app_bar_builder.dart';
import '../widgets/sidebar_resize_handle.dart';
import '../widgets/home_helper_widgets.dart';
import '../widgets/scroll_nav_buttons.dart';
import '../../../core/utils/tool_schema_sanitizer.dart';
import '../../../core/utils/model_capabilities.dart';
import '../services/chat_message_handler.dart';
import '../services/chat_stream_handler.dart';
import '../../../core/services/ocr/ocr_service.dart';
import '../../../core/services/media/media_picker_service.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key, this.isEmbeddedInDesktopNav = false});

  /// Whether this page is embedded in DesktopHomePage with DesktopNavRail
  /// If true, the sidebar bottom bar (with user avatar and settings) will be hidden
  final bool isEmbeddedInDesktopNav;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin, RouteAware {
  // Inline bottom tools panel removed; using modal bottom sheet instead
  // Animation tuning
  static const Duration _scrollAnimateDuration = Duration(milliseconds: 300);
  static const Duration _postSwitchScrollDelay = Duration(milliseconds: 220);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final InteractiveDrawerController _drawerController = InteractiveDrawerController();
  final FocusNode _inputFocus = FocusNode();
  final TextEditingController _inputController = TextEditingController();
  final ChatInputBarController _mediaController = ChatInputBarController();
  final ScrollController _scrollController = ScrollController();
  // 底部输入栏锚点（搜索、推理预算等 popover）
  final GlobalKey _inputBarKey = GlobalKey();
  // 顶部迷你地图按钮的单独锚点，避免与输入栏复用同一个 GlobalKey
  final GlobalKey _miniMapAnchorKey = GlobalKey(debugLabel: 'mini-map-anchor');
  // Desktop popover anchor keys
  final GlobalKey _searchAnchorKey = GlobalKey(debugLabel: 'search-anchor');
  final GlobalKey _reasoningAnchorKey = GlobalKey(debugLabel: 'reasoning-anchor');
  final GlobalKey _mcpAnchorKey = GlobalKey(debugLabel: 'mcp-anchor');
  late final AnimationController _convoFadeController;
  late final Animation<double> _convoFade;
  double _inputBarHeight = 72;

  late ChatService _chatService;
  Conversation? _currentConversation;
  List<ChatMessage> _messages = [];
  // Support concurrent generation per conversation
  final Map<String, StreamSubscription> _conversationStreams = <String, StreamSubscription>{}; // conversationId -> subscription
  final Set<String> _loadingConversationIds = <String>{}; // active generating conversations
  final Map<String, ReasoningData> _reasoning = <String, ReasoningData>{};
  final Map<String, TranslationUiState> _translations = <String, TranslationUiState>{};
  final Map<String, List<ToolUIPart>> _toolParts = <String, List<ToolUIPart>>{}; // assistantMessageId -> parts
  final Map<String, List<ReasoningSegmentData>> _reasoningSegments = <String, List<ReasoningSegmentData>>{}; // assistantMessageId -> reasoning segments
  // Inline <think> tag tracking for mixed rendering support
  final Map<String, String> _inlineThinkBuffer = <String, String>{}; // assistantMessageId -> accumulated think content
  final Map<String, bool> _inInlineThink = <String, bool>{}; // assistantMessageId -> currently inside <think> block
  // Message widget keys for navigation to previous question
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  GlobalKey _keyForMessage(String id) => _messageKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'msg:$id'));
  McpProvider? _mcpProvider;
  Set<String> _connectedMcpIds = <String>{};
  bool _showJumpToBottom = false;
  String? _visibleMessageId; // For mini rail active indicator
  bool _isUserScrolling = false;
  Timer? _userScrollTimer;
  // OCR service with LRU cache
  final OcrService _ocrService = OcrService(maxCacheSize: 50);
  // Tool call mode state (native or prompt)
  ToolCallMode _toolCallMode = ToolCallMode.native;

  // 流式 UI 性能优化: 使用轻量级 ValueNotifier 替代全局 setState()
  // 性能提升: 10 FPS -> 60 FPS
  final StreamingContentNotifier _streamingNotifier = StreamingContentNotifier();
  final StreamingThrottleManager _streamingThrottleManager = StreamingThrottleManager();

  // Tablet: whether the left embedded sidebar is visible
  bool _tabletSidebarOpen = true;
  bool _learningModeEnabled = false;
  static const Duration _sidebarAnimDuration = Duration(milliseconds: 260);
  static const Curve _sidebarAnimCurve = Curves.easeOutCubic;
  // Desktop: resizable embedded sidebar width
  double _embeddedSidebarWidth = 300;
  static const double _sidebarMinWidth = 200;
  static const double _sidebarMaxWidth = 360;
  bool _desktopUiInited = false;
  // Desktop right sidebar state
  bool _rightSidebarOpen = true;
  double _rightSidebarWidth = 300;

  // Mentioned models for @ mention feature
  List<ModelSelection> _mentionedModels = [];

  /// Add a model to the mentioned models list with duplicate prevention.
  /// Returns true if the model was added, false if it was already in the list.
  bool _addMentionedModel(ModelSelection model) {
    final isDuplicate = _mentionedModels.any((m) =>
        m.providerKey == model.providerKey && m.modelId == model.modelId);
    if (!isDuplicate) {
      setState(() => _mentionedModels.add(model));
      return true;
    }
    return false;
  }

  /// Remove a model from the mentioned models list.
  void _removeMentionedModel(ModelSelection model) {
    setState(() => _mentionedModels.removeWhere((m) =>
        m.providerKey == model.providerKey && m.modelId == model.modelId));
  }

  /// Clear all mentioned models after sending.
  void _clearMentionedModels() {
    setState(() => _mentionedModels.clear());
  }

  /// Send message to all mentioned models, or to default model if none mentioned.
  /// This is the main entry point for sending messages with @ mention support.
  Future<void> _sendToMentionedModels(ChatInputData input) async {
    if (_mentionedModels.isEmpty) {
      // No models mentioned, use default model (current behavior)
      await _sendMessage(input);
      return;
    }

    // Send to each mentioned model
    final modelsToSend = List<ModelSelection>.from(_mentionedModels);
    
    // Clear mentioned models immediately after capturing the list
    _clearMentionedModels();

    // Dispatch message to each mentioned model
    for (final model in modelsToSend) {
      await _sendMessageToModel(input, model.providerKey, model.modelId);
    }
  }

  // Drawer haptics for swipe-open
  double _lastDrawerValue = 0.0;
  // Removed early-open haptic; vibrate on open completion instead

  // Removed raw-pointer-based swipe-to-open; rely on drawer's own gestures

  Widget _buildAssistantBackground(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final assistant = context.watch<AssistantProvider>().currentAssistant;
    final bgRaw = (assistant?.background ?? '').trim();
    Widget? bg;
    if (bgRaw.isNotEmpty) {
      if (bgRaw.startsWith('http') || bgRaw.startsWith('data:')) {
        bg = Image.network(bgRaw, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink());
      } else {
        try {
          final fixed = SandboxPathResolver.fix(bgRaw);
          if (!kIsWeb && PlatformUtils.fileExistsSync(fixed)) {
            bg = Image(image: localFileImage(fixed), fit: BoxFit.cover);
          }
        } catch (_) {}
      }
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base fill to avoid black background when no assistant background set
          ColoredBox(color: cs.background),
          if (bg != null) Opacity(opacity: 0.9, child: bg),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.background.withOpacity(0.08),
                  cs.background.withOpacity(0.36),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build Mobile AppBar using HomeAppBarBuilder
  AppBar _buildMobileAppBar({
    required String title,
    required String? providerName,
    required String? modelDisplay,
    required ColorScheme cs,
  }) {
    return HomeAppBarBuilder(
      context: context,
      title: title,
      providerName: providerName,
      modelDisplay: modelDisplay,
      cs: cs,
      miniMapAnchorKey: _miniMapAnchorKey,
      onToggleSidebar: () {
        _dismissKeyboard();
        _drawerController.toggle();
      },
      onRenameConversation: _renameCurrentConversation,
      onShowModelSelect: () => showModelSelectSheet(context),
      onMiniMapTap: () async {
        final collapsed = _collapseVersions(_messages);
        final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux;
        final String? selectedId;
        if (isDesktop) {
          selectedId = await showDesktopMiniMapPopover(
            context,
            anchorKey: _miniMapAnchorKey,
            messages: collapsed,
          );
        } else {
          selectedId = await showMiniMapSheet(context, collapsed);
        }
        if (!mounted) return;
        if (selectedId != null && selectedId.isNotEmpty) {
          await _scrollToMessageId(selectedId);
        }
      },
      onNewConversation: () async {
        await _createNewConversation();
        if (mounted) {
          _forceScrollToBottomSoon();
        }
      },
      onToggleRightSidebar: _toggleRightSidebar,
    ).buildMobileAppBar();
  }

  /// Build Tablet AppBar using HomeAppBarBuilder
  AppBar _buildTabletAppBar({
    required String title,
    required String? providerName,
    required String? modelDisplay,
    required ColorScheme cs,
  }) {
    return HomeAppBarBuilder(
      context: context,
      title: title,
      providerName: providerName,
      modelDisplay: modelDisplay,
      cs: cs,
      miniMapAnchorKey: _miniMapAnchorKey,
      onToggleSidebar: _toggleTabletSidebar,
      onRenameConversation: _renameCurrentConversation,
      onShowModelSelect: () => showModelSelectSheet(context),
      onMiniMapTap: () async {
        final collapsed = _collapseVersions(_messages);
        final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux;
        final String? selectedId;
        if (isDesktop) {
          selectedId = await showDesktopMiniMapPopover(
            context,
            anchorKey: _miniMapAnchorKey,
            messages: collapsed,
          );
        } else {
          selectedId = await showMiniMapSheet(context, collapsed);
        }
        if (!mounted) return;
        if (selectedId != null && selectedId.isNotEmpty) {
          await _scrollToMessageId(selectedId);
        }
      },
      onNewConversation: () async {
        await _createNewConversation();
        if (mounted) {
          _forceScrollToBottomSoon();
        }
      },
      onToggleRightSidebar: _toggleRightSidebar,
    ).buildTabletAppBar();
  }

  // no-op placeholders removed

  Future<void> _showLearningPromptSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final prompt = await LearningModeStore.getPrompt();
    final controller = TextEditingController(text: prompt);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(l10n.bottomToolsSheetPrompt, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 10,
                  decoration: InputDecoration(
                    hintText: l10n.bottomToolsSheetPromptHint,
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        await LearningModeStore.resetPrompt();
                        controller.text = await LearningModeStore.getPrompt();
                      },
                      child: Text(l10n.bottomToolsSheetResetDefault),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        await LearningModeStore.setPrompt(controller.text.trim());
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: Text(l10n.bottomToolsSheetSave),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Anchor for chained "jump to previous question" navigation
  String? _lastJumpUserMessageId;

  // Deduplicate raw persisted tool events using same criteria
  List<Map<String, dynamic>> _dedupeToolEvents(List<Map<String, dynamic>> events) {
    final indexByKey = <String, int>{};
    final out = <Map<String, dynamic>>[];

    for (final raw in events) {
      final e = raw.map((k, v) => MapEntry(k.toString(), v));
      final id = (e['id']?.toString() ?? '').trim();
      final name = (e['name']?.toString() ?? '');
      final args = ((e['arguments'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{});
      final key = id.isNotEmpty ? 'id:$id' : 'name:$name|args:${jsonEncode(args)}';

      final idx = indexByKey[key];
      if (idx == null) {
        indexByKey[key] = out.length;
        out.add(e);
        continue;
      }

      final prev = out[idx];
      final merged = Map<String, dynamic>.from(prev);

      // Prefer non-empty content so late placeholders don't hide earlier results.
      final prevContent = (prev['content']?.toString() ?? '');
      final nextContent = (e['content']?.toString() ?? '');
      if (nextContent.isNotEmpty) {
        merged['content'] = e['content'];
      } else if (prevContent.isNotEmpty) {
        merged['content'] = prev['content'];
      } else {
        merged['content'] = e['content'] ?? prev['content'];
      }

      if (id.isNotEmpty) merged['id'] = id;
      if (name.isNotEmpty) merged['name'] = name;
      if (args.isNotEmpty) merged['arguments'] = args;

      out[idx] = merged;
    }

    return out;
  }

  // ========== 消息列表回调方法 ==========

  /// 删除消息（确认逻辑已在 UI 层处理）
  Future<void> _deleteMessage(ChatMessage message) async {
    final id = message.id;
    setState(() {
      _messages.removeWhere((m) => m.id == id);
      _reasoning.remove(id);
      _translations.remove(id);
      _toolParts.remove(id);
      _reasoningSegments.remove(id);
    });
    await _chatService.deleteMessage(id);
  }

  /// 编辑消息
  Future<void> _editMessage(ChatMessage message) async {
    final edited = await showMessageEditSheet(context, message: message);
    if (edited != null) {
      final newMsg = await _chatService.appendMessageVersion(messageId: message.id, content: edited);
      if (!mounted) return;
      setState(() {
        if (newMsg != null) {
          _messages.add(newMsg);
          final gid = (newMsg.groupId ?? newMsg.id);
          _versionSelections[gid] = newMsg.version;
        }
      });
      try {
        if (newMsg != null && _currentConversation != null) {
          final gid = (newMsg.groupId ?? newMsg.id);
          await _chatService.setSelectedVersion(_currentConversation!.id, gid, newMsg.version);
        }
      } catch (_) {}
    }
  }

  /// 切换到上一个版本
  Future<void> _goToPrevVersion(String gid, int currentIdx) async {
    final next = currentIdx - 1;
    _versionSelections[gid] = next;
    await _chatService.setSelectedVersion(_currentConversation!.id, gid, next);
    if (mounted) setState(() {});
  }

  /// 切换到下一个版本
  Future<void> _goToNextVersion(String gid, int currentIdx) async {
    final next = currentIdx + 1;
    _versionSelections[gid] = next;
    await _chatService.setSelectedVersion(_currentConversation!.id, gid, next);
    if (mounted) setState(() {});
  }

  /// Fork 对话到当前消息
  Future<void> _forkConversationAtMessage(ChatMessage message, List<ChatMessage> messages) async {
    final Map<String, int> groupFirstIndex = <String, int>{};
    final List<String> groupOrder = <String>[];
    for (int i = 0; i < _messages.length; i++) {
      final gid = (_messages[i].groupId ?? _messages[i].id);
      if (!groupFirstIndex.containsKey(gid)) {
        groupFirstIndex[gid] = i;
        groupOrder.add(gid);
      }
    }
    final targetGroup = (message.groupId ?? message.id);
    final targetOrderIndex = groupOrder.indexOf(targetGroup);
    if (targetOrderIndex >= 0) {
      final includeGroups = groupOrder.take(targetOrderIndex + 1).toSet();
      final selected = [for (final m in _messages) if (includeGroups.contains(m.groupId ?? m.id)) m];
      final sel = <String, int>{};
      for (final gid in includeGroups) {
        final v = _versionSelections[gid];
        if (v != null) sel[gid] = v;
      }
      final newConvo = await _chatService.forkConversation(
        title: _titleForLocale(context),
        assistantId: _currentConversation?.assistantId,
        sourceMessages: selected,
        versionSelections: sel,
      );
      if (!mounted) return;
      await _convoFadeController.reverse();
      _chatService.setCurrentConversation(newConvo.id);
      final msgs = _chatService.getMessages(newConvo.id);
      if (!mounted) return;
      setState(() {
        _currentConversation = newConvo;
        _messages = List.of(msgs);
        _loadVersionSelections();
        _restoreMessageUiState();
      });
      try { await WidgetsBinding.instance.endOfFrame; } catch (_) {}
      _scrollToBottom();
      await _convoFadeController.forward();
    }
  }

  /// 进入分享选择模式
  void _enterShareModeUpTo(int index, List<ChatMessage> messages) {
    setState(() {
      _selecting = true;
      _selectedItems.clear();
      for (int i = 0; i <= index && i < messages.length; i++) {
        final m = messages[i];
        if (m.role == 'user' || m.role == 'assistant') {
          _selectedItems.add(m.id);
        }
      }
    });
  }

  /// 构建推理段落列表


  // Selection mode state for export/share
  bool _selecting = false;
  final Set<String> _selectedItems = <String>{}; // selected message ids (collapsed view)


  /// Process inline <think> tags in streaming content for mixed rendering support.
  /// Returns the content with think blocks tracked separately.
  /// This method updates _inlineThinkBuffer, _inInlineThink, and _reasoningSegments.
  void _processInlineThinkTag(String messageId, String newContent) {
    if (newContent.isEmpty) return;

    // Get current state
    final inThink = _inInlineThink[messageId] ?? false;
    var buffer = _inlineThinkBuffer[messageId] ?? '';

    // Process the new content character by character to handle tag boundaries
    var remaining = newContent;

    while (remaining.isNotEmpty) {
      if (inThink || _inInlineThink[messageId] == true) {
        // Currently inside <think> block, look for </think>
        final endIndex = remaining.indexOf('</think>');
        if (endIndex == -1) {
          // No closing tag yet, buffer everything
          buffer += remaining;
          _inlineThinkBuffer[messageId] = buffer;
          remaining = '';
        } else {
          // Found closing tag
          buffer += remaining.substring(0, endIndex);
          remaining = remaining.substring(endIndex + '</think>'.length);

          // Create or update reasoning segment with the buffered content
          if (buffer.trim().isNotEmpty) {
            final segments = _reasoningSegments[messageId] ?? <ReasoningSegmentData>[];
            final toolCount = _toolParts[messageId]?.length ?? 0;

            // Check if we should append to existing segment or create new one
            if (segments.isEmpty) {
              // First segment
              final seg = ReasoningSegmentData();
              seg.text = buffer.trim();
              seg.startAt = DateTime.now();
              seg.expanded = true; // Inline think starts expanded
              seg.toolStartIndex = toolCount;
              segments.add(seg);
            } else {
              final lastSeg = segments.last;
              // If the last segment has tools after it (finishedAt != null), create new segment
              if (lastSeg.finishedAt != null && toolCount > lastSeg.toolStartIndex) {
                final seg = ReasoningSegmentData();
                seg.text = buffer.trim();
                seg.startAt = DateTime.now();
                seg.expanded = true;
                seg.toolStartIndex = toolCount;
                segments.add(seg);
              } else if (lastSeg.finishedAt == null) {
                // Append to current segment
                lastSeg.text += '\n\n' + buffer.trim();
              } else {
                // Last segment finished but no new tools, just append
                lastSeg.text += '\n\n' + buffer.trim();
                lastSeg.finishedAt = null; // Re-open the segment
              }
            }

            // Mark the last segment as finished since </think> was encountered
            if (segments.isNotEmpty) {
              segments.last.finishedAt = DateTime.now();
              // Auto-collapse based on settings
              final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
              if (autoCollapse) {
                segments.last.expanded = false;
              }
            }

            _reasoningSegments[messageId] = segments;
          }

          // Reset buffer and mark as not in think block
          buffer = '';
          _inlineThinkBuffer[messageId] = buffer;
          _inInlineThink[messageId] = false;
        }
      } else {
        // Not inside <think> block, look for <think>
        final startIndex = remaining.indexOf('<think>');
        if (startIndex == -1) {
          // No opening tag, content is regular text (handled elsewhere)
          remaining = '';
        } else {
          // Found opening tag, skip content before it (regular text)
          remaining = remaining.substring(startIndex + '<think>'.length);
          _inInlineThink[messageId] = true;
        }
      }
    }
  }

  /// Check if we should use inline think segments for this message.
  /// Returns true if the message content contains <think> tags but no native reasoning is provided.
  bool _shouldUseInlineThinkSegments(String messageId, String content, bool hasNativeReasoning) {
    if (hasNativeReasoning) return false;
    return content.contains('<think>') || (_inInlineThink[messageId] ?? false);
  }

  /// 创建统一的 StreamContext
  /// Prepare Gemini thought signatures for API calls.
  ///
  /// - Always strips `<!-- gemini_thought_signatures:... -->` from assistant text so other providers never see it.
  /// - For Gemini 3, re-attaches the stored signature comment (per messageId) so tool-calling turns remain valid.
  Future<void> _prepareGeminiThoughtSignaturesForApiMessages({
    required List<Map<String, dynamic>> apiMessages,
    required String? providerKey,
    required String? modelId,
  }) async {
    if (apiMessages.isEmpty) return;

    // 1) Strip any embedded signatures (legacy data) and persist them out-of-band.
    for (final m in apiMessages) {
      if ((m['role'] ?? '').toString() != 'assistant') continue;
      final raw = (m['content'] ?? '').toString();
      if (!GeminiThoughtSignatures.hasAny(raw)) continue;

      final id = (m['id'] ?? '').toString();
      final sig = GeminiThoughtSignatures.extractLast(raw);
      if (id.isNotEmpty && sig != null && sig.isNotEmpty) {
        final existing = _chatService.getGeminiThoughtSignature(id);
        if (existing != sig) {
          await _chatService.setGeminiThoughtSignature(id, sig);
        }
      }

      m['content'] = GeminiThoughtSignatures.stripAll(raw).trimRight();
    }

    // 2) Gemini 3: re-attach signature comments for request building.
    final pk = (providerKey ?? '').toLowerCase();
    final isGoogleProvider = pk.contains('gemini') || pk.contains('google');
    final needsPersist = isGoogleProvider && (modelId ?? '').toLowerCase().contains('gemini-3');
    if (!needsPersist) return;

    for (final m in apiMessages) {
      if ((m['role'] ?? '').toString() != 'assistant') continue;
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) continue;

      final content = (m['content'] ?? '').toString();
      if (content.contains(GeminiThoughtSignatures.tag)) continue;

      final sig = _chatService.getGeminiThoughtSignature(id);
      if (sig == null || sig.isEmpty) continue;

      m['content'] = content.isEmpty ? sig : '$content\n$sig';
    }
  }

  StreamContext _createStreamContext({
    required ChatMessage assistantMessage,
    required DateTime startTime,
    required bool streamOutput,
    required bool supportsReasoning,
  }) {
    final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
    // 为流式消息预创建 notifier，以便 UI 可以检测到并使用 ValueListenableBuilder
    _streamingNotifier.getNotifier(assistantMessage.id);
    return StreamContext(
      assistantMessage: assistantMessage,
      conversationId: assistantMessage.conversationId,
      chatService: _chatService,
      streamOutput: streamOutput,
      supportsReasoning: supportsReasoning,
      autoCollapseThinking: autoCollapse,
      startTime: startTime,
      reasoning: _reasoning,
      reasoningSegments: _reasoningSegments,
      toolParts: _toolParts,
      inlineThinkBuffer: _inlineThinkBuffer,
      inInlineThink: _inInlineThink,
      notifyUI: () { if (mounted) setState(() {}); },
      scrollToBottom: () { if (!_isUserScrolling) _scrollToBottomSoon(); },
      isMounted: () => mounted,
      isCurrentConversation: () => _currentConversation?.id == assistantMessage.conversationId,
      // 传入流式 UI 优化组件
      streamingNotifier: _streamingNotifier,
    );
  }

  /// 统一的流监听器设置
  StreamSubscription<ChatStreamChunk> _setupStreamListener({
    required Stream<ChatStreamChunk> stream,
    required StreamContext ctx,
    required Future<void> Function() finish,
    required void Function(Object error) onError,
    void Function()? onDone,
    bool enableInlineThink = true,
  }) {
    return stream.listen(
      (ChatStreamChunk chunk) async {
        // 处理 reasoning
        if ((chunk.reasoning ?? '').isNotEmpty) {
          await ChatStreamHandler.handleReasoningChunk(ctx, chunk.reasoning!);
        }

        // 处理 tool calls
        if ((chunk.toolCalls ?? const []).isNotEmpty) {
          await ChatStreamHandler.handleToolCallChunk(ctx, chunk.toolCalls!);
        }

        // 处理 tool results
        if ((chunk.toolResults ?? const []).isNotEmpty) {
          await ChatStreamHandler.handleToolResultChunk(ctx, chunk.toolResults!);
        }

        // 处理 usage
        ChatStreamHandler.handleUsageChunk(ctx, chunk.usage);

        // 处理完成
        if (chunk.isDone) {
          if (ChatStreamHandler.hasLoadingToolParts(ctx)) return;
          await finish();
          await ChatStreamHandler.handleStreamDone(ctx, () async {});
        } else {
          // 处理内容
          await ChatStreamHandler.handleContentChunk(ctx, chunk.content);

          // 处理 inline think tags (仅限 sendMessage)
          if (enableInlineThink && chunk.content.isNotEmpty) {
            final hasNativeReasoning = (_reasoning[ctx.messageId]?.text.isNotEmpty ?? false);
            if (!hasNativeReasoning) {
              _processInlineThinkTag(ctx.messageId, chunk.content);
              final inlineSegs = _reasoningSegments[ctx.messageId];
              if (inlineSegs != null && inlineSegs.isNotEmpty) {
                await _chatService.updateMessage(
                  ctx.messageId,
                  reasoningSegmentsJson: ReasoningStateManager.serializeSegments(inlineSegs),
                );
                if (mounted && ctx.isCurrentConversation()) setState(() {});
              }
            }
          }

          // 完成 reasoning（当内容开始时）
          if (ctx.streamOutput && chunk.content.isNotEmpty) {
            final insideInlineThink = _inInlineThink[ctx.messageId] ?? false;
            if (!insideInlineThink) {
              await ChatStreamHandler.finishReasoningOnContent(ctx);
            }
          }

          // 流式 UI 更新（使用节流机制优化性能）
          if (ctx.streamOutput) {
            final tokenUsageJson = ChatStreamHandler.buildTokenUsageJson(ctx);
            if (mounted && ctx.isCurrentConversation()) {
              // 更新 _messages 列表数据（不触发全局重建）
              final index = _messages.indexWhere((m) => m.id == ctx.messageId);
              if (index != -1) {
                _messages[index] = _messages[index].copyWith(
                  content: ctx.fullContent,
                  tokenUsageJson: tokenUsageJson,
                );
              }
              // 使用节流机制更新 UI（通过 ValueListenableBuilder 只重建流式消息 widget）
              _streamingThrottleManager.scheduleUpdate(
                ctx.messageId,
                ctx.fullContent,
                ctx.totalTokens,
                _streamingNotifier,
                tokenUsageJson: tokenUsageJson,
                onTick: () {
                  final disableAutoScroll = context.read<SettingsProvider>().disableAutoScroll;
                  if (!_isUserScrolling && !disableAutoScroll) {
                    _scrollToBottomSoon();
                  }
                },
              );
            }
            await _chatService.updateMessage(
              ctx.messageId,
              content: ctx.fullContent,
              tokenUsageJson: tokenUsageJson,
            );
          }
        }
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: true,
    );
  }

  /// Delegates to ModelCapabilities.supportsReasoning
  bool _isReasoningModel(String providerKey, String modelId) {
    final cfg = context.read<SettingsProvider>().getProviderConfig(providerKey);
    return ModelCapabilities.supportsReasoning(cfg, modelId);
  }

  /// Delegates to ModelCapabilities.supportsImages
  bool _isImageInputModel(String providerKey, String modelId) {
    final cfg = context.read<SettingsProvider>().getProviderConfig(providerKey);
    return ModelCapabilities.supportsImages(cfg, modelId);
  }

  // Get OCR text for multiple images with UI feedback (tool call display)
  Future<String?> _getOcrTextForImagesWithUI(List<String> imagePaths, String assistantMessageId) async {
    if (imagePaths.isEmpty) return null;
    final settings = context.read<SettingsProvider>();
    if (!OcrService.isConfigured(settings)) return null;

    final combined = StringBuffer();
    final List<String> uncached = <String>[];

    // Check cache first
    for (final raw in imagePaths) {
      final path = raw.trim();
      if (path.isEmpty) continue;
      final cached = _ocrService.getCached(path);
      if (cached != null && cached.trim().isNotEmpty) {
        combined.writeln(cached.trim());
      } else {
        uncached.add(path);
      }
    }

    // Fetch OCR for uncached images with UI feedback
    if (uncached.isNotEmpty) {
      final ocrId = 'ocr_${DateTime.now().millisecondsSinceEpoch}';
      final imageNames = uncached.map((p) => p.split('/').last.split('\\').last).join(', ');

      // Add loading tool event
      await _chatService.upsertToolEvent(
        assistantMessageId,
        id: ocrId,
        name: 'image_ocr',
        arguments: {'images': imageNames, 'count': uncached.length},
      );

      // Update UI
      final existing = List<ToolUIPart>.of(_toolParts[assistantMessageId] ?? const []);
      existing.add(ToolUIPart(
        id: ocrId,
        toolName: 'image_ocr',
        arguments: {'images': imageNames, 'count': uncached.length},
        loading: true,
      ));
      setState(() => _toolParts[assistantMessageId] = existing);

      try {
        // Run OCR
        for (final path in uncached) {
          final text = await OcrService.runOcr(imagePaths: [path], settings: settings);
          if (text != null && text.trim().isNotEmpty) {
            final t = text.trim();
            _ocrService.cache(path, t);
            combined.writeln(t);
          }
        }

        final result = combined.toString().trim();
        // Show actual OCR text in tool card, not just character count
        final content = result.isEmpty
            ? 'OCR completed but no text extracted'
            : result;

        // Update tool event with success
        await _chatService.upsertToolEvent(
          assistantMessageId,
          id: ocrId,
          name: 'image_ocr',
          arguments: {'images': imageNames, 'count': uncached.length},
          content: content,
        );

        // Update UI
        final parts = List<ToolUIPart>.of(_toolParts[assistantMessageId] ?? const []);
        final idx = parts.indexWhere((p) => p.id == ocrId);
        if (idx >= 0) {
          parts[idx] = ToolUIPart(
            id: ocrId,
            toolName: 'image_ocr',
            arguments: {'images': imageNames, 'count': uncached.length},
            content: content,
            loading: false,
          );
          setState(() => _toolParts[assistantMessageId] = parts);
        }
      } catch (e) {
        // Update tool event with error
        final errorMsg = 'OCR failed: ${e.toString()}';
        await _chatService.upsertToolEvent(
          assistantMessageId,
          id: ocrId,
          name: 'image_ocr',
          arguments: {'images': imageNames, 'count': uncached.length},
          content: errorMsg,
        );

        // Update UI
        final parts = List<ToolUIPart>.of(_toolParts[assistantMessageId] ?? const []);
        final idx = parts.indexWhere((p) => p.id == ocrId);
        if (idx >= 0) {
          parts[idx] = ToolUIPart(
            id: ocrId,
            toolName: 'image_ocr',
            arguments: {'images': imageNames, 'count': uncached.length},
            content: errorMsg,
            loading: false,
          );
          setState(() => _toolParts[assistantMessageId] = parts);
        }
      }
    }

    final out = combined.toString().trim();
    return out.isEmpty ? null : out;
  }

  // Whether current conversation is generating
  bool get _isCurrentConversationLoading {
    final cid = _currentConversation?.id;
    if (cid == null) return false;
    return _loadingConversationIds.contains(cid);
  }

  // Update loading state for a conversation and refresh UI if needed
  void _setConversationLoading(String conversationId, bool loading) {
    final prev = _loadingConversationIds.contains(conversationId);
    if (loading) {
      _loadingConversationIds.add(conversationId);
    } else {
      _loadingConversationIds.remove(conversationId);
    }
    if (mounted && prev != loading) {
      setState(() {}); // Update input bar + drawer indicators
    }
  }

  void _cleanupStreamingUiForMessage(String messageId) {
    _streamingThrottleManager.cleanup(messageId);
    _streamingNotifier.removeNotifier(messageId);
  }

  Future<void> _cancelStreaming() async {
    final cid = _currentConversation?.id;
    if (cid == null) return;
    // Cancel active stream for current conversation only
    final sub = _conversationStreams.remove(cid);
    await sub?.cancel();

    // Find the latest assistant streaming message within current conversation and mark it finished
    ChatMessage? streaming;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.role == 'assistant' && m.isStreaming) {
        streaming = m;
        break;
      }
    }
    if (streaming != null) {
      await _chatService.updateMessage(
        streaming.id,
        content: streaming.content,
        isStreaming: false,
        totalTokens: streaming.totalTokens,
      );
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == streaming!.id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(isStreaming: false);
          }
        });
      }
      _setConversationLoading(cid, false);

      final r = _reasoning[streaming.id];
      if (r != null) {
        if (r.finishedAt == null) {
          r.finishedAt = DateTime.now();
          await _chatService.updateMessage(
            streaming.id,
            reasoningText: r.text,
            reasoningFinishedAt: r.finishedAt,
          );
        }
        final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
        if (autoCollapse) {
          r.expanded = false;
        }
        _reasoning[streaming.id] = r;
        if (mounted) setState(() {});
      }

      final segs = _reasoningSegments[streaming.id];
      if (segs != null && segs.isNotEmpty && segs.last.finishedAt == null) {
        segs.last.finishedAt = DateTime.now();
        final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
        if (autoCollapse) {
          segs.last.expanded = false;
        }
        _reasoningSegments[streaming.id] = segs;
        await _chatService.updateMessage(
          streaming.id,
          reasoningSegmentsJson: ReasoningStateManager.serializeSegments(segs),
        );
      }

      _cleanupStreamingUiForMessage(streaming.id);
    } else {
      _setConversationLoading(cid, false);
    }
  }

  String _titleForLocale(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return l10n.titleForLocale;
  }

  // Version selections (groupId -> selected version index)
  Map<String, int> _versionSelections = <String, int>{};

  void _loadVersionSelections() {
    final cid = _currentConversation?.id;
    if (cid == null) {
      _versionSelections = <String, int>{};
      return;
    }
    try {
      _versionSelections = _chatService.getVersionSelections(cid);
    } catch (_) {
      _versionSelections = <String, int>{};
    }
  }

  // Restore per-message UI states (reasoning/segments/tool parts/translation) after switching conversations
  void _restoreMessageUiState() {
    // Clear first to avoid stale entries
    _reasoning.clear();
    _reasoningSegments.clear();
    _inlineThinkBuffer.clear();
    _inInlineThink.clear();
    _toolParts.clear();
    _translations.clear();

    for (final m in _messages) {
      if (m.role == 'assistant') {
        // Restore reasoning state
        final txt = m.reasoningText ?? '';
        if (txt.isNotEmpty || m.reasoningStartAt != null || m.reasoningFinishedAt != null) {
          final rd = ReasoningData();
          rd.text = txt;
          rd.startAt = m.reasoningStartAt;
          rd.finishedAt = m.reasoningFinishedAt;
          rd.expanded = false;
          _reasoning[m.id] = rd;
        }

        // Restore tool events persisted for this assistant message
        try {
          final events = _dedupeToolEvents(_chatService.getToolEvents(m.id));
          if (events.isNotEmpty) {
            _toolParts[m.id] = events
                .map((e) => ToolUIPart(
                      id: (e['id'] ?? '').toString(),
                      toolName: (e['name'] ?? '').toString(),
                      arguments: (e['arguments'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
                      content: (e['content']?.toString().isNotEmpty == true) ? e['content'].toString() : null,
                      loading: !(e['content']?.toString().isNotEmpty == true),
                    ))
                .toList();
          }
        } catch (_) {}

        // Restore reasoning segments
        final segments = ReasoningStateManager.deserializeSegments(m.reasoningSegmentsJson);
        if (segments.isNotEmpty) {
          _reasoningSegments[m.id] = segments;
        }
      }

      // Restore translation UI state: default collapsed
      if (m.translation != null && m.translation!.isNotEmpty) {
        final td = TranslationUiState();
        td.expanded = false;
        _translations[m.id] = td;
      }
    }
  }

  List<ChatMessage> _collapseVersions(List<ChatMessage> items) {
    return ChatMessageHandler.collapseVersions(items, _versionSelections);
  }

  String _clearContextLabel() {
    final l10n = AppLocalizations.of(context)!;
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final configured = (assistant?.limitContextMessages ?? true) ? (assistant?.contextMessageSize ?? 0) : 0;
    // Use collapsed view for counting
    final collapsed = _collapseVersions(_messages);
    // Map raw truncate index to collapsed start index
    final int tRaw = _currentConversation?.truncateIndex ?? -1;
    int startCollapsed = 0;
    if (tRaw > 0) {
      final seen = <String>{};
      final int limit = tRaw < _messages.length ? tRaw : _messages.length;
      int count = 0;
      for (int i = 0; i < limit; i++) {
        final gid0 = (_messages[i].groupId ?? _messages[i].id);
        if (seen.add(gid0)) count++;
      }
      startCollapsed = count; // inclusive start index in collapsed list
    }
    int remaining = 0;
    for (int i = 0; i < collapsed.length; i++) {
      if (i >= startCollapsed) {
        if (collapsed[i].content.trim().isNotEmpty) remaining++;
      }
    }
    if (configured > 0) {
      final actual = remaining > configured ? configured : remaining;
      return l10n.homePageClearContextWithCount(actual.toString(), configured.toString());
    }
    return l10n.homePageClearContext;
  }

  Future<void> _onClearContext() async {
    final convo = _currentConversation;
    if (convo == null) return;
    // 不传 defaultTitle，清空上下文不应该改标题
    final updated = await _chatService.toggleTruncateAtTail(convo.id);
    if (!mounted) return;
    if (updated != null) {
      setState(() {
        _currentConversation = updated;
      });
      _scrollToBottomSoon();
    }
    // No inline panel to close; modal sheet is dismissed before action
  }

  void _toggleTools() async {
    // Open as modal bottom sheet instead of inline overlay
    _dismissKeyboard();
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: BottomToolsSheet(
            clearLabel: _clearContextLabel(),
            onPhotos: () {
              Navigator.of(ctx).maybePop();
              _onPickPhotos();
            },
            onCamera: () {
              Navigator.of(ctx).maybePop();
              _onPickCamera();
            },
            onUpload: () {
              Navigator.of(ctx).maybePop();
              _onPickFiles();
            },
            onClear: () async {
              Navigator.of(ctx).maybePop();
              await _onClearContext();
            },
            onMaxTokens: () async {
              Navigator.of(ctx).maybePop();
              await showMaxTokensSheet(context);
            },
            onQuickPhrase: () {
              Navigator.of(ctx).maybePop();
              _showQuickPhraseMenu();
            },
            onLongPressQuickPhrase: () {
              Navigator.of(ctx).maybePop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QuickPhrasesPage()),
              );
            },
            onToolLoop: () async {
              Navigator.of(ctx).maybePop();
              await showToolLoopSheet(context);
            },
          ),
        );
      },
    );
  }

  /// Delegates to ModelCapabilities.supportsTools
  bool _isToolModel(String providerKey, String modelId) {
    final cfg = context.read<SettingsProvider>().getProviderConfig(providerKey);
    return ModelCapabilities.supportsTools(cfg, modelId);
  }

  // More page entry is temporarily removed.
  // void _openMorePage() {
  //   _dismissKeyboard();
  //   Navigator.of(context).push(
  //     MaterialPageRoute(builder: (_) => const MorePage()),
  //   );
  // }

  void _dismissKeyboard() {
    _inputFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
    try { SystemChannels.textInput.invokeMethod('TextInput.hide'); } catch (_) {}
  }

  Widget _buildChatInputBar(BuildContext context, {required bool builtinSearchActive}) {
    final settings = context.watch<SettingsProvider>();
    final a = context.watch<AssistantProvider>().currentAssistant;
    final pk = a?.chatModelProvider ?? settings.currentModelProvider;
    final mid = a?.chatModelId ?? settings.currentModelId;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;
    final isWindowsDesktop = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

    final inputBar = ChatInputBar(
      key: _inputBarKey,
      onMore: _toggleTools,
      searchEnabled: settings.searchEnabled || builtinSearchActive,
      onToggleSearch: (enabled) {
        context.read<SettingsProvider>().setSearchEnabled(enabled);
      },
      onSelectModel: () => showModelSelectSheet(context),
      onLongPressSelectModel: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProvidersPage()),
        );
      },
      onOpenMcp: () async {
        final a = context.read<AssistantProvider>().currentAssistant;
        if (a != null) {
          final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.linux;
          // 实时更新工具模式的回调
          void onToolModeChanged(ToolCallMode mode) {
            if (mounted) setState(() => _toolCallMode = mode);
          }
          if (isDesktop) {
            await showDesktopMcpServersPopover(
              context,
              anchorKey: _inputBarKey,
              assistantId: a.id,
              onToolModeChanged: onToolModeChanged,
            );
          } else {
            await showAssistantMcpSheet(
              context,
              assistantId: a.id,
              onToolModeChanged: onToolModeChanged,
            );
          }
          // 最终确保状态同步（以防回调未触发）
          final mode = await ToolCallModeStore.getMode();
          if (mounted) setState(() => _toolCallMode = mode);
        }
      },
      onLongPressMcp: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const McpPage()),
        );
      },
      onStop: _cancelStreaming,
      modelIcon: (settings.showModelIcon && ((a?.chatModelProvider ?? settings.currentModelProvider) != null) && ((a?.chatModelId ?? settings.currentModelId) != null))
          ? CurrentModelIcon(
              providerKey: a?.chatModelProvider ?? settings.currentModelProvider,
              modelId: a?.chatModelId ?? settings.currentModelId,
              size: 40,
              withBackground: true,
              backgroundColor: Colors.transparent,
            )
          : null,
      focusNode: _inputFocus,
      controller: _inputController,
      mediaController: _mediaController,
      onConfigureReasoning: () async {
        final convo = _currentConversation;
        if (convo == null) return;
        final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux;
        if (isDesktop) {
          final settings = context.read<SettingsProvider>();
          await showDesktopReasoningBudgetPopover(
            context,
            anchorKey: _inputBarKey,
            // Use conversation value, or fall back to global setting
            initialValue: convo.thinkingBudget ?? settings.thinkingBudget,
            onValueChanged: (value) async {
              // Update both conversation-level and global settings
              // So new conversations will use the same value
              await context.read<SettingsProvider>().setThinkingBudget(value);
              final updated = await _chatService.setConversationThinkingBudget(convo.id, value);
              if (updated != null && mounted) {
                setState(() {
                  _currentConversation = updated;
                });
              }
            },
          );
        } else {
          if (convo.thinkingBudget != null) {
            await context.read<SettingsProvider>().setThinkingBudget(convo.thinkingBudget);
          }
          await showReasoningBudgetSheet(context);
          final chosen = context.read<SettingsProvider>().thinkingBudget;
          final updated = await _chatService.setConversationThinkingBudget(convo.id, chosen);
          if (updated != null && mounted) {
            setState(() {
              _currentConversation = updated;
            });
          }
        }
      },
      reasoningActive: ReasoningStateManager.isReasoningEnabled((_currentConversation?.thinkingBudget) ?? settings.thinkingBudget),
      thinkingBudget: (_currentConversation?.thinkingBudget) ?? settings.thinkingBudget,
      supportsReasoning: (pk != null && mid != null) ? _isReasoningModel(pk, mid) : false,
      onConfigureMaxTokens: () async {
        final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux;
        if (isDesktop) {
          await showDesktopMaxTokensPopover(
            context,
            anchorKey: _inputBarKey,
          );
        } else {
          await showMaxTokensSheet(context);
        }
      },
      onConfigureToolLoop: () async {
        final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux;
        if (isDesktop) {
          await showDesktopToolLoopPopover(
            context,
            anchorKey: _inputBarKey,
          );
        } else {
          await showToolLoopSheet(context);
        }
      },
      maxTokensConfigured: (context.watch<AssistantProvider>().currentAssistant?.maxTokens ?? 0) > 0,
      onOpenSearch: () {
        final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux;
        if (isDesktop) {
          showDesktopSearchProviderPopover(
            context,
            anchorKey: _inputBarKey,
          );
        } else {
          showSearchSettingsSheet(context);
        }
      },
      searchAnchorKey: _searchAnchorKey,
      reasoningAnchorKey: _reasoningAnchorKey,
      mcpAnchorKey: _mcpAnchorKey,
      onSend: (text) {
        _sendToMentionedModels(text);
        _inputController.clear();
        _dismissKeyboard();
      },
      loading: _isCurrentConversationLoading,
      showMcpButton: (() {
        final pk2 = a?.chatModelProvider ?? settings.currentModelProvider;
        final mid3 = a?.chatModelId ?? settings.currentModelId;
        if (pk2 == null || mid3 == null) return false;
        return _isToolModel(pk2, mid3) && context.watch<McpProvider>().servers.isNotEmpty;
      })(),
      mcpActive: (() {
        final a = context.watch<AssistantProvider>().currentAssistant;
        final connected = context.watch<McpProvider>().connectedServers;
        final selected = a?.mcpServerIds ?? const <String>[];
        if (selected.isEmpty || connected.isEmpty) return false;
        return connected.any((s) => selected.contains(s.id));
      })(),
      mcpToolCount: (() {
        final a = context.watch<AssistantProvider>().currentAssistant;
        final mcpProvider = context.watch<McpProvider>();
        final selected = a?.mcpServerIds ?? const <String>[];
        if (selected.isEmpty) return 0;
        final enabledTools = mcpProvider.getEnabledToolsForServers(selected.toSet());
        return enabledTools.length;
      })(),
      // Tool mode toggle moved to MCP popover
      showToolModeButton: false,
      toolModeIsPrompt: _toolCallMode == ToolCallMode.prompt,
      onToggleToolMode: null,
      showQuickPhraseButton: false,
      onQuickPhrase: _showQuickPhraseMenu,
      onLongPressQuickPhrase: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuickPhrasesPage()),
        );
      },
      // 移动端通过 BottomToolsSheet (onMore -> _toggleTools) 访问这些功能
      // 桌面端直接在输入栏显示按钮
      showMiniMapButton: !isWindowsDesktop,
      onOpenMiniMap: () async {
        final collapsed = _collapseVersions(_messages);
        final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux;
        final String? selectedId;
        if (isDesktop) {
          selectedId = await showDesktopMiniMapPopover(
            context,
            anchorKey: _inputBarKey,
            messages: collapsed,
          );
        } else {
          selectedId = await showMiniMapSheet(context, collapsed);
        }
        if (selectedId != null && selectedId.isNotEmpty) {
          await _scrollToMessageId(selectedId);
        }
      },
      // 桌面端直接显示这些按钮，移动端通过 BottomToolsSheet 访问
      onPickCamera: isMobile ? null : _onPickCamera,
      onPickPhotos: isMobile ? null : _onPickPhotos,
      onUploadFiles: isMobile ? null : _onPickFiles,
      onToggleLearningMode: isMobile ? null : () async {
        final enabled = await LearningModeStore.isEnabled();
        await LearningModeStore.setEnabled(!enabled);
        if (mounted) setState(() => _learningModeEnabled = !enabled);
      },
      onLongPressLearning: isMobile ? null : _showLearningPromptSheet,
      learningModeActive: _learningModeEnabled,
      showMoreButton: isMobile,
      onClearContext: isMobile ? null : _onClearContext,
      clearContextLabel: _clearContextLabel(),
      // @ mention feature callbacks
      onMentionTap: () async {
        // Get current assistant's model for auto-scroll
        final assistant = context.read<AssistantProvider>().currentAssistant;
        final initialProvider = assistant?.chatModelProvider;
        final initialModelId = assistant?.chatModelId;
        
        final selection = await showModelSelector(
          context,
          initialProvider: initialProvider,
          initialModelId: initialModelId,
        );
        if (selection != null && mounted) {
          _addMentionedModel(selection);
        }
      },
      onAtTrigger: (textBeforeAt) async {
        // Get current assistant's model for auto-scroll
        final assistant = context.read<AssistantProvider>().currentAssistant;
        final initialProvider = assistant?.chatModelProvider;
        final initialModelId = assistant?.chatModelId;
        
        final selection = await showModelSelector(
          context,
          initialProvider: initialProvider,
          initialModelId: initialModelId,
        );
        if (selection != null && mounted) {
          _addMentionedModel(selection);
        }
        // Restore focus to input field
        if (mounted) {
          _inputFocus.requestFocus();
        }
      },
    );

    // Wrap with Column to include MentionedModelsChips above the input bar
    if (_mentionedModels.isEmpty) {
      return inputBar;
    }

    // Build provider and model display name maps for chips
    final providerNames = <String, String>{};
    final modelDisplayNames = <String, String>{};
    for (final model in _mentionedModels) {
      final cfg = settings.getProviderConfig(model.providerKey);
      if (cfg != null) {
        providerNames[model.providerKey] = cfg.name.isNotEmpty ? cfg.name : model.providerKey;
        // Try to get model display name from overrides
        final ov = cfg.modelOverrides[model.modelId] as Map?;
        final displayName = (ov?['name'] as String?)?.trim();
        modelDisplayNames['${model.providerKey}::${model.modelId}'] = 
            (displayName != null && displayName.isNotEmpty) ? displayName : model.modelId;
      } else {
        providerNames[model.providerKey] = model.providerKey;
        modelDisplayNames['${model.providerKey}::${model.modelId}'] = model.modelId;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MentionedModelsChips(
          mentionedModels: _mentionedModels,
          onRemove: _removeMentionedModel,
          providerNames: providerNames,
          modelDisplayNames: modelDisplayNames,
        ),
        const SizedBox(height: 8),
        inputBar,
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _convoFadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _convoFade = CurvedAnimation(parent: _convoFadeController, curve: Curves.easeOutCubic);
    _convoFadeController.value = 1.0;
    // Use the provided ChatService instance
    _chatService = context.read<ChatService>();
    _initChat();
    _scrollController.addListener(_onScrollControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureInputBar());
    // Load learning mode for button highlight
    Future.microtask(() async {
      final v = await LearningModeStore.isEnabled();
      if (mounted) setState(() => _learningModeEnabled = v);
    });
    // Load tool call mode
    Future.microtask(() async {
      final mode = await ToolCallModeStore.getMode();
      if (mounted) setState(() => _toolCallMode = mode);
    });

    // Initialize quick phrases provider
    Future.microtask(() async {
      try {
        await context.read<QuickPhraseProvider>().initialize();
      } catch (_) {}
    });

    // Attach MCP provider listener to auto-join new connected servers
    try {
      _mcpProvider = context.read<McpProvider>();
      _connectedMcpIds = _mcpProvider!.connectedServers.map((s) => s.id).toSet();
      _mcpProvider!.addListener(_onMcpChanged);
    } catch (_) {}

    // 鐩戝惉閿洏寮瑰嚭
    // Input focus listener - no scroll on focus, scroll only happens on message send
    _inputFocus.addListener(() {
      // No-op: focus should not trigger scroll
    });

    // Attach drawer value listener to catch swipe-open and close events
    _drawerController.addListener(_onDrawerValueChanged);

    // Desktop: auto-focus input on page load
    if (PlatformUtils.isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inputFocus.requestFocus();
      });
    }
  }

  void _onDrawerValueChanged() {
    final v = _drawerController.value;
    // If user starts opening the drawer via swipe, dismiss the keyboard once
    if (_lastDrawerValue <= 0.01 && v > 0.01) {
      _dismissKeyboard();
    }
    // Fire haptic when drawer becomes sufficiently open (completion)
    if (_lastDrawerValue < 0.95 && v >= 0.95) {
      try {
        if (context.read<SettingsProvider>().hapticsOnDrawer) {
          Haptics.drawerPulse();
        }
      } catch (_) {}
    }
    // Fire haptic when drawer becomes sufficiently closed (cancellation)
    if (_lastDrawerValue > 0.05 && v <= 0.05) {
      try {
        if (context.read<SettingsProvider>().hapticsOnDrawer) {
          Haptics.drawerPulse();
        }
      } catch (_) {}
    }
    _lastDrawerValue = v;
  }

  // Toggle tablet sidebar (embedded mode); keep icon and haptics same style as mobile
  void _toggleTabletSidebar() {
    _dismissKeyboard();
    try {
      if (context.read<SettingsProvider>().hapticsOnDrawer) {
        Haptics.drawerPulse();
      }
    } catch (_) {}
    setState(() {
      _tabletSidebarOpen = !_tabletSidebarOpen;
    });
    try { context.read<SettingsProvider>().setDesktopSidebarOpen(_tabletSidebarOpen); } catch (_) {}
  }

  void _toggleRightSidebar() {
    setState(() {
      _rightSidebarOpen = !_rightSidebarOpen;
    });
    try {
      context.read<SettingsProvider>().setDesktopRightSidebarOpen(_rightSidebarOpen);
    } catch (_) {}
  }

  Widget _buildTabletSidebar(BuildContext context) {
    final sidebar = SideDrawer(
      embedded: true,
      embeddedWidth: _embeddedSidebarWidth,
      userName: context.watch<UserProvider>().name,
      assistantName: (() {
        final l10n = AppLocalizations.of(context)!;
        final a = context.watch<AssistantProvider>().currentAssistant;
        final n = a?.name.trim();
        return (n == null || n.isEmpty) ? l10n.homePageDefaultAssistant : n;
      })(),
      loadingConversationIds: _loadingConversationIds,
      // Hide bottom bar when embedded in DesktopHomePage (which has DesktopNavRail)
      showBottomBar: !widget.isEmbeddedInDesktopNav,
        onSelectConversation: (id) {
          _switchConversationAnimated(id);
        },
        onNewConversation: () async {
          await _createNewConversationAnimated();
        },
    );

    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: _sidebarAnimDuration,
      curve: _sidebarAnimCurve,
      width: _tabletSidebarOpen ? _embeddedSidebarWidth : 0,
      color: Colors.transparent,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          maxWidth: _embeddedSidebarWidth,
          child: SizedBox(width: _embeddedSidebarWidth, child: sidebar),
        ),
      ),
    );
  }

  // ZoomDrawer state listener removed; handled by _onDrawerValueChanged

  void _onScrollControllerChanged() {
    try {
      if (!_scrollController.hasClients) return;
      
      // Detect user scrolling
      if (_scrollController.position.userScrollDirection != ScrollDirection.idle) {
        _isUserScrolling = true;
        // Reset chained jump anchor when user manually scrolls
        _lastJumpUserMessageId = null;
        
        // Cancel previous timer and set a new one
        _userScrollTimer?.cancel();
        final secs = context.read<SettingsProvider>().autoScrollIdleSeconds;
        _userScrollTimer = Timer(Duration(seconds: secs), () {
          if (mounted) {
            // 只有在当前对话还在加载（消息生成中）时才恢复自动滚动
            // 如果消息已完成，用户滚动查看历史时不应被打断
            final cid = _currentConversation?.id;
            final stillLoading = cid != null && _loadingConversationIds.contains(cid);
            if (stillLoading) {
              setState(() {
                _isUserScrolling = false;
              });
            }
          }
        });
      }
      
      // Only show when not near bottom
      final pos = _scrollController.position;
      final atBottom = pos.pixels >= (pos.maxScrollExtent - 24);
      final shouldShow = !atBottom;
      if (_showJumpToBottom != shouldShow) {
        setState(() => _showJumpToBottom = shouldShow);
      }
      
      // Update visible message for mini rail indicator
      _updateVisibleMessageId();
    } catch (_) {}
  }

  /// Detect which message is currently most visible and update _visibleMessageId
  void _updateVisibleMessageId() {
    if (!mounted || _messages.isEmpty) return;
    try {
      final media = MediaQuery.of(context);
      final listTop = kToolbarHeight + media.padding.top;
      final listBottom = media.size.height - media.padding.bottom - _inputBarHeight;
      final centerY = (listTop + listBottom) / 2;

      final collapsed = _collapseVersions(_messages);
      String? bestId;
      double bestDistance = double.infinity;

      for (final m in collapsed) {
        final key = _messageKeys[m.id];
        final ctx = key?.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        final bottom = top + box.size.height;
        // Check if visible
        if (bottom < listTop || top > listBottom) continue;
        // Distance from center
        final msgCenter = (top + bottom) / 2;
        final dist = (msgCenter - centerY).abs();
        if (dist < bestDistance) {
          bestDistance = dist;
          bestId = m.id;
        }
      }

      if (bestId != null && bestId != _visibleMessageId) {
        setState(() => _visibleMessageId = bestId);
      }
    } catch (_) {}
  }

  Future<void> _initChat() async {
    await _chatService.init();
    // Respect user preference: create new chat on launch
    final prefs = context.read<SettingsProvider>();
    if (prefs.newChatOnLaunch) {
      await _createNewConversation();
    } else {
      // When disabled, jump to the most recent conversation if exists
      final conversations = _chatService.getAllConversations();
      if (conversations.isNotEmpty) {
        final recent = conversations.first; // already sorted by updatedAt desc
        _chatService.setCurrentConversation(recent.id);
        final msgs = _chatService.getMessages(recent.id);
        setState(() {
          _currentConversation = recent;
          _messages = List.of(msgs);
          _loadVersionSelections();
          _restoreMessageUiState();
        });
        // Only auto-scroll if鐢ㄦ埛鏈富鍔ㄦ粴鍔?
        if (!_isUserScrolling) _scrollToBottomSoon();
      }
    }
  }

  Future<void> _switchConversationAnimated(String id) async {
    if (_currentConversation?.id == id) return;
    // 清理旧对话的流式 UI 状态
    _streamingNotifier.clear();
    _streamingThrottleManager.clear();
    try {
      await _convoFadeController.reverse();
    } catch (_) {}
    _chatService.setCurrentConversation(id);
    final convo = _chatService.getConversation(id);
    if (convo != null) {
      final msgs = _chatService.getMessages(id);
      if (mounted) {
        setState(() {
          _currentConversation = convo;
          _messages = List.of(msgs);
          _loadVersionSelections();
          _restoreMessageUiState();
        });
        // Ensure list lays out, then jump to bottom while hidden
        try { await WidgetsBinding.instance.endOfFrame; } catch (_) {}
        final disableAutoScroll = context.read<SettingsProvider>().disableAutoScroll;
        if (!_isUserScrolling && !disableAutoScroll) _scrollToBottom();
      }
    }
    if (mounted) {
      try { await _convoFadeController.forward(); } catch (_) {}
      // Desktop: auto-focus input after switching conversation
      if (PlatformUtils.isDesktop) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _inputFocus.requestFocus();
        });
      }
    }
  }

  Future<void> _createNewConversationAnimated() async {
    try { await _convoFadeController.reverse(); } catch (_) {}
    await _createNewConversation();
    if (mounted) {
      // New conversation typically empty; still forward fade smoothly
      try { await _convoFadeController.forward(); } catch (_) {}
      // Desktop: auto-focus input after creating new conversation
      if (PlatformUtils.isDesktop) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _inputFocus.requestFocus();
        });
      }
    }
  }

  // _onMcpChanged defined below; remove listener in the main dispose at bottom

  Future<void> _onMcpChanged() async {
    if (!mounted) return;
    final prov = _mcpProvider;
    if (prov == null) return;
    final now = prov.connectedServers.map((s) => s.id).toSet();
    final added = now.difference(_connectedMcpIds);
    _connectedMcpIds = now;
    // Assistant-level MCP selection is managed in Assistant settings; no per-conversation merge.
  }

  Future<void> _onPickPhotos() async {
    final settings = context.read<SettingsProvider>();
    final providerKey = settings.currentModelProvider;
    final accessCode = (providerKey == null) ? null : settings.getProviderConfig(providerKey).apiKey;

    final files = await MediaPickerService.pickImages();
    if (files.isEmpty) return;
    final paths = await MediaPickerService.copyPickedFiles(files, accessCode: accessCode);
    if (paths.isNotEmpty) {
      _mediaController.addImages(paths);
      if (!_isUserScrolling) _scrollToBottomSoon();
    }
  }

  Future<void> _onPickCamera() async {
    final settings = context.read<SettingsProvider>();
    final providerKey = settings.currentModelProvider;
    final accessCode = (providerKey == null) ? null : settings.getProviderConfig(providerKey).apiKey;

    try {
      final picker = ImagePicker();
      final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 1440);
      if (!mounted || f == null) return;

      if (kIsWeb) {
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) return;
        final url = await UploadService.uploadBytes(
          filename: f.name.isNotEmpty ? f.name : 'camera.jpg',
          bytes: bytes,
          accessCode: accessCode,
        );
        _mediaController.addImages([url]);
        if (!_isUserScrolling) _scrollToBottomSoon();
        return;
      }

      final saved = await MediaPickerService.copyPickedFiles([XFile(f.path)], accessCode: accessCode);
      if (saved.isNotEmpty) {
        _mediaController.addImages(saved);
        if (!_isUserScrolling) _scrollToBottomSoon();
      }
    } catch (e) {
      debugPrint('Camera capture failed: $e');
    }
  }

  Future<void> _onPickFiles() async {
    final result = await MediaPickerService.pickDocuments();
    if (result.isEmpty) return;
    final docs = result.map((r) => DocumentAttachment(
      path: r.path,
      fileName: r.name,
      mime: r.mime,
    )).toList();
    _mediaController.addFiles(docs);
    if (!_isUserScrolling) _scrollToBottomSoon();
  }

  Future<void> _createNewConversation() async {
    final ap = context.read<AssistantProvider>();
    final settings = context.read<SettingsProvider>();
    final assistantId = ap.currentAssistantId;
    // Don't change global default model - just use assistant's model if set
    final a = ap.currentAssistant;
    final conversation = await _chatService.createDraftConversation(title: _titleForLocale(context), assistantId: assistantId);
    // Default-enable MCP: select all connected servers for this conversation
    // MCP defaults are now managed per assistant; no per-conversation enabling here
    setState(() {
      _currentConversation = conversation;
      _messages = [];
      _versionSelections.clear();
      _reasoning.clear();
      _translations.clear();
      _toolParts.clear();
      _reasoningSegments.clear();
      _inlineThinkBuffer.clear();
      _inInlineThink.clear();
    });
    if (!_isUserScrolling) _scrollToBottomSoon();
  }

  Future<void> _sendMessage(ChatInputData input) async {
    final content = input.text.trim();
    if (content.isEmpty && input.imagePaths.isEmpty && input.documents.isEmpty) return;
    if (_currentConversation == null) await _createNewConversation();

    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    
    // Use assistant's model if set, otherwise fall back to global default
    final providerKey = assistant?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = assistant?.chatModelId ?? settings.currentModelId;

    if (providerKey == null || modelId == null) {
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.homePagePleaseSelectModel,
        type: NotificationType.warning,
      );
      return;
    }

    // Add user message
    // Persist user message; append image and document markers for display
    // Note: OCR is now processed inline when preparing API messages, not stored in DB
    final imageMarkers = input.imagePaths.map((p) => '\n[image:$p]').join();
    final docMarkers = input.documents.map((d) => '\n[file:${d.path}|${d.fileName}|${d.mime}]').join();
    final userMessage = await _chatService.addMessage(
      conversationId: _currentConversation!.id,
      role: 'user',
      content: content + imageMarkers + docMarkers,
    );

    setState(() {
      _messages.add(userMessage);
    });
    _setConversationLoading(_currentConversation!.id, true);

    // 寤惰繜婊氬姩纭繚UI鏇存柊瀹屾垚
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToBottom();
    });

    // Create assistant message placeholder
    final assistantMessage = await _chatService.addMessage(
      conversationId: _currentConversation!.id,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
    );

    setState(() {
      _messages.add(assistantMessage);
    });

    // Haptics on generate (if enabled)
    try {
      if (context.read<SettingsProvider>().hapticsOnGenerate) {
        Haptics.light();
      }
    } catch (_) {}

    // Reset tool parts for this new assistant message
    _toolParts.remove(assistantMessage.id);

    // Initialize reasoning state only when enabled and model supports it
    // Use conversation-level thinkingBudget (what user adjusts in UI) for consistency
    final effectiveThinkingBudget = _currentConversation?.thinkingBudget ?? settings.thinkingBudget;
    final supportsReasoning = _isReasoningModel(providerKey, modelId);
    final enableReasoning = supportsReasoning && ReasoningStateManager.isReasoningEnabled(effectiveThinkingBudget);
    if (enableReasoning) {
      final rd = ReasoningData();
      _reasoning[assistantMessage.id] = rd;
      await _chatService.updateMessage(
        assistantMessage.id,
        reasoningStartAt: DateTime.now(),
      );
    }

    // 娣诲姞鍔╂墜娑堟伅鍚庝篃婊氬姩鍒板簳閮?
    Future.delayed(const Duration(milliseconds: 100), () {
      final disableAutoScroll = context.read<SettingsProvider>().disableAutoScroll;
      if (!_isUserScrolling && !disableAutoScroll) _scrollToBottom();
    });

    // Prepare messages for API
    // Apply truncateIndex and collapse versions first, then transform the last user message to include document content
    final tIndex = _currentConversation?.truncateIndex ?? -1;
    final apiMessages = ChatMessageHandler.prepareBaseApiMessages(
      messages: _messages,
      truncateIndex: tIndex,
      versionSelections: _versionSelections,
    );

    // Build document prompts inline for each user message
    // Use a cache to avoid re-reading the same document multiple times
    final Map<String, String?> docTextCache = <String, String?>{};

    // Check if current chat model supports images
    final currentModelSupportsImages = _isImageInputModel(providerKey, modelId);

    // Check if OCR is active and should be used
    // OCR should only be used when:
    // 1. OCR is enabled in settings
    // 2. OCR model is configured
    // 3. Current chat model does NOT support images
    final ocrActive = settings.ocrEnabled &&
        settings.ocrModelProvider != null &&
        settings.ocrModelId != null &&
        !currentModelSupportsImages;

    // Process each user message to inline its document attachments and OCR
    for (int i = 0; i < apiMessages.length; i++) {
      if (apiMessages[i]['role'] != 'user') continue;

      final rawContent = (apiMessages[i]['content'] ?? '').toString();
      final parsedInput = ChatMessageHandler.parseMessageContent(rawContent);

      // Collect video paths to exclude from OCR
      final videoPaths = <String>{
        for (final d in parsedInput.documents)
          if (d.mime.toLowerCase().startsWith('video/')) d.path.trim(),
      }..removeWhere((p) => p.isEmpty);

      // Clean markers from the text
      // If OCR is active, also remove image markers since they'll be processed via OCR
      String cleanedText = rawContent.replaceAll(RegExp(r"\[file:.*?\]"), '').trim();
      if (ocrActive) {
        cleanedText = cleanedText.replaceAll(RegExp(r"\[image:.*?\]"), '');
      }

      // Build document prompts for this message
      final filePrompts = StringBuffer();
      for (final doc in parsedInput.documents) {
        final text = await ChatMessageHandler.readDocumentCached(doc, docTextCache);
        if (text == null || text.trim().isEmpty) continue;

        filePrompts.writeln('## user sent a file: ${doc.fileName}');
        filePrompts.writeln('<content>');
        filePrompts.writeln('```');
        filePrompts.writeln(text);
        filePrompts.writeln('```');
        filePrompts.writeln('</content>');
        filePrompts.writeln();
      }

      // Merge document content with cleaned text
      String merged = (filePrompts.toString() + cleanedText).trim();

      // Process OCR for images if enabled
      if (ocrActive) {
        final ocrTargets = parsedInput.imagePaths
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty && !videoPaths.contains(p))
            .toSet()
            .toList();
        if (ocrTargets.isNotEmpty) {
          final ocrText = await _getOcrTextForImagesWithUI(ocrTargets, assistantMessage.id);
          if (ocrText != null && ocrText.trim().isNotEmpty) {
            merged = (OcrService.wrapOcrBlock(ocrText) + merged).trim();
          }
        }
      }

      final userText = merged.isEmpty ? cleanedText : merged;

      // Apply message template only to the last user message
      final isLastUserMessage = () {
        for (int j = i + 1; j < apiMessages.length; j++) {
          if (apiMessages[j]['role'] == 'user') return false;
        }
        return true;
      }();

      if (isLastUserMessage) {
        final templ = (assistant?.messageTemplate ?? '{{ message }}').trim().isEmpty
            ? '{{ message }}'
            : (assistant!.messageTemplate);
        final templated = PromptTransformer.applyMessageTemplate(
          templ,
          role: 'user',
          message: userText,
          now: DateTime.now(),
        );
        apiMessages[i]['content'] = templated;
      } else {
        apiMessages[i]['content'] = userText;
      }
    }

    // Inject system prompt (assistant.systemPrompt with placeholders)
    if ((assistant?.systemPrompt.trim().isNotEmpty ?? false)) {
      final vars = PromptTransformer.buildPlaceholders(
        context: context,
        assistant: assistant!,
        modelId: modelId,
        modelName: modelId,
        userNickname: context.read<UserProvider>().name,
      );
      final sys = PromptTransformer.replacePlaceholders(assistant.systemPrompt, vars);
      apiMessages.insert(0, {'role': 'system', 'content': sys});
    }

    // Inject Memories prompt and Recent Chats if enabled
    try {
      if (assistant?.enableMemory == true) {
        final mp = context.read<MemoryProvider>();
        final mems = mp.getForAssistant(assistant!.id);
        final memPrompt = ChatMessageHandler.buildMemoriesPrompt(mems);
        if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
          apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + memPrompt;
        } else {
          apiMessages.insert(0, {'role': 'system', 'content': memPrompt});
        }
      }
      if (assistant?.enableRecentChatsReference == true) {
        final chats = context.read<ChatService>().getAllConversations();
        // Exclude current conversation to avoid self-reference, include summary
        final relevantChats = chats
            .where((c) => c.assistantId == assistant!.id && c.id != _currentConversation?.id)
            .where((c) => c.title.trim().isNotEmpty)
            .take(10)
            .map((c) => <String, String>{
                  'timestamp': c.updatedAt.toIso8601String().substring(0, 10),
                  'title': c.title.trim(),
                  'summary': (c.summary ?? '').trim(),
                })
            .toList();
        if (relevantChats.isNotEmpty) {
          final recentPrompt = ChatMessageHandler.buildRecentChatsPromptWithSummary(relevantChats);
          if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
            apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + recentPrompt;
          } else {
            apiMessages.insert(0, {'role': 'system', 'content': recentPrompt});
          }
        }
      }
    } catch (_) {}

    // Determine tool support and built-in Gemini search status
    final supportsTools = _isToolModel(providerKey, modelId);
    bool _hasBuiltInGeminiSearch() {
      try {
        final cfg = settings.getProviderConfig(providerKey);
        // Only official Gemini API supports built-in search
        if (cfg.providerType != ProviderKind.google || (cfg.vertexAI == true)) return false;
        final ov = cfg.modelOverrides[modelId] as Map?;
        final list = (ov?['builtInTools'] as List?) ?? const <dynamic>[];
        return list.map((e) => e.toString().toLowerCase()).contains('search');
      } catch (_) {
        return false;
      }
    }
    final hasBuiltInSearch = _hasBuiltInGeminiSearch();

    // Optionally inject search tool usage guide (when search is enabled and not using Gemini built-in search)
    if (settings.searchEnabled && !hasBuiltInSearch) {
      final prompt = SearchToolService.getSystemPrompt();
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + prompt;
      } else {
        apiMessages.insert(0, {'role': 'system', 'content': prompt});
      }
    }
    // Inject sticker tool usage guide (when sticker is enabled)
    if (settings.stickerEnabled && supportsTools) {
      final prompt = StickerToolService.getSystemPrompt(frequency: settings.stickerFrequency);
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + prompt;
      } else {
        apiMessages.insert(0, {'role': 'system', 'content': prompt});
      }
    }
    // Inject learning mode prompt when enabled (global)
    try {
      final lmEnabled = await LearningModeStore.isEnabled();
      if (lmEnabled) {
        final lp = await LearningModeStore.getPrompt();
        if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
          apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + lp;
        } else {
          apiMessages.insert(0, {'role': 'system', 'content': lp});
        }
      }
    } catch (_) {}

    // Limit context length according to assistant settings
    if (assistant?.limitContextMessages ?? true) {
      final keep = (assistant?.contextMessageSize ?? 64).clamp(0, 512);
      int startIdx = 0;
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        startIdx = 1;
      }
      final tail = apiMessages.sublist(startIdx);
      if (keep == 0) {
        // contextMessageSize=0: clear all history
        apiMessages.removeRange(startIdx, apiMessages.length);
      } else if (tail.length > keep) {
        final trimmed = tail.sublist(tail.length - keep);
        apiMessages
          ..removeRange(startIdx, apiMessages.length)
          ..addAll(trimmed);
      }
    }

    // Convert any local Markdown image links to inline base64 for model context
    for (int i = 0; i < apiMessages.length; i++) {
      final s = (apiMessages[i]['content'] ?? '').toString();
      if (s.isNotEmpty) {
        apiMessages[i]['content'] = await MarkdownMediaSanitizer.inlineLocalImagesToBase64(s);
      }
    }

    // Get provider config
    final config = settings.getProviderConfig(providerKey);

    // Stream response
    final bool streamOutput = assistant?.streamOutput ?? true;
    bool _finishHandled = false;
    bool _titleQueued = false;

    try {
      // Prepare tools (Search tool + MCP tools)
      final List<Map<String, dynamic>> toolDefs = <Map<String, dynamic>>[];
      Future<String> Function(String, Map<String, dynamic>)? onToolCall;

      // Search tool (skip when Gemini built-in search is active)
      if (settings.searchEnabled && !hasBuiltInSearch && supportsTools) {
        toolDefs.add(SearchToolService.getToolDefinition());
      }

      // Sticker tool
      if (settings.stickerEnabled && supportsTools) {
        toolDefs.add(StickerToolService.getToolDefinition());
      }

      // Memory tools
      if (assistant?.enableMemory == true && supportsTools) {
        toolDefs.addAll([
          {
            'type': 'function',
            'function': {
              'name': 'create_memory',
              'description': 'create a memory record',
              'parameters': {
                'type': 'object',
                'properties': {
                  'content': {'type': 'string', 'description': 'The content of the memory record'}
                },
                'required': ['content']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'edit_memory',
              'description': 'update a memory record',
              'parameters': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'integer', 'description': 'The id of the memory record'},
                  'content': {'type': 'string', 'description': 'The content of the memory record'}
                },
                'required': ['id', 'content']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'delete_memory',
              'description': 'delete a memory record',
              'parameters': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'integer', 'description': 'The id of the memory record'}
                },
                'required': ['id']
              }
            }
          },
        ]);
      }

      // MCP tools
      final mcp = context.read<McpProvider>();
      final toolSvc = context.read<McpToolService>();
      final tools = toolSvc.listAvailableToolsForAssistant(mcp, context.read<AssistantProvider>(), assistant?.id);
      if (supportsTools && tools.isNotEmpty) {
        final providerCfg = settings.getProviderConfig(providerKey);
        final providerKind = ProviderConfig.classify(providerCfg.id, explicitType: providerCfg.providerType);
        toolDefs.addAll(tools.map((t) => ChatMessageHandler.buildMcpToolDefinition(t, providerKind)));
      }

      if (toolDefs.isNotEmpty) {
        onToolCall = (name, args) async {
          if (name == SearchToolService.toolName && settings.searchEnabled) {
            final q = (args['query'] ?? '').toString();
            return await SearchToolService.executeSearch(q, settings);
          }
          // Sticker tool
          if (name == StickerToolService.toolName && settings.stickerEnabled) {
            final stickerId = (args['sticker_id'] as num?)?.toInt() ?? 0;
            return await StickerToolService.getSticker(stickerId);
          }
          // Memory tools
          if (assistant?.enableMemory == true) {
            try {
              final mp = context.read<MemoryProvider>();
              if (name == 'create_memory') {
                final content = (args['content'] ?? '').toString();
                if (content.isEmpty) return '';
                final m = await mp.add(assistantId: assistant!.id, content: content);
                return m.content;
              } else if (name == 'edit_memory') {
                final id = (args['id'] as num?)?.toInt() ?? -1;
                final content = (args['content'] ?? '').toString();
                if (id <= 0 || content.isEmpty) return '';
                final m = await mp.update(id: id, content: content);
                return m?.content ?? '';
              } else if (name == 'delete_memory') {
                final id = (args['id'] as num?)?.toInt() ?? -1;
                if (id <= 0) return '';
                final ok = await mp.delete(id: id);
                return ok ? 'deleted' : '';
              }
            } catch (_) {}
          }
          // Fallback to MCP tools
          final text = await toolSvc.callToolTextForAssistant(
            mcp,
            context.read<AssistantProvider>(),
            assistantId: assistant?.id,
            toolName: name,
            arguments: args,
          );
          return text;
        };
      }

      // Build assistant-level custom request overrides
      final aOverrides = ChatMessageHandler.buildAssistantOverrides(assistant);
    final aHeaders = aOverrides.headers;
    final aBody = aOverrides.body;

    await _prepareGeminiThoughtSignaturesForApiMessages(
      apiMessages: apiMessages,
      providerKey: providerKey,
      modelId: modelId,
    );

    // Timing tracking (Cherry Studio style)
    final startTime = DateTime.now();
    DateTime? firstTokenTime;

    final stream = ChatApiService.sendMessageStream(
      config: config,
      modelId: modelId,
      messages: apiMessages,
      userImagePaths: input.imagePaths,
      thinkingBudget: _currentConversation?.thinkingBudget ?? settings.thinkingBudget,
      temperature: assistant?.temperature,
      topP: assistant?.topP,
      maxTokens: assistant?.maxTokens,
      maxToolLoopIterations: assistant?.maxToolLoopIterations ?? 10,
      tools: toolDefs.isEmpty ? null : toolDefs,
      onToolCall: onToolCall,
      extraHeaders: aHeaders,
      extraBody: aBody,
      toolCallMode: _toolCallMode,
    );

      // 创建 StreamContext
      final ctx = _createStreamContext(
        assistantMessage: assistantMessage,
        startTime: startTime,
        streamOutput: streamOutput,
        supportsReasoning: supportsReasoning,
      );

      Future<void> finish({bool generateTitle = true}) async {
        final shouldGenerateTitle = generateTitle && !_titleQueued;
        if (_finishHandled) {
          if (shouldGenerateTitle) {
            _titleQueued = true;
            _maybeGenerateTitleFor(assistantMessage.conversationId);
            _maybeGenerateSummaryFor(assistantMessage.conversationId);
          }
          return;
        }
        _finishHandled = true;
        if (shouldGenerateTitle) {
          _titleQueued = true;
        }
        final processedContent = await MarkdownMediaSanitizer.replaceInlineBase64Images(ctx.fullContent);
        
        // Estimate token usage if not provided by API
        debugPrint('[TokenUsage] finish() - usage: ${ctx.usage != null ? "prompt=${ctx.usage!.promptTokens}, completion=${ctx.usage!.completionTokens}" : "null"}');
        final effectiveUsage = ChatMessageHandler.estimateOrFixTokenUsage(
          usage: ctx.usage,
          apiMessages: apiMessages,
          processedContent: processedContent,
        );
        
        // Calculate metrics (Cherry Studio style)
        String? tokenUsageJson;
        if (effectiveUsage != null) {
          final Map<String, dynamic> tokenUsageMap = {
            'promptTokens': effectiveUsage.promptTokens,
            'completionTokens': effectiveUsage.completionTokens,
            'cachedTokens': effectiveUsage.cachedTokens,
            'thoughtTokens': effectiveUsage.thoughtTokens,
            'totalTokens': effectiveUsage.totalTokens,
            if (effectiveUsage.rounds != null) 'rounds': effectiveUsage.rounds,
          };
          
          // Add timing metrics - always calculate even if we don't have exact firstTokenTime
          final now = DateTime.now();
          final firstToken = ctx.firstTokenTime;
          
          if (firstToken != null) {
            // We have accurate first token timestamp
            final timeFirstTokenMs = firstToken.difference(startTime).inMilliseconds;
            final timeCompletionMs = now.difference(firstToken).inMilliseconds;
            final safeCompletionMs = timeCompletionMs > 0 ? timeCompletionMs : 1;
            final tokenSpeed = effectiveUsage.completionTokens / (safeCompletionMs / 1000.0);
            
            tokenUsageMap['time_first_token_millsec'] = timeFirstTokenMs;
            tokenUsageMap['time_completion_millsec'] = timeCompletionMs;
            tokenUsageMap['token_speed'] = double.parse(tokenSpeed.toStringAsFixed(1));
          } else {
            // Fallback: estimate using total time (assume first token at 10% of total time)
            final totalMs = now.difference(startTime).inMilliseconds;
            if (totalMs > 0 && effectiveUsage.completionTokens > 0) {
              final estimatedFirstTokenMs = (totalMs * 0.1).round();
              final estimatedCompletionMs = (totalMs * 0.9).round();
              final safeCompletionMs = estimatedCompletionMs > 0 ? estimatedCompletionMs : 1;
              final tokenSpeed = effectiveUsage.completionTokens / (safeCompletionMs / 1000.0);
              
              tokenUsageMap['time_first_token_millsec'] = estimatedFirstTokenMs;
              tokenUsageMap['time_completion_millsec'] = estimatedCompletionMs;
              tokenUsageMap['token_speed'] = double.parse(tokenSpeed.toStringAsFixed(1));
            }
          }
          
          tokenUsageJson = jsonEncode(tokenUsageMap);
        }
        await _chatService.updateMessage(
          assistantMessage.id,
          content: processedContent,
          totalTokens: null, // Don't save totalTokens for new messages
          tokenUsageJson: tokenUsageJson,
          isStreaming: false,
        );
        if (!mounted) return;
        setState(() {
          final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
          if (index != -1) {
            _messages[index] = _messages[index].copyWith(
              content: processedContent,
              totalTokens: null, // Don't save totalTokens for new messages
              tokenUsageJson: tokenUsageJson,
              isStreaming: false,
            );
          }
        });
        _setConversationLoading(assistantMessage.conversationId, false);
        final r = _reasoning[assistantMessage.id];
        if (r != null) {
          if (r.finishedAt == null) {
            r.finishedAt = DateTime.now();
          }
          final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
          if (autoCollapse) {
            r.expanded = false; // auto close after finish
          }
          _reasoning[assistantMessage.id] = r;
          if (mounted) setState(() {});
        }

        // Also finish any unfinished reasoning segments
        final segments = _reasoningSegments[assistantMessage.id];
        if (segments != null && segments.isNotEmpty && segments.last.finishedAt == null) {
          segments.last.finishedAt = DateTime.now();
          final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
          if (autoCollapse) {
            segments.last.expanded = false;
          }
          _reasoningSegments[assistantMessage.id] = segments;
          if (mounted) setState(() {});
        }

        // Save reasoning segments to database
        if (segments != null && segments.isNotEmpty) {
          await _chatService.updateMessage(
            assistantMessage.id,
            reasoningSegmentsJson: ReasoningStateManager.serializeSegments(segments),
          );
        }
        if (shouldGenerateTitle) {
          _maybeGenerateTitleFor(assistantMessage.conversationId);
          _maybeGenerateSummaryFor(assistantMessage.conversationId);
        }
        _cleanupStreamingUiForMessage(assistantMessage.id);
      }

      // Track stream per conversation to allow concurrent sessions
      final String _cidForStream = assistantMessage.conversationId;
      await _conversationStreams[_cidForStream]?.cancel();

      // 使用统一的流监听器
      final _sub = _setupStreamListener(
        stream: stream,
        ctx: ctx,
        finish: finish,
        enableInlineThink: true,
        onError: (e) async {
          final errText = '${AppLocalizations.of(context)!.generationInterrupted}: $e';
          final displayContent = ChatStreamHandler.buildErrorDisplayContent(ctx.fullContent, errText);

          await _chatService.updateMessage(
            assistantMessage.id,
            content: displayContent,
            isStreaming: false,
          );

          if (!mounted) {
            _cleanupStreamingUiForMessage(assistantMessage.id);
            return;
          }
          setState(() {
            final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(
                content: displayContent,
                isStreaming: false,
              );
            }
          });
          _cleanupStreamingUiForMessage(assistantMessage.id);
          _setConversationLoading(assistantMessage.conversationId, false);
          await ChatStreamHandler.finishReasoningOnError(ctx);
          await _conversationStreams.remove(_cidForStream)?.cancel();
          showAppSnackBar(
            context,
            message: errText,
            type: NotificationType.error,
          );
        },
        onDone: () async {
          if (_loadingConversationIds.contains(_cidForStream)) {
            await finish(generateTitle: true);
          }
          await _conversationStreams.remove(_cidForStream)?.cancel();
        },
      );
      _conversationStreams[_cidForStream] = _sub;
    } catch (e) {
      final errText = '${AppLocalizations.of(context)!.generationInterrupted}: $e';
      await _chatService.updateMessage(
        assistantMessage.id,
        content: errText,
        isStreaming: false,
      );

      setState(() {
        final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: errText,
            isStreaming: false,
          );
        }
      });
      _setConversationLoading(assistantMessage.conversationId, false);
      _cleanupStreamingUiForMessage(assistantMessage.id);
      await _conversationStreams.remove(assistantMessage.conversationId)?.cancel();
      showAppSnackBar(
        context,
        message: errText,
        type: NotificationType.error,
      );
    }
  }

  /// Send message to a specific model (used for @ mention multi-model dispatch).
  /// This creates a separate response stream for the specified model.
  Future<void> _sendMessageToModel(ChatInputData input, String providerKey, String modelId) async {
    final content = input.text.trim();
    if (content.isEmpty && input.imagePaths.isEmpty && input.documents.isEmpty) return;
    if (_currentConversation == null) await _createNewConversation();

    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;

    // Add user message (only for the first model in multi-model dispatch)
    // Check if we already have a user message with this content in the current conversation
    final existingUserMsg = _messages.lastWhere(
      (m) => m.role == 'user' && m.conversationId == _currentConversation!.id,
      orElse: () => ChatMessage(id: '', conversationId: '', role: '', content: '', timestamp: DateTime.now()),
    );
    
    final imageMarkers = input.imagePaths.map((p) => '\n[image:$p]').join();
    final docMarkers = input.documents.map((d) => '\n[file:${d.path}|${d.fileName}|${d.mime}]').join();
    final expectedContent = content + imageMarkers + docMarkers;
    
    ChatMessage userMessage;
    if (existingUserMsg.id.isEmpty || existingUserMsg.content != expectedContent) {
      // Add new user message
      userMessage = await _chatService.addMessage(
        conversationId: _currentConversation!.id,
        role: 'user',
        content: expectedContent,
      );
      setState(() {
        _messages.add(userMessage);
      });
    } else {
      userMessage = existingUserMsg;
    }

    _setConversationLoading(_currentConversation!.id, true);

    // Delay scroll to ensure UI updates
    Future.delayed(const Duration(milliseconds: 100), () {
      final disableAutoScroll = context.read<SettingsProvider>().disableAutoScroll;
      if (!_isUserScrolling && !disableAutoScroll) _scrollToBottom();
    });

    // Create assistant message placeholder with the specified model
    final assistantMessage = await _chatService.addMessage(
      conversationId: _currentConversation!.id,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
    );

    setState(() {
      _messages.add(assistantMessage);
    });

    // Haptics on generate (if enabled)
    try {
      if (context.read<SettingsProvider>().hapticsOnGenerate) {
        Haptics.light();
      }
    } catch (_) {}

    // Reset tool parts for this new assistant message
    _toolParts.remove(assistantMessage.id);

    // Initialize reasoning state only when enabled and model supports it
    // Use conversation-level thinkingBudget (what user adjusts in UI) for consistency
    final effectiveThinkingBudget = _currentConversation?.thinkingBudget ?? settings.thinkingBudget;
    final supportsReasoning = _isReasoningModel(providerKey, modelId);
    final enableReasoning = supportsReasoning && ReasoningStateManager.isReasoningEnabled(effectiveThinkingBudget);
    if (enableReasoning) {
      final rd = ReasoningData();
      _reasoning[assistantMessage.id] = rd;
      await _chatService.updateMessage(
        assistantMessage.id,
        reasoningStartAt: DateTime.now(),
      );
    }

    // Scroll after adding assistant message
    Future.delayed(const Duration(milliseconds: 100), () {
      final disableAutoScroll = context.read<SettingsProvider>().disableAutoScroll;
      if (!_isUserScrolling && !disableAutoScroll) _scrollToBottom();
    });

    // Prepare messages for API (reuse the same logic as _sendMessage)
    final tIndex = _currentConversation?.truncateIndex ?? -1;
    final apiMessages = ChatMessageHandler.prepareBaseApiMessages(
      messages: _messages,
      truncateIndex: tIndex,
      versionSelections: _versionSelections,
    );

    // Build document prompts inline for each user message
    final Map<String, String?> docTextCache = <String, String?>{};
    final currentModelSupportsImages = _isImageInputModel(providerKey, modelId);
    final ocrActive = settings.ocrEnabled &&
        settings.ocrModelProvider != null &&
        settings.ocrModelId != null &&
        !currentModelSupportsImages;

    // Process each user message to inline its document attachments and OCR
    for (int i = 0; i < apiMessages.length; i++) {
      if (apiMessages[i]['role'] != 'user') continue;

      final rawContent = (apiMessages[i]['content'] ?? '').toString();
      final parsedInput = ChatMessageHandler.parseMessageContent(rawContent);

      final videoPaths = <String>{
        for (final d in parsedInput.documents)
          if (d.mime.toLowerCase().startsWith('video/')) d.path.trim(),
      }..removeWhere((p) => p.isEmpty);

      String cleanedText = rawContent.replaceAll(RegExp(r"\[file:.*?\]"), '').trim();
      if (ocrActive) {
        cleanedText = cleanedText.replaceAll(RegExp(r"\[image:.*?\]"), '');
      }

      final filePrompts = StringBuffer();
      for (final doc in parsedInput.documents) {
        final text = await ChatMessageHandler.readDocumentCached(doc, docTextCache);
        if (text == null || text.trim().isEmpty) continue;

        filePrompts.writeln('## user sent a file: ${doc.fileName}');
        filePrompts.writeln('<content>');
        filePrompts.writeln('```');
        filePrompts.writeln(text);
        filePrompts.writeln('```');
        filePrompts.writeln('</content>');
        filePrompts.writeln();
      }

      String merged = (filePrompts.toString() + cleanedText).trim();

      if (ocrActive) {
        final ocrTargets = parsedInput.imagePaths
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty && !videoPaths.contains(p))
            .toSet()
            .toList();
        if (ocrTargets.isNotEmpty) {
          final ocrText = await _getOcrTextForImagesWithUI(ocrTargets, assistantMessage.id);
          if (ocrText != null && ocrText.trim().isNotEmpty) {
            merged = (OcrService.wrapOcrBlock(ocrText) + merged).trim();
          }
        }
      }

      final userText = merged.isEmpty ? cleanedText : merged;

      final isLastUserMessage = () {
        for (int j = i + 1; j < apiMessages.length; j++) {
          if (apiMessages[j]['role'] == 'user') return false;
        }
        return true;
      }();

      if (isLastUserMessage) {
        final templ = (assistant?.messageTemplate ?? '{{ message }}').trim().isEmpty
            ? '{{ message }}'
            : (assistant!.messageTemplate);
        final templated = PromptTransformer.applyMessageTemplate(
          templ,
          role: 'user',
          message: userText,
          now: DateTime.now(),
        );
        apiMessages[i]['content'] = templated;
      } else {
        apiMessages[i]['content'] = userText;
      }
    }

    // Inject system prompt
    if ((assistant?.systemPrompt.trim().isNotEmpty ?? false)) {
      final vars = PromptTransformer.buildPlaceholders(
        context: context,
        assistant: assistant!,
        modelId: modelId,
        modelName: modelId,
        userNickname: context.read<UserProvider>().name,
      );
      final sys = PromptTransformer.replacePlaceholders(assistant.systemPrompt, vars);
      apiMessages.insert(0, {'role': 'system', 'content': sys});
    }

    // Inject Memories and Recent Chats if enabled
    try {
      if (assistant?.enableMemory == true) {
        final mp = context.read<MemoryProvider>();
        final mems = mp.getForAssistant(assistant!.id);
        final memPrompt = ChatMessageHandler.buildMemoriesPrompt(mems);
        if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
          apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + memPrompt;
        } else {
          apiMessages.insert(0, {'role': 'system', 'content': memPrompt});
        }
      }
      if (assistant?.enableRecentChatsReference == true) {
        final chats = context.read<ChatService>().getAllConversations();
        // Exclude current conversation to avoid self-reference, include summary
        final relevantChats = chats
            .where((c) => c.assistantId == assistant!.id && c.id != _currentConversation?.id)
            .where((c) => c.title.trim().isNotEmpty)
            .take(10)
            .map((c) => <String, String>{
                  'timestamp': c.updatedAt.toIso8601String().substring(0, 10),
                  'title': c.title.trim(),
                  'summary': (c.summary ?? '').trim(),
                })
            .toList();
        if (relevantChats.isNotEmpty) {
          final recentPrompt = ChatMessageHandler.buildRecentChatsPromptWithSummary(relevantChats);
          if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
            apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + recentPrompt;
          } else {
            apiMessages.insert(0, {'role': 'system', 'content': recentPrompt});
          }
        }
      }
    } catch (_) {}

    // Determine tool support
    final supportsTools = _isToolModel(providerKey, modelId);
    bool _hasBuiltInGeminiSearch() {
      try {
        final cfg = settings.getProviderConfig(providerKey);
        if (cfg.providerType != ProviderKind.google || (cfg.vertexAI == true)) return false;
        final ov = cfg.modelOverrides[modelId] as Map?;
        final list = (ov?['builtInTools'] as List?) ?? const <dynamic>[];
        return list.map((e) => e.toString().toLowerCase()).contains('search');
      } catch (_) {
        return false;
      }
    }
    final hasBuiltInSearch = _hasBuiltInGeminiSearch();

    // Inject search tool usage guide
    if (settings.searchEnabled && !hasBuiltInSearch) {
      final prompt = SearchToolService.getSystemPrompt();
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + prompt;
      } else {
        apiMessages.insert(0, {'role': 'system', 'content': prompt});
      }
    }

    // Inject sticker tool usage guide
    if (settings.stickerEnabled && supportsTools) {
      final prompt = StickerToolService.getSystemPrompt();
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + prompt;
      } else {
        apiMessages.insert(0, {'role': 'system', 'content': prompt});
      }
    }

    // Inject learning mode prompt
    try {
      final lmEnabled = await LearningModeStore.isEnabled();
      if (lmEnabled) {
        final lp = await LearningModeStore.getPrompt();
        if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
          apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + lp;
        } else {
          apiMessages.insert(0, {'role': 'system', 'content': lp});
        }
      }
    } catch (_) {}

    // Limit context length
    if (assistant?.limitContextMessages ?? true) {
      final keep = (assistant?.contextMessageSize ?? 64).clamp(0, 512);
      int startIdx = 0;
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        startIdx = 1;
      }
      final tail = apiMessages.sublist(startIdx);
      if (keep == 0) {
        apiMessages.removeRange(startIdx, apiMessages.length);
      } else if (tail.length > keep) {
        final trimmed = tail.sublist(tail.length - keep);
        apiMessages
          ..removeRange(startIdx, apiMessages.length)
          ..addAll(trimmed);
      }
    }

    // Convert local Markdown image links to inline base64
    for (int i = 0; i < apiMessages.length; i++) {
      final s = (apiMessages[i]['content'] ?? '').toString();
      if (s.isNotEmpty) {
        apiMessages[i]['content'] = await MarkdownMediaSanitizer.inlineLocalImagesToBase64(s);
      }
    }

    // Get provider config
    final config = settings.getProviderConfig(providerKey);

    // Stream response
    final bool streamOutput = assistant?.streamOutput ?? true;
    bool _finishHandled = false;
    bool _titleQueued = false;

    try {
      // Prepare tools
      final List<Map<String, dynamic>> toolDefs = <Map<String, dynamic>>[];
      Future<String> Function(String, Map<String, dynamic>)? onToolCall;

      if (settings.searchEnabled && !hasBuiltInSearch && supportsTools) {
        toolDefs.add(SearchToolService.getToolDefinition());
      }

      if (settings.stickerEnabled && supportsTools) {
        toolDefs.add(StickerToolService.getToolDefinition());
      }

      if (assistant?.enableMemory == true && supportsTools) {
        toolDefs.addAll([
          {
            'type': 'function',
            'function': {
              'name': 'create_memory',
              'description': 'create a memory record',
              'parameters': {
                'type': 'object',
                'properties': {
                  'content': {'type': 'string', 'description': 'The content of the memory record'}
                },
                'required': ['content']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'edit_memory',
              'description': 'update a memory record',
              'parameters': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'integer', 'description': 'The id of the memory record'},
                  'content': {'type': 'string', 'description': 'The content of the memory record'}
                },
                'required': ['id', 'content']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'delete_memory',
              'description': 'delete a memory record',
              'parameters': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'integer', 'description': 'The id of the memory record'}
                },
                'required': ['id']
              }
            }
          },
        ]);
      }

      // MCP tools
      final mcp = context.read<McpProvider>();
      final toolSvc = context.read<McpToolService>();
      final tools = toolSvc.listAvailableToolsForAssistant(mcp, context.read<AssistantProvider>(), assistant?.id);
      if (supportsTools && tools.isNotEmpty) {
        final providerCfg = settings.getProviderConfig(providerKey);
        final providerKind = ProviderConfig.classify(providerCfg.id, explicitType: providerCfg.providerType);
        toolDefs.addAll(tools.map((t) => ChatMessageHandler.buildMcpToolDefinition(t, providerKind)));
      }

      if (toolDefs.isNotEmpty) {
        onToolCall = (name, args) async {
          if (name == SearchToolService.toolName && settings.searchEnabled) {
            final q = (args['query'] ?? '').toString();
            return await SearchToolService.executeSearch(q, settings);
          }
          if (name == StickerToolService.toolName && settings.stickerEnabled) {
            final stickerId = (args['sticker_id'] as num?)?.toInt() ?? 0;
            return await StickerToolService.getSticker(stickerId);
          }
          if (assistant?.enableMemory == true) {
            try {
              final mp = context.read<MemoryProvider>();
              if (name == 'create_memory') {
                final content = (args['content'] ?? '').toString();
                if (content.isEmpty) return '';
                final m = await mp.add(assistantId: assistant!.id, content: content);
                return m.content;
              } else if (name == 'edit_memory') {
                final id = (args['id'] as num?)?.toInt() ?? -1;
                final content = (args['content'] ?? '').toString();
                if (id <= 0 || content.isEmpty) return '';
                final m = await mp.update(id: id, content: content);
                return m?.content ?? '';
              } else if (name == 'delete_memory') {
                final id = (args['id'] as num?)?.toInt() ?? -1;
                if (id <= 0) return '';
                final ok = await mp.delete(id: id);
                return ok ? 'deleted' : '';
              }
            } catch (_) {}
          }
          final text = await toolSvc.callToolTextForAssistant(
            mcp,
            context.read<AssistantProvider>(),
            assistantId: assistant?.id,
            toolName: name,
            arguments: args,
          );
          return text;
        };
      }

      final aOverrides = ChatMessageHandler.buildAssistantOverrides(assistant);
      final aHeaders = aOverrides.headers;
      final aBody = aOverrides.body;

      await _prepareGeminiThoughtSignaturesForApiMessages(
        apiMessages: apiMessages,
        providerKey: providerKey,
        modelId: modelId,
      );

      final startTime = DateTime.now();

      final stream = ChatApiService.sendMessageStream(
        config: config,
        modelId: modelId,
        messages: apiMessages,
        userImagePaths: input.imagePaths,
        thinkingBudget: _currentConversation?.thinkingBudget ?? settings.thinkingBudget,
        temperature: assistant?.temperature,
        topP: assistant?.topP,
        maxTokens: assistant?.maxTokens,
        maxToolLoopIterations: assistant?.maxToolLoopIterations ?? 10,
        tools: toolDefs.isEmpty ? null : toolDefs,
        onToolCall: onToolCall,
        extraHeaders: aHeaders,
        extraBody: aBody,
        toolCallMode: _toolCallMode,
      );

      final ctx = _createStreamContext(
        assistantMessage: assistantMessage,
        startTime: startTime,
        streamOutput: streamOutput,
        supportsReasoning: supportsReasoning,
      );

      Future<void> finish({bool generateTitle = true}) async {
        final shouldGenerateTitle = generateTitle && !_titleQueued;
        if (_finishHandled) {
          if (shouldGenerateTitle) {
            _titleQueued = true;
            _maybeGenerateTitleFor(assistantMessage.conversationId);
            _maybeGenerateSummaryFor(assistantMessage.conversationId);
          }
          return;
        }
        _finishHandled = true;
        if (shouldGenerateTitle) {
          _titleQueued = true;
        }
        final processedContent = await MarkdownMediaSanitizer.replaceInlineBase64Images(ctx.fullContent);
        
        final effectiveUsage = ChatMessageHandler.estimateOrFixTokenUsage(
          usage: ctx.usage,
          apiMessages: apiMessages,
          processedContent: processedContent,
        );
        
        String? tokenUsageJson;
        if (effectiveUsage != null) {
          final Map<String, dynamic> tokenUsageMap = {
            'promptTokens': effectiveUsage.promptTokens,
            'completionTokens': effectiveUsage.completionTokens,
            'cachedTokens': effectiveUsage.cachedTokens,
            'thoughtTokens': effectiveUsage.thoughtTokens,
            'totalTokens': effectiveUsage.totalTokens,
            if (effectiveUsage.rounds != null) 'rounds': effectiveUsage.rounds,
          };
          
          final now = DateTime.now();
          final firstToken = ctx.firstTokenTime;
          
          if (firstToken != null) {
            final timeFirstTokenMs = firstToken.difference(startTime).inMilliseconds;
            final timeCompletionMs = now.difference(firstToken).inMilliseconds;
            final safeCompletionMs = timeCompletionMs > 0 ? timeCompletionMs : 1;
            final tokenSpeed = effectiveUsage.completionTokens / (safeCompletionMs / 1000.0);
            
            tokenUsageMap['time_first_token_millsec'] = timeFirstTokenMs;
            tokenUsageMap['time_completion_millsec'] = timeCompletionMs;
            tokenUsageMap['token_speed'] = double.parse(tokenSpeed.toStringAsFixed(1));
          } else {
            final totalMs = now.difference(startTime).inMilliseconds;
            if (totalMs > 0 && effectiveUsage.completionTokens > 0) {
              final estimatedFirstTokenMs = (totalMs * 0.1).round();
              final estimatedCompletionMs = (totalMs * 0.9).round();
              final safeCompletionMs = estimatedCompletionMs > 0 ? estimatedCompletionMs : 1;
              final tokenSpeed = effectiveUsage.completionTokens / (safeCompletionMs / 1000.0);
              
              tokenUsageMap['time_first_token_millsec'] = estimatedFirstTokenMs;
              tokenUsageMap['time_completion_millsec'] = estimatedCompletionMs;
              tokenUsageMap['token_speed'] = double.parse(tokenSpeed.toStringAsFixed(1));
            }
          }
          
          tokenUsageJson = jsonEncode(tokenUsageMap);
        }
        await _chatService.updateMessage(
          assistantMessage.id,
          content: processedContent,
          totalTokens: null,
          tokenUsageJson: tokenUsageJson,
          isStreaming: false,
        );
        if (!mounted) return;
        setState(() {
          final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
          if (index != -1) {
            _messages[index] = _messages[index].copyWith(
              content: processedContent,
              totalTokens: null,
              tokenUsageJson: tokenUsageJson,
              isStreaming: false,
            );
          }
        });
        _setConversationLoading(assistantMessage.conversationId, false);
        final r = _reasoning[assistantMessage.id];
        if (r != null) {
          if (r.finishedAt == null) {
            r.finishedAt = DateTime.now();
          }
          final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
          if (autoCollapse) {
            r.expanded = false;
          }
          _reasoning[assistantMessage.id] = r;
          if (mounted) setState(() {});
        }

        final segments = _reasoningSegments[assistantMessage.id];
        if (segments != null && segments.isNotEmpty && segments.last.finishedAt == null) {
          segments.last.finishedAt = DateTime.now();
          final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
          if (autoCollapse) {
            segments.last.expanded = false;
          }
          _reasoningSegments[assistantMessage.id] = segments;
          if (mounted) setState(() {});
        }

        if (segments != null && segments.isNotEmpty) {
          await _chatService.updateMessage(
            assistantMessage.id,
            reasoningSegmentsJson: ReasoningStateManager.serializeSegments(segments),
          );
        }
        if (shouldGenerateTitle) {
          _maybeGenerateTitleFor(assistantMessage.conversationId);
          _maybeGenerateSummaryFor(assistantMessage.conversationId);
        }
        _cleanupStreamingUiForMessage(assistantMessage.id);
      }

      final String _cidForStream = assistantMessage.conversationId;
      // Note: Don't cancel existing streams for multi-model dispatch
      // Each model gets its own stream tracked by message ID instead of conversation ID
      final streamKey = '${_cidForStream}_${assistantMessage.id}';

      final _sub = _setupStreamListener(
        stream: stream,
        ctx: ctx,
        finish: finish,
        enableInlineThink: true,
        onError: (e) async {
          final errText = '${AppLocalizations.of(context)!.generationInterrupted}: $e';
          final displayContent = ChatStreamHandler.buildErrorDisplayContent(ctx.fullContent, errText);

          await _chatService.updateMessage(
            assistantMessage.id,
            content: displayContent,
            isStreaming: false,
          );

          if (!mounted) {
            _cleanupStreamingUiForMessage(assistantMessage.id);
            return;
          }
          setState(() {
            final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(
                content: displayContent,
                isStreaming: false,
              );
            }
          });
          _cleanupStreamingUiForMessage(assistantMessage.id);
          _setConversationLoading(assistantMessage.conversationId, false);
          await ChatStreamHandler.finishReasoningOnError(ctx);
          await _conversationStreams.remove(streamKey)?.cancel();
          showAppSnackBar(
            context,
            message: errText,
            type: NotificationType.error,
          );
        },
        onDone: () async {
          if (_loadingConversationIds.contains(_cidForStream)) {
            await finish(generateTitle: true);
          }
          await _conversationStreams.remove(streamKey)?.cancel();
        },
      );
      _conversationStreams[streamKey] = _sub;
    } catch (e) {
      final errText = '${AppLocalizations.of(context)!.generationInterrupted}: $e';
      await _chatService.updateMessage(
        assistantMessage.id,
        content: errText,
        isStreaming: false,
      );

      setState(() {
        final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: errText,
            isStreaming: false,
          );
        }
      });
      _setConversationLoading(assistantMessage.conversationId, false);
      _cleanupStreamingUiForMessage(assistantMessage.id);
      showAppSnackBar(
        context,
        message: errText,
        type: NotificationType.error,
      );
    }
  }

  /// Re-answer a message with a different model selected via @ mention.
  /// Opens the model selector and generates a new response using the selected model
  /// with the same conversation context as the original message.
  Future<void> _reAnswerWithModel(ChatMessage message) async {
    if (_currentConversation == null) return;
    if (message.role != 'assistant') return;

    // Get current model for auto-scroll position
    final initialProvider = message.providerId;
    final initialModelId = message.modelId;

    // Open model selector
    final selection = await showModelSelector(
      context,
      initialProvider: initialProvider,
      initialModelId: initialModelId,
    );

    if (selection == null || !mounted) return;

    // Cancel any ongoing stream
    await _cancelStreaming();

    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) return;

    // Compute versioning target (groupId + nextVersion)
    final targetGroupId = message.groupId ?? message.id;
    int maxVer = -1;
    for (final m in _messages) {
      final gid = (m.groupId ?? m.id);
      if (gid == targetGroupId) {
        if (m.version > maxVer) maxVer = m.version;
      }
    }
    final nextVersion = maxVer + 1;

    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final providerKey = selection.providerKey;
    final modelId = selection.modelId;

    // Create assistant message placeholder (new version in target group with selected model)
    final assistantMessage = await _chatService.addMessage(
      conversationId: _currentConversation!.id,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
      groupId: targetGroupId,
      version: nextVersion,
    );

    // Persist selection to the latest version of this group
    final gid = assistantMessage.groupId ?? assistantMessage.id;
    _versionSelections[gid] = assistantMessage.version;
    await _chatService.setSelectedVersion(_currentConversation!.id, gid, assistantMessage.version);

    setState(() {
      _messages.add(assistantMessage);
    });
    _setConversationLoading(_currentConversation!.id, true);

    // Haptics on regenerate
    try {
      if (context.read<SettingsProvider>().hapticsOnGenerate) {
        Haptics.light();
      }
    } catch (_) {}

    // Initialize reasoning state only when enabled and model supports it
    // Use conversation-level thinkingBudget (what user adjusts in UI) for consistency
    final effectiveThinkingBudget = _currentConversation?.thinkingBudget ?? settings.thinkingBudget;
    final supportsReasoning = _isReasoningModel(providerKey, modelId);
    final enableReasoning = supportsReasoning && ReasoningStateManager.isReasoningEnabled(effectiveThinkingBudget);
    if (enableReasoning) {
      final rd = ReasoningData();
      _reasoning[assistantMessage.id] = rd;
      await _chatService.updateMessage(assistantMessage.id, reasoningStartAt: DateTime.now());
    }

    // Build API messages from current context (apply truncate + collapse versions)
    // Use messages up to and including the original message's position
    final tIndex = _currentConversation?.truncateIndex ?? -1;
    final messagesForContext = _messages.where((m) {
      final mIdx = _messages.indexOf(m);
      // Include messages before the new assistant message
      return mIdx < _messages.length - 1;
    }).toList();
    
    final apiMessages = ChatMessageHandler.prepareBaseApiMessages(
      messages: messagesForContext,
      truncateIndex: tIndex,
      versionSelections: _versionSelections,
    );

    // Inject system prompt
    if ((assistant?.systemPrompt.trim().isNotEmpty ?? false)) {
      final vars = PromptTransformer.buildPlaceholders(
        context: context,
        assistant: assistant!,
        modelId: modelId,
        modelName: modelId,
        userNickname: context.read<UserProvider>().name,
      );
      final sys = PromptTransformer.replacePlaceholders(assistant.systemPrompt, vars);
      apiMessages.insert(0, {'role': 'system', 'content': sys});
    }

    // Inject Memories + Recent Chats
    try {
      if (assistant?.enableMemory == true) {
        final mp = context.read<MemoryProvider>();
        final mems = mp.getForAssistant(assistant!.id);
        final memPrompt = ChatMessageHandler.buildMemoriesPrompt(mems);
        if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
          apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + memPrompt;
        } else {
          apiMessages.insert(0, {'role': 'system', 'content': memPrompt});
        }
      }
      if (assistant?.enableRecentChatsReference == true) {
        final chats = context.read<ChatService>().getAllConversations();
        // Exclude current conversation to avoid self-reference, include summary
        final relevantChats = chats
            .where((c) => c.assistantId == assistant!.id && c.id != _currentConversation?.id)
            .where((c) => c.title.trim().isNotEmpty)
            .take(10)
            .map((c) => <String, String>{
                  'timestamp': c.updatedAt.toIso8601String().substring(0, 10),
                  'title': c.title.trim(),
                  'summary': (c.summary ?? '').trim(),
                })
            .toList();
        if (relevantChats.isNotEmpty) {
          final recentPrompt = ChatMessageHandler.buildRecentChatsPromptWithSummary(relevantChats);
          if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
            apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + recentPrompt;
          } else {
            apiMessages.insert(0, {'role': 'system', 'content': recentPrompt});
          }
        }
      }
    } catch (_) {}

    // Inject search tool usage guide when enabled
    if (settings.searchEnabled) {
      final prompt = SearchToolService.getSystemPrompt();
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + prompt;
      } else {
        apiMessages.insert(0, {'role': 'system', 'content': prompt});
      }
    }

    // Inject sticker tool usage guide when enabled
    if (settings.stickerEnabled) {
      final prompt = StickerToolService.getSystemPrompt();
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + prompt;
      } else {
        apiMessages.insert(0, {'role': 'system', 'content': prompt});
      }
    }

    // Determine tool support
    final supportsTools = _isToolModel(providerKey, modelId);
    bool _hasBuiltInGeminiSearch() {
      try {
        final cfg = settings.getProviderConfig(providerKey);
        if (cfg.providerType != ProviderKind.google || (cfg.vertexAI == true)) return false;
        final ov = cfg.modelOverrides[modelId] as Map?;
        final list = (ov?['builtInTools'] as List?) ?? const <dynamic>[];
        return list.map((e) => e.toString().toLowerCase()).contains('search');
      } catch (_) {
        return false;
      }
    }
    final hasBuiltInSearch = _hasBuiltInGeminiSearch();

    // Get provider config
    final config = settings.getProviderConfig(providerKey);

    // Stream response
    final bool streamOutput = assistant?.streamOutput ?? true;
    bool _finishHandled = false;
    bool _titleQueued = false;

    try {
      // Prepare tools
      final List<Map<String, dynamic>> toolDefs = <Map<String, dynamic>>[];
      Future<String> Function(String, Map<String, dynamic>)? onToolCall;

      if (settings.searchEnabled && !hasBuiltInSearch && supportsTools) {
        toolDefs.add(SearchToolService.getToolDefinition());
      }

      if (settings.stickerEnabled && supportsTools) {
        toolDefs.add(StickerToolService.getToolDefinition());
      }

      if (assistant?.enableMemory == true && supportsTools) {
        toolDefs.addAll(ChatMessageHandler.memoryToolDefinitions);
      }

      // MCP tools
      final mcp = context.read<McpProvider>();
      final toolSvc = context.read<McpToolService>();
      final tools = toolSvc.listAvailableToolsForAssistant(mcp, context.read<AssistantProvider>(), assistant?.id);
      if (supportsTools && tools.isNotEmpty) {
        final providerCfg = settings.getProviderConfig(providerKey);
        final providerKind = ProviderConfig.classify(providerCfg.id, explicitType: providerCfg.providerType);
        toolDefs.addAll(tools.map((t) => ChatMessageHandler.buildMcpToolDefinition(t, providerKind)));
      }

      if (toolDefs.isNotEmpty) {
        onToolCall = (name, args) async {
          if (name == SearchToolService.toolName && settings.searchEnabled) {
            final q = (args['query'] ?? '').toString();
            return await SearchToolService.executeSearch(q, settings);
          }
          if (name == StickerToolService.toolName && settings.stickerEnabled) {
            final stickerId = (args['sticker_id'] as num?)?.toInt() ?? 0;
            return await StickerToolService.getSticker(stickerId);
          }
          if (assistant?.enableMemory == true) {
            final mp = context.read<MemoryProvider>();
            final result = await ChatMessageHandler.handleMemoryToolCall(
              toolName: name,
              args: args,
              memoryProvider: mp,
              assistantId: assistant!.id,
            );
            if (result != null) return result;
          }
          final text = await toolSvc.callToolTextForAssistant(
            mcp,
            context.read<AssistantProvider>(),
            assistantId: assistant?.id,
            toolName: name,
            arguments: args,
          );
          return text;
        };
      }

      final aOverrides = ChatMessageHandler.buildAssistantOverrides(assistant);
      final aHeaders = aOverrides.headers;
      final aBody = aOverrides.body;

      await _prepareGeminiThoughtSignaturesForApiMessages(
        apiMessages: apiMessages,
        providerKey: providerKey,
        modelId: modelId,
      );

      final startTime = DateTime.now();

      final stream = ChatApiService.sendMessageStream(
        config: config,
        modelId: modelId,
        messages: apiMessages,
        userImagePaths: const [],
        thinkingBudget: _currentConversation?.thinkingBudget ?? settings.thinkingBudget,
        temperature: assistant?.temperature,
        topP: assistant?.topP,
        maxTokens: assistant?.maxTokens,
        maxToolLoopIterations: assistant?.maxToolLoopIterations ?? 10,
        tools: toolDefs.isEmpty ? null : toolDefs,
        onToolCall: onToolCall,
        extraHeaders: aHeaders,
        extraBody: aBody,
        toolCallMode: _toolCallMode,
      );

      final ctx = _createStreamContext(
        assistantMessage: assistantMessage,
        startTime: startTime,
        streamOutput: streamOutput,
        supportsReasoning: supportsReasoning,
      );

      Future<void> finish({bool generateTitle = true}) async {
        final shouldGenerateTitle = generateTitle && !_titleQueued;
        if (_finishHandled) {
          if (shouldGenerateTitle) {
            _titleQueued = true;
            _maybeGenerateTitleFor(assistantMessage.conversationId);
            _maybeGenerateSummaryFor(assistantMessage.conversationId);
          }
          return;
        }
        _finishHandled = true;
        if (shouldGenerateTitle) {
          _titleQueued = true;
        }
        final processedContent = await MarkdownMediaSanitizer.replaceInlineBase64Images(ctx.fullContent);
        
        final effectiveUsage = ChatMessageHandler.estimateOrFixTokenUsage(
          usage: ctx.usage,
          apiMessages: apiMessages,
          processedContent: processedContent,
        );
        
        String? tokenUsageJson;
        if (effectiveUsage != null) {
          final Map<String, dynamic> tokenUsageMap = {
            'promptTokens': effectiveUsage.promptTokens,
            'completionTokens': effectiveUsage.completionTokens,
            'cachedTokens': effectiveUsage.cachedTokens,
            'thoughtTokens': effectiveUsage.thoughtTokens,
            'totalTokens': effectiveUsage.totalTokens,
            if (effectiveUsage.rounds != null) 'rounds': effectiveUsage.rounds,
          };
          tokenUsageJson = jsonEncode(tokenUsageMap);
        }
        await _chatService.updateMessage(
          assistantMessage.id,
          content: processedContent,
          totalTokens: null,
          tokenUsageJson: tokenUsageJson,
          isStreaming: false,
        );
        if (!mounted) return;
        setState(() {
          final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
          if (index != -1) {
            _messages[index] = _messages[index].copyWith(
              content: processedContent,
              totalTokens: null,
              tokenUsageJson: tokenUsageJson,
              isStreaming: false,
            );
          }
        });
        _setConversationLoading(assistantMessage.conversationId, false);
        if (shouldGenerateTitle) {
          _maybeGenerateTitleFor(assistantMessage.conversationId);
          _maybeGenerateSummaryFor(assistantMessage.conversationId);
        }
        _cleanupStreamingUiForMessage(assistantMessage.id);
      }

      final _cidForStream = assistantMessage.conversationId;
      await _conversationStreams[_cidForStream]?.cancel();

      final _sub = _setupStreamListener(
        stream: stream,
        ctx: ctx,
        finish: finish,
        enableInlineThink: true,
        onError: (e) async {
          final errText = '${AppLocalizations.of(context)!.generationInterrupted}: $e';
          final displayContent = ChatStreamHandler.buildErrorDisplayContent(ctx.fullContent, errText);

          await _chatService.updateMessage(
            assistantMessage.id,
            content: displayContent,
            isStreaming: false,
          );

          if (!mounted) {
            _cleanupStreamingUiForMessage(assistantMessage.id);
            return;
          }
          setState(() {
            final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(
                content: displayContent,
                isStreaming: false,
              );
            }
          });
          _cleanupStreamingUiForMessage(assistantMessage.id);
          _setConversationLoading(assistantMessage.conversationId, false);
          await ChatStreamHandler.finishReasoningOnError(ctx);
          await _conversationStreams.remove(_cidForStream)?.cancel();
          showAppSnackBar(
            context,
            message: errText,
            type: NotificationType.error,
          );
        },
        onDone: () async {
          if (_loadingConversationIds.contains(_cidForStream)) {
            await finish(generateTitle: true);
          }
          await _conversationStreams.remove(_cidForStream)?.cancel();
        },
      );
      _conversationStreams[_cidForStream] = _sub;
    } catch (e) {
      final errText = '${AppLocalizations.of(context)!.generationInterrupted}: $e';
      await _chatService.updateMessage(
        assistantMessage.id,
        content: errText,
        isStreaming: false,
      );

      setState(() {
        final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: errText,
            isStreaming: false,
          );
        }
      });
      _setConversationLoading(assistantMessage.conversationId, false);
      _cleanupStreamingUiForMessage(assistantMessage.id);
      showAppSnackBar(
        context,
        message: errText,
        type: NotificationType.error,
      );
    }
  }

  Future<void> _regenerateAtMessage(ChatMessage message) async {
    if (_currentConversation == null) return;
    // Cancel any ongoing stream
    await _cancelStreaming();

    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) return;

    // Compute versioning target (groupId + nextVersion) and where to cut
    String? targetGroupId;
    int nextVersion = 0;
    int lastKeep;
    if (message.role == 'assistant') {
      // Keep the existing assistant message as old version
      lastKeep = idx; // remove after this
      targetGroupId = message.groupId ?? message.id;
      int maxVer = -1;
      for (final m in _messages) {
        final gid = (m.groupId ?? m.id);
        if (gid == targetGroupId) {
          if (m.version > maxVer) maxVer = m.version;
        }
      }
      nextVersion = maxVer + 1;
    } else {
      // User message: find the first assistant reply after the FIRST occurrence of this user group,
      // not after the current version's position (which may be appended at tail after edits).
      final userGroupId = message.groupId ?? message.id;
      int userFirst = -1;
      for (int i = 0; i < _messages.length; i++) {
        final gid0 = (_messages[i].groupId ?? _messages[i].id);
        if (gid0 == userGroupId) { userFirst = i; break; }
      }
      if (userFirst < 0) userFirst = idx; // fallback

      int aid = -1;
      for (int i = userFirst + 1; i < _messages.length; i++) {
        if (_messages[i].role == 'assistant') { aid = i; break; }
      }
      if (aid >= 0) {
        lastKeep = aid; // keep that assistant message as old version
        targetGroupId = _messages[aid].groupId ?? _messages[aid].id;
        int maxVer = -1;
        for (final m in _messages) {
          final gid = (m.groupId ?? m.id);
          if (gid == targetGroupId) {
            if (m.version > maxVer) maxVer = m.version;
          }
        }
        nextVersion = maxVer + 1;
      } else {
        // No assistant reply yet; keep up to the first user message occurrence and start new group
        lastKeep = userFirst;
        targetGroupId = null; // will be set to new id automatically
        nextVersion = 0;
      }
    }

    // Remove messages after lastKeep (persistently), but preserve:
    // - all versions of groups that already appeared up to lastKeep (e.g., edited user messages), and
    // - all versions of the target assistant group we are regenerating
    if (lastKeep < _messages.length - 1) {
      // Collect groups that appear at or before lastKeep
      final keepGroups = <String>{};
      for (int i = 0; i <= lastKeep && i < _messages.length; i++) {
        final g = (_messages[i].groupId ?? _messages[i].id);
        keepGroups.add(g);
      }
      if (targetGroupId != null) keepGroups.add(targetGroupId!);

      final trailing = _messages.sublist(lastKeep + 1);
      final removeIds = <String>[];
      for (final m in trailing) {
        final gid = (m.groupId ?? m.id);
        final shouldKeep = keepGroups.contains(gid);
        if (!shouldKeep) removeIds.add(m.id);
      }
      for (final id in removeIds) {
        try { await _chatService.deleteMessage(id); } catch (_) {}
        _reasoning.remove(id);
        _translations.remove(id);
        _toolParts.remove(id);
        _reasoningSegments.remove(id);
      }
      if (removeIds.isNotEmpty) {
        setState(() {
          _messages.removeWhere((m) => removeIds.contains(m.id));
        });
      }
    }

    // Start a new assistant generation from current context
    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    
    // Use assistant's model if set, otherwise fall back to global default
    final providerKey = assistant?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = assistant?.chatModelId ?? settings.currentModelId;

    if (providerKey == null || modelId == null) {
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.homePagePleaseSelectModel,
        type: NotificationType.warning,
      );
      return;
    }

    // Create assistant message placeholder (new version in target group)
    final assistantMessage = await _chatService.addMessage(
      conversationId: _currentConversation!.id,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
      groupId: targetGroupId,
      version: nextVersion,
    );

    // Persist selection to the latest version of this group
    final gid = assistantMessage.groupId ?? assistantMessage.id;
    _versionSelections[gid] = assistantMessage.version;
    await _chatService.setSelectedVersion(_currentConversation!.id, gid, assistantMessage.version);

    setState(() {
      _messages.add(assistantMessage);
    });
    _setConversationLoading(_currentConversation!.id, true);

    // Haptics on regenerate
    try {
      if (context.read<SettingsProvider>().hapticsOnGenerate) {
        Haptics.light();
      }
    } catch (_) {}

    // Initialize reasoning state only when enabled and model supports it
    // Use conversation-level thinkingBudget (what user adjusts in UI) for consistency
    final effectiveThinkingBudget = _currentConversation?.thinkingBudget ?? settings.thinkingBudget;
    final supportsReasoning = _isReasoningModel(providerKey, modelId);
    final enableReasoning = supportsReasoning && ReasoningStateManager.isReasoningEnabled(effectiveThinkingBudget);
    if (enableReasoning) {
      final rd = ReasoningData();
      _reasoning[assistantMessage.id] = rd;
      await _chatService.updateMessage(assistantMessage.id, reasoningStartAt: DateTime.now());
    }

    // Build API messages from current context (apply truncate + collapse versions)
    final tIndex = _currentConversation?.truncateIndex ?? -1;
    final apiMessages = ChatMessageHandler.prepareBaseApiMessages(
      messages: _messages,
      truncateIndex: tIndex,
      versionSelections: _versionSelections,
    );

    // Inject system prompt
    if ((assistant?.systemPrompt.trim().isNotEmpty ?? false)) {
      final vars = PromptTransformer.buildPlaceholders(
        context: context,
        assistant: assistant!,
        modelId: modelId,
        modelName: modelId,
        userNickname: context.read<UserProvider>().name,
      );
      final sys = PromptTransformer.replacePlaceholders(assistant.systemPrompt, vars);
      apiMessages.insert(0, {'role': 'system', 'content': sys});
    }
    // Inject Memories + Recent Chats
    try {
      if (assistant?.enableMemory == true) {
        final mp = context.read<MemoryProvider>();
        final mems = mp.getForAssistant(assistant!.id);
        final memPrompt = ChatMessageHandler.buildMemoriesPrompt(mems);
        if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
          apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + memPrompt;
        } else {
          apiMessages.insert(0, {'role': 'system', 'content': memPrompt});
        }
      }
      if (assistant?.enableRecentChatsReference == true) {
        final chats = context.read<ChatService>().getAllConversations();
        // Exclude current conversation to avoid self-reference, include summary
        final relevantChats = chats
            .where((c) => c.assistantId == assistant!.id && c.id != _currentConversation?.id)
            .where((c) => c.title.trim().isNotEmpty)
            .take(10)
            .map((c) => <String, String>{
                  'timestamp': c.updatedAt.toIso8601String().substring(0, 10),
                  'title': c.title.trim(),
                  'summary': (c.summary ?? '').trim(),
                })
            .toList();
        if (relevantChats.isNotEmpty) {
          final recentPrompt = ChatMessageHandler.buildRecentChatsPromptWithSummary(relevantChats);
          if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
            apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + recentPrompt;
          } else {
            apiMessages.insert(0, {'role': 'system', 'content': recentPrompt});
          }
        }
      }
    } catch (_) {}
    // Inject search tool usage guide when enabled
    if (settings.searchEnabled) {
      final prompt = SearchToolService.getSystemPrompt();
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + prompt;
      } else {
        apiMessages.insert(0, {'role': 'system', 'content': prompt});
      }
    }
    // Inject sticker tool usage guide when enabled
    if (settings.stickerEnabled) {
      final prompt = StickerToolService.getSystemPrompt(frequency: settings.stickerFrequency);
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + prompt;
      } else {
        apiMessages.insert(0, {'role': 'system', 'content': prompt});
      }
    }
    // Inject learning mode prompt when enabled (global)
    try {
      final lmEnabled = await LearningModeStore.isEnabled();
      if (lmEnabled) {
        final lp = await LearningModeStore.getPrompt();
        if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
          apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + lp;
        } else {
          apiMessages.insert(0, {'role': 'system', 'content': lp});
        }
      }
    } catch (_) {}

    // Limit context length
    if (assistant?.limitContextMessages ?? true) {
      final keep = (assistant?.contextMessageSize ?? 64).clamp(0, 512);
      int startIdx = 0;
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        startIdx = 1;
      }
      final tail = apiMessages.sublist(startIdx);
      if (keep == 0) {
        // contextMessageSize=0: clear all history
        apiMessages.removeRange(startIdx, apiMessages.length);
      } else if (tail.length > keep) {
        final trimmed = tail.sublist(tail.length - keep);
        apiMessages..removeRange(startIdx, apiMessages.length)..addAll(trimmed);
      }
    }

    // Convert any local Markdown image links to inline base64 for model context
    for (int i = 0; i < apiMessages.length; i++) {
      final s = (apiMessages[i]['content'] ?? '').toString();
      if (s.isNotEmpty) {
        apiMessages[i]['content'] = await MarkdownMediaSanitizer.inlineLocalImagesToBase64(s);
      }
    }

    // Prepare tools (Memory + Search + MCP)
    final List<Map<String, dynamic>> toolDefs = <Map<String, dynamic>>[];
    Future<String> Function(String, Map<String, dynamic>)? onToolCall;
    try {
      if (assistant?.enableMemory == true && _isToolModel(providerKey, modelId)) {
        toolDefs.addAll([
          {
            'type': 'function',
            'function': {
              'name': 'create_memory',
              'description': 'create a memory record',
              'parameters': {
                'type': 'object',
                'properties': {
                  'content': {'type': 'string', 'description': 'The content of the memory record'}
                },
                'required': ['content']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'edit_memory',
              'description': 'update a memory record',
              'parameters': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'integer', 'description': 'The id of the memory record'},
                  'content': {'type': 'string', 'description': 'The content of the memory record'}
                },
                'required': ['id', 'content']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'delete_memory',
              'description': 'delete a memory record',
              'parameters': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'integer', 'description': 'The id of the memory record'}
                },
                'required': ['id']
              }
            }
          },
        ]);
      }
      if (settings.searchEnabled) {
        toolDefs.add(SearchToolService.getToolDefinition());
      }
      if (settings.stickerEnabled) {
        toolDefs.add(StickerToolService.getToolDefinition());
      }
      final mcp = context.read<McpProvider>();
      final toolSvc = context.read<McpToolService>();
      final tools = toolSvc.listAvailableToolsForAssistant(mcp, context.read<AssistantProvider>(), assistant?.id);
      final supportsTools = _isToolModel(providerKey, modelId);
      if (supportsTools && tools.isNotEmpty) {
        final providerCfg = settings.getProviderConfig(providerKey);
        final providerKind = ProviderConfig.classify(providerCfg.id, explicitType: providerCfg.providerType);
        toolDefs.addAll(tools.map((t) => ChatMessageHandler.buildMcpToolDefinition(t, providerKind)));
      }
      if (toolDefs.isNotEmpty) {
        onToolCall = (name, args) async {
          if (name == SearchToolService.toolName && settings.searchEnabled) {
            final q = (args['query'] ?? '').toString();
            return await SearchToolService.executeSearch(q, settings);
          }
          // Sticker tool
          if (name == StickerToolService.toolName && settings.stickerEnabled) {
            final stickerId = (args['sticker_id'] as num?)?.toInt() ?? 0;
            return await StickerToolService.getSticker(stickerId);
          }
          // Memory tools
          if (assistant?.enableMemory == true) {
            try {
              final mp = context.read<MemoryProvider>();
              if (name == 'create_memory') {
                final content = (args['content'] ?? '').toString();
                if (content.isEmpty) return '';
                final m = await mp.add(assistantId: assistant!.id, content: content);
                return m.content;
              } else if (name == 'edit_memory') {
                final id = (args['id'] as num?)?.toInt() ?? -1;
                final content = (args['content'] ?? '').toString();
                if (id <= 0 || content.isEmpty) return '';
                final m = await mp.update(id: id, content: content);
                return m?.content ?? '';
              } else if (name == 'delete_memory') {
                final id = (args['id'] as num?)?.toInt() ?? -1;
                if (id <= 0) return '';
                final ok = await mp.delete(id: id);
                return ok ? 'deleted' : '';
              }
            } catch (_) {}
          }
          final text = await toolSvc.callToolTextForAssistant(
            mcp,
            context.read<AssistantProvider>(),
            assistantId: assistant?.id,
            toolName: name,
            arguments: args,
          );
          return text;
        };
      }
    } catch (_) {}

    // Build assistant-level custom request overrides
    final aOverrides = ChatMessageHandler.buildAssistantOverrides(assistant);
    final aHeaders = aOverrides.headers;
    final aBody = aOverrides.body;

    await _prepareGeminiThoughtSignaturesForApiMessages(
      apiMessages: apiMessages,
      providerKey: providerKey,
      modelId: modelId,
    );

    final stream = ChatApiService.sendMessageStream(
      config: settings.getProviderConfig(providerKey),
      modelId: modelId,
      messages: apiMessages,
      thinkingBudget: _currentConversation?.thinkingBudget ?? settings.thinkingBudget,
      temperature: assistant?.temperature,
      topP: assistant?.topP,
      maxTokens: assistant?.maxTokens,
      maxToolLoopIterations: assistant?.maxToolLoopIterations ?? 10,
      tools: toolDefs.isEmpty ? null : toolDefs,
      onToolCall: onToolCall,
      extraHeaders: aHeaders,
      extraBody: aBody,
      toolCallMode: _toolCallMode,
    );

    // Timing tracking
    final startTime = DateTime.now();
    final bool streamOutput = assistant?.streamOutput ?? true;

    // 创建 StreamContext
    final ctx = _createStreamContext(
      assistantMessage: assistantMessage,
      startTime: startTime,
      streamOutput: streamOutput,
      supportsReasoning: supportsReasoning,
    );

    // 定义 finish 函数（使用 ctx 中的数据）
    Future<void> finish() async {
      final processedContent = await MarkdownMediaSanitizer.replaceInlineBase64Images(ctx.fullContent);
      final effectiveUsage = ChatMessageHandler.estimateOrFixTokenUsage(
        usage: ctx.usage,
        apiMessages: apiMessages,
        processedContent: processedContent,
      );

      String? tokenUsageJson;
      if (effectiveUsage != null) {
        final Map<String, dynamic> tokenUsageMap = {
          'promptTokens': effectiveUsage.promptTokens,
          'completionTokens': effectiveUsage.completionTokens,
          'cachedTokens': effectiveUsage.cachedTokens,
          'thoughtTokens': effectiveUsage.thoughtTokens,
          'totalTokens': effectiveUsage.totalTokens,
          if (effectiveUsage.rounds != null) 'rounds': effectiveUsage.rounds,
        };

        final now = DateTime.now();
        final firstToken = ctx.firstTokenTime;
        if (firstToken != null) {
          final timeFirstTokenMs = firstToken.difference(startTime).inMilliseconds;
          final timeCompletionMs = now.difference(firstToken).inMilliseconds;
          final safeCompletionMs = timeCompletionMs > 0 ? timeCompletionMs : 1;
          final tokenSpeed = effectiveUsage.completionTokens / (safeCompletionMs / 1000.0);
          tokenUsageMap['time_first_token_millsec'] = timeFirstTokenMs;
          tokenUsageMap['time_completion_millsec'] = timeCompletionMs;
          tokenUsageMap['token_speed'] = double.parse(tokenSpeed.toStringAsFixed(1));
        } else {
          final totalMs = now.difference(startTime).inMilliseconds;
          if (totalMs > 0 && effectiveUsage.completionTokens > 0) {
            final estimatedFirstTokenMs = (totalMs * 0.1).round();
            final estimatedCompletionMs = (totalMs * 0.9).round();
            final safeCompletionMs = estimatedCompletionMs > 0 ? estimatedCompletionMs : 1;
            final tokenSpeed = effectiveUsage.completionTokens / (safeCompletionMs / 1000.0);
            tokenUsageMap['time_first_token_millsec'] = estimatedFirstTokenMs;
            tokenUsageMap['time_completion_millsec'] = estimatedCompletionMs;
            tokenUsageMap['token_speed'] = double.parse(tokenSpeed.toStringAsFixed(1));
          }
        }
        tokenUsageJson = jsonEncode(tokenUsageMap);
      }

      await _chatService.updateMessage(
        assistantMessage.id,
        content: processedContent,
        totalTokens: null,
        tokenUsageJson: tokenUsageJson,
        isStreaming: false,
      );
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: processedContent,
            totalTokens: null,
            tokenUsageJson: tokenUsageJson,
            isStreaming: false,
          );
        }
      });
      _setConversationLoading(assistantMessage.conversationId, false);

      final r = _reasoning[assistantMessage.id];
      if (r != null && r.finishedAt == null) {
        r.finishedAt = DateTime.now();
        await _chatService.updateMessage(assistantMessage.id, reasoningText: r.text, reasoningFinishedAt: r.finishedAt);
      }
      final segments = _reasoningSegments[assistantMessage.id];
      if (segments != null && segments.isNotEmpty && segments.last.finishedAt == null) {
        segments.last.finishedAt = DateTime.now();
        if (ctx.autoCollapseThinking) segments.last.expanded = false;
        _reasoningSegments[assistantMessage.id] = segments;
        if (mounted) setState(() {});
        await _chatService.updateMessage(assistantMessage.id, reasoningSegmentsJson: ReasoningStateManager.serializeSegments(segments));
      }
      _cleanupStreamingUiForMessage(assistantMessage.id);
    }

    final String _cid = assistantMessage.conversationId;
    await _conversationStreams[_cid]?.cancel();

    // 使用统一的流监听器
    final _sub2 = _setupStreamListener(
      stream: stream,
      ctx: ctx,
      finish: finish,
      enableInlineThink: false, // regenerate 不需要 inline think 处理
      onError: (e) async {
        final errText = '${AppLocalizations.of(context)!.generationInterrupted}: $e';
        final displayContent = ChatStreamHandler.buildErrorDisplayContent(ctx.fullContent, errText);
        final tokenUsageJson = ctx.usage != null ? jsonEncode({
          'promptTokens': ctx.usage!.promptTokens,
          'completionTokens': ctx.usage!.completionTokens,
          'cachedTokens': ctx.usage!.cachedTokens,
          'thoughtTokens': ctx.usage!.thoughtTokens,
          'totalTokens': ctx.usage!.totalTokens,
          if (ctx.usage!.rounds != null) 'rounds': ctx.usage!.rounds,
        }) : null;

        await _chatService.updateMessage(
          assistantMessage.id,
          content: displayContent,
          totalTokens: null,
          tokenUsageJson: tokenUsageJson,
          isStreaming: false,
        );

        if (mounted) {
          setState(() {
            final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(
                content: displayContent,
                isStreaming: false,
                totalTokens: null,
                tokenUsageJson: tokenUsageJson,
              );
            }
          });
        }
        _cleanupStreamingUiForMessage(assistantMessage.id);
        _setConversationLoading(assistantMessage.conversationId, false);
        await ChatStreamHandler.finishReasoningOnError(ctx);
        await _conversationStreams.remove(_cid)?.cancel();
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: errText,
          type: NotificationType.error,
        );
      },
      onDone: () async {
        await _conversationStreams.remove(_cid)?.cancel();
      },
    );
    _conversationStreams[_cid] = _sub2;
  }

  Future<void> _maybeGenerateTitle({bool force = false}) async {
    final convo = _currentConversation;
    if (convo == null) return;
    await _maybeGenerateTitleFor(convo.id, force: force);
  }

  Future<void> _maybeGenerateTitleFor(String conversationId, {bool force = false}) async {
    final convo = _chatService.getConversation(conversationId);
    if (convo == null) return;
    if (!force && convo.title.isNotEmpty && convo.title != _titleForLocale(context)) return;

    final settings = context.read<SettingsProvider>();
    final assistantProvider = context.read<AssistantProvider>();

    // Get assistant for this conversation
    final assistant = convo.assistantId != null
        ? assistantProvider.getById(convo.assistantId!)
        : assistantProvider.currentAssistant;

    // Decide model: prefer title model, else fall back to assistant's model, then to global default
    final provKey = settings.titleModelProvider
        ?? assistant?.chatModelProvider
        ?? settings.currentModelProvider;
    final mdlId = settings.titleModelId
        ?? assistant?.chatModelId
        ?? settings.currentModelId;
    if (provKey == null || mdlId == null) return;
    final cfg = settings.getProviderConfig(provKey);

    // Build content from messages - take last 4 messages (approximately 2 rounds)
    final msgs = _chatService.getMessages(convo.id);
    final tIndex = convo.truncateIndex;
    final List<ChatMessage> sourceAll = (tIndex >= 0 && tIndex <= msgs.length) ? msgs.sublist(tIndex) : msgs;
    final List<ChatMessage> source = _collapseVersions(sourceAll);
    // Take last 4 messages for title generation, no character limit
    final recentMsgs = source.length > 4 ? source.sublist(source.length - 4) : source;
    final joined = recentMsgs
        .where((m) => m.content.isNotEmpty)
        .map((m) => '${m.role == 'assistant' ? 'Assistant' : 'User'}: ${m.content}')
        .join('\n\n');
    final content = joined;
    final locale = Localizations.localeOf(context).toLanguageTag();

    String prompt = settings.titlePrompt
        .replaceAll('{locale}', locale)
        .replaceAll('{content}', content);

    final l10n = AppLocalizations.of(context)!;
    try {
      final title = (await ChatApiService.generateText(config: cfg, modelId: mdlId, prompt: prompt)).trim();
      if (title.isNotEmpty) {
        await _chatService.renameConversation(convo.id, title);
        if (mounted && _currentConversation?.id == convo.id) {
          setState(() {
            _currentConversation = _chatService.getConversation(convo.id);
          });
        }
        if (mounted) {
          showAppSnackBar(context, message: l10n.titleGenerationSuccess(title), type: NotificationType.success);
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, message: l10n.titleGenerationFailed(e.toString()), type: NotificationType.error);
      }
    }
  }

  /// Automatically generate a summary for the conversation if conditions are met.
  /// Only generates every 5 new messages and only if recent chats reference is enabled.
  Future<void> _maybeGenerateSummaryFor(String conversationId) async {
    final convo = _chatService.getConversation(conversationId);
    if (convo == null) return;

    final msgCount = convo.messageIds.length;
    // Only generate summary every 5 new messages
    if (msgCount == 0 || msgCount - convo.lastSummarizedMessageCount < 5) return;

    final settings = context.read<SettingsProvider>();
    final assistantProvider = context.read<AssistantProvider>();

    // Get assistant for this conversation
    final assistant = convo.assistantId != null
        ? assistantProvider.getById(convo.assistantId!)
        : assistantProvider.currentAssistant;

    // Only generate summary if assistant has recent chats reference enabled
    if (assistant?.enableRecentChatsReference != true) return;

    // Use summary model if configured, else fall back to title model, then current model
    final provKey = settings.summaryModelProvider ??
        settings.titleModelProvider ??
        assistant?.chatModelProvider ??
        settings.currentModelProvider;
    final mdlId = settings.summaryModelId ??
        settings.titleModelId ??
        assistant?.chatModelId ??
        settings.currentModelId;
    if (provKey == null || mdlId == null) return;

    final cfg = settings.getProviderConfig(provKey);

    // Get all messages and filter user messages
    final msgs = _chatService.getMessages(convo.id);
    final allUserMsgs = msgs
        .where((m) => m.role == 'user' && m.content.trim().isNotEmpty)
        .toList();

    if (allUserMsgs.isEmpty) return;

    // Get previous summary (empty string if first time)
    final previousSummary = (convo.summary ?? '').trim();

    // Get only the recent user messages since last summarization
    final lastSummarizedMsgCount = (convo.lastSummarizedMessageCount < 0) ? 0 : convo.lastSummarizedMessageCount;
    final msgsAtLastSummary = msgs.take(lastSummarizedMsgCount).toList();
    final userMsgsAtLastSummary = msgsAtLastSummary
        .where((m) => m.role == 'user' && m.content.trim().isNotEmpty)
        .length;

    // Get new user messages since last summary
    final newUserMsgs = allUserMsgs.skip(userMsgsAtLastSummary).toList();
    if (newUserMsgs.isEmpty) return;

    final recentMessages = newUserMsgs
        .map((m) => m.content.trim())
        .join('\n\n');

    // Truncate if too long
    final content =
        recentMessages.length > 2000 ? recentMessages.substring(0, 2000) : recentMessages;

    final prompt = settings.summaryPrompt
        .replaceAll('{previous_summary}', previousSummary)
        .replaceAll('{user_messages}', content);

    try {
      final summary =
          (await ChatApiService.generateText(config: cfg, modelId: mdlId, prompt: prompt))
              .trim();

      if (summary.isNotEmpty) {
        await _chatService.updateConversationSummary(convo.id, summary, msgCount);
        if (mounted && _currentConversation?.id == convo.id) {
          setState(() {
            _currentConversation = _chatService.getConversation(convo.id);
          });
        }
      }
    } catch (_) {
      // Keep old summary on failure, ignore silently
    }
  }

  Future<void> _renameCurrentConversation() async {
    if (_currentConversation == null) return;

    final controller = TextEditingController(text: _currentConversation!.title);
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.sideDrawerMenuRename),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.sideDrawerRenameHint),
            onSubmitted: (_) => Navigator.of(ctx).pop(true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.sideDrawerCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.sideDrawerOK),
            ),
          ],
        );
      },
    );
    if (ok == true && mounted) {
      final newTitle = controller.text.trim();
      if (newTitle.isNotEmpty) {
        await _chatService.renameConversation(_currentConversation!.id, newTitle);
        setState(() {
          _currentConversation = _chatService.getConversation(_currentConversation!.id);
        });
      }
    }
    controller.dispose();
  }

  void _scrollToBottom() {
    try {
      if (!_scrollController.hasClients) return;
      
      // Prevent using controller while it is still attached to old/new list simultaneously
      if (_scrollController.positions.length != 1) {
        // Try again after microtask when the previous list detaches
        Future.microtask(_scrollToBottom);
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(max);
      if (_showJumpToBottom) {
        setState(() => _showJumpToBottom = false);
      }
    } catch (_) {
      // Ignore transient attachment errors
    }
  }

  void _forceScrollToBottom() {
    // Force scroll to bottom when user explicitly clicks the button
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
    _lastJumpUserMessageId = null;
    _scrollToBottom();
  }

  // Force scroll after rebuilds when switching topics/conversations
  void _forceScrollToBottomSoon() {
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    Future.delayed(_postSwitchScrollDelay, _scrollToBottom);
  }

  void _measureInputBar() {
    try {
      final ctx = _inputBarKey.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final h = box.size.height;
      if ((_inputBarHeight - h).abs() > 1.0) {
        setState(() => _inputBarHeight = h);
      }
    } catch (_) {}
  }

  // Ensure scroll reaches bottom even after widget tree transitions
  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    Future.delayed(const Duration(milliseconds: 120), _scrollToBottom);
  }

  Future<void> _showQuickPhraseMenu() async {
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final quickPhraseProvider = context.read<QuickPhraseProvider>();
    final globalPhrases = quickPhraseProvider.globalPhrases;
    final assistantPhrases = assistant != null
        ? quickPhraseProvider.getForAssistant(assistant.id)
        : <QuickPhrase>[];

    final allAvailable = [...globalPhrases, ...assistantPhrases];

    // Dismiss keyboard before showing menu to prevent flickering
    _dismissKeyboard();

    final QuickPhrase? selected;

    // Desktop: use popover; Mobile: use bottom menu
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    if (isDesktop) {
      selected = await showDesktopQuickPhrasePopover(
        context,
        anchorKey: _inputBarKey,
        phrases: allAvailable,
      );
    } else {
      // Get input bar height for positioning menu above it
      final RenderBox? inputBox = _inputBarKey.currentContext?.findRenderObject() as RenderBox?;
      if (inputBox == null) return;

      final inputBarHeight = inputBox.size.height;
      final topLeft = inputBox.localToGlobal(Offset.zero);
      final position = Offset(topLeft.dx, inputBarHeight);

      selected = await showQuickPhraseMenu(
        context: context,
        phrases: allAvailable,
        position: position,
      );
    }

    if (selected != null && mounted) {
      // Insert content at cursor position
      final text = _inputController.text;
      final selection = _inputController.selection;
      final start = (selection.start >= 0 && selection.start <= text.length) 
          ? selection.start 
          : text.length;
      final end = (selection.end >= 0 && selection.end <= text.length && selection.end >= start) 
          ? selection.end 
          : start;
      
      final newText = text.replaceRange(start, end, selected.content);
      _inputController.value = _inputController.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + selected.content.length),
        composing: TextRange.empty,
      );
      
      setState(() {});
      
      // Don't auto-refocus to prevent keyboard flickering on Android
      // User can tap input field if they want to continue typing
    }
  }

  // Scroll to a specific message id (from mini map selection)
  Future<void> _scrollToMessageId(String targetId) async {
    try {
      if (!mounted || !_scrollController.hasClients) return;
      final messages = _collapseVersions(_messages);
      final tIndex = messages.indexWhere((m) => m.id == targetId);
      if (tIndex < 0) return;

      // Try direct ensureVisible first
      final tKey = _messageKeys[targetId];
      final tCtx = tKey?.currentContext;
      if (tCtx != null) {
        await Scrollable.ensureVisible(
          tCtx,
          alignment: 0.1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        _lastJumpUserMessageId = targetId; // allow chaining with prev-question
        return;
      }

      // Coarse jump based on index ratio to bring target into build range
      final pos0 = _scrollController.position;
      final denom = (messages.length - 1).clamp(1, 1 << 30);
      final ratio = tIndex / denom;
      final coarse = (pos0.maxScrollExtent * ratio).clamp(0.0, pos0.maxScrollExtent);
      _scrollController.jumpTo(coarse);
      await WidgetsBinding.instance.endOfFrame;
      final tCtxAfterCoarse = _messageKeys[targetId]?.currentContext;
      if (tCtxAfterCoarse != null) {
        await Scrollable.ensureVisible(tCtxAfterCoarse, alignment: 0.1, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
        _lastJumpUserMessageId = targetId;
        return;
      }

      // Determine direction using visible anchor indices
      final media = MediaQuery.of(context);
      final double listTop = kToolbarHeight + media.padding.top;
      final double listBottom = media.size.height - media.padding.bottom - _inputBarHeight - 8;
      int? firstVisibleIdx;
      int? lastVisibleIdx;
      for (int i = 0; i < messages.length; i++) {
        final key = _messageKeys[messages[i].id];
        final ctx = key?.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        final bottom = top + box.size.height;
        final visible = bottom > listTop && top < listBottom;
        if (visible) {
          firstVisibleIdx ??= i;
          lastVisibleIdx = i;
        }
      }
      final anchor = lastVisibleIdx ?? firstVisibleIdx ?? 0;
      final dirDown = tIndex > anchor; // target below

      // Page in steps until the target builds, then ensureVisible
      const int maxAttempts = 40;
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        final ctx2 = _messageKeys[targetId]?.currentContext;
        if (ctx2 != null) {
          await Scrollable.ensureVisible(
            ctx2,
            alignment: 0.1,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
          );
          _lastJumpUserMessageId = targetId;
          return;
        }
        final pos = _scrollController.position;
        final viewH = media.size.height;
        final step = viewH * 0.85 * (dirDown ? 1 : -1);
        double newOffset = pos.pixels + step;
        if (newOffset < 0) newOffset = 0;
        if (newOffset > pos.maxScrollExtent) newOffset = pos.maxScrollExtent;
        if ((newOffset - pos.pixels).abs() < 1) break;
        _scrollController.jumpTo(newOffset);
        await WidgetsBinding.instance.endOfFrame;
      }
    } catch (_) {}
  }

  // Jump to the previous user message (question) above the current viewport
  Future<void> _jumpToPreviousQuestion() async {
    try {
      if (!mounted || !_scrollController.hasClients) return;
      final messages = _collapseVersions(_messages);
      if (messages.isEmpty) return;
      // Build an id->index map for quick lookup
      final Map<String, int> idxById = <String, int>{};
      for (int i = 0; i < messages.length; i++) { idxById[messages[i].id] = i; }

      // Determine anchor index: prefer last jumped user; otherwise bottom-most visible item
      int? anchor;
      if (_lastJumpUserMessageId != null && idxById.containsKey(_lastJumpUserMessageId)) {
        anchor = idxById[_lastJumpUserMessageId!];
      } else {
        final media = MediaQuery.of(context);
        final double listTop = kToolbarHeight + media.padding.top;
        final double listBottom = media.size.height - media.padding.bottom - _inputBarHeight - 8;
        int? firstVisibleIdx;
        int? lastVisibleIdx;
        for (int i = 0; i < messages.length; i++) {
          final key = _messageKeys[messages[i].id];
          final ctx = key?.currentContext;
          if (ctx == null) continue;
          final box = ctx.findRenderObject() as RenderBox?;
          if (box == null || !box.attached) continue;
          final top = box.localToGlobal(Offset.zero).dy;
          final bottom = top + box.size.height;
          final visible = bottom > listTop && top < listBottom;
          if (visible) {
            firstVisibleIdx ??= i;
            lastVisibleIdx = i;
          }
        }
        anchor = lastVisibleIdx ?? firstVisibleIdx ?? (messages.length - 1);
      }
      // Search backward for previous user message from the anchor index
      int target = -1;
      for (int i = (anchor ?? 0) - 1; i >= 0; i--) {
        if (messages[i].role == 'user') { target = i; break; }
      }
      if (target < 0) {
        // No earlier user message; jump to top instantly
        _scrollController.jumpTo(0.0);
        _lastJumpUserMessageId = null;
        return;
      }
      // If target widget is not built yet (off-screen far above), page up until it is
      const int maxAttempts = 12; // about 10 pages max
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        final tKey = _messageKeys[messages[target].id];
        final tCtx = tKey?.currentContext;
        if (tCtx != null) {
          await Scrollable.ensureVisible(
            tCtx,
            alignment: 0.08,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
          );
          _lastJumpUserMessageId = messages[target].id;
          return;
        }
        // Step up by ~85% of viewport height
        final pos = _scrollController.position;
        final viewH = MediaQuery.of(context).size.height;
        final step = viewH * 0.85;
        final newOffset = (pos.pixels - step) < 0 ? 0.0 : (pos.pixels - step);
        if ((pos.pixels - newOffset).abs() < 1) break; // reached top
        _scrollController.jumpTo(newOffset);
        // Let the list build newly visible children
        await WidgetsBinding.instance.endOfFrame;
      }
      // Final fallback: go to top if still not found
      _scrollController.jumpTo(0.0);
      _lastJumpUserMessageId = null;
    } catch (_) {}
  }

  // Jump to the next user message (question) below the current viewport
  Future<void> _jumpToNextQuestion() async {
    try {
      if (!mounted || !_scrollController.hasClients) return;
      final messages = _collapseVersions(_messages);
      if (messages.isEmpty) return;

      // Build an id->index map for quick lookup
      final Map<String, int> idxById = <String, int>{};
      for (int i = 0; i < messages.length; i++) {
        idxById[messages[i].id] = i;
      }

      // Determine anchor index: prefer last jumped user; otherwise top-most visible item
      int? anchor;
      if (_lastJumpUserMessageId != null && idxById.containsKey(_lastJumpUserMessageId)) {
        anchor = idxById[_lastJumpUserMessageId!];
      } else {
        final media = MediaQuery.of(context);
        final double listTop = kToolbarHeight + media.padding.top;
        final double listBottom = media.size.height - media.padding.bottom - _inputBarHeight - 8;
        int? firstVisibleIdx;
        for (int i = 0; i < messages.length; i++) {
          final key = _messageKeys[messages[i].id];
          final ctx = key?.currentContext;
          if (ctx == null) continue;
          final box = ctx.findRenderObject() as RenderBox?;
          if (box == null || !box.attached) continue;
          final top = box.localToGlobal(Offset.zero).dy;
          final bottom = top + box.size.height;
          final visible = bottom > listTop && top < listBottom;
          if (visible) {
            firstVisibleIdx ??= i;
          }
        }
        anchor = firstVisibleIdx ?? 0;
      }

      // Search forward for next user message from the anchor index
      int target = -1;
      for (int i = (anchor ?? 0) + 1; i < messages.length; i++) {
        if (messages[i].role == 'user') {
          target = i;
          break;
        }
      }
      if (target < 0) {
        // No later user message; jump to bottom instantly
        _scrollToBottom();
        _lastJumpUserMessageId = null;
        return;
      }

      // If target widget is not built yet (off-screen far below), page down until it is
      const int maxAttempts = 12;
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        final tKey = _messageKeys[messages[target].id];
        final tCtx = tKey?.currentContext;
        if (tCtx != null) {
          await Scrollable.ensureVisible(
            tCtx,
            alignment: 0.08,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
          );
          _lastJumpUserMessageId = messages[target].id;
          return;
        }
        // Step down by ~85% of viewport height
        final pos = _scrollController.position;
        final viewH = MediaQuery.of(context).size.height;
        final step = viewH * 0.85;
        final newOffset = (pos.pixels + step) > pos.maxScrollExtent
            ? pos.maxScrollExtent
            : (pos.pixels + step);
        if ((newOffset - pos.pixels).abs() < 1) break; // reached bottom
        _scrollController.jumpTo(newOffset);
        // Let the list build newly visible children
        await WidgetsBinding.instance.endOfFrame;
      }
      // Final fallback: go to bottom if still not found
      _scrollToBottom();
      _lastJumpUserMessageId = null;
    } catch (_) {}
  }

  // Scroll to the very top of the message list
  void _scrollToTop() {
    try {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      _lastJumpUserMessageId = null;
    } catch (_) {}
  }

  // Translate message functionality
  Future<void> _translateMessage(ChatMessage message) async {
    final l10n = AppLocalizations.of(context)!;
    // Show language selector
    final language = await showLanguageSelector(context);
    if (language == null) return;

    // Check if clear translation is selected
    if (language.code == '__clear__') {
      // Clear the translation (use empty string so UI hides immediately)
      final updatedMessage = message.copyWith(translation: '');
      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index != -1) {
          _messages[index] = updatedMessage;
        }
        // Remove translation state
        _translations.remove(message.id);
      });
      await _chatService.updateMessage(message.id, translation: '');
      return;
    }

    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;

    // Check if translation model is set, fallback to assistant's model, then to global default
    final translateProvider = settings.translateModelProvider
        ?? assistant?.chatModelProvider
        ?? settings.currentModelProvider;
    final translateModelId = settings.translateModelId
        ?? assistant?.chatModelId
        ?? settings.currentModelId;

    if (translateProvider == null || translateModelId == null) {
      showAppSnackBar(
        context,
        message: l10n.homePagePleaseSetupTranslateModel,
        type: NotificationType.warning,
      );
      return;
    }

    // Extract text content from message (removing reasoning text if present)
    String textToTranslate = message.content;

    // Set loading state and initialize translation data
    final loadingMessage = message.copyWith(translation: l10n.homePageTranslating);
    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages[index] = loadingMessage;
      }
      // Initialize translation state with expanded
      _translations[message.id] = TranslationUiState();
    });

    try {
      // Get translation prompt with placeholders replaced
      String prompt = settings.translatePrompt
          .replaceAll('{source_text}', textToTranslate)
          .replaceAll('{target_lang}', language.displayName);

      // Create translation request
      final provider = settings.getProviderConfig(translateProvider);

      final translationStream = ChatApiService.sendMessageStream(
        config: provider,
        modelId: translateModelId,
        messages: [
          {'role': 'user', 'content': prompt}
        ],
      );

      final buffer = StringBuffer();

      await for (final chunk in translationStream) {
        buffer.write(chunk.content);

        // Update translation in real-time
        final updatingMessage = message.copyWith(translation: buffer.toString());
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = updatingMessage;
          }
        });
      }

      // Save final translation
      await _chatService.updateMessage(message.id, translation: buffer.toString());

    } catch (e) {
      // Clear translation on error (empty to hide immediately)
      final errorMessage = message.copyWith(translation: '');
      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index != -1) {
          _messages[index] = errorMessage;
        }
        // Remove translation state on error
        _translations.remove(message.id);
      });

      await _chatService.updateMessage(message.id, translation: '');

      showAppSnackBar(
        context,
        message: l10n.homePageTranslateFailed(e.toString()),
        type: NotificationType.error,
      );
    }
  }

  /// 构建滚动到底部按钮（平板布局）
  Widget _buildScrollToBottomButton(BuildContext context) {
    final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
    if (!showSetting || _messages.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomOffset = _inputBarHeight + 12;
    return Align(
      alignment: Alignment.bottomRight,
      child: SafeArea(
        top: false,
        bottom: false,
        child: IgnorePointer(
          ignoring: !_showJumpToBottom,
          child: AnimatedScale(
            scale: _showJumpToBottom ? 1.0 : 0.9,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              opacity: _showJumpToBottom ? 1 : 0,
              child: Padding(
                padding: EdgeInsets.only(right: 16, bottom: bottomOffset),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.white.withOpacity(0.07),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.10)
                              : cs.outline.withOpacity(0.20),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _forceScrollToBottom,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Lucide.ChevronDown,
                              size: 18,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建滚动导航按钮面板（平板布局）- 4个按钮
  Widget _buildScrollNavButtons(BuildContext context) {
    final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
    if (!showSetting || _messages.isEmpty) return const SizedBox.shrink();
    return ScrollNavButtonsPanel(
      visible: _showJumpToBottom,
      bottomOffset: _inputBarHeight + 12,
      onScrollToTop: _scrollToTop,
      onPreviousMessage: _jumpToPreviousQuestion,
      onNextMessage: _jumpToNextQuestion,
      onScrollToBottom: _scrollToBottom,
    );
  }

  /// 构建选择工具栏（平板布局）
  Widget _buildSelectionToolbar(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 122),
          child: AnimatedSelectionBar(
            visible: _selecting,
            child: SelectionToolbar(
              onCancel: () {
                setState(() {
                  _selecting = false;
                  _selectedItems.clear();
                });
              },
              onConfirm: () async {
                final convo = _currentConversation;
                if (convo == null) return;
                final collapsed = _collapseVersions(_messages);
                final selected = <ChatMessage>[];
                for (final m in collapsed) {
                  if (_selectedItems.contains(m.id)) selected.add(m);
                }
                if (selected.isEmpty) {
                  final l10n = AppLocalizations.of(context)!;
                  showAppSnackBar(
                    context,
                    message: l10n.homePageSelectMessagesToShare,
                    type: NotificationType.info,
                  );
                  return;
                }
                setState(() { _selecting = false; });
                await showChatExportSheet(context, conversation: convo, selectedMessages: selected);
                if (mounted) setState(() { _selectedItems.clear(); });
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 构建右侧主题侧边栏（桌面平板布局）
  Widget _buildRightTopicsSidebar(BuildContext context) {
    final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    final sp = context.watch<SettingsProvider>();
    final topicsOnRight = sp.desktopTopicPosition == DesktopTopicPosition.right;
    if (!isDesktop || !topicsOnRight) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isDesktop)
          SidebarResizeHandle(
            visible: _rightSidebarOpen,
            onDrag: (dx) {
              setState(() {
                _rightSidebarWidth = (_rightSidebarWidth - dx).clamp(_sidebarMinWidth, _sidebarMaxWidth);
              });
            },
            onDragEnd: () {
              try { context.read<SettingsProvider>().setDesktopRightSidebarWidth(_rightSidebarWidth); } catch (_) {}
            },
          ),
        AnimatedContainer(
          duration: _sidebarAnimDuration,
          curve: _sidebarAnimCurve,
          width: _rightSidebarOpen ? _rightSidebarWidth : 0,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerRight,
              minWidth: 0,
              maxWidth: _rightSidebarWidth,
              child: SizedBox(
                width: _rightSidebarWidth,
                child: SideDrawer(
                  embedded: true,
                  embeddedWidth: _rightSidebarWidth,
                  userName: context.watch<UserProvider>().name,
                  assistantName: (() {
                    final l10n = AppLocalizations.of(context)!;
                    final a = context.watch<AssistantProvider>().currentAssistant;
                    final n = a?.name.trim();
                    return (n == null || n.isEmpty) ? l10n.homePageDefaultAssistant : n;
                  })(),
                  loadingConversationIds: _loadingConversationIds,
                  desktopTopicsOnly: true,
                  onSelectConversation: (id) {
                    _switchConversationAnimated(id);
                  },
                  onNewConversation: () async {
                    await _createNewConversationAnimated();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }



  @override
  Widget build(BuildContext context) {
    // Tablet and larger: fixed side panel + constrained content
    final width = MediaQuery.sizeOf(context).width;
    // Desktop UI initialization
    if (width >= AppBreakpoints.tablet && !_desktopUiInited) {
      _desktopUiInited = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final sp = context.read<SettingsProvider>();
        setState(() {
          _embeddedSidebarWidth = sp.desktopSidebarWidth.clamp(_sidebarMinWidth, _sidebarMaxWidth);
          _tabletSidebarOpen = sp.desktopSidebarOpen;
          _rightSidebarOpen = sp.desktopRightSidebarOpen;
          _rightSidebarWidth = sp.desktopRightSidebarWidth.clamp(_sidebarMinWidth, _sidebarMaxWidth);
        });
      });
    }
    if (width >= AppBreakpoints.tablet) {
      final title = ((_currentConversation?.title ?? '').trim().isNotEmpty)
          ? _currentConversation!.title
          : _titleForLocale(context);
      final cs = Theme.of(context).colorScheme;
      final settings = context.watch<SettingsProvider>();
      final assistant = context.watch<AssistantProvider>().currentAssistant;
      final providerKey = assistant?.chatModelProvider ?? settings.currentModelProvider;
      final modelId = assistant?.chatModelId ?? settings.currentModelId;
      String? providerName;
      String? modelDisplay;
      if (providerKey != null && modelId != null) {
        final cfg = settings.getProviderConfig(providerKey);
        providerName = cfg.name.isNotEmpty ? cfg.name : providerKey;
        final ov = cfg.modelOverrides[modelId] as Map?;
        modelDisplay = (ov != null && (ov['name'] as String?)?.isNotEmpty == true) ? (ov['name'] as String) : modelId;
      }
      return _buildTabletLayout(context, title: title, providerName: providerName, modelDisplay: modelDisplay, cs: cs);
    }

    final title = ((_currentConversation?.title ?? '').trim().isNotEmpty)
        ? _currentConversation!.title
        : _titleForLocale(context);
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final assistant = context.watch<AssistantProvider>().currentAssistant;
    
    // Use assistant's model if set, otherwise fall back to global default
    final providerKey = assistant?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = assistant?.chatModelId ?? settings.currentModelId;
    String? providerName;
    String? modelDisplay;
    if (providerKey != null && modelId != null) {
      final cfg = settings.getProviderConfig(providerKey);
      providerName = cfg.name.isNotEmpty ? cfg.name : providerKey;
      final ov = cfg.modelOverrides[modelId] as Map?;
      modelDisplay = (ov != null && (ov['name'] as String?)?.isNotEmpty == true) ? (ov['name'] as String) : modelId;
    }

    // Chats are seeded via ChatProvider in main.dart

    return InteractiveDrawer(
      controller: _drawerController,
      side: DrawerSide.left,
      drawerWidth: MediaQuery.sizeOf(context).width * 0.75,
      scrimColor: cs.onSurface,
      maxScrimOpacity: 0.12,
      barrierDismissible: true,
      // onScrimTap: () {
      //   // Vibrate when tapping right-side scrim to close
      //   try {
      //     if (context.read<SettingsProvider>().hapticsOnDrawer) {
      //       Haptics.drawerPulse();
      //     }
      //   } catch (_) {}
      // },
      drawer: SideDrawer(
        userName: context.watch<UserProvider>().name,
        assistantName: (() {
          final l10n = AppLocalizations.of(context)!;
          final a = context.watch<AssistantProvider>().currentAssistant;
          final n = a?.name.trim();
          return (n == null || n.isEmpty) ? l10n.homePageDefaultAssistant : n;
        })(),
        loadingConversationIds: _loadingConversationIds,
        onSelectConversation: (id) {
          // Update current selection for highlight in drawer and animate switch
          _switchConversationAnimated(id);
          // // Haptic feedback when closing the sidebar
          // try {
          //   if (context.read<SettingsProvider>().hapticsOnDrawer) {
          //     Haptics.drawerPulse();
          //   }
          // } catch (_) {}
          _drawerController.close();
        },
        onNewConversation: () async {
          await _createNewConversationAnimated();
          // // Haptic feedback when closing the sidebar
          // try {
          //   if (context.read<SettingsProvider>().hapticsOnDrawer) {
          //     Haptics.drawerPulse();
          //   }
          // } catch (_) {}
          _drawerController.close();
        },
      ),
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: true,
        extendBodyBehindAppBar: true,
        appBar: _buildMobileAppBar(
          title: title,
          providerName: providerName,
          modelDisplay: modelDisplay,
          cs: cs,
        ),
      body: Stack(
          children: [
            // Assistant-specific chat background + gradient overlay to improve readability
            Builder(
              builder: (context) {
              final bg = context.watch<AssistantProvider>().currentAssistant?.background;
              final maskStrength = context.watch<SettingsProvider>().chatBackgroundMaskStrength;
            if (bg == null || bg.trim().isEmpty) return const SizedBox.shrink();
            ImageProvider? provider;
            if (bg.startsWith('http')) {
              provider = NetworkImage(bg);
            } else {
              provider = PlatformUtils.fileImageProvider(SandboxPathResolver.fix(bg));
            }
            if (provider == null) return const SizedBox.shrink();
            return Positioned.fill(
              child: Stack(
                children: [
                  // Background image
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: provider,
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.04), BlendMode.srcATop),
                        ),
                      ),
                    ),
                  ),
                  // Vertical gradient overlay (top ~20% -> bottom ~50%) using theme background color
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: () {
                              final top = (0.20 * maskStrength).clamp(0.0, 1.0);
                              final bottom = (0.50 * maskStrength).clamp(0.0, 1.0);
                              return [
                                cs.background.withOpacity(top),
                                cs.background.withOpacity(bottom),
                              ];
                            }(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          // Main column content
          Padding(
            padding: EdgeInsets.only(top: kToolbarHeight + MediaQuery.of(context).padding.top),
            child: Column(
            children: [
              // Chat messages list (animate when switching topic)
              Expanded(
                child: Builder(
                    builder: (context) {
                      final __content = KeyedSubtree(
                        key: ValueKey<String>(_currentConversation?.id ?? 'none'),
                        child: MessageListView(
                          scrollController: _scrollController,
                          messages: _messages,
                          versionSelections: _versionSelections,
                          currentConversation: _currentConversation,
                          messageKeys: _messageKeys,
                          reasoning: _reasoning,
                          translations: _translations,
                          selecting: _selecting,
                          selectedItems: _selectedItems,
                          toolParts: _toolParts,
                          streamingNotifier: _streamingNotifier,
                          clearContextLabel: _clearContextLabel(),
                          onVersionChange: (gid, vers) async {
                            _versionSelections[gid] = vers;
                            await _chatService.setSelectedVersion(_currentConversation!.id, gid, vers);
                            if (mounted) setState(() {});
                          },
                          onRegenerateMessage: (msg) {
                            _regenerateAtMessage(msg);
                          },
                          onSend: (text) => _sendMessage(ChatInputData(text: text)),
                          onResendMessage: (msg) {
                            _sendMessage(ChatInputData(text: msg.content));
                          },
                          onTranslateMessage: (msg) {
                            _translateMessage(msg);
                          },
                          onEditMessage: (msg) {
                            _editMessage(msg);
                          },
                          onDeleteMessage: (msg, byGroup) async {
                            await _deleteMessage(msg);
                          },
                          onForkConversation: (msg) async {
                            await _forkConversationAtMessage(msg, _messages);
                          },
                          onShareMessage: (index, messages) {
                            _enterShareModeUpTo(index, messages);
                          },
                          onSpeakMessage: (msg) async {
                            await context.read<TtsProvider>().speak(msg.content);
                          },
                          onToggleSelection: (id, val) {
                            setState(() {
                              if (val) _selectedItems.add(id);
                              else _selectedItems.remove(id);
                            });
                          },
                          onToggleReasoning: (id) {
                            setState(() {
                              _reasoning[id]?.expanded = !(_reasoning[id]?.expanded ?? false);
                            });
                          },
                          onToggleTranslation: (id) {
                            setState(() {
                              _translations[id]?.expanded = !(_translations[id]?.expanded ?? true);
                            });
                          },
                          onToggleReasoningSegment: (msgId, entryKey) {
                            setState(() {
                               _reasoningSegments[msgId]?[entryKey].expanded = !(_reasoningSegments[msgId]?[entryKey].expanded ?? false);
                            });
                          },
                          onMentionReAnswer: _reAnswerWithModel,
                          reasoningSegments: _reasoningSegments,
                        ),
                      );
                      final isAndroid = Theme.of(context).platform == TargetPlatform.android;
                      Widget w = __content;
                      if (!isAndroid) {
                        w = FadeTransition(opacity: _convoFade, child: w);
                      }
                      return w;
                    },
                  ),
              ),
              // Input bar
              NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (n) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _measureInputBar());
                  return false;
                },
                child: SizeChangedLayoutNotifier(
                  child: Builder(
                    builder: (context) {
                      // Enforce model capabilities: disable MCP selection if model doesn't support tools
                      final settings = context.watch<SettingsProvider>();
                      final ap = context.watch<AssistantProvider>();
                      final a = ap.currentAssistant;
                      // Use assistant's model if set, otherwise fall back to global default
                      final pk = a?.chatModelProvider ?? settings.currentModelProvider;
                      final mid = a?.chatModelId ?? settings.currentModelId;
                      if (pk != null && mid != null) {
                        final supportsTools = _isToolModel(pk, mid);
                        if (!supportsTools && (a?.mcpServerIds.isNotEmpty ?? false)) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final aa = ap.currentAssistant;
                            if (aa != null && aa.mcpServerIds.isNotEmpty) {
                              ap.updateAssistant(aa.copyWith(mcpServerIds: const <String>[]));
                            }
                          });
                        }
                        final supportsReasoning = _isReasoningModel(pk, mid);
                        if (!supportsReasoning) {
                          final enabledNow = ReasoningStateManager.isReasoningEnabled(_currentConversation?.thinkingBudget ?? settings.thinkingBudget);
                          if (enabledNow) {
                            WidgetsBinding.instance.addPostFrameCallback((_) async {
                              final convo = _currentConversation;
                              if (convo != null) {
                                final updated = await _chatService.setConversationThinkingBudget(convo.id, 0);
                                if (updated != null && mounted) {
                                  setState(() {
                                    _currentConversation = updated;
                                  });
                                }
                              }
                            });
                          }
                        }
                      }
                      // Compute whether built-in search is active
                      final currentProvider = a?.chatModelProvider ?? settings.currentModelProvider;
                      final currentModelId = a?.chatModelId ?? settings.currentModelId;
                      final cfg = (currentProvider != null)
                          ? settings.getProviderConfig(currentProvider)
                          : null;
                      bool builtinSearchActive = false;
                      if (cfg != null && currentModelId != null) {
                        final mid2 = currentModelId;
                        final isGeminiOfficial = cfg.providerType == ProviderKind.google && (cfg.vertexAI != true);
                        final isClaude = cfg.providerType == ProviderKind.claude;
                        final isOpenAIResponses = cfg.providerType == ProviderKind.openai && (cfg.useResponseApi == true);
                        if (isGeminiOfficial || isClaude || isOpenAIResponses) {
                          final ov = cfg.modelOverrides[mid2] as Map?;
                          final list = (ov?['builtInTools'] as List?) ?? const <dynamic>[];
                          builtinSearchActive = list.map((e) => e.toString().toLowerCase()).contains('search');
                        }
                      }
                      return _buildChatInputBar(context, builtinSearchActive: builtinSearchActive);
                    },
                  ),
                ),
              ),
            ],
            ),
          ),

          // // iOS-style blur/fade effect above input area
          // Positioned(
          //   left: 0,
          //   right: 0,
          //   bottom: _inputBarHeight,
          //   child: IgnorePointer(
          //     child: Container(
          //       height: 20,
          //       decoration: BoxDecoration(
          //         gradient: LinearGradient(
          //           begin: Alignment.topCenter,
          //           end: Alignment.bottomCenter,
          //           colors: [
          //             Theme.of(context).colorScheme.background.withOpacity(0.0),
          //             Theme.of(context).colorScheme.background.withOpacity(0.8),
          //             Theme.of(context).colorScheme.background.withOpacity(1.0),
          //           ],
          //           stops: const [0.0, 0.6, 1.0],
          //         ),
          //       ),
          //     ),
          //   ),
          // ),

          // Inline tools sheet removed; replaced by modal bottom sheet

          // Selection toolbar overlay (above input bar) with iOS glass capsule + animations
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                // Move higher: 72 + 12 + 38
                padding: const EdgeInsets.only(bottom: 122),
                child: AnimatedSelectionBar(
                  visible: _selecting,
                  child: SelectionToolbar(
                    onCancel: () {
                      setState(() {
                        _selecting = false;
                        _selectedItems.clear();
                      });
                    },
                    onConfirm: () async {
                      final convo = _currentConversation;
                      if (convo == null) return;
                      final collapsed = _collapseVersions(_messages);
                      final selected = <ChatMessage>[];
                      for (final m in collapsed) {
                        if (_selectedItems.contains(m.id)) selected.add(m);
                      }
                      if (selected.isEmpty) {
                        final l10n = AppLocalizations.of(context)!;
                        showAppSnackBar(
                          context,
                          message: l10n.homePageSelectMessagesToShare,
                          type: NotificationType.info,
                        );
                        return;
                      }
                      setState(() { _selecting = false; });
                      await showChatExportSheet(context, conversation: convo, selectedMessages: selected);
                      if (mounted) setState(() { _selectedItems.clear(); });
                    },
                  ),
                ),
              ),
            ),
          ),

          // Scroll navigation buttons (4 buttons: top, prev, next, bottom)
          Builder(builder: (context) {
            final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
            if (!showSetting || _messages.isEmpty) return const SizedBox.shrink();
            return ScrollNavButtonsPanel(
              visible: _showJumpToBottom,
              bottomOffset: _inputBarHeight + 12,
              onScrollToTop: _scrollToTop,
              onPreviousMessage: _jumpToPreviousQuestion,
              onNextMessage: _jumpToNextQuestion,
              onScrollToBottom: _scrollToBottom,
            );
          }),

          // LobeChat-style mini rail navigation (right side)
          Builder(builder: (context) {
            final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
            if (!showSetting) return const SizedBox.shrink();
            final collapsed = _collapseVersions(_messages);
            return ChatMiniRail(
              messages: collapsed,
              activeMessageId: _visibleMessageId,
              onJumpToMessage: (id) => _scrollToMessageId(id),
            );
          }),
        ],
        ),
      ),
      );
  }

  Widget _buildTabletLayout(
    BuildContext context, {
    required String title,
    required String? providerName,
    required String? modelDisplay,
    required ColorScheme cs,
  }) {
    final bool _isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (_isDesktop && !_desktopUiInited) {
      _desktopUiInited = true;
      try {
        final sp = context.read<SettingsProvider>();
        _embeddedSidebarWidth = sp.desktopSidebarWidth.clamp(_sidebarMinWidth, _sidebarMaxWidth);
        _tabletSidebarOpen = sp.desktopSidebarOpen;
      } catch (_) {}
    }
    return Stack(
      children: [
        Positioned.fill(child: _buildAssistantBackground(context)),
        SizedBox.expand(
      child: Row(
      children: [
        _buildTabletSidebar(context),
        if (_isDesktop)
          SidebarResizeHandle(
            visible: _tabletSidebarOpen,
            onDrag: (dx) {
              setState(() {
                _embeddedSidebarWidth = (_embeddedSidebarWidth + dx).clamp(_sidebarMinWidth, _sidebarMaxWidth);
              });
            },
            onDragEnd: () {
              try { context.read<SettingsProvider>().setDesktopSidebarWidth(_embeddedSidebarWidth); } catch (_) {}
            },
          )
        else
          AnimatedContainer(
            duration: _sidebarAnimDuration,
            curve: _sidebarAnimCurve,
            width: _tabletSidebarOpen ? 0.6 : 0,
            child: _tabletSidebarOpen
                ? VerticalDivider(
                    width: 0.6,
                    thickness: 0.5,
                    color: cs.outlineVariant.withOpacity(0.20),
                  )
                : const SizedBox.shrink(),
          ),
        Expanded(
          child: Scaffold(
            key: _scaffoldKey,
            resizeToAvoidBottomInset: true,
            extendBodyBehindAppBar: true,
            backgroundColor: Colors.transparent,
            appBar: _buildTabletAppBar(
              title: title,
              providerName: providerName,
              modelDisplay: modelDisplay,
              cs: cs,
            ),
            body: Stack(
              children: [

                Padding(
                  padding: EdgeInsets.only(top: kToolbarHeight + MediaQuery.of(context).padding.top),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: context.watch<SettingsProvider>().desktopWideContent
                            ? double.infinity
                            : context.watch<SettingsProvider>().desktopNarrowContentWidth,
                      ),
                      child: Column(
                        children: [
                          // Message list (add subtle animate on conversation switch)
                          Expanded(
                            child: FadeTransition(
                              opacity: _convoFade,
                                child: MessageListView(
                                  scrollController: _scrollController,
                                  messages: _messages,
                                  versionSelections: _versionSelections,
                                  currentConversation: _currentConversation,
                                  messageKeys: _messageKeys,
                                  reasoning: _reasoning,
                                  translations: _translations,
                                  selecting: _selecting,
                                  selectedItems: _selectedItems,
                                  toolParts: _toolParts,
                                  streamingNotifier: _streamingNotifier,
                                  onVersionChange: (gid, vers) async {
                                    _versionSelections[gid] = vers;
                                    await _chatService.setSelectedVersion(_currentConversation!.id, gid, vers);
                                    if (mounted) setState(() {});
                                  },
                                  onRegenerateMessage: (msg) {
                                    _regenerateAtMessage(msg);
                                  },
                                  onSend: (text) => _sendMessage(ChatInputData(text: text)),
                                  onResendMessage: (msg) {
                                    _sendMessage(ChatInputData(text: msg.content));
                                  },
                                  onTranslateMessage: (msg) {
                                    _translateMessage(msg);
                                  },
                                  onEditMessage: (msg) {
                                    _editMessage(msg);
                                  },
                                  onDeleteMessage: (msg, byGroup) async {
                                    await _deleteMessage(msg);
                                  },
                                  onForkConversation: (msg) async {
                                    await _forkConversationAtMessage(msg, _messages);
                                  },
                                  onShareMessage: (index, messages) {
                                    _enterShareModeUpTo(index, messages);
                                  },
                                  onSpeakMessage: (msg) async {
                                    await context.read<TtsProvider>().speak(msg.content);
                                  },
                                  onToggleSelection: (id, val) {
                                    setState(() {
                                      if (val) _selectedItems.add(id);
                                      else _selectedItems.remove(id);
                                    });
                                  },
                                  onToggleReasoning: (id) {
                                    setState(() {
                                      _reasoning[id]?.expanded = !(_reasoning[id]?.expanded ?? false);
                                    });
                                  },
                                  onToggleTranslation: (id) {
                                    setState(() {
                                      _translations[id]?.expanded = !(_translations[id]?.expanded ?? true);
                                    });
                                  },
                                  onToggleReasoningSegment: (msgId, entryKey) {
                                    setState(() {
                                       _reasoningSegments[msgId]?[entryKey].expanded = !(_reasoningSegments[msgId]?[entryKey].expanded ?? false);
                                    });
                                  },
                                  onMentionReAnswer: _reAnswerWithModel,
                                  reasoningSegments: _reasoningSegments,
                                  clearContextLabel: _clearContextLabel(),
                                ),
                              ),
                            ),


                          // Input bar with max width
                          NotificationListener<SizeChangedLayoutNotification>(
                            onNotification: (n) {
                              WidgetsBinding.instance.addPostFrameCallback((_) => _measureInputBar());
                              return false;
                            },
                            child: SizeChangedLayoutNotifier(
                              child: Builder(
                                builder: (context) {
                                  final settings = context.watch<SettingsProvider>();
                                  final ap = context.watch<AssistantProvider>();
                                  final a = ap.currentAssistant;
                                  final pk = a?.chatModelProvider ?? settings.currentModelProvider;
                                  final mid = a?.chatModelId ?? settings.currentModelId;
                                  if (pk != null && mid != null) {
                                    final supportsTools = _isToolModel(pk, mid);
                                    if (!supportsTools && (a?.mcpServerIds.isNotEmpty ?? false)) {
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        final aa = ap.currentAssistant;
                                        if (aa != null && aa.mcpServerIds.isNotEmpty) {
                                          ap.updateAssistant(aa.copyWith(mcpServerIds: const <String>[]));
                                        }
                                      });
                                    }
                                    final supportsReasoning = _isReasoningModel(pk, mid);
                                    if (!supportsReasoning) {
                                      final enabledNow = ReasoningStateManager.isReasoningEnabled(_currentConversation?.thinkingBudget ?? settings.thinkingBudget);
                                      if (enabledNow) {
                                        WidgetsBinding.instance.addPostFrameCallback((_) async {
                                          final convo = _currentConversation;
                                          if (convo != null) {
                                            final updated = await _chatService.setConversationThinkingBudget(convo.id, 0);
                                            if (updated != null && mounted) {
                                              setState(() {
                                                _currentConversation = updated;
                                              });
                                            }
                                          }
                                        });
                                      }
                                    }
                                  }
                                  // Compute whether built-in search is active
                                  final currentProvider = a?.chatModelProvider ?? settings.currentModelProvider;
                                  final currentModelId = a?.chatModelId ?? settings.currentModelId;
                                  final cfg = (currentProvider != null) ? settings.getProviderConfig(currentProvider) : null;
                                  bool builtinSearchActive = false;
                                  if (cfg != null && currentModelId != null) {
                                    final mid2 = currentModelId;
                                    final isGeminiOfficial = cfg.providerType == ProviderKind.google && (cfg.vertexAI != true);
                                    final isClaude = cfg.providerType == ProviderKind.claude;
                                    final isOpenAIResponses = cfg.providerType == ProviderKind.openai && (cfg.useResponseApi == true);
                                    if (isGeminiOfficial || isClaude || isOpenAIResponses) {
                                      final ov = cfg.modelOverrides[mid2] as Map?;
                                      final list = (ov?['builtInTools'] as List?) ?? const <dynamic>[];
                                      builtinSearchActive = list.map((e) => e.toString().toLowerCase()).contains('search');
                                    }
                                  }

                                  Widget input = _buildChatInputBar(context, builtinSearchActive: builtinSearchActive);

                                  input = Center(
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: context.watch<SettingsProvider>().desktopWideContent
                                            ? double.infinity
                                            : context.watch<SettingsProvider>().desktopNarrowContentWidth,
                                      ),
                                      child: input,
                                    ),
                                  );
                                  return input;
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Selection toolbar overlay (tablet) with iOS glass capsule + animations
                _buildSelectionToolbar(context),

                // Scroll navigation buttons (4 buttons: top, prev, next, bottom)
                _buildScrollNavButtons(context),

                // LobeChat-style mini rail navigation (right side)
                Builder(builder: (context) {
                  final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
                  if (!showSetting) return const SizedBox.shrink();
                  final collapsed = _collapseVersions(_messages);
                  return ChatMiniRail(
                    messages: collapsed,
                    activeMessageId: _visibleMessageId,
                    onJumpToMessage: (id) => _scrollToMessageId(id),
                  );
                }),
              ],
            ),
          ),
        ),
        // Fixed right topics sidebar when enabled
        _buildRightTopicsSidebar(context),
      ],
    ),
    ),
  ],
);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _convoFadeController.dispose();
    _mcpProvider?.removeListener(_onMcpChanged);
    // Remove drawer value listener
    _drawerController.removeListener(_onDrawerValueChanged);
    _inputFocus.dispose();
    _inputController.dispose();
    _scrollController.removeListener(_onScrollControllerChanged);
    _scrollController.dispose();
    try {
      for (final s in _conversationStreams.values) { s.cancel(); }
    } catch (_) {}
    _conversationStreams.clear();
    _userScrollTimer?.cancel();
    // 清理流式 UI 优化资源
    _streamingNotifier.dispose();
    _streamingThrottleManager.dispose();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  void _triggerConversationFade() {
    try {
      _convoFadeController.stop();
      _convoFadeController.value = 0;
      _convoFadeController.forward();
    } catch (_) {}
  }

  @override
  void didPushNext() {
    // Navigating away: drop focus so it won't be restored.
    _dismissKeyboard();
  }

  @override
  void didPopNext() {
    // Returning to this page: desktop focuses input, mobile dismisses keyboard
    if (PlatformUtils.isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inputFocus.requestFocus();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dismissKeyboard());
    }
  }

}


