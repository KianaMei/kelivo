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
