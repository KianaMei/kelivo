import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons/lucide_adapter.dart';
import '../l10n/app_localizations.dart';
import '../core/providers/mcp_provider.dart';
import '../core/providers/assistant_provider.dart';
import '../core/providers/settings_provider.dart';
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

    final settings = context.watch<SettingsProvider>();
    final serverRows = <Widget>[];

    // Server list with tool counts
    for (final s in servers) {
      final isSelected = selected.contains(s.id);
      final tools = s.tools;
      final enabledTools = tools.where((t) => t.enabled).length;
      final toolCountText = '$enabledTools/${tools.length}';

      serverRows.add(_RowItem(
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

    // Pinned section (Clear + Sticker toggle) - compact horizontal layout
    Widget pinnedSection = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Horizontal row with Clear and Sticker toggle
          Row(
            children: [
              // Clear all button
              Expanded(
                child: _CompactActionButton(
                  icon: Lucide.CircleX,
                  label: l10n.assistantEditClearButton,
                  onTap: () async {
                    await context.read<AssistantProvider>().updateAssistant(
                      a.copyWith(mcpServerIds: const <String>[]),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Sticker tool toggle
              Expanded(
                child: _CompactToggleButton(
                  icon: Lucide.Smile,
                  label: '表情包',
                  enabled: settings.stickerEnabled,
                  onTap: () => context.read<SettingsProvider>().setStickerEnabled(!settings.stickerEnabled),
                ),
              ),
            ],
          ),
          if (servers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.3)),
          ],
        ],
      ),
    );

    if (servers.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pinnedSection,
          Padding(
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
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pinned section (always visible)
            pinnedSection,
            // Scrollable server list
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...serverRows.map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: w,
                    )),
                  ],
                ),
              ),
            ),
          ],
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

/// Compact action button (e.g., Clear)
class _CompactActionButton extends StatefulWidget {
  const _CompactActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_CompactActionButton> createState() => _CompactActionButtonState();
}

class _CompactActionButtonState extends State<_CompactActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final baseBg = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04);
    final hoverBg = isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : baseBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: cs.onSurface.withOpacity(0.7)),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface.withOpacity(0.8),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact toggle button with active state (e.g., Sticker)
class _CompactToggleButton extends StatefulWidget {
  const _CompactToggleButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_CompactToggleButton> createState() => _CompactToggleButtonState();
}

class _CompactToggleButtonState extends State<_CompactToggleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    final Color baseBg;
    final Color hoverBg;
    final Color iconColor;
    final Color textColor;
    
    if (widget.enabled) {
      baseBg = cs.primary.withOpacity(0.15);
      hoverBg = cs.primary.withOpacity(0.25);
      iconColor = cs.primary;
      textColor = cs.primary;
    } else {
      baseBg = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04);
      hoverBg = isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08);
      iconColor = cs.onSurface.withOpacity(0.7);
      textColor = cs.onSurface.withOpacity(0.8);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : baseBg,
            borderRadius: BorderRadius.circular(10),
            border: widget.enabled ? Border.all(color: cs.primary.withOpacity(0.3), width: 1) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
