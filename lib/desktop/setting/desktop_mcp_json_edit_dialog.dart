import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../icons/lucide_adapter.dart';
import '../../core/providers/mcp_provider.dart';
import '../../shared/widgets/snackbar.dart';
import '../../l10n/app_localizations.dart';

Future<void> showDesktopMcpJsonEditDialog(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        child: _DesktopMcpJsonEditDialog(),
      ),
    ),
  );
}

class _DesktopMcpJsonEditDialog extends StatefulWidget {
  @override
  State<_DesktopMcpJsonEditDialog> createState() => _DesktopMcpJsonEditDialogState();
}

class _DesktopMcpJsonEditDialogState extends State<_DesktopMcpJsonEditDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final mcp = context.read<McpProvider>();
    _controller.text = mcp.exportServersAsUiJson();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      // Quick JSON check
      jsonDecode(_controller.text);
    } catch (e) {
      setState(() => _error = e.toString());
      showAppSnackBar(context, message: l10n.mcpJsonEditParseFailed, type: NotificationType.warning);
      return;
    }
    try {
      await context.read<McpProvider>().replaceAllFromJson(_controller.text);
      if (!mounted) return;
      Navigator.of(context).maybePop();
      showAppSnackBar(context, message: l10n.mcpJsonEditSavedApplied);
    } catch (e) {
      setState(() => _error = e.toString());
      if (!mounted) return;
      showAppSnackBar(context, message: e.toString(), type: NotificationType.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.mcpJsonEditTitle,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Lucide.X, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.2)),

        // Editor
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              ),
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13.5,
                  height: 1.4,
                ),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),

        // Error
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),

        // Footer
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.2)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.mcpPageCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _save,
                child: Text(l10n.mcpServerEditSheetSave),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
