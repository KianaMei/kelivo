import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../l10n/app_localizations.dart';

/// Prompt configuration tab (simplified version).
/// Full implementation to be completed in next iteration.
class PromptTab extends StatefulWidget {
  const PromptTab({super.key, required this.assistantId});
  
  final String assistantId;

  @override
  State<PromptTab> createState() => _PromptTabState();
}

class _PromptTabState extends State<PromptTab> {
  late final TextEditingController _sysCtrl;
  late final FocusNode _sysFocus;

  @override
  void initState() {
    super.initState();
    final ap = context.read<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;
    _sysCtrl = TextEditingController(text: a.systemPrompt);
    _sysFocus = FocusNode();
  }

  @override
  void dispose() {
    _sysCtrl.dispose();
    _sysFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.assistantEditSystemPromptTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        TextField(
          controller: _sysCtrl,
          focusNode: _sysFocus,
          minLines: 8,
          maxLines: 20,
          decoration: InputDecoration(
            hintText: l10n.assistantEditSystemPromptHint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (v) {
            ap.updateAssistant(a.copyWith(systemPrompt: v));
          },
        ),
      ],
    );
  }
}
