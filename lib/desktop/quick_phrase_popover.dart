import 'dart:async';
import 'package:flutter/material.dart';

import '../core/models/quick_phrase.dart';
import '../icons/lucide_adapter.dart';
import 'desktop_popover.dart';

/// Show desktop quick phrase selection popover
Future<QuickPhrase?> showDesktopQuickPhrasePopover(
  BuildContext context, {
  required GlobalKey anchorKey,
  required List<QuickPhrase> phrases,
}) async {
  final completer = Completer<QuickPhrase?>();

  // Get close callback
  final closePopover = await showDesktopPopover(
    context,
    anchorKey: anchorKey,
    child: _QuickPhraseContent(
      phrases: phrases,
      onSelect: (p) {
        if (!completer.isCompleted) {
          completer.complete(p);
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

class _QuickPhraseContent extends StatelessWidget {
  const _QuickPhraseContent({
    required this.phrases,
    required this.onSelect,
  });

  final List<QuickPhrase> phrases;
  final ValueChanged<QuickPhrase> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (phrases.isEmpty) {
      // Show empty state
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Lucide.Zap,
              size: 48,
              color: cs.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无快捷短语',
              style: TextStyle(
                color: cs.onSurface.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          shrinkWrap: true,
          itemCount: phrases.length,
          itemBuilder: (context, index) {
            final p = phrases[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: _RowItem(
                title: p.title,
                preview: p.content,
                isGlobal: p.isGlobal,
                onTap: () => onSelect(p),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RowItem extends StatefulWidget {
  const _RowItem({
    required this.title,
    required this.preview,
    required this.isGlobal,
    required this.onTap,
  });

  final String title;
  final String preview;
  final bool isGlobal;
  final VoidCallback onTap;

  @override
  State<_RowItem> createState() => _RowItemState();
}

class _RowItemState extends State<_RowItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final baseBg = Colors.transparent;
    final hoverBg = (isDark ? Colors.white : Colors.black)
        .withOpacity(isDark ? 0.12 : 0.10);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : baseBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Icon based on scope
              Icon(
                widget.isGlobal ? Lucide.Zap : Lucide.botMessageSquare,
                size: 16,
                color: cs.primary.withOpacity(0.8),
              ),
              const SizedBox(width: 8),

              // Title
              Expanded(
                flex: 1,
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Content preview
              Expanded(
                flex: 1,
                child: Text(
                  widget.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: cs.onSurface.withOpacity(0.70),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
