import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/quick_phrase.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/tactile_widgets.dart';

class QuickPhraseTab extends StatelessWidget {
  const QuickPhraseTab({super.key, required this.assistantId});
  
  final String assistantId;

  Future<void> _showAddEditSheet(BuildContext context, {QuickPhrase? phrase}) async {
    final result = await showModalBottomSheet<Map<String, String>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _QuickPhraseEditSheet(phrase: phrase, assistantId: assistantId),
    );

    if (result != null && context.mounted) {
      final title = result['title']?.trim() ?? '';
      final content = result['content']?.trim() ?? '';
      if (title.isEmpty || content.isEmpty) return;

      if (phrase == null) {
        final newPhrase = QuickPhrase(
          id: const Uuid().v4(),
          title: title,
          content: content,
          isGlobal: false,
          assistantId: assistantId,
        );
        await context.read<QuickPhraseProvider>().add(newPhrase);
      } else {
        await context.read<QuickPhraseProvider>().update(phrase.copyWith(title: title, content: content));
      }
    }
  }

  Future<void> _deletePhrase(BuildContext context, QuickPhrase phrase) async {
    await context.read<QuickPhraseProvider>().delete(phrase.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quickPhraseProvider = context.watch<QuickPhraseProvider>();
    final phrases = quickPhraseProvider.getForAssistant(assistantId);

    if (phrases.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Lucide.Zap, size: 64, color: cs.primary.withOpacity(0.6)),
              const SizedBox(height: 16),
              Text(
                l10n.assistantEditQuickPhraseDescription,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.7)),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200),
                child: IosButton(
                  label: l10n.assistantEditAddQuickPhraseButton,
                  icon: Lucide.Plus,
                  filled: true,
                  neutral: false,
                  onTap: () => _showAddEditSheet(context),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
          itemCount: phrases.length,
          buildDefaultDragHandles: false,
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex -= 1;
            context.read<QuickPhraseProvider>().reorderPhrases(
                  oldIndex: oldIndex,
                  newIndex: newIndex,
                  assistantId: assistantId,
                );
          },
          itemBuilder: (context, index) {
            final phrase = phrases[index];
            return Slidable(
              key: ValueKey(phrase.id),
              endActionPane: ActionPane(
                motion: const StretchMotion(),
                extentRatio: 0.35,
                children: [
                  CustomSlidableAction(
                    autoClose: true,
                    backgroundColor: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? cs.error.withOpacity(0.22) : cs.error.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.error.withOpacity(0.35)),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Lucide.Trash2, color: cs.error, size: 18),
                          const SizedBox(height: 4),
                          Text(l10n.quickPhraseDeleteButton, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700, fontSize: 12)),
                        ],
                      ),
                    ),
                    onPressed: (_) => _deletePhrase(context, phrase),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TactileRow(
                  onTap: () => _showAddEditSheet(context, phrase: phrase),
                  pressedScale: 0.98,
                  builder: (pressed) {
                    final bg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
                    final overlay = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);
                    final pressedBg = Color.alphaBlend(overlay, bg);
                    return Container(
                      decoration: BoxDecoration(
                        color: pressed ? pressedBg : bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06), width: 0.6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Lucide.botMessageSquare, size: 18, color: cs.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(phrase.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                ),
                                Icon(Lucide.ChevronRight, size: 18, color: cs.onSurface.withOpacity(0.4)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(phrase.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 60,
          child: Center(
            child: _GlassCircleButton(icon: Lucide.Plus, color: cs.primary, onTap: () => _showAddEditSheet(context)),
          ),
        ),
      ],
    );
  }
}

class _GlassCircleButton extends StatefulWidget {
  const _GlassCircleButton({required this.icon, required this.color, required this.onTap, this.size = 48});
  
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  State<_GlassCircleButton> createState() => _GlassCircleButtonState();
}

class _GlassCircleButtonState extends State<_GlassCircleButton> {
  bool _pressed = false;
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassBase = isDark ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.06);
    final overlay = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);
    final tileColor = _pressed ? Color.alphaBlend(overlay, glassBase) : glassBase;
    final borderColor = cs.outlineVariant.withOpacity(0.10);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: tileColor,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 1.0),
              ),
              child: Center(child: Icon(widget.icon, size: 18, color: widget.color)),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickPhraseEditSheet extends StatefulWidget {
  const _QuickPhraseEditSheet({required this.phrase, required this.assistantId});
  
  final QuickPhrase? phrase;
  final String? assistantId;

  @override
  State<_QuickPhraseEditSheet> createState() => _QuickPhraseEditSheetState();
}

class _QuickPhraseEditSheetState extends State<_QuickPhraseEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.phrase?.title ?? '');
    _contentController = TextEditingController(text: widget.phrase?.content ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                widget.phrase == null ? l10n.quickPhraseAddTitle : l10n.quickPhraseEditTitle,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.quickPhraseTitleLabel,
                filled: true,
                fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: l10n.quickPhraseContentLabel,
                alignLabelWithHint: true,
                filled: true,
                fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: IosButton(label: l10n.quickPhraseCancelButton, onTap: () => Navigator.of(context).pop(), filled: false, neutral: true),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: IosButton(
                    label: l10n.quickPhraseSaveButton,
                    onTap: () {
                      Navigator.of(context).pop({'title': _titleController.text, 'content': _contentController.text});
                    },
                    icon: Lucide.Check,
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
  }
}
