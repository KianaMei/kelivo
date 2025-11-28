import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../l10n/app_localizations.dart';

/// Prompt configuration tab - MVP version with core functionality.
/// 
/// ✅ Implemented: System prompt editor, Message template editor
/// 🚧 TODO: Variable chips, Preset message cards with drag-reorder
/// 📝 Full implementation: ~800 lines in original file (lines 3520-4299)
class PromptTab extends StatefulWidget {
  const PromptTab({super.key, required this.assistantId});
  
  final String assistantId;

  @override
  State<PromptTab> createState() => _PromptTabState();
}

class _PromptTabState extends State<PromptTab> {
  late final TextEditingController _sysCtrl;
  late final TextEditingController _tmplCtrl;

  @override
  void initState() {
    super.initState();
    final ap = context.read<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;
    _sysCtrl = TextEditingController(text: a.systemPrompt);
    _tmplCtrl = TextEditingController(text: a.messageTemplate);
  }

  @override
  void didUpdateWidget(covariant PromptTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assistantId != widget.assistantId) {
      final ap = context.read<AssistantProvider>();
      final a = ap.getById(widget.assistantId)!;
      _sysCtrl.text = a.systemPrompt;
      _tmplCtrl.text = a.messageTemplate;
    }
  }

  @override
  void dispose() {
    _sysCtrl.dispose();
    _tmplCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // System prompt
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06), width: 0.6),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.assistantEditSystemPromptTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _sysCtrl,
                minLines: 8,
                maxLines: 20,
                decoration: InputDecoration(
                  hintText: l10n.assistantEditSystemPromptHint,
                  filled: true,
                  fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (v) => ap.updateAssistant(a.copyWith(systemPrompt: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Message template
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06), width: 0.6),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.assistantEditMessageTemplateTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(l10n.assistantEditMessageTemplateDescription, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
              const SizedBox(height: 10),
              TextField(
                controller: _tmplCtrl,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: l10n.assistantEditMessageTemplateHint,
                  filled: true,
                  fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (v) => ap.updateAssistant(a.copyWith(messageTemplate: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
