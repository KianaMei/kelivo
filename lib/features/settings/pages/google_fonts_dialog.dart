import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GoogleFontsDialog extends StatefulWidget {
  const GoogleFontsDialog({super.key, required this.title});
  final String title;

  static Future<String?> show(BuildContext context, {required String title}) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => GoogleFontsDialog(title: title),
    );
  }

  @override
  State<GoogleFontsDialog> createState() => _GoogleFontsDialogState();
}

class _GoogleFontsDialogState extends State<GoogleFontsDialog> {
  late final TextEditingController _filterCtrl;

  @override
  void initState() {
    super.initState();
    _filterCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allFonts = GoogleFonts.asMap().keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final fonts = _filtered(allFonts);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      insetPadding: const EdgeInsets.fromLTRB(40, 36, 40, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            // Filter
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: TextField(
                controller: _filterCtrl,
                decoration: InputDecoration(
                  hintText: '输入以过滤字体…',
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? Colors.white10 : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.28), width: 0.8),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 4),
            // List
            Expanded(
              child: ListView.builder(
                itemCount: fonts.length,
                itemBuilder: (context, i) {
                  final fam = fonts[i];
                  TextStyle preview;
                  try {
                    preview = GoogleFonts.getFont(fam, fontSize: 18);
                  } catch (_) {
                    preview = const TextStyle(fontSize: 18);
                  }
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(fam),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                      child: Row(
                        children: [
                          Expanded(child: Text(fam, style: TextStyle(fontSize: 14, color: cs.onSurface))),
                          Text('Aa字', style: preview),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  List<String> _filtered(List<String> all) {
    final q = _filterCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((e) => e.toLowerCase().contains(q)).toList();
  }
}

