import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'google_fonts_picker_page.dart';

class FontSettingsPage extends StatefulWidget {
  const FontSettingsPage({super.key});

  @override
  State<FontSettingsPage> createState() => _FontSettingsPageState();
}

class _FontSettingsPageState extends State<FontSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final sp = context.watch<SettingsProvider>();
    final fam = sp.appFontFamily;
    final isGoogle = sp.appFontIsGoogle;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.desktopSettingsFontsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _sectionTitle(context, '应用字体（App Font）'),
          _card(
            context,
            children: [
              ListTile(
                dense: true,
                title: const Text('当前字体'),
                subtitle: Text((fam == null || fam.isEmpty) ? 'System Default' : fam),
                trailing: (fam == null || fam.isEmpty)
                    ? null
                    : Text(isGoogle ? 'Google' : 'System', style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                title: const Text('从 Google Fonts 选择'),
                onTap: () async {
                  final sel = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => const GoogleFontsPickerPage(title: 'Google Fonts')),
                  );
                  if (!mounted || sel == null || sel.trim().isEmpty) return;
                  await context.read<SettingsProvider>().setAppFontFamily(sel, isGoogle: true);
                },
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                title: const Text('输入系统字体名'),
                onTap: () async => _showSystemFontInput(context),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                title: const Text('清除并恢复默认'),
                onTap: () async => context.read<SettingsProvider>().setAppFontFamily(null),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, '代码字体（Code Font）'),
          _card(
            context,
            children: [
              ListTile(
                dense: true,
                title: const Text('当前字体'),
                subtitle: Text((sp.codeFontFamily == null || sp.codeFontFamily!.isEmpty) ? 'System Default' : sp.codeFontFamily!),
                trailing: (sp.codeFontFamily == null || sp.codeFontFamily!.isEmpty)
                    ? null
                    : Text(sp.codeFontIsGoogle ? 'Google' : 'System', style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                title: const Text('从 Google Fonts 选择'),
                onTap: () async {
                  final sel = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => const GoogleFontsPickerPage(title: 'Google Fonts')),
                  );
                  if (!mounted || sel == null || sel.trim().isEmpty) return;
                  await context.read<SettingsProvider>().setCodeFontFamily(sel, isGoogle: true);
                },
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                title: const Text('输入系统字体名'),
                onTap: () async => _showSystemCodeFontInput(context),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                title: const Text('清除并恢复默认'),
                onTap: () async => context.read<SettingsProvider>().setCodeFontFamily(null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showSystemFontInput(BuildContext context) async {
    final ctrl = TextEditingController();
    final fam = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('系统字体名'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: '例如：Segoe UI / PingFang SC'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('确定')),
          ],
        );
      },
    );
    if (!mounted || fam == null || fam.isEmpty) return;
    await context.read<SettingsProvider>().setAppFontFamily(fam, isGoogle: false);
  }

  Future<void> _showSystemCodeFontInput(BuildContext context) async {
    final ctrl = TextEditingController();
    final fam = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('系统字体名（代码）'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: '例如：JetBrains Mono / Consolas'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('确定')),
          ],
        );
      },
    );
    if (!mounted || fam == null || fam.isEmpty) return;
    await context.read<SettingsProvider>().setCodeFontFamily(fam, isGoogle: false);
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.7))),
    );
  }

  Widget _card(BuildContext context, {required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.28), width: 0.8),
      ),
      child: Column(children: children),
    );
  }
}

