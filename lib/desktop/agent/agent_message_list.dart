import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/agent_message.dart';
import '../../icons/lucide_adapter.dart' as lucide;

/// Message list for displaying agent conversation
class AgentMessageList extends StatelessWidget {
  const AgentMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
  });

  final List<AgentMessage> messages;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const _EmptyState();
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return _MessageBubble(message: message);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(lucide.Lucide.Bot, size: 40, color: cs.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'Start a conversation',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask the agent to help with coding tasks',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final AgentMessage message;

  @override
  Widget build(BuildContext context) {
    switch (message.type) {
      case AgentMessageType.user:
        return _UserMessage(message: message);
      case AgentMessageType.assistant:
        return _AssistantMessage(message: message);
      case AgentMessageType.toolCall:
        return _ToolCallMessage(message: message);
      case AgentMessageType.toolResult:
        return _ToolResultMessage(message: message);
      case AgentMessageType.error:
        return _ErrorMessage(message: message);
      case AgentMessageType.system:
        return _SystemMessage(message: message);
    }
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.message});
  final AgentMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(lucide.Lucide.User, size: 16, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                message.content,
                style: TextStyle(fontSize: 14, color: cs.onSurface),
              ),
            ),
          ),
          const SizedBox(width: 48), // Balance
        ],
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({required this.message});
  final AgentMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.secondary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: message.isStreaming
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(lucide.Lucide.Bot, size: 16, color: cs.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    message.content.isEmpty && message.isStreaming
                        ? '...'
                        : message.content,
                    style: TextStyle(fontSize: 14, color: cs.onSurface),
                  ),
                ),
                if (!message.isStreaming && message.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _CopyButton(text: message.content),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _ToolCallMessage extends StatefulWidget {
  const _ToolCallMessage({required this.message});
  final AgentMessage message;

  @override
  State<_ToolCallMessage> createState() => _ToolCallMessageState();
}

class _ToolCallMessageState extends State<_ToolCallMessage> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRunning = widget.message.toolStatus == ToolCallStatus.running;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 44),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Icon(
                      _getToolIcon(widget.message.toolName ?? ''),
                      size: 16,
                      color: cs.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.message.toolName ?? 'Tool',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    if (isRunning)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      _expanded ? lucide.Lucide.ChevronUp : lucide.Lucide.ChevronDown,
                      size: 16,
                      color: cs.onSurface.withOpacity(0.5),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
                child: SelectableText(
                  widget.message.toolInputPreview ?? widget.message.toolInputJson ?? '(no input)',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: cs.onSurface.withOpacity(0.8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

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
}

class _ToolResultMessage extends StatefulWidget {
  const _ToolResultMessage({required this.message});
  final AgentMessage message;

  @override
  State<_ToolResultMessage> createState() => _ToolResultMessageState();
}

class _ToolResultMessageState extends State<_ToolResultMessage> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final result = widget.message.toolResult ?? '';
    final isLong = result.length > 200;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 44),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.05),
          border: Border.all(color: Colors.green.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: isLong ? () => setState(() => _expanded = !_expanded) : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      widget.message.toolName ?? 'Result',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.green.shade700,
                      ),
                    ),
                    if (isLong) ...[
                      const Spacer(),
                      Icon(
                        _expanded ? lucide.Lucide.ChevronUp : lucide.Lucide.ChevronDown,
                        size: 14,
                        color: cs.onSurface.withOpacity(0.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (result.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: SelectableText(
                  _expanded || !isLong ? result : '${result.substring(0, 200)}...',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: cs.onSurface.withOpacity(0.8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});
  final AgentMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.error.withOpacity(0.08),
          border: Border.all(color: cs.error.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: cs.error),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                message.content,
                style: TextStyle(fontSize: 13, color: cs.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.message});
  final AgentMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Skip [Done] and [Aborted] markers
    if (message.content == '[Done]' || message.content == '[Aborted]') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            message.content,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check : Icons.copy,
              size: 12,
              color: cs.onSurface.withOpacity(0.5),
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? 'Copied' : 'Copy',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
