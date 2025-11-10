import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons/lucide_adapter.dart';
import '../l10n/app_localizations.dart';
import '../core/providers/mcp_provider.dart';
import '../core/providers/assistant_provider.dart';
import 'desktop_popover.dart';

/// Show desktop MCP servers selection popover
Future<void> showDesktopMcpServersPopover(
  BuildContext context, {
  required GlobalKey anchorKey,
  required String assistantId,
}) async {
  await showDesktopPopover(
    context,
    anchorKey: anchorKey,
    child: _McpServersContent(assistantId: assistantId),
    maxHeight: 520,
  );
}

class _McpServersContent extends StatelessWidget {
  const _McpServersContent({required this.assistantId});
  final String assistantId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final mcp = context.watch<McpProvider>();
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(assistantId);

    if (a == null) {
      return const SizedBox.shrink();
    }

    final selected = a.mcpServerIds.toSet();
    final servers = mcp.servers
        .where((s) => mcp.statusFor(s.id) == McpStatus.connected)
        .toList();

    final rows = <Widget>[];

    // Clear all option
    rows.add(_RowItem(
      leading: Icon(Lucide.CircleX, size: 16, color: cs.onSurface),
      label: l10n.assistantEditClearButton,
      toolCount: null,
      selected: false,
      onTap: () async {
        await context.read<AssistantProvider>().updateAssistant(
          a.copyWith(mcpServerIds: const <String>[]),
        );
      },
    ));

    // Server list with tool counts
    for (final s in servers) {
      final isSelected = selected.contains(s.id);
      final tools = s.tools;
      final enabledTools = tools.where((t) => t.enabled).length;
      final toolCountText = '$enabledTools/${tools.length}';

      rows.add(_RowItem(
        leading: Icon(
          Lucide.Hammer,
          size: 16,
          color: isSelected ? cs.primary : cs.onSurface,
        ),
        label: s.name,
        toolCount: toolCountText,
        selected: isSelected,
        onTap: () async {
          final set = a.mcpServerIds.toSet();
          if (isSelected) {
            set.remove(s.id);
          } else {
            set.add(s.id);
          }
          await context.read<AssistantProvider>().updateAssistant(
            a.copyWith(mcpServerIds: set.toList()),
          );
        },
      ));
    }

    if (servers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            l10n.assistantEditMcpNoServersMessage,
            style: TextStyle(
              color: cs.onSurface.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...rows.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: w,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowItem extends StatefulWidget {
  const _RowItem({
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
    this.toolCount,
  });

  final Widget leading;
  final String label;
  final String? toolCount;
  final bool selected;
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
    final onColor = widget.selected ? cs.primary : cs.onSurface;
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
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : baseBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Center(child: widget.leading),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ).copyWith(color: onColor),
                ),
              ),
              // Tool count badge
              if (widget.toolCount != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: cs.primary.withOpacity(0.35),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    widget.toolCount!,
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: widget.selected
                    ? Icon(
                        Lucide.Check,
                        key: const ValueKey('check'),
                        size: 16,
                        color: cs.primary,
                      )
                    : const SizedBox(
                        width: 16,
                        key: ValueKey('space'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
