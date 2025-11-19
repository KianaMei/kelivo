import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../shared/widgets/ios_switch.dart';
import 'package:provider/provider.dart';
import '../core/providers/settings_provider.dart';
import '../icons/lucide_adapter.dart';
import 'package:file_picker/file_picker.dart';
import '../l10n/app_localizations.dart';
import '../core/services/haptics.dart';
import '../shared/widgets/ios_tile_button.dart';

Future<String?> showDesktopAddProviderDialog(BuildContext context) async {
  return showGeneralDialog<String?>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'add-provider-dialog',
    barrierColor: Colors.black.withOpacity(0.25),
    pageBuilder: (ctx, _, __) => const _AddProviderDialogBody(),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AddProviderDialogBody extends StatefulWidget {
  const _AddProviderDialogBody();
  @override
  State<_AddProviderDialogBody> createState() => _AddProviderDialogBodyState();
}

class _AddProviderDialogBodyState extends State<_AddProviderDialogBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  // OpenAI
  bool _openaiEnabled = true;
  late final TextEditingController _openaiName = TextEditingController(text: 'OpenAI');
  late final TextEditingController _openaiKey = TextEditingController();
  late final TextEditingController _openaiBase = TextEditingController(text: 'https://api.openai.com/v1');
  late final TextEditingController _openaiPath = TextEditingController(text: '/chat/completions');
  bool _openaiUseResponse = false;

  // Google
  bool _googleEnabled = true;
  late final TextEditingController _googleName = TextEditingController(text: 'Google');
  late final TextEditingController _googleKey = TextEditingController();
  late final TextEditingController _googleBase = TextEditingController(text: 'https://generativelanguage.googleapis.com/v1beta');
  bool _googleVertex = false;
  late final TextEditingController _googleLocation = TextEditingController(text: 'us-central1');
  late final TextEditingController _googleProject = TextEditingController();
  late final TextEditingController _googleSaJson = TextEditingController();

  // Claude
  bool _claudeEnabled = true;
  late final TextEditingController _claudeName = TextEditingController(text: 'Claude');
  late final TextEditingController _claudeKey = TextEditingController();
  late final TextEditingController _claudeBase = TextEditingController(text: 'https://api.anthropic.com/v1');

  Widget _inputRow({required String label, required TextEditingController controller, String? hint, bool obscure = false, bool enabled = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFEBECF0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.18), width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.18), width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.primary.withOpacity(0.5), width: 1.2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _switchRow({required String label, required bool value, required ValueChanged<bool> onChanged}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        IosSwitch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _iosCard({required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF7F7F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.12), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(height: 10, thickness: 0.6, color: cs.outlineVariant.withOpacity(0.18)),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _openaiForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _iosCard(children: [
          _switchRow(label: l10n.addProviderSheetEnabledLabel, value: _openaiEnabled, onChanged: (v) => setState(() => _openaiEnabled = v)),
          _switchRow(label: 'Response API', value: _openaiUseResponse, onChanged: (v) => setState(() => _openaiUseResponse = v)),
        ]),
        const SizedBox(height: 10),
        _inputRow(label: l10n.addProviderSheetNameLabel, controller: _openaiName),
        const SizedBox(height: 10),
        _inputRow(label: 'API Key', controller: _openaiKey),
        const SizedBox(height: 10),
        _inputRow(label: 'API Base Url', controller: _openaiBase),
        const SizedBox(height: 10),
        if (!_openaiUseResponse)
          _inputRow(label: l10n.addProviderSheetApiPathLabel, controller: _openaiPath, hint: '/chat/completions'),
      ],
    );
  }

  Widget _googleForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _iosCard(children: [
          _switchRow(label: l10n.addProviderSheetEnabledLabel, value: _googleEnabled, onChanged: (v) => setState(() => _googleEnabled = v)),
          _switchRow(label: 'Vertex AI', value: _googleVertex, onChanged: (v) => setState(() => _googleVertex = v)),
        ]),
        const SizedBox(height: 10),
        _inputRow(label: l10n.addProviderSheetNameLabel, controller: _googleName),
        const SizedBox(height: 10),
        if (!_googleVertex) ...[
          _inputRow(label: 'API Key', controller: _googleKey),
          const SizedBox(height: 10),
          _inputRow(label: 'API Base Url', controller: _googleBase),
          const SizedBox(height: 10),
        ],
        if (_googleVertex) ...[
          _inputRow(label: l10n.addProviderSheetVertexAiLocationLabel, controller: _googleLocation, hint: 'us-central1'),
          const SizedBox(height: 10),
          _inputRow(label: l10n.addProviderSheetVertexAiProjectIdLabel, controller: _googleProject),
          const SizedBox(height: 10),
          _multilineRow(
            label: l10n.addProviderSheetVertexAiServiceAccountJsonLabel,
            controller: _googleSaJson,
            hint: '{\n  "type": "service_account", ...\n}',
            actions: [
              TextButton.icon(
                onPressed: _importGoogleServiceAccount,
                icon: const Icon(Icons.upload_file, size: 16),
                label: Text(l10n.addProviderSheetImportJsonButton),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _claudeForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _iosCard(children: [
          _switchRow(label: l10n.addProviderSheetEnabledLabel, value: _claudeEnabled, onChanged: (v) => setState(() => _claudeEnabled = v)),
        ]),
        const SizedBox(height: 10),
        _inputRow(label: l10n.addProviderSheetNameLabel, controller: _claudeName),
        const SizedBox(height: 10),
        _inputRow(label: 'API Key', controller: _claudeKey),
        const SizedBox(height: 10),
        _inputRow(label: 'API Base Url', controller: _claudeBase),
      ],
    );
  }

  Future<void> _onAdd() async {
    final settings = context.read<SettingsProvider>();
    String uniqueKey(String prefix, String display) {
      final existing = context.read<SettingsProvider>().providerConfigs.keys.toSet();
      if (display.toLowerCase() == prefix.toLowerCase()) {
        int i = 1;
        String candidate = '$prefix - $i';
        while (existing.contains(candidate)) {
          i++;
          candidate = '$prefix - $i';
        }
        return candidate;
      }
      String base = '$prefix - $display';
      if (!existing.contains(base)) return base;
      int i = 2;
      String candidate = '$base ($i)';
      while (existing.contains(candidate)) {
        i++;
        candidate = '$base ($i)';
      }
      return candidate;
    }
    final idx = _tab.index;
    String createdKey = '';
    if (idx == 0) {
      final rawName = _openaiName.text.trim();
      final display = rawName.isEmpty ? 'OpenAI' : rawName;
      final keyName = uniqueKey('OpenAI', display);
      final cfg = ProviderConfig(
        id: keyName,
        enabled: _openaiEnabled,
        name: display,
        apiKey: _openaiKey.text.trim(),
        baseUrl: _openaiBase.text.trim().isEmpty ? 'https://api.openai.com/v1' : _openaiBase.text.trim(),
        providerType: ProviderKind.openai,
        chatPath: _openaiUseResponse ? null : (_openaiPath.text.trim().isEmpty ? '/chat/completions' : _openaiPath.text.trim()),
        useResponseApi: _openaiUseResponse,
        models: const [],
        modelOverrides: const {},
        proxyEnabled: false,
        proxyHost: '',
        proxyPort: '8080',
        proxyUsername: '',
        proxyPassword: '',
      );
      await settings.setProviderConfig(keyName, cfg);
      createdKey = keyName;
    } else if (idx == 1) {
      final rawName = _googleName.text.trim();
      final display = rawName.isEmpty ? 'Google' : rawName;
      final keyName = uniqueKey('Google', display);
      final cfg = ProviderConfig(
        id: keyName,
        enabled: _googleEnabled,
        name: display,
        apiKey: _googleVertex ? '' : _googleKey.text.trim(),
        baseUrl: _googleVertex ? 'https://aiplatform.googleapis.com' : (_googleBase.text.trim().isEmpty ? 'https://generativelanguage.googleapis.com/v1beta' : _googleBase.text.trim()),
        providerType: ProviderKind.google,
        vertexAI: _googleVertex,
        location: _googleVertex ? (_googleLocation.text.trim().isEmpty ? 'us-central1' : _googleLocation.text.trim()) : '',
        projectId: _googleVertex ? _googleProject.text.trim() : '',
        serviceAccountJson: _googleVertex ? _googleSaJson.text.trim() : null,
        models: const [],
        modelOverrides: const {},
        proxyEnabled: false,
        proxyHost: '',
        proxyPort: '8080',
        proxyUsername: '',
        proxyPassword: '',
      );
      await settings.setProviderConfig(keyName, cfg);
      createdKey = keyName;
    } else {
      final rawName = _claudeName.text.trim();
      final display = rawName.isEmpty ? 'Claude' : rawName;
      final keyName = uniqueKey('Claude', display);
      final cfg = ProviderConfig(
        id: keyName,
        enabled: _claudeEnabled,
        name: display,
        apiKey: _claudeKey.text.trim(),
        baseUrl: _claudeBase.text.trim().isEmpty ? 'https://api.anthropic.com/v1' : _claudeBase.text.trim(),
        providerType: ProviderKind.claude,
        models: const [],
        modelOverrides: const {},
        proxyEnabled: false,
        proxyHost: '',
        proxyPort: '8080',
        proxyUsername: '',
        proxyPassword: '',
      );
      await settings.setProviderConfig(keyName, cfg);
      createdKey = keyName;
    }

    final order = List<String>.of(context.read<SettingsProvider>().providersOrder);
    order.remove(createdKey);
    order.insert(0, createdKey);
    await context.read<SettingsProvider>().setProvidersOrder(order);

    if (mounted) Navigator.of(context).pop(createdKey);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Material(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF7F7F9),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? Colors.white.withOpacity(0.08) : cs.outlineVariant.withOpacity(0.25),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.addProviderSheetTitle,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      _TactileIconButton(
                        icon: Lucide.X,
                        color: cs.onSurface,
                        size: 22,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
                
                // Tab Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _SegTabBar(controller: _tab, tabs: const ['OpenAI', 'Google', 'Claude']),
                ),
                
                const SizedBox(height: 16),
                
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ListView(
                      children: [
                        AnimatedBuilder(
                          animation: _tab,
                          builder: (_, __) {
                            final idx = _tab.index;
                            return Column(
                              children: [
                                if (idx == 0) _openaiForm(l10n),
                                if (idx == 1) _googleForm(l10n),
                                if (idx == 2) _claudeForm(l10n),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                
                // Footer Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: IosTileButton(
                      icon: Lucide.Plus,
                      label: l10n.addProviderSheetAddButton,
                      backgroundColor: cs.primary,
                      onTap: _onAdd,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _multilineRow({required String label, required TextEditingController controller, String? hint, List<Widget>? actions}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8)))),
            if (actions != null) ...actions,
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: 8,
          minLines: 4,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFEBECF0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.18), width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.18), width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.primary.withOpacity(0.5), width: 1.2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _importGoogleServiceAccount() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final path = file.path;
      if (path == null) return;
      final text = await File(path).readAsString();
      _googleSaJson.text = text;
      try {
        final obj = jsonDecode(text) as Map<String, dynamic>;
        final pid = (obj['project_id'] as String?)?.trim();
        if ((pid ?? '').isNotEmpty && _googleProject.text.trim().isEmpty) {
          _googleProject.text = pid!;
        }
      } catch (_) {}
      if (mounted) setState(() {});
    } catch (_) {}
  }
}

// Desktop-styled Tab Bar
class _SegTabBar extends StatelessWidget {
  const _SegTabBar({required this.controller, required this.tabs});
  final TabController controller;
  final List<String> tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    const double outerHeight = 40;
    const double innerPadding = 3;
    const double gap = 4;
    const double minSegWidth = 88;
    final double pillRadius = 10;
    final double innerRadius = pillRadius - innerPadding;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availWidth = constraints.maxWidth;
        final double innerAvailWidth = availWidth - innerPadding * 2;
        final double segWidth = math.max(
          minSegWidth,
          (innerAvailWidth - gap * (tabs.length - 1)) / tabs.length,
        );
        final double rowWidth = segWidth * tabs.length + gap * (tabs.length - 1);

        final Color shellBg = isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE8E8EA);

        List<Widget> children = [];
        for (int index = 0; index < tabs.length; index++) {
          final bool selected = controller.index == index;
          children.add(
            SizedBox(
              width: segWidth,
              height: double.infinity,
              child: _TactileRow(
                onTap: () => controller.animateTo(index),
                builder: (pressed) {
                  final Color baseBg = selected ? (isDark ? Colors.white.withOpacity(0.12) : Colors.white) : Colors.transparent;
                  final Color baseTextColor = selected ? cs.primary : cs.onSurface.withOpacity(0.75);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: baseBg,
                      borderRadius: BorderRadius.circular(innerRadius),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tabs[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: baseTextColor,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          if (index != tabs.length - 1) children.add(const SizedBox(width: gap));
        }

        return Container(
          height: outerHeight,
          decoration: BoxDecoration(
            color: shellBg,
            borderRadius: BorderRadius.circular(pillRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(innerPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
        );
      },
    );
  }
}

class _TactileRow extends StatefulWidget {
  const _TactileRow({required this.builder, this.onTap});
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      onTap: widget.onTap,
      child: widget.builder(_pressed),
    );
  }
}

class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({required this.icon, required this.color, required this.onTap, this.size = 22});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;
  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final press = base.withOpacity(0.7);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () { Haptics.light(); widget.onTap(); },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.size, color: _pressed ? press : base),
          ),
        ),
      ),
    );
  }
}
