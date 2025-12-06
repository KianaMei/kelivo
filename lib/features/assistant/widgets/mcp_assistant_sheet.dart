import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/models/tool_call_mode.dart';
import '../../../core/services/tool_call_mode_store.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../core/services/haptics.dart';

Future<void> showAssistantMcpSheet(
  BuildContext context, {
  required String assistantId,
  void Function(ToolCallMode mode)? onToolModeChanged,
}) async {
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AssistantMcpSheet(
      assistantId: assistantId,
      onToolModeChanged: onToolModeChanged,
    ),
  );
}

class _AssistantMcpSheet extends StatefulWidget {
  const _AssistantMcpSheet({
    required this.assistantId,
    this.onToolModeChanged,
  });
  final String assistantId;
  final void Function(ToolCallMode mode)? onToolModeChanged;

  @override
  State<_AssistantMcpSheet> createState() => _AssistantMcpSheetState();
}

class _AssistantMcpSheetState extends State<_AssistantMcpSheet> {
  ToolCallMode _toolCallMode = ToolCallMode.native;
  bool _stickerSettingsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadToolCallMode();
  }

  Future<void> _loadToolCallMode() async {
    final mode = await ToolCallModeStore.getMode();
    if (mounted) setState(() => _toolCallMode = mode);
  }

  Future<void> _toggleToolCallMode() async {
    Haptics.light();
    final newMode = await ToolCallModeStore.toggleMode();
    if (mounted) {
      setState(() => _toolCallMode = newMode);
      // 实时通知父组件模式已更改
      widget.onToolModeChanged?.call(newMode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final mcp = context.watch<McpProvider>();
    final ap = context.watch<AssistantProvider>();
    final settings = context.watch<SettingsProvider>();
    final a = ap.getById(widget.assistantId)!;

    final selected = a.mcpServerIds.toSet();
    final servers = mcp.servers.where((s) => mcp.statusFor(s.id) == McpStatus.connected).toList();

    Widget tag(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.primary.withOpacity(0.35)),
          ),
          child: Text(text, style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w600)),
        );

    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    // Pinned section (Clear + Tool Mode + Sticker toggle) - compact horizontal layout
    Widget pinnedSection = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // First row: Clear all button
        Row(
          children: [
            Expanded(
              child: _CompactActionButton(
                icon: Lucide.CircleX,
                label: l10n.assistantEditClearButton,
                onTap: () async {
                  Haptics.light();
                  final next = a.copyWith(mcpServerIds: const <String>[]);
                  await context.read<AssistantProvider>().updateAssistant(next);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Second row: Tool call mode toggle + Sticker toggle
        Row(
          children: [
            // Tool call mode toggle (native/prompt)
            Expanded(
              child: Tooltip(
                message: _toolCallMode == ToolCallMode.prompt
                    ? l10n.toolModePromptDescription
                    : l10n.toolModeNativeDescription,
                child: _CompactToggleButton(
                  icon: _toolCallMode == ToolCallMode.prompt
                      ? Lucide.MessageSquareCode
                      : Lucide.Wrench,
                  label: _toolCallMode == ToolCallMode.prompt
                      ? l10n.toolModePrompt
                      : l10n.toolModeNative,
                  enabled: _toolCallMode == ToolCallMode.prompt,
                  onTap: _toggleToolCallMode,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Sticker tool toggle
            Expanded(
              child: _CompactToggleButton(
                icon: settings.stickerEnabled ? Lucide.Smile : Lucide.Frown,
                label: '表情包',
                enabled: settings.stickerEnabled,
                onTap: () {
                  Haptics.light();
                  context.read<SettingsProvider>().setStickerEnabled(!settings.stickerEnabled);
                },
              ),
            ),
            const SizedBox(width: 6),
            // Sticker settings button
            _CompactIconButton(
              icon: _stickerSettingsExpanded ? Lucide.ChevronUp : Lucide.Settings,
              onTap: () {
                Haptics.light();
                setState(() => _stickerSettingsExpanded = !_stickerSettingsExpanded);
              },
            ),
          ],
        ),
        // Expandable sticker settings section
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _stickerSettingsExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 显示工具调用卡片
                  _StickerSettingRow(
                    icon: Lucide.Eye,
                    label: '显示工具调用卡片',
                    value: settings.showStickerToolUI,
                    onChanged: (v) {
                      Haptics.light();
                      context.read<SettingsProvider>().setShowStickerToolUI(v);
                    },
                  ),
                  const SizedBox(height: 4),
                  // 表情包大小
                  _StickerSegmentRow(
                    icon: Lucide.Maximize2,
                    label: '表情包大小',
                    options: const ['小', '中', '大'],
                    selectedIndex: settings.stickerSize,
                    onChanged: (v) {
                      Haptics.light();
                      context.read<SettingsProvider>().setStickerSize(v);
                    },
                  ),
                  const SizedBox(height: 4),
                  // 表情包频率
                  _StickerSegmentRow(
                    icon: Lucide.Activity,
                    label: '使用频率',
                    options: const ['低', '中', '高'],
                    selectedIndex: settings.stickerFrequency,
                    onChanged: (v) {
                      Haptics.light();
                      context.read<SettingsProvider>().setStickerFrequency(v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        if (servers.isNotEmpty) ...[
          const SizedBox(height: 10),
          Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.3)),
          const SizedBox(height: 10),
        ],
      ],
    );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Text(
                        l10n.mcpAssistantSheetTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (servers.isNotEmpty) ...[
                      Positioned(
                        right: 0,
                        child: IosIconButton(
                          icon: Lucide.Check,
                          size: 18,
                          minSize: 34,
                          padding: const EdgeInsets.all(8),
                          onTap: () async {
                            Haptics.light();
                            final ids = servers.map((e) => e.id).toList(growable: false);
                            final next = a.copyWith(mcpServerIds: ids);
                            await context.read<AssistantProvider>().updateAssistant(next);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Pinned section (always visible)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: pinnedSection,
            ),
            // Scrollable server list
            if (servers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
                child: Center(
                  child: Text(
                    l10n.assistantEditMcpNoServersMessage,
                    style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                  ),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...servers.asMap().entries.map((entry) {
                        final index = entry.key;
                        final s = entry.value;
                        final tools = s.tools;
                        final enabledTools = tools.where((t) => t.enabled).length;
                        final isSelected = selected.contains(s.id);
                        return Padding(
                          padding: EdgeInsets.only(bottom: index < servers.length - 1 ? 10 : 0),
                          child: IosCardPress(
                            borderRadius: BorderRadius.circular(14),
                            baseColor: cs.surface,
                            duration: const Duration(milliseconds: 260),
                            onTap: () async {
                              Haptics.light();
                              final set = Set<String>.from(a.mcpServerIds);
                              if (isSelected) set.remove(s.id); else set.add(s.id);
                              await context.read<AssistantProvider>().updateAssistant(a.copyWith(mcpServerIds: set.toList()));
                            },
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(Lucide.Hammer, size: 18, color: cs.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    s.name,
                                    style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                tag(l10n.assistantEditMcpToolsCountTag(enabledTools.toString(), tools.length.toString())),
                                const SizedBox(width: 8),
                                IosSwitch(
                                  value: isSelected,
                                  onChanged: (v) async {
                                    final set = a.mcpServerIds.toSet();
                                    if (v) set.add(s.id); else set.remove(s.id);
                                    await context.read<AssistantProvider>().updateAssistant(a.copyWith(mcpServerIds: set.toList()));
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
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


/// Compact action button for mobile (e.g., Clear)
class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: cs.onSurface.withOpacity(0.7)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact toggle button with active state for mobile (e.g., Sticker)
class _CompactToggleButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color bg;
    final Color iconColor;
    final Color textColor;
    
    if (enabled) {
      // Enabled state: use primary color
      bg = cs.primary.withOpacity(isDark ? 0.15 : 0.12);
      iconColor = cs.primary;
      textColor = cs.primary;
    } else {
      // Disabled state: default muted style
      bg = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05);
      iconColor = cs.onSurface.withOpacity(0.7);
      textColor = cs.onSurface.withOpacity(0.8);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          // No border highlight for enabled state
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact icon-only button for mobile
class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.7)),
        ),
      ),
    );
  }
}

/// Compact setting row with icon, label and switch for mobile
class _StickerSettingRow extends StatelessWidget {
  const _StickerSettingRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurface.withOpacity(0.6)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withOpacity(0.85),
              ),
            ),
          ),
          IosSwitch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Compact setting row with icon, label and segmented buttons for mobile
class _StickerSegmentRow extends StatelessWidget {
  const _StickerSegmentRow({
    required this.icon,
    required this.label,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurface.withOpacity(0.6)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withOpacity(0.85),
              ),
            ),
          ),
          // Segmented buttons
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(options.length, (i) {
                final isSelected = i == selectedIndex;
                return GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cs.primary.withOpacity(isDark ? 0.25 : 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      options[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? cs.primary : cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
