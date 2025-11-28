import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../l10n/app_localizations.dart';

/// Basic settings tab (simplified version).
/// Full implementation to be completed in next iteration.
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
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Assistant Name', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            hintText: 'Enter assistant name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (v) {
            ap.updateAssistant(a.copyWith(name: v));
          },
        ),
      ],
    );
  }
}
