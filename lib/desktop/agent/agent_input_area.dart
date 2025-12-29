import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../icons/lucide_adapter.dart' as lucide;

/// Input area for agent prompts
class AgentInputArea extends StatefulWidget {
  const AgentInputArea({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.onAbort,
    required this.isRunning,
    this.workingDirectory,
    this.onSelectDirectory,
  });

  final TextEditingController controller;
  final void Function(String prompt) onSubmit;
  final VoidCallback onAbort;
  final bool isRunning;
  final String? workingDirectory;
  final VoidCallback? onSelectDirectory;

  @override
  State<AgentInputArea> createState() => _AgentInputAreaState();
}

class _AgentInputAreaState extends State<AgentInputArea> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = widget.controller.text.trim();
    if (text.isEmpty || widget.isRunning) return;
    widget.onSubmit(text);
    widget.controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline.withOpacity(0.15))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Working directory indicator
          if (widget.workingDirectory != null)
            InkWell(
              onTap: widget.onSelectDirectory,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Icon(lucide.Lucide.FolderOpen, size: 14, color: cs.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.workingDirectory!,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      lucide.Lucide.ChevronRight,
                      size: 14,
                      color: cs.onSurface.withOpacity(0.4),
                    ),
                  ],
                ),
              ),
            ),

          // Input row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Text input
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.enter): _submit,
                        const SingleActivator(LogicalKeyboardKey.enter, shift: true): () {
                          // Insert newline
                          final text = widget.controller.text;
                          final selection = widget.controller.selection;
                          final newText = text.replaceRange(
                            selection.start,
                            selection.end,
                            '\n',
                          );
                          widget.controller.value = TextEditingValue(
                            text: newText,
                            selection: TextSelection.collapsed(offset: selection.start + 1),
                          );
                        },
                      },
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(fontSize: 14, color: cs.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Ask the agent to help with a task...',
                          hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.4)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Send/Abort button
                widget.isRunning
                    ? _ActionButton(
                        icon: lucide.Lucide.StopCircle,
                        label: 'Stop',
                        color: cs.error,
                        onTap: widget.onAbort,
                      )
                    : _ActionButton(
                        icon: lucide.Lucide.Send,
                        label: 'Send',
                        color: cs.primary,
                        onTap: _submit,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
