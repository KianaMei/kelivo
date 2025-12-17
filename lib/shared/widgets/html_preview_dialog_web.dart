import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import '../../icons/lucide_adapter.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark-reasonable.dart';

Future<void> showHtmlPreviewDialog(BuildContext context, String htmlText) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => _HtmlPreviewWebPage(htmlContent: htmlText),
    ),
  );
}

class _HtmlPreviewWebPage extends StatelessWidget {
  const _HtmlPreviewWebPage({required this.htmlContent});

  final String htmlContent;

  void _openPreview() {
    final bytes = utf8.encode(htmlContent);
    final b64 = base64Encode(bytes);
    final url = 'data:text/html;base64,$b64';
    html.WindowBase? win;
    try {
      win = html.window.open(url, '_blank');
    } catch (_) {}
    if (win == null) {
      // Fallback: navigate current tab
      try {
        html.window.location.href = url;
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = isDark ? atomOneDarkReasonableTheme : githubTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('HTML Preview'),
        actions: [
          IconButton(
            tooltip: 'Open preview',
            onPressed: _openPreview,
            icon: const Icon(Lucide.ExternalLink),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: cs.surfaceContainerHighest.withOpacity(0.25),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: HighlightView(
                htmlContent,
                language: 'html',
                theme: theme,
                padding: const EdgeInsets.all(12),
                textStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
