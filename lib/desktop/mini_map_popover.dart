import 'dart:async';
import 'package:flutter/material.dart';

import '../core/models/chat_message.dart';
import 'desktop_popover.dart';

/// Show desktop mini map popover to quickly navigate message history
Future<String?> showDesktopMiniMapPopover(
  BuildContext context, {
  required GlobalKey anchorKey,
  required List<ChatMessage> messages,
}) async {
  if (messages.isEmpty) return null;

  final completer = Completer<String?>();

  // Get close callback
  final closePopover = await showDesktopPopover(
    context,
    anchorKey: anchorKey,
    child: _MiniMapContent(
      messages: messages,
      onSelect: (id) {
        if (!completer.isCompleted) {
          completer.complete(id);
        }
      },
    ),
    maxHeight: 520,
  );

  // When selection is made, close popover
  completer.future.then((result) {
    if (result != null) {
      closePopover();
    }
  });

  return completer.future;
}

class _MiniMapContent extends StatelessWidget {
  const _MiniMapContent({
    required this.messages,
    required this.onSelect,
  });

  final List<ChatMessage> messages;
  final ValueChanged<String> onSelect;

  String _oneLine(String s) {
    var t = s
        .replaceAll(RegExp(r'<think>[\s\S]*?<\/think>', caseSensitive: false), '')
        .replaceAll(RegExp(r"\[image:[^\]]+\]"), "")
        .replaceAll(RegExp(r"\[file:[^\]]+\]"), "")
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t;
  }

  List<_QaPair> _buildPairs(List<ChatMessage> items) {
    final pairs = <_QaPair>[];
    ChatMessage? pendingUser;
    for (final m in items) {
      if (m.role == 'user') {
        if (pendingUser != null) {
          pairs.add(_QaPair(user: pendingUser, assistant: null));
        }
        pendingUser = m;
      } else if (m.role == 'assistant') {
        if (pendingUser != null) {
          pairs.add(_QaPair(user: pendingUser, assistant: m));
          pendingUser = null;
        } else {
          pairs.add(_QaPair(user: null, assistant: m));
        }
      }
    }
    if (pendingUser != null) {
      pairs.add(_QaPair(user: pendingUser, assistant: null));
    }
    return pairs;
  }

  @override
  Widget build(BuildContext context) {
    final pairs = _buildPairs(messages);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          primary: false,
          shrinkWrap: true,
          itemCount: pairs.length,
          itemBuilder: (context, index) {
            final p = pairs[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _MiniMapRow(
                user: p.user,
                assistant: p.assistant,
                toOneLine: _oneLine,
                onSelect: onSelect,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QaPair {
  final ChatMessage? user;
  final ChatMessage? assistant;
  _QaPair({required this.user, required this.assistant});
}

class _MiniMapRow extends StatefulWidget {
  const _MiniMapRow({
    required this.user,
    required this.assistant,
    required this.toOneLine,
    required this.onSelect,
  });

  final ChatMessage? user;
  final ChatMessage? assistant;
  final String Function(String) toOneLine;
  final ValueChanged<String> onSelect;

  @override
  State<_MiniMapRow> createState() => _MiniMapRowState();
}

class _MiniMapRowState extends State<_MiniMapRow> {
  bool _hoverUser = false;
  bool _hoverAssistant = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userText = widget.user?.content ?? '';
    final asstText = widget.assistant?.content ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // User bubble (right-aligned)
        if (userText.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hoverUser = true),
              onExit: (_) => setState(() => _hoverUser = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.user != null
                    ? () => widget.onSelect(widget.user!.id)
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(
                      _hoverUser ? (isDark ? 0.22 : 0.14) : (isDark ? 0.15 : 0.08),
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    widget.toOneLine(userText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: cs.onSurface,
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
            ),
          ),

        if (userText.isNotEmpty && asstText.isNotEmpty)
          const SizedBox(height: 6),

        // Assistant line (left-aligned)
        if (asstText.isNotEmpty)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hoverAssistant = true),
            onExit: (_) => setState(() => _hoverAssistant = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.assistant != null
                  ? () => widget.onSelect(widget.assistant!.id)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: _hoverAssistant
                      ? cs.onSurface.withOpacity(0.05)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.toOneLine(asstText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
