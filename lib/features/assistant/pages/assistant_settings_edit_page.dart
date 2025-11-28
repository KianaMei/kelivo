import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../desktop/window_title_bar.dart';
import '../tabs/basic_settings_tab.dart';
import '../tabs/custom_request_tab.dart';
import '../tabs/mcp_tab.dart';
import '../tabs/memory_tab.dart';
import '../tabs/prompt_tab.dart';
import '../tabs/quick_phrase_tab.dart';
import '../widgets/seg_tab_bar.dart';
import '../widgets/tactile_widgets.dart';

class AssistantSettingsEditPage extends StatefulWidget {
  const AssistantSettingsEditPage({super.key, required this.assistantId});
  final String assistantId;

  @override
  State<AssistantSettingsEditPage> createState() => _AssistantSettingsEditPageState();
}

class _AssistantSettingsEditPageState extends State<AssistantSettingsEditPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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
            child: TactileIconButton(
              icon: Lucide.ArrowLeft,
              color: cs.onSurface,
              size: 22,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          title: Text(l10n.assistantEditPageTitle),
          actions: [
            if (defaultTargetPlatform == TargetPlatform.windows) const WindowCaptionActions(),
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
          child: TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(assistant.name.isNotEmpty ? assistant.name : l10n.assistantEditPageTitle),
        actions: [
          if (defaultTargetPlatform == TargetPlatform.windows) const WindowCaptionActions(),
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
        ],
      ),
    );
  }
}

/// Desktop dialog for assistant settings.
enum _AssistantDesktopMenu { basic, prompts, memory, mcp, quick, custom }

Future<void> showAssistantDesktopDialog(BuildContext context, {required String assistantId}) async {
  final cs = Theme.of(context).colorScheme;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: cs.surface,
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
    final l10n = AppLocalizations.of(context)!;
    
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.assistantEditPageTitle,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Lucide.X, size: 18),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.12)),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 200,
                child: ListView(
                  children: [
                    _menuItem(_AssistantDesktopMenu.basic, l10n.assistantEditPageBasicTab),
                    _menuItem(_AssistantDesktopMenu.prompts, l10n.assistantEditPagePromptsTab),
                    _menuItem(_AssistantDesktopMenu.memory, l10n.assistantEditPageMemoryTab),
                    _menuItem(_AssistantDesktopMenu.mcp, l10n.assistantEditPageMcpTab),
                    _menuItem(_AssistantDesktopMenu.quick, l10n.assistantEditPageQuickPhraseTab),
                    _menuItem(_AssistantDesktopMenu.custom, l10n.assistantEditPageCustomTab),
                  ],
                ),
              ),
              VerticalDivider(width: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.12)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _buildContent(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _menuItem(_AssistantDesktopMenu menu, String label) {
    final selected = _menu == menu;
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      selected: selected,
      title: Text(label),
      onTap: () => setState(() => _menu = menu),
      selectedTileColor: cs.primary.withOpacity(0.1),
    );
  }
  
  Widget _buildContent() {
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
    }
  }
}
