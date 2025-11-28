import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../model/widgets/model_select_sheet.dart';
import '../widgets/tactile_widgets.dart';

/// Basic settings tab - MVP version with core functionality.
/// 
/// ✅ Implemented: Name input, Model selection
/// 🚧 TODO: Avatar picker, Temperature/TopP/MaxTokens sliders, Background preview
/// 📝 Full implementation: ~2600 lines in original file (lines 894-3517)
class BasicSettingsTab extends StatefulWidget {
  const BasicSettingsTab({super.key, required this.assistantId});
  
  final String assistantId;

  @override
  State<BasicSettingsTab> createState() => _BasicSettingsTabState();
}

class _BasicSettingsTabState extends State<BasicSettingsTab> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final ap = context.read<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;
    _nameCtrl = TextEditingController(text: a.name);
  }

  @override
  void didUpdateWidget(covariant BasicSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assistantId != widget.assistantId) {
      final ap = context.read<AssistantProvider>();
      final a = ap.getById(widget.assistantId)!;
      _nameCtrl.text = a.name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;
    final settings = context.read<SettingsProvider>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Name input
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06), width: 0.6),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.assistantEditAssistantNameLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  hintText: l10n.assistantEditAssistantNameHint,
                  filled: true,
                  fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (v) => ap.updateAssistant(a.copyWith(name: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Model selection card
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06), width: 0.6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Lucide.MessageCircle, size: 18, color: cs.onSurface),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l10n.assistantEditChatModelTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(l10n.assistantEditChatModelSubtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                const SizedBox(height: 8),
                TactileRow(
                  onTap: () async {
                    final sel = await showModelSelector(context);
                    if (sel != null) {
                      await ap.updateAssistant(a.copyWith(chatModelProvider: sel.providerKey, chatModelId: sel.modelId));
                    }
                  },
                  pressedScale: 0.98,
                  builder: (pressed) {
                    final bg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
                    final overlay = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);
                    final pressedBg = Color.alphaBlend(overlay, bg);
                    
                    String display = l10n.assistantEditModelUseGlobalDefault;
                    if (a.chatModelProvider != null && a.chatModelId != null) {
                      try {
                        final cfg = settings.getProviderConfig(a.chatModelProvider!);
                        final ov = cfg.modelOverrides[a.chatModelId] as Map?;
                        display = (ov != null && (ov['name'] as String?)?.isNotEmpty == true) ? (ov['name'] as String) : a.chatModelId!;
                      } catch (_) {
                        display = a.chatModelId ?? '';
                      }
                    }
                    
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: pressed ? pressedBg : bg, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Icon(Lucide.Bot, size: 20, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                          Icon(Lucide.ChevronRight, size: 16, color: cs.onSurface.withOpacity(0.4)),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Settings switches
        iosSectionCard(
          children: [
            iosSwitchRow(
              context,
              icon: Lucide.User,
              label: l10n.assistantEditUseAssistantAvatarTitle,
              value: a.useAssistantAvatar,
              onChanged: (v) => ap.updateAssistant(a.copyWith(useAssistantAvatar: v)),
            ),
            iosDivider(context),
            iosSwitchRow(
              context,
              icon: Lucide.Zap,
              label: l10n.assistantEditStreamOutputTitle,
              value: a.streamOutput,
              onChanged: (v) => ap.updateAssistant(a.copyWith(streamOutput: v)),
            ),
          ],
        ),
      ],
    );
  }
}
