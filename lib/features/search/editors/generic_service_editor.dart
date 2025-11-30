import 'package:flutter/material.dart';
import '../../../core/services/search/search_service.dart';

/// Generic service configuration editor
/// For services that don't use multi-key management (like SearXNG)
class GenericServiceEditor extends StatefulWidget {
  const GenericServiceEditor({super.key, required this.initial});
  final SearchServiceOptions initial;

  @override
  State<GenericServiceEditor> createState() => GenericServiceEditorState();
}

class GenericServiceEditorState extends State<GenericServiceEditor> {
  final Map<String, TextEditingController> _c = {};

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    if (s is SearXNGOptions) {
      _c['url'] = TextEditingController(text: s.url);
      _c['engines'] = TextEditingController(text: s.engines);
      _c['language'] = TextEditingController(text: s.language);
      _c['username'] = TextEditingController(text: s.username);
      _c['password'] = TextEditingController(text: s.password);
    }
  }

  @override
  void dispose() {
    for (final v in _c.values) v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.initial;

    Widget field(String k, String label, {bool obscure = false, String? hint}) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(isDark ? 0.18 : 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _c.putIfAbsent(k, () => TextEditingController()),
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        );

    if (s is SearXNGOptions) {
      return SingleChildScrollView(
        child: Column(
          children: [
            field('url', '实例地址'),
            field('engines', '引擎（可选）', hint: 'google,duckduckgo'),
            field('language', '语言（可选）', hint: 'en-US'),
            field('username', '用户名（可选）'),
            field('password', '密码（可选）', obscure: true),
          ],
        ),
      );
    }

    if (s is BingLocalOptions) {
      return Center(child: Text('无额外配置', style: TextStyle(color: cs.onSurface.withOpacity(0.8))));
    }

    return const Center(child: Text('此服务应使用多Key编辑器'));
  }

  SearchServiceOptions? buildUpdated() {
    final s = widget.initial;
    if (s is SearXNGOptions) {
      return SearXNGOptions(
        id: s.id,
        url: _c['url']!.text,
        engines: _c['engines']!.text,
        language: _c['language']!.text,
        username: _c['username']!.text,
        password: _c['password']!.text,
      );
    }
    if (s is BingLocalOptions) return s;
    return null;
  }
}
