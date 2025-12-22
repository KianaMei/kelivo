import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../../../theme/design_tokens.dart';
import '../../../icons/lucide_adapter.dart';
import 'rich_chat_input.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import '../../../shared/responsive/breakpoints.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'dart:convert';
import '../../../core/models/chat_input_data.dart';
import '../../../utils/clipboard_images.dart';
import '../../../utils/platform_utils.dart';
import '../../../utils/local_image_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/search/search_service.dart';
import '../../../utils/brand_assets.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../desktop/desktop_context_menu.dart';
import 'clipboard_image_persister.dart';

class ChatInputBarController {
  _ChatInputBarState? _state;
  void _bind(_ChatInputBarState s) => _state = s;
  void _unbind(_ChatInputBarState s) { if (identical(_state, s)) _state = null; }

  void addImages(List<String> paths) => _state?._addImages(paths);
  void clearImages() => _state?._clearImages();
  void addFiles(List<DocumentAttachment> docs) => _state?._addFiles(docs);
  void clearFiles() => _state?._clearFiles();
}

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    this.onSend,
    this.onStop,
    this.onSelectModel,
    this.onLongPressSelectModel,
    this.onOpenMcp,
    this.onLongPressMcp,
    this.onToggleSearch,
    this.onOpenSearch,
    this.onMore,
    this.onConfigureReasoning,
    this.onConfigureMaxTokens,
    this.onConfigureToolLoop,
    this.moreOpen = false,
    this.focusNode,
    this.modelIcon,
    this.controller,
    this.mediaController,
    this.loading = false,
    this.reasoningActive = false,
    this.thinkingBudget,
    this.supportsReasoning = true,
    this.maxTokensConfigured = false,
    this.showMcpButton = false,
    this.mcpActive = false,
    this.mcpToolCount = 0,
    this.searchEnabled = false,
    this.showMiniMapButton = false,
    this.onOpenMiniMap,
    this.onPickCamera,
    this.onPickPhotos,
    this.onUploadFiles,
    this.onToggleLearningMode,
    this.onClearContext,
    this.onLongPressLearning,
    this.learningModeActive = false,
    this.showMoreButton = true,
    this.showQuickPhraseButton = false,
    this.onQuickPhrase,
    this.onLongPressQuickPhrase,
    this.searchAnchorKey,
    this.reasoningAnchorKey,
    this.mcpAnchorKey,
    this.onToggleToolMode,
    this.toolModeIsPrompt = false,
    this.showToolModeButton = false,
    this.onMentionTap,
    this.onAtTrigger,
  });

  final ValueChanged<ChatInputData>? onSend;
  final VoidCallback? onStop;
  final VoidCallback? onSelectModel;
  final VoidCallback? onLongPressSelectModel;
  final VoidCallback? onOpenMcp;
  final VoidCallback? onLongPressMcp;
  final ValueChanged<bool>? onToggleSearch;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onMore;
  final VoidCallback? onConfigureReasoning;
  final VoidCallback? onConfigureMaxTokens;
  final VoidCallback? onConfigureToolLoop;
  final bool moreOpen;
  final FocusNode? focusNode;
  final Widget? modelIcon;
  final TextEditingController? controller;
  final ChatInputBarController? mediaController;
  final bool loading;
  final bool reasoningActive;
  final int? thinkingBudget;
  final bool supportsReasoning;
  final bool maxTokensConfigured;
  final bool showMcpButton;
  final bool mcpActive;
  final int mcpToolCount;
  final bool searchEnabled;
  final bool showMiniMapButton;
  final VoidCallback? onOpenMiniMap;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickPhotos;
  final VoidCallback? onUploadFiles;
  final VoidCallback? onToggleLearningMode;
  final VoidCallback? onClearContext;
  final VoidCallback? onLongPressLearning;
  final bool learningModeActive;
  final bool showMoreButton;
  final bool showQuickPhraseButton;
  final VoidCallback? onQuickPhrase;
  final VoidCallback? onLongPressQuickPhrase;
  final GlobalKey? searchAnchorKey;
  final GlobalKey? reasoningAnchorKey;
  final GlobalKey? mcpAnchorKey;
  /// Callback when tool mode toggle is pressed
  final VoidCallback? onToggleToolMode;
  /// Whether the current tool mode is "prompt" (true) or "native" (false)
  final bool toolModeIsPrompt;
  /// Whether to show the tool mode toggle button
  final bool showToolModeButton;
  /// Callback when @ button is tapped to mention models
  final VoidCallback? onMentionTap;
  /// Callback when "@" character is typed in input field
  /// The parameter is the text before the "@" character
  final ValueChanged<String>? onAtTrigger;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  late TextEditingController _controller;
  bool _searchEnabled = false;
  final List<String> _images = <String>[]; // local file paths
  final List<DocumentAttachment> _docs = <DocumentAttachment>[]; // files to upload
  final Map<LogicalKeyboardKey, Timer?> _repeatTimers = {};
  static const Duration _repeatInitialDelay = Duration(milliseconds: 300);
  static const Duration _repeatPeriod = Duration(milliseconds: 35);
  // Collapse toggle for a subset of quick-action buttons (tool loop / camera / learning / mini-map).
  // Default collapsed as requested.
  bool _extraActionsCollapsed = true;
  // Expand/collapse for input field
  bool _isExpanded = false;
  // Rich text input mode
  bool _useRichInput = false;
  final GlobalKey<RichChatInputState> _richInputKey = GlobalKey<RichChatInputState>();
  
  /// Show expand button when text has 3+ lines
  bool get _showExpandButton {
    final text = _controller.text;
    if (text.isEmpty) return false;
    return '\n'.allMatches(text).length >= 2;
  }

  void _addImages(List<String> paths) {
    if (paths.isEmpty) return;
    setState(() => _images.addAll(paths));
  }

  void _clearImages() {
    setState(() => _images.clear());
  }

  void _addFiles(List<DocumentAttachment> docs) {
    if (docs.isEmpty) return;
    setState(() => _docs.addAll(docs));
  }

  void _clearFiles() {
    setState(() => _docs.clear());
  }

  void _removeImageAt(int index) async {
    final path = _images[index];
    setState(() => _images.removeAt(index));
    // best-effort delete (IO only; web is no-op)
    try {
      // ignore: unawaited_futures
      PlatformUtils.deleteFile(path);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    widget.mediaController?._bind(this);
    _searchEnabled = widget.searchEnabled;
  }

  @override
  void dispose() {
    _repeatTimers.values.forEach((t) { try { t?.cancel(); } catch (_) {} });
    _repeatTimers.clear();
    widget.mediaController?._unbind(this);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchEnabled != widget.searchEnabled) {
      _searchEnabled = widget.searchEnabled;
    }
  }

  String _hint(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return l10n.chatInputBarHint;
  }

  void _handleSend() {
    String text;
    if (_useRichInput) {
      // 使用 markdown 格式保留富文本格式
      text = _richInputKey.currentState?.markdown ?? '';
    } else {
      text = _controller.text.trim();
    }
    if (text.isEmpty && _images.isEmpty && _docs.isEmpty) return;
    widget.onSend?.call(ChatInputData(text: text, imagePaths: List.of(_images), documents: List.of(_docs)));
    if (_useRichInput) {
      _richInputKey.currentState?.clear();
    } else {
      _controller.clear();
    }
    _images.clear();
    _docs.clear();
    setState(() {});
  }

  void _handleTextChange(String text) {
    setState(() {});
    // Detect "@" character and trigger model selector
    if (text.endsWith('@') && widget.onAtTrigger != null) {
      final textBeforeAt = text.substring(0, text.length - 1);
      // Remove the "@" from input
      _controller.text = textBeforeAt;
      _controller.selection = TextSelection.collapsed(offset: textBeforeAt.length);
      // Trigger the callback
      widget.onAtTrigger!(textBeforeAt);
    }
  }

  void _insertNewlineAtCursor() {
    final value = _controller.value;
    final selection = value.selection;
    final text = value.text;
    if (!selection.isValid) {
      _controller.text = text + '\n';
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    } else {
      final start = selection.start;
      final end = selection.end;
      final newText = text.replaceRange(start, end, '\n');
      _controller.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + 1),
        composing: TextRange.empty,
      );
    }
    setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    // Enhance hardware keyboard behavior
    final w = MediaQuery.sizeOf(node.context!).width;
    final isTabletOrDesktop = w >= AppBreakpoints.tablet;
    final isIosTablet = (!kIsWeb) && defaultTargetPlatform == TargetPlatform.iOS && isTabletOrDesktop;

    final isDown = event is RawKeyDownEvent;
    final key = event.logicalKey;
    final isEnter = key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;
    final isArrow = key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight;
    final isPasteV = key == LogicalKeyboardKey.keyV;

    // Enter handling on tablet/desktop: Enter=send, Shift+Enter=newline
    if (isEnter && isTabletOrDesktop) {
      if (!isDown) return KeyEventResult.handled; // ignore key up
      final keys = RawKeyboard.instance.keysPressed;
      final shift = keys.contains(LogicalKeyboardKey.shiftLeft) || keys.contains(LogicalKeyboardKey.shiftRight);
      if (shift) {
        _insertNewlineAtCursor();
      } else {
        _handleSend();
      }
      return KeyEventResult.handled;
    }

    // Paste handling for images on iOS/macOS (tablet/desktop)
    if (isDown && isPasteV) {
      final keys = RawKeyboard.instance.keysPressed;
      final meta = keys.contains(LogicalKeyboardKey.metaLeft) || keys.contains(LogicalKeyboardKey.metaRight);
      final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) || keys.contains(LogicalKeyboardKey.controlRight);
      if (meta || ctrl) {
        _handlePasteFromClipboard();
        return KeyEventResult.handled;
      }
    }

    // Arrow repeat fix only needed on iOS tablets
    if (!isIosTablet || !isArrow) return KeyEventResult.ignored;

    final keys = RawKeyboard.instance.keysPressed;
    final shift = keys.contains(LogicalKeyboardKey.shiftLeft) || keys.contains(LogicalKeyboardKey.shiftRight);
    final alt = keys.contains(LogicalKeyboardKey.altLeft) || keys.contains(LogicalKeyboardKey.altRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) || keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) || keys.contains(LogicalKeyboardKey.controlRight);

    void moveOnce() {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _moveCaret(-1, extend: shift, byWord: alt);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _moveCaret(1, extend: shift, byWord: alt);
      }
    }

    if (isDown) {
      // Initial move
      moveOnce();
      // Start repeat timer if not already
      if (!_repeatTimers.containsKey(key)) {
        Timer? periodic;
        final starter = Timer(_repeatInitialDelay, () {
          periodic = Timer.periodic(_repeatPeriod, (_) => moveOnce());
          _repeatTimers[key] = periodic!;
        });
        // Store starter temporarily; replace when periodic begins
        _repeatTimers[key] = starter;
      }
      return KeyEventResult.handled;
    } else {
      // Key up -> cancel repeat
      final t = _repeatTimers.remove(key);
      try { t?.cancel(); } catch (_) {}
      return KeyEventResult.handled;
    }
  }

  Future<void> _handlePasteFromClipboard() async {
    // Try image first via platform channel
    final paths = await ClipboardImages.getImagePaths();
    if (paths.isNotEmpty) {
      final persisted = await _persistClipboardImages(paths);
      if (persisted.isNotEmpty) {
        _addImages(persisted);
      }
      return;
    }
    // Fallback: paste text
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isEmpty) return;
      final value = _controller.value;
      final sel = value.selection;
      if (!sel.isValid) {
        _controller.text = value.text + text;
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      } else {
        final start = sel.start;
        final end = sel.end;
        final newText = value.text.replaceRange(start, end, text);
        _controller.value = value.copyWith(
          text: newText,
          selection: TextSelection.collapsed(offset: start + text.length),
          composing: TextRange.empty,
        );
      }
      setState(() {});
    } catch (_) {}
  }

  Future<List<String>> _persistClipboardImages(List<String> srcPaths) async {
    return persistClipboardImages(srcPaths);
  }

  void _moveCaret(int dir, {bool extend = false, bool byWord = false}) {
    final text = _controller.text;
    if (text.isEmpty) return;
    TextSelection sel = _controller.selection;
    if (!sel.isValid) {
      final off = dir < 0 ? text.length : 0;
      _controller.selection = TextSelection.collapsed(offset: off);
      return;
    }

    int nextOffset(int from, int direction) {
      if (!byWord) return (from + direction).clamp(0, text.length);
      // Move by simple word boundary: skip whitespace; then skip non-whitespace
      int i = from;
      if (direction < 0) {
        // Move left
        while (i > 0 && text[i - 1].trim().isEmpty) i--;
        while (i > 0 && text[i - 1].trim().isNotEmpty) i--;
      } else {
        // Move right
        while (i < text.length && text[i].trim().isEmpty) i++;
        while (i < text.length && text[i].trim().isNotEmpty) i++;
      }
      return i.clamp(0, text.length);
    }

    if (extend) {
      final newExtent = nextOffset(sel.extentOffset, dir);
      _controller.selection = sel.copyWith(extentOffset: newExtent);
    } else {
      final base = dir < 0 ? sel.start : sel.end;
      final collapsed = nextOffset(base, dir);
      _controller.selection = TextSelection.collapsed(offset: collapsed);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;
    final hasText = _useRichInput 
        ? (_richInputKey.currentState?.plainText.isNotEmpty ?? false)
        : _controller.text.trim().isNotEmpty;
    final hasImages = _images.isNotEmpty;
    final hasDocs = _docs.isNotEmpty;

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xxs, AppSpacing.sm, AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // File attachments (if any)
            if (hasDocs) ...[
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final d = _docs[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: isDark ? [] : AppShadows.soft,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.insert_drive_file, size: 18),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              d.fileName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              setState(() => _docs.removeAt(idx));
                              // best-effort delete persisted attachment
                              try {
                                PlatformUtils.deleteFileSync(d.path);
                              } catch (_) {}
                            },
                            child: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            // Image previews (if any)
            if (hasImages) ...[
              SizedBox(
                height: 64,
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 6),
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final path = _images[idx];
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: (() {
                              if (path.startsWith('data:')) {
                                return Image.memory(
                                  base64Decode(path.substring(path.indexOf('base64,') + 7)),
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                );
                              }
                              final lower = path.toLowerCase();
                              final isUrl = lower.startsWith('http://') || lower.startsWith('https://');
                              if (isUrl) {
                                return Image.network(
                                  path,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 64,
                                    height: 64,
                                    color: Colors.black12,
                                    child: const Icon(Icons.broken_image),
                                  ),
                                );
                              }
                              if (kIsWeb) {
                                return Container(
                                  width: 64,
                                  height: 64,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.image_not_supported),
                                );
                              }
                              return Image(
                                image: localFileImage(path),
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 64,
                                  height: 64,
                                  color: Colors.black12,
                                  child: const Icon(Icons.broken_image),
                                ),
                              );
                            })(),
                          ),
                        ),
                        Positioned(
                          right: -6,
                          top: -6,
                          child: GestureDetector(
                            onTap: () => _removeImageAt(idx),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            // Main input container with iOS-like frosted glass effect
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  decoration: BoxDecoration(
                    // Translucent background over blurred content
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(20),
                    // Use previous gray border for better contrast on white
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.10)
                          : theme.colorScheme.outline.withOpacity(0.20),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                  // Input field - supports both plain text and rich text modes
                  if (_useRichInput)
                    RichChatInput(
                      key: _richInputKey,
                      focusNode: widget.focusNode,
                      hintText: _hint(context),
                      minLines: 1,
                      maxLines: _isExpanded ? 25 : 8,
                      onSend: (_) => _handleSend(),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xxs, AppSpacing.md, AppSpacing.xs),
                      child: Stack(
                      children: [
                        Focus(
                          onKey: (node, event) => _handleKeyEvent(node, event),
                          child: TextField(
                            controller: _controller,
                            focusNode: widget.focusNode,
                            onChanged: (text) => _handleTextChange(text),
                            minLines: 1,
                            maxLines: _isExpanded ? 25 : 5,
                            // On iOS, show "Send" on the return key and submit on tap.
                            // Still keep multiline so pasted text preserves line breaks.
                            keyboardType: TextInputType.multiline,
                            textInputAction: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                                ? TextInputAction.send
                                : TextInputAction.newline,
                            onSubmitted: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                                ? (_) => _handleSend()
                                : null,
                            contextMenuBuilder: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                                ? (BuildContext context, EditableTextState state) {
                                    final l10n = AppLocalizations.of(context)!;
                                    return AdaptiveTextSelectionToolbar.buttonItems(
                                      anchors: state.contextMenuAnchors,
                                      buttonItems: <ContextMenuButtonItem>[
                                        ...state.contextMenuButtonItems,
                                        ContextMenuButtonItem(
                                          onPressed: () {
                                            // Insert a newline at current caret or replace selection
                                            _insertNewlineAtCursor();
                                            state.hideToolbar();
                                          },
                                          label: l10n.chatInputBarInsertNewline,
                                        ),
                                      ],
                                    );
                                  }
                                : null,
                            autofocus: false,
                            decoration: InputDecoration(
                              hintText: _hint(context),
                              hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.45)),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 2),
                            ),
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 15,
                            ),
                            cursorColor: theme.colorScheme.primary,
                          ),
                        ),
                        // Expand/Collapse icon button (only shown when 3+ lines)
                        if (_showExpandButton)
                          Positioned(
                            top: 10,
                            right: 12,
                            child: GestureDetector(
                              onTap: () => setState(() => _isExpanded = !_isExpanded),
                              child: Icon(
                                _isExpanded ? Lucide.ChevronsDownUp : Lucide.ChevronsUpDown,
                                size: 16,
                                color: theme.colorScheme.onSurface.withOpacity(0.45),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Bottom buttons row (no divider)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.xs),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _CompactIconButton(
                              tooltip: AppLocalizations.of(context)!.chatInputBarSelectModelTooltip,
                              icon: Lucide.Boxes,
                              child: widget.modelIcon,
                              modelIcon: true,
                              onTap: widget.onSelectModel,
                              onLongPress: widget.onLongPressSelectModel,
                            ),
                            if (widget.onMentionTap != null) ...[
                              const SizedBox(width: 8),
                              _CompactIconButton(
                                tooltip: '@',
                                icon: Lucide.AtSign,
                                onTap: widget.onMentionTap,
                              ),
                            ],
                            const SizedBox(width: 8),
                            Container(
                              key: widget.searchAnchorKey,
                              child: (() {
                                // Determine current search state to render icon
                                final settings = context.watch<SettingsProvider>();
                                final ap = context.watch<AssistantProvider>();
                                final a = ap.currentAssistant;
                                final currentProviderKey = a?.chatModelProvider ?? settings.currentModelProvider;
                              final currentModelId = a?.chatModelId ?? settings.currentModelId;
                              final cfg = (currentProviderKey != null)
                                  ? settings.getProviderConfig(currentProviderKey)
                                  : null;
                              bool builtinSearchActive = false;
                              if (cfg != null && currentModelId != null) {
                                final isGeminiOfficial = cfg.providerType == ProviderKind.google && (cfg.vertexAI != true);
                                final isClaude = cfg.providerType == ProviderKind.claude;
                                final isOpenAIResponses = cfg.providerType == ProviderKind.openai && (cfg.useResponseApi == true);
                                // Check if it's a Grok model (more robust detection)
                                final isGrok = _isGrokModel(cfg, currentModelId);
                                if (isGeminiOfficial || isClaude || isOpenAIResponses || isGrok) {
                                  final ov = cfg.modelOverrides[currentModelId] as Map?;
                                  final list = (ov?['builtInTools'] as List?) ?? const <dynamic>[];
                                  builtinSearchActive = list
                                      .map((e) => e.toString().toLowerCase())
                                      .contains('search');
                                }
                              }
                              final appSearchEnabled = settings.searchEnabled;
                              final theme = Theme.of(context);
                              final isDark = theme.brightness == Brightness.dark;

                              // Not enabled at all -> default globe (not themed)
                              if (!appSearchEnabled && !builtinSearchActive) {
                                return _CompactIconButton(
                                  tooltip: AppLocalizations.of(context)!.chatInputBarOnlineSearchTooltip,
                                  icon: Lucide.Globe,
                                  active: false,
                                  onTap: widget.onOpenSearch,
                                );
                              }

                              // Built-in search -> show magnifier icon in theme color
                              if (builtinSearchActive) {
                                return _CompactIconButton(
                                  tooltip: AppLocalizations.of(context)!.chatInputBarOnlineSearchTooltip,
                                  icon: Lucide.Search,
                                  active: true,
                                  onTap: widget.onOpenSearch,
                                );
                              }

                              // External provider search -> brand icon tinted to theme color
                              // Resolve selected service and its brand asset
                              final services = settings.searchServices;
                              final sel = settings.searchServiceSelected
                                  .clamp(0, services.isNotEmpty ? services.length - 1 : 0);
                              final options = services.isNotEmpty
                                  ? services[sel]
                                  : SearchServiceOptions.defaultOption;
                              final svc = SearchService.getService(options);
                              final asset = BrandAssets.assetForName(svc.name);

                              return _CompactIconButton(
                                tooltip: AppLocalizations.of(context)!.chatInputBarOnlineSearchTooltip,
                                icon: Lucide.Globe,
                                active: true,
                                onTap: widget.onOpenSearch,
                                childBuilder: (c) {
                                  if (asset != null) {
                                    if (asset.endsWith('.svg')) {
                                      return SvgPicture.asset(
                                        asset,
                                        width: 20,
                                        height: 20,
                                        colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
                                      );
                                    } else {
                                      return Image.asset(
                                        asset,
                                        width: 20,
                                        height: 20,
                                        color: c,
                                        colorBlendMode: BlendMode.srcIn,
                                      );
                                    }
                                  } else {
                                    return Icon(Lucide.Globe, size: 20, color: c);
                                  }
                                },
                              );
                            })(),
                            ),
                            if (widget.supportsReasoning) ...[
                              const SizedBox(width: 8),
                              Container(
                                key: widget.reasoningAnchorKey,
                                child: _ReasoningButton(
                                  thinkingBudget: widget.thinkingBudget,
                                  active: widget.reasoningActive,
                                  onTap: widget.onConfigureReasoning,
                                ),
                              ),
                            ],
                            if (widget.showMcpButton) ...[
                              const SizedBox(width: 8),
                              Container(
                                key: widget.mcpAnchorKey,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _CompactIconButton(
                                      tooltip: AppLocalizations.of(context)!.chatInputBarMcpServersTooltip,
                                      icon: Lucide.Hammer,
                                      active: widget.mcpActive,
                                      onTap: widget.onOpenMcp,
                                      onLongPress: widget.onLongPressMcp,
                                    ),
                                    if (widget.mcpToolCount > 0) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        '${widget.mcpToolCount}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: widget.mcpActive
                                            ? Theme.of(context).colorScheme.primary
                                            : (Theme.of(context).brightness == Brightness.dark
                                                ? Colors.white70
                                                : Colors.black54),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            // Rich text mode toggle (all platforms)
                            const SizedBox(width: 8),
                            _CompactIconButton(
                              tooltip: _useRichInput ? '切换到普通输入' : '切换到富文本输入',
                              icon: Lucide.CaseSensitive,
                              active: _useRichInput,
                              onTap: () => setState(() => _useRichInput = !_useRichInput),
                            ),
                            if (widget.onClearContext != null) ...[
                              const SizedBox(width: 8),
                              _CompactIconButton(
                                tooltip: AppLocalizations.of(context)!.bottomToolsSheetClearContext,
                                icon: Lucide.Eraser,
                                onTap: widget.onClearContext,
                              ),
                            ],
                            // Desktop extra actions (collapse button and more)
                            if (!isMobile) ...[
                              const SizedBox(width: 8),
                              _CompactIconButton(
                                tooltip: _extraActionsCollapsed ? '展开' : '收起',
                                icon: _extraActionsCollapsed ? Lucide.ChevronRight : Lucide.ChevronLeft,
                                onTap: () => setState(() => _extraActionsCollapsed = !_extraActionsCollapsed),
                              ),
                              if (!_extraActionsCollapsed) ...[
                                if (widget.onPickPhotos != null) ...[
                                  const SizedBox(width: 8),
                                  _CompactIconButton(
                                    tooltip: AppLocalizations.of(context)!.bottomToolsSheetPhotos,
                                    icon: Lucide.Image,
                                    onTap: widget.onPickPhotos,
                                  ),
                                ],
                                if (widget.onUploadFiles != null) ...[
                                  const SizedBox(width: 8),
                                  _CompactIconButton(
                                    tooltip: AppLocalizations.of(context)!.bottomToolsSheetUpload,
                                    icon: Lucide.Paperclip,
                                    onTap: widget.onUploadFiles,
                                  ),
                                ],
                                if (widget.onConfigureMaxTokens != null) ...[
                                  const SizedBox(width: 8),
                                  _CompactIconButton(
                                    tooltip: AppLocalizations.of(context)!.chatInputBarMaxTokensTooltip,
                                    icon: Lucide.FileText,
                                    active: widget.maxTokensConfigured,
                                    onTap: widget.onConfigureMaxTokens,
                                  ),
                                ],
                                if (widget.onConfigureToolLoop != null) ...[
                                  const SizedBox(width: 8),
                                  _CompactIconButton(
                                    tooltip: '工具循环',
                                    icon: Lucide.RefreshCw,
                                    active: false,
                                    onTap: widget.onConfigureToolLoop,
                                  ),
                                ],
                                if (widget.onPickCamera != null) ...[
                                  const SizedBox(width: 8),
                                  _CompactIconButton(
                                    tooltip: AppLocalizations.of(context)!.bottomToolsSheetCamera,
                                    icon: Lucide.Camera,
                                    onTap: widget.onPickCamera,
                                  ),
                                ],
                                if (widget.onToggleLearningMode != null) ...[
                                  const SizedBox(width: 8),
                                  _CompactIconButton(
                                    tooltip: AppLocalizations.of(context)!.bottomToolsSheetLearningMode,
                                    icon: Lucide.BookOpenText,
                                    active: widget.learningModeActive,
                                    onTap: widget.onToggleLearningMode,
                                    onLongPress: widget.onLongPressLearning,
                                  ),
                                ],
                                if (widget.showMiniMapButton) ...[
                                  const SizedBox(width: 8),
                                  _CompactIconButton(
                                    tooltip: AppLocalizations.of(context)!.miniMapTooltip,
                                    icon: Lucide.Map,
                                    onTap: widget.onOpenMiniMap,
                                  ),
                                ],
                              ],
                            ],
                          ],
                        ),
                        Row(
                          children: [
                            if (widget.showMoreButton) ...[
                              _CompactIconButton(
                                tooltip: AppLocalizations.of(context)!.chatInputBarMoreTooltip,
                                icon: Lucide.Plus,
                                active: widget.moreOpen,
                                onTap: widget.onMore,
                                childBuilder: (c) => AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  transitionBuilder: (child, anim) => RotationTransition(
                                    turns: Tween<double>(begin: 0.85, end: 1).animate(anim),
                                    child: FadeTransition(opacity: anim, child: child),
                                  ),
                                  child: Icon(
                                    widget.moreOpen ? Lucide.X : Lucide.Plus,
                                    key: ValueKey(widget.moreOpen ? 'close' : 'add'),
                                    size: 20,
                                    color: c,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            _CompactSendButton(
                              enabled: (hasText || hasImages || hasDocs) && !widget.loading,
                              loading: widget.loading,
                              onSend: _handleSend,
                              onStop: widget.loading ? widget.onStop : null,
                              color: theme.colorScheme.primary,
                              icon: Lucide.ArrowUp,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
                )),)],

        ),
      ),
    );
  }
}

// New compact button for the integrated input bar
class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.onLongPress,
    this.tooltip,
    this.active = false,
    this.child,
    this.childBuilder,
    this.modelIcon = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final bool active;
  final Widget? child;
  final Widget Function(Color color)? childBuilder;
  final bool modelIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Active state shows primary color, inactive shows default muted color
    final fgColor = active
        ? theme.colorScheme.primary
        : (isDark ? Colors.white70 : Colors.black54);

    // Keep overall button size constant. For model icon with child, enlarge child slightly
    // and reduce padding so (2*padding + childSize) stays unchanged.
    final bool isModelChild = modelIcon && child != null;
    final double iconSize = 20.0; // default glyph size
    final double childSize = isModelChild ? 28.0 : iconSize; // enlarge circle a bit more
    final double padding = isModelChild ? 1.0 : 6.0; // keep total ~30px (2*1 + 28)

    final button = IosIconButton(
      size: isModelChild ? childSize : 20,
      padding: EdgeInsets.all(padding),
      onTap: onTap,
      onLongPress: onLongPress,
      color: fgColor,
      builder: childBuilder != null
          ? (c) => SizedBox(width: childSize, height: childSize, child: childBuilder!(c))
          : (child != null
              ? (_) => SizedBox(width: childSize, height: childSize, child: child)
              : null),
      icon: child == null && childBuilder == null ? icon : null,
    );

    return tooltip == null ? button : Semantics(tooltip: tooltip!, child: button);
  }
}

// Keep original button for compatibility if needed elsewhere
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    this.onTap,
    this.tooltip,
    this.active = false,
    this.child,
    this.padding,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool active;
  final Widget? child;
  final double? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = active ? theme.colorScheme.primary.withOpacity(0.12) : Colors.transparent;
    final fgColor = active ? theme.colorScheme.primary : (isDark ? Colors.white : Colors.black87);

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: const ShapeDecoration(shape: CircleBorder()),
      child: Material(
        color: bgColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(padding ?? 10),
            child: child ?? Icon(icon, size: 22, color: fgColor),
          ),
        ),
      ),
    );

    // Avoid Material Tooltip's ticker conflicts on some platforms; use semantics-only tooltip
    return tooltip == null ? button : Semantics(tooltip: tooltip!, child: button);
  }
}

// New compact send button for the integrated input bar
class _CompactSendButton extends StatelessWidget {
  const _CompactSendButton({
    required this.enabled,
    required this.onSend,
    required this.color,
    required this.icon,
    this.loading = false,
    this.onStop,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = (enabled || loading) ? color : (isDark ? Colors.white12 : Colors.grey.shade300.withOpacity(0.84));
    final fg = (enabled || loading) ? (isDark ? Colors.black : Colors.white) : (isDark ? Colors.white70 : Colors.grey.shade600);

    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: loading ? onStop : (enabled ? onSend : null),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
            child: loading
                ? SvgPicture.asset(
                    key: const ValueKey('stop'),
                    'assets/icons/stop.svg',
                    width: 18,
                    height: 18,
                    colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                  )
                : Icon(icon, key: const ValueKey('send'), size: 18, color: fg),
          ),
        ),
      ),
    );
  }
}

// Keep original button for compatibility if needed elsewhere
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.onSend,
    required this.color,
    required this.icon,
    this.loading = false,
    this.onStop,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = (enabled || loading) ? color : (isDark ? Colors.white12 : Colors.grey.shade300);
    final fg = (enabled || loading) ? (isDark ? Colors.black : Colors.white) : (isDark ? Colors.white70 : Colors.grey.shade600);

    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: loading ? onStop : (enabled ? onSend : null),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
            child: loading
                ? SvgPicture.asset(
                    key: const ValueKey('stop'),
                    'assets/icons/stop.svg',
                    width: 22,
                    height: 22,
                    colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                  )
                : Icon(icon, key: const ValueKey('send'), size: 22, color: fg),
          ),
        ),
      ),
    );
  }
}

// Helper function to detect Grok models with robust checking
bool _isGrokModel(ProviderConfig cfg, String modelId) {
  // Check logical model ID
  final logicalModel = modelId.toLowerCase();

  // Check API model ID (if different from logical ID)
  String apiModel = logicalModel;
  try {
    final ov = cfg.modelOverrides[modelId];
    if (ov is Map<String, dynamic>) {
      final raw = (ov['apiModelId'] ?? ov['api_model_id'])?.toString().trim();
      if (raw != null && raw.isNotEmpty) {
        apiModel = raw.toLowerCase();
      }
    }
  } catch (_) {}

  // Check common Grok model name patterns
  final grokPatterns = ['grok', 'xai-'];
  for (final pattern in grokPatterns) {
    if (apiModel.contains(pattern) || logicalModel.contains(pattern)) {
      return true;
    }
  }

  return false;
}

/// Reasoning button with color-coded effort level indicator
class _ReasoningButton extends StatelessWidget {
  const _ReasoningButton({
    required this.thinkingBudget,
    required this.active,
    this.onTap,
  });

  final int? thinkingBudget;
  final bool active;
  final VoidCallback? onTap;

  /// Get effort level from budget value
  /// Supports both new effort level constants (-10, -20, -30, -40) and legacy positive values
  String _effortForBudget(int? budget) {
    if (budget == null || budget == -1) return 'auto';
    if (budget == 0) return 'off';
    // Handle effort level constants
    if (budget == -10) return 'minimal';
    if (budget == -20) return 'low';
    if (budget == -30) return 'medium';
    if (budget == -40) return 'high';
    // Handle legacy positive values (backward compatibility)
    if (budget < 4096) return 'low';
    if (budget < 16384) return 'medium';
    return 'high';
  }

  /// Get color for effort level
  Color _colorForEffort(String effort) {
    switch (effort) {
      case 'auto': return Colors.blue;
      case 'off': return Colors.grey;
      case 'minimal': return Colors.teal;
      case 'low': return Colors.green;
      case 'medium': return Colors.orange;
      case 'high': return Colors.red;
      default: return Colors.grey;
    }
  }

  /// Get short label for effort level
  String _labelForEffort(String effort) {
    switch (effort) {
      case 'auto': return 'A';
      case 'off': return '';
      case 'minimal': return 'm';
      case 'low': return 'L';
      case 'medium': return 'M';
      case 'high': return 'H';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effort = _effortForBudget(thinkingBudget);
    final effortColor = _colorForEffort(effort);
    final label = _labelForEffort(effort);

    // Inactive (off) uses default muted color, active uses effort-specific color
    final fgColor = active ? effortColor : (isDark ? Colors.white38 : Colors.black26);

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/icons/deepthink.svg',
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(fgColor, BlendMode.srcIn),
          ),
          if (active && label.isNotEmpty) ...[
            const SizedBox(width: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: effortColor.withOpacity(isDark ? 0.25 : 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: effortColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
