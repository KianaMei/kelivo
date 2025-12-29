import 'package:flutter/material.dart';
import '../../core/services/agent/agent_service.dart'
    if (dart.library.html) '../../core/services/agent/agent_service_stub.dart';

/// Show a tool permission dialog for agent tool execution approval
Future<bool?> showToolPermissionDialog(
  BuildContext context, {
  required PermissionRequest request,
}) async {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'tool-permission',
    barrierColor: Colors.black.withOpacity(0.4),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) => _ToolPermissionDialog(request: request),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ToolPermissionDialog extends StatelessWidget {
  const _ToolPermissionDialog({required this.request});

  final PermissionRequest request;

  IconData _getToolIcon(String toolName) {
    switch (toolName.toLowerCase()) {
      case 'bash':
        return Icons.terminal;
      case 'read':
        return Icons.description_outlined;
      case 'write':
      case 'edit':
        return Icons.edit_outlined;
      case 'glob':
      case 'grep':
        return Icons.search;
      case 'webfetch':
      case 'websearch':
        return Icons.public;
      default:
        return Icons.build_outlined;
    }
  }

  Color _getToolColor(String toolName, ColorScheme cs) {
    switch (toolName.toLowerCase()) {
      case 'bash':
        return Colors.orange;
      case 'read':
        return cs.primary;
      case 'write':
      case 'edit':
        return Colors.amber.shade700;
      case 'webfetch':
      case 'websearch':
        return Colors.blue;
      default:
        return cs.tertiary;
    }
  }

  bool _isDangerous(String toolName) {
    final name = toolName.toLowerCase();
    return name == 'bash' || name == 'write' || name == 'edit';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDangerous = _isDangerous(request.toolName);

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDangerous
                    ? cs.errorContainer.withOpacity(0.3)
                    : cs.primaryContainer.withOpacity(0.3),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getToolColor(request.toolName, cs).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getToolIcon(request.toolName),
                      color: _getToolColor(request.toolName, cs),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tool Permission Request',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          request.toolName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDangerous)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber, size: 14, color: cs.error),
                          const SizedBox(width: 4),
                          Text(
                            'Risky',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: cs.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The agent wants to execute the following action:',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outline.withOpacity(0.3)),
                      ),
                      child: SelectableText(
                        request.inputPreview ?? _formatInput(request.input),
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: cs.outline.withOpacity(0.2))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withOpacity(0.5)),
                    ),
                    child: const Text('Deny'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: isDangerous ? cs.error : cs.primary,
                    ),
                    child: Text(isDangerous ? 'Allow (Risky)' : 'Allow'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatInput(Map<String, dynamic> input) {
    if (input.isEmpty) return '(no input)';
    final buffer = StringBuffer();
    for (final entry in input.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    return buffer.toString().trim();
  }
}
