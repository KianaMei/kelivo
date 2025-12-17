import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../shared/widgets/snackbar.dart';

Future<void> showMessageExportSheet(BuildContext context, ChatMessage message) async {
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: _MessageExportSheetWeb(message: message),
    ),
  );
}

class _MessageExportSheetWeb extends StatelessWidget {
  const _MessageExportSheetWeb({required this.message});

  final ChatMessage message;

  String _safeFileName(String raw, {String ext = 'md'}) {
    final base = raw.trim().isEmpty ? 'kelivo_message' : raw.trim();
    final cleaned = base
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final short = cleaned.length > 40 ? cleaned.substring(0, 40).trim() : cleaned;
    return '$short.$ext';
  }

  void _downloadText(String filename, String text) {
    final bytes = utf8.encode(text);
    final blob = html.Blob(<dynamic>[bytes], 'text/plain;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final a = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';
    html.document.body?.children.add(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = message.content;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy message'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: content));
              if (!context.mounted) return;
              Navigator.of(context).pop();
              showAppSnackBar(context, message: 'Copied', type: NotificationType.success);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Download as Markdown'),
            subtitle: Text(
              _safeFileName(content.isNotEmpty ? content.split('\n').first : ''),
              style: TextStyle(color: cs.onSurface.withOpacity(0.65)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              final name = _safeFileName(content.isNotEmpty ? content.split('\n').first : '');
              _downloadText(name, content);
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.18)),
            ),
            padding: const EdgeInsets.all(12),
            child: Text(
              content,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurface.withOpacity(0.9)),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showChatExportSheet(
  BuildContext context, {
  required Conversation conversation,
  required List<ChatMessage> selectedMessages,
}) async {
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: _BatchExportSheetWeb(conversation: conversation, messages: selectedMessages),
      );
    },
  );
}

class _BatchExportSheetWeb extends StatelessWidget {
  const _BatchExportSheetWeb({required this.conversation, required this.messages});

  final Conversation conversation;
  final List<ChatMessage> messages;

  String _safeFileName(String raw, {String ext = 'md'}) {
    final base = raw.trim().isEmpty ? 'kelivo_chat' : raw.trim();
    final cleaned = base
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final short = cleaned.length > 40 ? cleaned.substring(0, 40).trim() : cleaned;
    return '$short.$ext';
  }

  void _downloadText(String filename, String text) {
    final bytes = utf8.encode(text);
    final blob = html.Blob(<dynamic>[bytes], 'text/plain;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final a = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';
    html.document.body?.children.add(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(url);
  }

  String _formatTime(DateTime time) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    return fmt.format(time);
  }

  String _getRoleName(BuildContext context, ChatMessage msg) {
    if (msg.role == 'user') return 'User';
    if (msg.role == 'assistant') return 'Assistant';
    return msg.role;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = conversation.title.trim().isNotEmpty
        ? conversation.title
        : 'Chat';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Export ${messages.length} messages',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: cs.onSurface),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy all messages'),
            onTap: () async {
              final buf = StringBuffer();
              for (final msg in messages) {
                buf.writeln('${_getRoleName(context, msg)} (${_formatTime(msg.timestamp)}):');
                buf.writeln(msg.content);
                buf.writeln();
              }
              await Clipboard.setData(ClipboardData(text: buf.toString()));
              if (!context.mounted) return;
              Navigator.of(context).pop();
              showAppSnackBar(context, message: 'Copied', type: NotificationType.success);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Download as Markdown'),
            subtitle: Text(
              _safeFileName(title),
              style: TextStyle(color: cs.onSurface.withOpacity(0.65)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              final buf = StringBuffer();
              buf.writeln('# $title');
              buf.writeln();
              for (final msg in messages) {
                buf.writeln('> ${_formatTime(msg.timestamp)} · ${_getRoleName(context, msg)}');
                buf.writeln();
                buf.writeln(msg.content);
                buf.writeln();
              }
              final name = _safeFileName(title);
              _downloadText(name, buf.toString());
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.18)),
            ),
            padding: const EdgeInsets.all(12),
            child: Text(
              '${messages.length} messages selected',
              style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
            ),
          ),
        ],
      ),
    );
  }
}

