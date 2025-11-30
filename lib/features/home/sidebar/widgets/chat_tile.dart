import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';
import '../../../../core/services/chat/chat_service.dart';
import '../../../../core/models/chat_item.dart';
import '../../../../core/models/chat_message.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/count_badge.dart';

/// Single conversation tile in the sidebar list
class ChatTile extends StatefulWidget {
  const ChatTile({
    super.key,
    required this.chat,
    required this.textColor,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.selected = false,
    this.loading = false,
    this.embedded = false,
  });

  final ChatItem chat;
  final Color textColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(Offset globalPosition)? onSecondaryTap;
  final bool selected;
  final bool loading;
  final bool embedded;

  @override
  State<ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends State<ChatTile> {
  bool _hovered = false;
  bool get _isDesktop => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Count assistant messages for this conversation
    final assistantCount = context.select<ChatService, int>((svc) {
      final cid = widget.chat.id;
      final msgs = svc.getMessages(cid);
      if (msgs.isEmpty) return 0;

      final Map<String, List<ChatMessage>> byGroup = <String, List<ChatMessage>>{};
      final List<String> order = <String>[];
      for (final m in msgs) {
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

      final sel = svc.getVersionSelections(cid);
      int n = 0;
      for (final gid in order) {
        final vers = byGroup[gid]!;
        int idx = sel[gid] ?? (vers.length - 1);
        if (idx < 0 || idx >= vers.length) idx = vers.length - 1;
        final chosen = vers[idx];
        if (chosen.role == 'assistant') n++;
      }
      return n;
    });
    final embedded = widget.embedded;
    final Color tileColor;
    if (embedded) {
      // In tablet embedded mode, keep selected highlight, others transparent
      tileColor = widget.selected ? cs.primary.withOpacity(0.16) : Colors.transparent;
    } else {
      tileColor = widget.selected ? cs.primary.withOpacity(0.12) : cs.surface;
    }
    final base = _isDesktop && !widget.selected && _hovered
        ? (embedded ? cs.primary.withOpacity(0.08) : cs.surface.withOpacity(0.9))
        : tileColor;
    final double vGap = _isDesktop ? 4 : 4;
    return Padding(
      padding: EdgeInsets.only(bottom: vGap),
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          if (_isDesktop) {
            widget.onSecondaryTap?.call(details.globalPosition);
          }
        },
        onLongPress: () {
          if (_isDesktop) return;
          widget.onLongPress?.call();
        },
        child: MouseRegion(
          onEnter: (_) { if (_isDesktop) setState(() => _hovered = true); },
          onExit: (_) { if (_isDesktop) setState(() => _hovered = false); },
          cursor: _isDesktop ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: IosCardPress(
          baseColor: base,
          borderRadius: BorderRadius.circular(16),
          haptics: false,
          onTap: widget.onTap,
          onLongPress: _isDesktop ? null : widget.onLongPress,
          padding: EdgeInsets.fromLTRB(_isDesktop ? 14 : 14, _isDesktop ? 9 : 10, 8, _isDesktop ? 9 : 10),
          child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: _isDesktop ? 14 : 15,
                      color: widget.textColor,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (assistantCount > 0) ...[
                  const SizedBox(width: 8),
                  CountBadge(count: assistantCount, selected: widget.selected),
                ],
                if (widget.loading) ...[
                  const SizedBox(width: 8),
                  const LoadingDot(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
