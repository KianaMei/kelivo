import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/memory_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/tactile_widgets.dart';

/// Memory management tab for assistant settings.
class MemoryTab extends StatelessWidget {
  const MemoryTab({super.key, required this.assistantId});
  
  final String assistantId;

  Future<void> _showAddEditSheet(
    BuildContext context, {
    int? id,
    String initial = '',
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: initial);
    
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Lucide.Library, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.assistantEditMemoryDialogTitle,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: l10n.assistantEditMemoryDialogHint,
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark
                        ? Colors.white10
                        : const Color(0xFFF7F7F9),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: IosButton(
                        label: l10n.assistantEditEmojiDialogCancel,
                        icon: Lucide.X,
                        onTap: () => Navigator.of(ctx).pop(),
                        filled: false,
                        neutral: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: IosButton(
                        label: l10n.assistantEditEmojiDialogSave,
                        icon: Lucide.Check,
                        onTap: () async {
                          final text = controller.text.trim();
                          if (text.isEmpty) return;
                          final mp = context.read<MemoryProvider>();
                          if (id == null) {
                            await mp.add(assistantId: assistantId, content: text);
                          } else {
                            await mp.update(id: id, content: text);
                          }
                          if (context.mounted) Navigator.of(ctx).pop();
                        },
                        filled: true,
                        neutral: false,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(assistantId)!;
    final mp = context.watch<MemoryProvider>();
    
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        mp.initialize();
      });
    } catch (_) {}
    
    final memories = mp.getForAssistant(assistantId);

    Widget sectionCard({
      required Widget child,
      EdgeInsets padding = const EdgeInsets.symmetric(vertical: 6),
    }) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06),
                width: 0.6,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(padding: padding, child: child),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      children: [
        sectionCard(
          child: Column(
            children: [
              iosSwitchRow(
                context,
                icon: Lucide.bookHeart,
                label: l10n.assistantEditMemorySwitchTitle,
                value: a.enableMemory,
                onChanged: (v) async {
                  await context.read<AssistantProvider>().updateAssistant(a.copyWith(enableMemory: v));
                },
              ),
              iosDivider(context),
              iosSwitchRow(
                context,
                icon: Lucide.History,
                label: l10n.assistantEditRecentChatsSwitchTitle,
                value: a.enableRecentChatsReference,
                onChanged: (v) async {
                  await context.read<AssistantProvider>().updateAssistant(a.copyWith(enableRecentChatsReference: v));
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.assistantEditManageMemoryTitle,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              TactileRow(
                onTap: () => _showAddEditSheet(context),
                pressedScale: 0.97,
                builder: (pressed) {
                  final color = pressed ? cs.primary.withOpacity(0.7) : cs.primary;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Plus, size: 16, color: color),
                      const SizedBox(width: 4),
                      Text(
                        l10n.assistantEditAddMemoryButton,
                        style: TextStyle(color: color, fontWeight: FontWeight.w600),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        if (memories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l10n.assistantEditMemoryEmpty,
              style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 12),
            ),
          ),
        ...memories.map((m) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06),
                  width: 0.6,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        m.content,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TactileIconButton(
                      icon: Lucide.Pencil,
                      size: 18,
                      color: cs.primary,
                      onTap: () => _showAddEditSheet(context, id: m.id, initial: m.content),
                    ),
                    const SizedBox(width: 6),
                    TactileIconButton(
                      icon: Lucide.Trash2,
                      size: 18,
                      color: cs.error,
                      onTap: () async {
                        await context.read<MemoryProvider>().delete(id: m.id);
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 32),
      ],
    );
  }
}
