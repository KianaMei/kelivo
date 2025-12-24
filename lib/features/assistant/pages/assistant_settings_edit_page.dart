import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../desktop/window_title_bar.dart';
import '../../../core/services/haptics.dart';
// Modular tabs
import '../tabs/basic_settings_tab.dart';
import '../tabs/prompt_tab.dart';
import '../tabs/memory_tab.dart';
import '../tabs/mcp_tab.dart';
import '../tabs/custom_request_tab.dart';
import '../tabs/quick_phrase_tab.dart';
import '../tabs/assistant_regex_tab.dart';
import '../widgets/seg_tab_bar.dart';

class AssistantSettingsEditPage extends StatefulWidget {
  const AssistantSettingsEditPage({super.key, required this.assistantId});
  final String assistantId;

  @override
  State<AssistantSettingsEditPage> createState() =>
      _AssistantSettingsEditPageState();
}

class _AssistantSettingsEditPageState extends State<AssistantSettingsEditPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<AssistantProvider>();
    final assistant = provider.getById(widget.assistantId);

    if (assistant == null) {
      return Scaffold(
        appBar: AppBar(
          leading: Tooltip(
            message: l10n.settingsPageBackButton,
            child: _TactileIconButton(
              icon: Lucide.ArrowLeft,
              color: cs.onSurface,
              size: 22,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          title: Text(l10n.assistantEditPageTitle),
          actions: [
            if (defaultTargetPlatform == TargetPlatform.windows)
              const WindowCaptionActions(),
            const SizedBox(width: 12),
          ],
        ),
        body: Center(child: Text(l10n.assistantEditPageNotFound)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(
          assistant.name.isNotEmpty
              ? assistant.name
              : l10n.assistantEditPageTitle,
        ),
        actions: [
          if (defaultTargetPlatform == TargetPlatform.windows)
            const WindowCaptionActions(),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegTabBar(
              controller: _tabController,
              tabs: [
                l10n.assistantEditPageBasicTab,
                l10n.assistantEditPagePromptsTab,
                l10n.assistantEditPageMemoryTab,
                l10n.assistantEditPageQuickPhraseTab,
                l10n.assistantEditPageCustomTab,
                l10n.assistantEditPageRegexTab,
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          BasicSettingsTab(assistantId: assistant.id),
          PromptTab(assistantId: assistant.id),
          MemoryTab(assistantId: assistant.id),
          QuickPhraseTab(assistantId: assistant.id),
          CustomRequestTab(assistantId: assistant.id),
          AssistantRegexTab(assistantId: assistant.id),
        ],
      ),
    );
  }
}

// ===== TactileIconButton (used by AppBar leading) =====

class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final pressColor = base.withValues(alpha: 0.7);
    final icon = Icon(
      widget.icon,
      size: widget.size,
      color: _pressed ? pressColor : base,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: icon,
      ),
    );
  }
}

// ===== Desktop Assistant Dialog =====

enum _AssistantDesktopMenu { basic, prompts, memory, mcp, quick, custom, regex }

/// Show assistant edit dialog for desktop platforms
Future<void> showAssistantDesktopDialog(BuildContext context, {required String assistantId}) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 640),
          child: _DesktopAssistantDialogShell(assistantId: assistantId),
        ),
      );
    },
  );
}

class _DesktopAssistantDialogShell extends StatefulWidget {
  const _DesktopAssistantDialogShell({required this.assistantId});
  final String assistantId;
  @override
  State<_DesktopAssistantDialogShell> createState() => _DesktopAssistantDialogShellState();
}

class _DesktopAssistantDialogShellState extends State<_DesktopAssistantDialogShell> {
  _AssistantDesktopMenu _menu = _AssistantDesktopMenu.basic;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = context.watch<AssistantProvider>().getById(widget.assistantId);
    final name = a?.name ?? AppLocalizations.of(context)!.assistantEditPageTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Lucide.X, size: 18),
                  color: cs.onSurface,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withValues(alpha: 0.12)),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DesktopAssistantMenu(
                selected: _menu,
                onSelect: (m) => setState(() => _menu = m),
              ),
              VerticalDivider(width: 1, thickness: 0.5, color: cs.outlineVariant.withValues(alpha: 0.12)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  child: () {
                    switch (_menu) {
                      case _AssistantDesktopMenu.basic:
                        return BasicSettingsTab(assistantId: widget.assistantId);
                      case _AssistantDesktopMenu.prompts:
                        return PromptTab(assistantId: widget.assistantId);
                      case _AssistantDesktopMenu.memory:
                        return MemoryTab(assistantId: widget.assistantId);
                      case _AssistantDesktopMenu.mcp:
                        return McpTab(assistantId: widget.assistantId);
                      case _AssistantDesktopMenu.quick:
                        return QuickPhraseTab(assistantId: widget.assistantId);
                      case _AssistantDesktopMenu.custom:
                        return CustomRequestTab(assistantId: widget.assistantId);
                      case _AssistantDesktopMenu.regex:
                        return AssistantRegexDesktopPane(assistantId: widget.assistantId);
                    }
                  }(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopAssistantMenu extends StatefulWidget {
  const _DesktopAssistantMenu({required this.selected, required this.onSelect});
  final _AssistantDesktopMenu selected;
  final ValueChanged<_AssistantDesktopMenu> onSelect;
  @override
  State<_DesktopAssistantMenu> createState() => _DesktopAssistantMenuState();
}

class _DesktopAssistantMenuState extends State<_DesktopAssistantMenu> {
  int _hover = -1;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = <(_AssistantDesktopMenu, String)>[
      (_AssistantDesktopMenu.basic, l10n.assistantEditPageBasicTab),
      (_AssistantDesktopMenu.prompts, l10n.assistantEditPagePromptsTab),
      (_AssistantDesktopMenu.memory, l10n.assistantEditPageMemoryTab),
      (_AssistantDesktopMenu.mcp, l10n.assistantEditPageMcpTab),
      (_AssistantDesktopMenu.quick, l10n.assistantEditPageQuickPhraseTab),
      (_AssistantDesktopMenu.custom, l10n.assistantEditPageCustomTab),
      (_AssistantDesktopMenu.regex, l10n.assistantEditPageRegexTab),
    ];
    return SizedBox(
      width: 220,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final selected = widget.selected == items[i].$1;
          final bg = selected
              ? cs.primary.withValues(alpha: 0.10)
              : (_hover == i
                  ? (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04))
                  : Colors.transparent);
          final fg = selected ? cs.primary : cs.onSurface.withValues(alpha: 0.9);
          return MouseRegion(
            onEnter: (_) => setState(() => _hover = i),
            onExit: (_) => setState(() => _hover = -1),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => widget.onSelect(items[i].$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    items[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, color: fg, decoration: TextDecoration.none),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
