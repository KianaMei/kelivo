import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/chat_message.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/markdown_with_highlight.dart';

/// LobeChat-style mini rail navigation displayed on the right side of chat.
/// Shows a vertical bar for each message, width proportional to content length.
/// Clicking a bar scrolls to that message.
class ChatMiniRail extends StatefulWidget {
  const ChatMiniRail({
    super.key,
    required this.messages,
    required this.onJumpToMessage,
    this.activeMessageId,
    this.minMessages = 4,
  });

  /// List of messages to display indicators for
  final List<ChatMessage> messages;

  /// Callback when user clicks an indicator to jump to a message
  final ValueChanged<String> onJumpToMessage;

  /// Currently visible/active message ID (for highlighting)
  final String? activeMessageId;

  /// Minimum number of messages required to show the rail
  final int minMessages;

  @override
  State<ChatMiniRail> createState() => _ChatMiniRailState();
}

class _ChatMiniRailState extends State<ChatMiniRail> {
  static const double _minIndicatorWidth = 14;
  static const double _maxIndicatorWidth = 28;
  static const int _maxContentLength = 320;

  double _getIndicatorWidth(String? content) {
    if (content == null || content.isEmpty) return _minIndicatorWidth;
    final ratio = math.min(content.length / _maxContentLength, 1.0);
    return _minIndicatorWidth + (_maxIndicatorWidth - _minIndicatorWidth) * ratio;
  }

  String _getPreviewText(String? content) {
    if (content == null || content.isEmpty) return '';
    // Remove think blocks and inline markers, keep line breaks for markdown
    var text = content
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[image:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[file:[^\]]+\]'), '')
        .trim();
    // Collapse multiple blank lines but keep single line breaks
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    if (text.length > 200) {
      text = '${text.substring(0, 200)}…';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    // Only show if we have enough messages
    if (widget.messages.length < widget.minMessages) {
      return const SizedBox.shrink();
    }

    // Filter to user and assistant messages only
    final indicators = widget.messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .toList();

    if (indicators.length < widget.minMessages) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;

    // Calculate max height for indicators (limit to ~60% of screen)
    final screenHeight = MediaQuery.of(context).size.height;
    final maxIndicatorHeight = screenHeight * 0.5;

    return Positioned(
      right: 6,
      top: 0,
      bottom: 0,
      child: Center(
        child: SizedBox(
          width: 32,
          // Only indicators, no arrow buttons (navigation handled by ScrollNavButtonsPanel)
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxIndicatorHeight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final msg in indicators)
                    _IndicatorBar(
                      key: ValueKey(msg.id),
                      width: _getIndicatorWidth(msg.content),
                      isActive: msg.id == widget.activeMessageId,
                      isUser: msg.role == 'user',
                      preview: _getPreviewText(msg.content),
                      roleLabel: msg.role == 'user' ? l10n.miniRailSenderUser : l10n.miniRailSenderAssistant,
                      onTap: () => widget.onJumpToMessage(msg.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IndicatorBar extends StatefulWidget {
  const _IndicatorBar({
    super.key,
    required this.width,
    required this.isActive,
    required this.isUser,
    required this.preview,
    required this.roleLabel,
    required this.onTap,
  });

  final double width;
  final bool isActive;
  final bool isUser;
  final String preview;
  final String roleLabel;
  final VoidCallback onTap;

  @override
  State<_IndicatorBar> createState() => _IndicatorBarState();
}

class _IndicatorBarState extends State<_IndicatorBar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final barColor = widget.isActive
        ? cs.primary
        : _hovered
            ? cs.onSurface.withOpacity(0.25)
            : cs.onSurface.withOpacity(0.12);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: _CompactTooltip(
        roleLabel: widget.roleLabel,
        preview: widget.preview,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: widget.width,
              height: 10,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact tooltip that shows on the left side with limited width
class _CompactTooltip extends StatefulWidget {
  const _CompactTooltip({
    required this.roleLabel,
    required this.preview,
    required this.child,
  });

  final String roleLabel;
  final String preview;
  final Widget child;

  @override
  State<_CompactTooltip> createState() => _CompactTooltipState();
}

class _CompactTooltipState extends State<_CompactTooltip> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isHoveredOnTrigger = false;
  bool _isHoveredOnTooltip = false;

  void _showTooltip() {
    if (_overlayEntry != null || widget.preview.isEmpty) return;
    _overlayEntry = OverlayEntry(
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Positioned(
          width: 360,
          child: CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.centerLeft,
            followerAnchor: Alignment.centerRight,
            offset: const Offset(-8, 0),
            child: MouseRegion(
              onEnter: (_) {
                _isHoveredOnTooltip = true;
              },
              onExit: (_) {
                _isHoveredOnTooltip = false;
                _tryHideTooltip();
              },
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[850] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.roleLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                          const Spacer(),
                          // Copy button
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: widget.preview));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已复制'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.copy_rounded,
                                size: 12,
                                color: cs.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: SingleChildScrollView(
                          child: SelectionArea(
                            child: MarkdownWithCodeHighlight(
                              text: widget.preview,
                              baseStyle: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(0.8),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _tryHideTooltip() {
    // Delay to allow mouse to move to tooltip
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_isHoveredOnTrigger && !_isHoveredOnTooltip && mounted) {
        _hideTooltip();
      }
    });
  }

  void _hideTooltip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideTooltip();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          _isHoveredOnTrigger = true;
          Future.delayed(const Duration(milliseconds: 400), () {
            if (_isHoveredOnTrigger && mounted) _showTooltip();
          });
        },
        onExit: (_) {
          _isHoveredOnTrigger = false;
          _tryHideTooltip();
        },
        child: widget.child,
      ),
    );
  }
}
