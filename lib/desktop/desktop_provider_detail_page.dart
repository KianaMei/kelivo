import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../utils/brand_assets.dart';
import '../utils/provider_avatar_manager.dart';
import '../icons/lucide_adapter.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/model_provider.dart';
import '../features/model/widgets/model_detail_sheet.dart';
import '../features/model/widgets/model_select_sheet.dart';
import 'model_fetch_dialog.dart';
import 'model_edit_dialog.dart';
import '../features/provider/widgets/share_provider_sheet.dart';
import '../features/provider/pages/multi_key_manager_page.dart';
import '../features/provider/pages/provider_network_page.dart';
import '../l10n/app_localizations.dart';
import '../shared/widgets/snackbar.dart';
import '../shared/widgets/ios_switch.dart';
import '../core/services/haptics.dart';
import 'widgets/desktop_avatar_picker_dialog.dart' show showDesktopAvatarPickerDialog;
import 'desktop_context_menu.dart' show showDesktopAnchoredMenu, DesktopContextMenuItem;
import '../features/provider/pages/multi_key_manager_page.dart';

/// Get effective ModelInfo with user overrides applied
ModelInfo _getEffectiveModelInfo(String modelId, ProviderConfig cfg) {
  // Start with inferred model info
  ModelInfo base = ModelRegistry.infer(ModelInfo(id: modelId, displayName: modelId));
  
  // Apply user overrides if they exist
  final ov = cfg.modelOverrides[modelId] as Map?;
  if (ov != null) {
    final name = (ov['name'] as String?)?.trim() ?? base.displayName;
    final typeStr = (ov['type'] as String?) ?? '';
    final type = typeStr == 'embedding' ? ModelType.embedding : ModelType.chat;
    
    final inArr = (ov['input'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final outArr = (ov['output'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final abArr = (ov['abilities'] as List?)?.map((e) => e.toString()).toList() ?? [];
    
    final input = inArr.isEmpty ? base.input : inArr.map((e) => e == 'image' ? Modality.image : Modality.text).toList();
    final output = outArr.isEmpty ? base.output : outArr.map((e) => e == 'image' ? Modality.image : Modality.text).toList();
    final abilities = abArr.isEmpty ? base.abilities : abArr.map((e) => e == 'reasoning' ? ModelAbility.reasoning : ModelAbility.tool).toList();
    
    return ModelInfo(
      id: modelId,
      displayName: name,
      type: type,
      input: input,
      output: output,
      abilities: abilities,
    );
  }
  
  return base;
}

/// Shows desktop provider detail dialog (75% of screen size)
Future<void> showDesktopProviderDetailDialog(
  BuildContext context, {
  required String providerKey,
  required String displayName,
}) async {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'provider-detail-dialog',
    barrierColor: Colors.black.withOpacity(0.25),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) {
      return DesktopProviderDetailPage(
        keyName: providerKey,
        displayName: displayName,
      );
    },
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

/// Desktop provider detail page - full screen detail view for a specific AI provider
/// Replaces the mobile-style PageView + iOS card design with desktop-native layout
class DesktopProviderDetailPage extends StatefulWidget {
  const DesktopProviderDetailPage({
    super.key,
    required this.keyName,
    required this.displayName,
    this.embedded = false,
    this.onBack,
  });

  final String keyName;
  final String displayName;

  /// Whether this page is embedded in a Master-Detail layout (no dialog wrapper)
  final bool embedded;

  /// Optional callback when back button is pressed in embedded mode
  final VoidCallback? onBack;

  @override
  State<DesktopProviderDetailPage> createState() => _DesktopProviderDetailPageState();
}

class _DesktopProviderDetailPageState extends State<DesktopProviderDetailPage> {
  bool _showSearch = false;
  final TextEditingController _filterCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _showApiKey = false;
  bool _eyeHover = false;

  // Persistent controllers for provider fields (desktop)
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _baseUrlCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();
  final TextEditingController _projectIdCtrl = TextEditingController();
  final TextEditingController _saJsonCtrl = TextEditingController();
  final TextEditingController _apiPathCtrl = TextEditingController();

  void _syncCtrl(TextEditingController c, String newText) {
    final v = c.value;
    // Do not disturb ongoing IME composition
    if (v.composing.isValid) return;
    if (c.text != newText) {
      c.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
  }

  void _syncControllersFromConfig(ProviderConfig cfg) {
    _syncCtrl(_apiKeyCtrl, cfg.apiKey);
    _syncCtrl(_baseUrlCtrl, cfg.baseUrl);
    _syncCtrl(_apiPathCtrl, cfg.chatPath ?? '/chat/completions');
    _syncCtrl(_locationCtrl, cfg.location ?? '');
    _syncCtrl(_projectIdCtrl, cfg.projectId ?? '');
    _syncCtrl(_saJsonCtrl, cfg.serviceAccountJson ?? '');
  }

  /// Remove all control characters (newlines, carriage returns, tabs, etc.) from a string
  String _sanitizeUrl(String input) {
    return input.trim().replaceAll(RegExp(r'[\r\n\t\f\v\x00-\x1F\x7F]'), '');
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    _searchFocus.dispose();
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _locationCtrl.dispose();
    _projectIdCtrl.dispose();
    _saJsonCtrl.dispose();
    _apiPathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    final cfg = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);

    // Keep controllers synced without breaking IME composition
    _syncControllersFromConfig(cfg);
    final kind = ProviderConfig.classify(widget.keyName, explicitType: cfg.providerType);

    final models = List<String>.from(cfg.models);
    final filtered = _applyFilter(models, _filterCtrl.text.trim());
    final groups = _groupModels(filtered);

    bool _isUserAdded(String key) {
      const fixed = {
        'KelivoIN', 'OpenAI', 'Gemini', 'SiliconFlow', 'OpenRouter',
        'DeepSeek', 'Tensdaq', 'Aliyun', 'Zhipu AI', 'Claude', 'Grok', 'ByteDance',
      };
      return !fixed.contains(key);
    }

    final size = MediaQuery.of(context).size;
    final maxWidth = size.width * 0.75;
    final maxHeight = size.height * 0.75;

    final dialogContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // AppBar replacement - Header (simplified)
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Tooltip(
                message: l10n.settingsPageBackButton,
                child: _IconBtn(
                  icon: Lucide.X,
                  color: cs.onSurface,
                  onTap: () {
                    // If embedded with onBack callback, use it; otherwise pop
                    if (widget.embedded && widget.onBack != null) {
                      widget.onBack!();
                    } else {
                      Navigator.of(context).maybePop();
                    }
                  },
                ),
              ),
              const Spacer(),
              // Enabled switch
              IosSwitch(
                value: cfg.enabled,
                onChanged: (v) async {
                  final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                  await sp.setProviderConfig(widget.keyName, old.copyWith(enabled: v));
                },
              ),
              const SizedBox(width: 8),
              // Test connection
              Tooltip(
                message: l10n.providerDetailPageTestButton,
                child: _IconBtn(
                  icon: Lucide.HeartPulse,
                  onTap: () => _showTestConnectionDialog(context),
                ),
              ),
              const SizedBox(width: 8),
              // Share config
              Tooltip(
                message: l10n.providerDetailPageShareTooltip,
                child: _IconBtn(
                  icon: Lucide.Share2,
                  onTap: () => _shareProvider(context),
                ),
              ),
              const SizedBox(width: 8),
              // Settings button
              Tooltip(
                message: 'Settings',
                child: _IconBtn(
                  icon: Lucide.Settings,
                  onTap: () => _showProviderSettingsDialog(context),
                ),
              ),
              const SizedBox(width: 8),
              // Delete provider (only for user-added)
              if (_isUserAdded(widget.keyName))
                Tooltip(
                  message: l10n.providerDetailPageDeleteButton,
                  child: _IconBtn(
                    icon: Lucide.Trash2,
                    color: cs.error,
                    onTap: () => _deleteProvider(context),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        // Body - List content
        Expanded(
          child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          // Avatar and Name section (moved from header)
          _ProviderHeaderSection(
            providerKey: widget.keyName,
            displayName: widget.displayName,
            customAvatarPath: cfg.customAvatarPath,
            currentName: cfg.name.isNotEmpty ? cfg.name : widget.displayName,
            onAvatarTap: (GlobalKey key) => _showAvatarPickerMenu(context, key),
          ),
          const SizedBox(height: 16),
          
          // Partner info banners
          if (widget.keyName.toLowerCase() == 'kelivoin') ...[
            _buildInfoBanner(
              context,
              text: 'Powered by ',
              linkText: 'Pollinations AI',
              url: 'https://pollinations.ai',
            ),
            const SizedBox(height: 12),
          ],
          if (widget.keyName.toLowerCase() == 'tensdaq') ...[
            _buildInfoBanner(
              context,
              text: '革命性竞价 AI MaaS 平台，价格由市场供需决定，告别高成本固定定价。\n官网：',
              linkText: 'https://dashboard.x-aio.com',
              url: 'https://dashboard.x-aio.com',
            ),
            const SizedBox(height: 12),
          ],
          if (widget.keyName.toLowerCase() == 'siliconflow') ...[
            _buildInfoBanner(
              context,
              text: '已内置硅基流动的免费模型，无需 API Key。若需更强大的模型，请申请并在此配置你自己的 API Key。\n官网：',
              linkText: 'https://siliconflow.cn',
              url: 'https://siliconflow.cn',
            ),
            const SizedBox(height: 12),
          ],

          // API Key section (hidden when Google Vertex)
          if (!(kind == ProviderKind.google && (cfg.vertexAI == true))) ...[
            _sectionLabel(context, l10n.multiKeyPageKey, bold: true),
            const SizedBox(height: 6),
            if (cfg.multiKeyEnabled == true)
              Row(
                children: [
                  Expanded(
                    child: AbsorbPointer(
                      child: Opacity(
                        opacity: 0.6,
                        child: TextField(
                          controller: TextEditingController(text: '••••••••'),
                          readOnly: true,
                          style: const TextStyle(fontSize: 14),
                          decoration: _inputDecoration(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _DeskButton(
                    label: l10n.providerDetailPageManageKeysButton,
                    filled: false,
                    onTap: () => _showMultiKeyDialog(context),
                  ),
                ],
              )
            else
              TextField(
                controller: _apiKeyCtrl,
                obscureText: !_showApiKey,
                onChanged: (v) async {
                  // For API keys, save immediately
                  final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                  await sp.setProviderConfig(widget.keyName, old.copyWith(apiKey: v));
                },
                style: const TextStyle(fontSize: 14),
                decoration: _inputDecoration(context).copyWith(
                  hintText: l10n.providerDetailPageApiKeyHint,
                  suffixIcon: MouseRegion(
                    onEnter: (_) => setState(() => _eyeHover = true),
                    onExit: (_) => setState(() => _eyeHover = false),
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => setState(() => _showApiKey = !_showApiKey),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: _eyeHover
                              ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.black.withOpacity(0.04))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                          child: Icon(
                            _showApiKey ? Lucide.EyeOff : Lucide.Eye,
                            key: ValueKey(_showApiKey),
                            size: 18,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 20),
                ),
              ),
            const SizedBox(height: 14),
          ],

          // API Base URL or Vertex AI fields
          if (!(kind == ProviderKind.google && (cfg.vertexAI == true))) ...[
            _sectionLabel(context, 'API Base URL', bold: true),
            const SizedBox(height: 6),
            Focus(
              onFocusChange: (has) async {
                if (!has) {
                  final v = _sanitizeUrl(_baseUrlCtrl.text);
                  final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                  await sp.setProviderConfig(widget.keyName, old.copyWith(baseUrl: v));
                }
              },
              child: TextField(
                controller: _baseUrlCtrl,
                onChanged: (v) async {
                  if (_baseUrlCtrl.value.composing.isValid) return;
                  final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                  await sp.setProviderConfig(widget.keyName, old.copyWith(baseUrl: _sanitizeUrl(v)));
                },
                style: const TextStyle(fontSize: 14),
                decoration: _inputDecoration(context).copyWith(
                  hintText: ProviderConfig.defaultsFor(widget.keyName, displayName: widget.displayName).baseUrl,
                ),
              ),
            ),
          ] else ...[
            // Vertex AI fields
            _sectionLabel(context, l10n.providerDetailPageLocationLabel, bold: true),
            const SizedBox(height: 6),
            Focus(
              onFocusChange: (has) async {
                if (!has) {
                  final v = _locationCtrl.text.trim();
                  final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                  await sp.setProviderConfig(widget.keyName, old.copyWith(location: v));
                }
              },
              child: TextField(
                controller: _locationCtrl,
                onChanged: (v) async {
                  if (_locationCtrl.value.composing.isValid) return;
                  final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                  await sp.setProviderConfig(widget.keyName, old.copyWith(location: v.trim()));
                },
                style: const TextStyle(fontSize: 14),
                decoration: _inputDecoration(context).copyWith(hintText: 'us-central1'),
              ),
            ),
            const SizedBox(height: 14),
            _sectionLabel(context, l10n.providerDetailPageProjectIdLabel, bold: true),
            const SizedBox(height: 6),
            Focus(
              onFocusChange: (has) async {
                if (!has) {
                  final v = _projectIdCtrl.text.trim();
                  final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                  await sp.setProviderConfig(widget.keyName, old.copyWith(projectId: v));
                }
              },
              child: TextField(
                controller: _projectIdCtrl,
                onChanged: (v) async {
                  if (_projectIdCtrl.value.composing.isValid) return;
                  final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                  await sp.setProviderConfig(widget.keyName, old.copyWith(projectId: v.trim()));
                },
                style: const TextStyle(fontSize: 14),
                decoration: _inputDecoration(context).copyWith(hintText: 'my-project-id'),
              ),
            ),
            const SizedBox(height: 14),
            _sectionLabel(context, l10n.providerDetailPageServiceAccountJsonLabel, bold: true),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 120),
              child: Focus(
                onFocusChange: (has) async {
                  if (!has) {
                    final v = _saJsonCtrl.text;
                    final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                    await sp.setProviderConfig(widget.keyName, old.copyWith(serviceAccountJson: v));
                  }
                },
                child: TextField(
                  controller: _saJsonCtrl,
                  maxLines: null,
                  minLines: 6,
                  onChanged: (v) async {
                    if (_saJsonCtrl.value.composing.isValid) return;
                    final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                    await sp.setProviderConfig(widget.keyName, old.copyWith(serviceAccountJson: v));
                  },
                  style: const TextStyle(fontSize: 14),
                  decoration: _inputDecoration(context).copyWith(
                    hintText: '{\n  "type": "service_account", ...\n}',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _DeskButton(
                label: l10n.providerDetailPageImportJsonButton,
                filled: false,
                onTap: () => _importServiceAccountJson(context),
              ),
            ),
          ],

          // API Path (OpenAI chat)
          if (kind == ProviderKind.openai && (cfg.useResponseApi != true)) ...[
            const SizedBox(height: 14),
            _sectionLabel(context, l10n.providerDetailPageApiPathLabel, bold: true),
            const SizedBox(height: 6),
            Focus(
              onFocusChange: (has) async {
                if (!has) {
                  final v = _sanitizeUrl(_apiPathCtrl.text);
                  final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                  await sp.setProviderConfig(widget.keyName, old.copyWith(chatPath: v));
                }
              },
              child: TextField(
                controller: _apiPathCtrl,
                onChanged: (v) async {
                  if (_apiPathCtrl.value.composing.isValid) return;
                  final old = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                  await sp.setProviderConfig(widget.keyName, old.copyWith(chatPath: _sanitizeUrl(v)));
                },
                style: const TextStyle(fontSize: 14),
                decoration: _inputDecoration(context).copyWith(hintText: '/chat/completions'),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Add/Fetch model buttons (moved here from below models)
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DeskButton(
                  label: l10n.providerDetailPageFetchModelsButton,
                  filled: true,
                  onTap: () => _fetchModels(context),
                ),
                const SizedBox(width: 8),
                _DeskButton(
                  label: l10n.addProviderSheetAddButton ?? 'Add Model',
                  filled: false,
                  onTap: () => _addModel(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Models section header
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      l10n.providerDetailPageModelsTab,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    _GreyCapsule(label: '${models.length}'),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => SizeTransition(
                  sizeFactor: anim,
                  axis: Axis.horizontal,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: _showSearch
                    ? SizedBox(
                        key: const ValueKey('search-field'),
                        width: 240,
                        child: TextField(
                          controller: _filterCtrl,
                          focusNode: _searchFocus,
                          autofocus: true,
                          style: const TextStyle(fontSize: 14),
                          decoration: _inputDecoration(context).copyWith(
                            hintText: l10n.providerDetailPageFilterHint,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      )
                    : _IconBtn(
                        key: const ValueKey('search-icon'),
                        icon: Lucide.Search,
                        onTap: () => setState(() {
                          _showSearch = true;
                          _searchFocus.addListener(() {
                            if (!_searchFocus.hasFocus) setState(() => _showSearch = false);
                          });
                        }),
                      ),
              ),
              const SizedBox(width: 8),
              _IconBtn(
                icon: Lucide.HeartPulse,
                onTap: () => _showTestConnectionDialog(context),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Model groups (default expanded)
          for (final entry in groups.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ModelGroupAccordion(
                group: entry.key,
                modelIds: entry.value,
                providerKey: widget.keyName,
              ),
            ),

          const SizedBox(height: 12),
        ],
          ),
        ),
      ],
    );

    final dialog = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
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
            child: dialogContent,
          ),
        ),
      ),
    );

    // Embedded mode: return content directly without dialog wrapper
    if (widget.embedded) {
      return Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          // Listen for ESC key to go back to provider list
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            if (widget.onBack != null) {
              widget.onBack!();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: cs.surface,  // Use theme surface color for consistency
          elevation: 0,
          child: dialogContent,
        ),
      );
    }

    // Dialog mode: return with dialog wrapper
    return Material(
      type: MaterialType.transparency,
      child: dialog,
    );
  }

  // ========== Helper Methods ==========

  Map<String, List<String>> _groupModels(List<String> models) {
    final map = <String, List<String>>{};
    for (final m in models) {
      var g = m;
      if (m.contains('/')) {
        g = m.split('/').first;
      } else if (m.contains(':')) {
        g = m.split(':').first;
      } else if (m.contains('-')) {
        g = m.split('-').first;
      }
      (map[g] ??= <String>[]).add(m);
    }
    // Stable sort by key
    final entries = map.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return {for (final e in entries) e.key: e.value};
  }

  List<String> _applyFilter(List<String> src, String q) {
    if (q.isEmpty) return src;
    final k = q.toLowerCase();
    return [for (final m in src) if (m.toLowerCase().contains(k)) m];
  }

  InputDecoration _inputDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      isDense: true,
      filled: true,
      // 增强对比度：深色模式更明显，浅色模式更深
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
    );
  }

  Widget _buildInfoBanner(BuildContext context, {required String text, required String linkText, required String url}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withOpacity(0.35)),
      ),
      child: Text.rich(
        TextSpan(
          text: text,
          style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
          children: [
            TextSpan(
              text: linkText,
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  final uri = Uri.parse(url);
                  try {
                    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                    if (!ok) await launchUrl(uri);
                  } catch (_) {
                    await launchUrl(uri);
                  }
                },
            ),
          ],
        ),
      ),
    );
  }
  // ========== Action Methods ==========

  Future<void> _showProviderSettingsDialog(BuildContext context) async {
    await showDesktopProviderSettingsDialog(
      context,
      providerKey: widget.keyName,
      displayName: widget.displayName,
    );
  }

  Future<void> _showAvatarPickerMenu(BuildContext context, GlobalKey avatarKey) async {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.read<SettingsProvider>();
    
    await showDesktopAnchoredMenu(
      context,
      anchorKey: avatarKey,
      offset: const Offset(0, 8),
      items: [
        DesktopContextMenuItem(
          icon: Lucide.User,
          label: l10n.desktopAvatarMenuUseEmoji,
          onTap: () async => await _pickEmoji(context),
        ),
        DesktopContextMenuItem(
          icon: Lucide.Image,
          label: l10n.desktopAvatarMenuChangeFromImage,
          onTap: () async => await _pickLocalImage(context),
        ),
        DesktopContextMenuItem(
          icon: Lucide.Link,
          label: l10n.sideDrawerEnterLink,
          onTap: () async => await _inputImageUrl(context),
        ),
        DesktopContextMenuItem(
          icon: Icons.person_outline,
          label: 'QQ头像',
          onTap: () async => await _inputQQAvatar(context),
        ),
        DesktopContextMenuItem(
          icon: Lucide.RotateCw,
          label: l10n.desktopAvatarMenuReset,
          onTap: () async {
            final cfg = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
            if (cfg.customAvatarPath != null && cfg.customAvatarPath!.isNotEmpty) {
              if (cfg.customAvatarPath!.length > 4) {
                await ProviderAvatarManager.deleteAvatar(cfg.customAvatarPath!);
              }
              await sp.setProviderConfig(widget.keyName, cfg.copyWith(customAvatarPath: ''));
            }
          },
        ),
      ],
    );
  }

  Future<void> _pickEmoji(BuildContext context) async {
    final emoji = await showDesktopEmojiPickerDialog(context);
    print('🎨 [_pickEmoji] Selected emoji: $emoji');
    if (emoji != null && emoji.isNotEmpty && mounted) {
      final sp = context.read<SettingsProvider>();
      final cfg = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
      
      print('📝 [_pickEmoji] Current customAvatarPath: ${cfg.customAvatarPath}');
      
      // Delete old avatar file if exists (but not emoji)
      if (cfg.customAvatarPath != null &&
          cfg.customAvatarPath!.isNotEmpty &&
          cfg.customAvatarPath!.length > 4) {
        print('🗑️ [_pickEmoji] Deleting old avatar: ${cfg.customAvatarPath}');
        await ProviderAvatarManager.deleteAvatar(cfg.customAvatarPath!);
      }
      
      print('💾 [_pickEmoji] Saving emoji: $emoji for provider: ${widget.keyName}');
      await sp.setProviderConfig(widget.keyName, cfg.copyWith(customAvatarPath: emoji));
      
      // Verify it was saved
      final newCfg = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
      print('✅ [_pickEmoji] Saved! New customAvatarPath: ${newCfg.customAvatarPath}');
      
      showAppSnackBar(context, message: '表情已保存');
    }
  }

  Future<void> _pickLocalImage(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();

        final relativePath = await ProviderAvatarManager.saveAvatar(widget.keyName, bytes);

        if (mounted) {
          final sp = context.read<SettingsProvider>();
          final cfg = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);

          // Delete old avatar if exists
          if (cfg.customAvatarPath != null && cfg.customAvatarPath!.isNotEmpty) {
            await ProviderAvatarManager.deleteAvatar(cfg.customAvatarPath!);
          }

          await sp.setProviderConfig(widget.keyName, cfg.copyWith(customAvatarPath: relativePath));
          showAppSnackBar(context, message: '头像已保存');
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, message: '保存头像失败: $e', type: NotificationType.error);
      }
    }
  }

  Future<void> _inputImageUrl(BuildContext context) async {
    final url = await showDesktopTextInputDialog(
      context,
      title: '图片URL',
      hint: 'https://example.com/avatar.png',
    );

    if (url != null && url.trim().isNotEmpty && mounted) {
      try {
        final response = await http.get(Uri.parse(url.trim())).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200 && mounted) {
          final bytes = response.bodyBytes;
          final relativePath = await ProviderAvatarManager.saveAvatar(widget.keyName, bytes);

          if (mounted) {
            final sp = context.read<SettingsProvider>();
            final cfg = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);

            // Delete old avatar if exists
            if (cfg.customAvatarPath != null && cfg.customAvatarPath!.isNotEmpty) {
              await ProviderAvatarManager.deleteAvatar(cfg.customAvatarPath!);
            }

            await sp.setProviderConfig(widget.keyName, cfg.copyWith(customAvatarPath: relativePath));
            showAppSnackBar(context, message: '头像已保存');
          }
        } else if (mounted) {
          showAppSnackBar(context, message: '下载图片失败: HTTP ${response.statusCode}', type: NotificationType.error);
        }
      } catch (e) {
        if (mounted) {
          showAppSnackBar(context, message: '下载图片失败: $e', type: NotificationType.error);
        }
      }
    }
  }

  Future<void> _inputQQAvatar(BuildContext context) async {
    final qq = await showDesktopQQInputDialog(context);

    if (qq != null && qq.trim().isNotEmpty && mounted) {
      try {
        final url = 'https://q2.qlogo.cn/headimg_dl?dst_uin=${qq.trim()}&spec=100';
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty && mounted) {
          final bytes = response.bodyBytes;
          final relativePath = await ProviderAvatarManager.saveAvatar(widget.keyName, bytes);

          if (mounted) {
            final sp = context.read<SettingsProvider>();
            final cfg = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);

            // Delete old avatar if exists
            if (cfg.customAvatarPath != null && cfg.customAvatarPath!.isNotEmpty) {
              await ProviderAvatarManager.deleteAvatar(cfg.customAvatarPath!);
            }

            await sp.setProviderConfig(widget.keyName, cfg.copyWith(customAvatarPath: relativePath));
            showAppSnackBar(context, message: 'QQ头像已保存');
          }
        } else if (mounted) {
          showAppSnackBar(context, message: '下载QQ头像失败', type: NotificationType.error);
        }
      } catch (e) {
        if (mounted) {
          showAppSnackBar(context, message: '下载QQ头像失败: $e', type: NotificationType.error);
        }
      }
    }
  }

  Future<void> _showTestConnectionDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _DesktopConnectionTestDialog(
        providerKey: widget.keyName,
        displayName: widget.displayName,
      ),
    );
  }

  Future<void> _fetchModels(BuildContext context) async {
    await showDesktopModelFetchDialog(
      context,
      providerKey: widget.keyName,
      providerDisplayName: widget.displayName,
    );
  }

  Future<void> _addModel(BuildContext context) async {
    final ok = await showDesktopCreateModelDialog(context, providerKey: widget.keyName);
    if (!mounted) return;
    if (ok == true) {
      setState(() {});
    }
  }

  // Old inline implementation (replaced by imported dialog)
  Future<void> _showDesktopModelFetchDialogOld(BuildContext context) async {
    final sp = context.read<SettingsProvider>();
    final cfg = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    final l10n = AppLocalizations.of(context)!;
    
    // Check if we have API key for providers that need it
    final bool _isDefaultSilicon = widget.keyName.toLowerCase() == 'siliconflow';
    final bool _hasUserKey = (cfg.multiKeyEnabled == true && (cfg.apiKeys?.isNotEmpty == true)) || cfg.apiKey.trim().isNotEmpty;
    final bool _restrictToFree = _isDefaultSilicon && !_hasUserKey;

    List<dynamic> items = [];
    bool loading = true;
    String error = '';
    final Set<String> selected = Set<String>.from(cfg.models);
    final filterCtrl = TextEditingController();

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'model-fetch-dialog',
      barrierColor: Colors.black.withOpacity(0.25),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) {
        final cs = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final size = MediaQuery.of(ctx).size;

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            // Load models on first build
            if (loading && items.isEmpty && error.isEmpty) {
              Future.microtask(() async {
                try {
                  if (_restrictToFree) {
                    // SiliconFlow free models only
                    final list = <ModelInfo>[
                      ModelRegistry.infer(ModelInfo(id: 'THUDM/GLM-4-9B-0414', displayName: 'THUDM/GLM-4-9B-0414')),
                      ModelRegistry.infer(ModelInfo(id: 'Qwen/Qwen3-8B', displayName: 'Qwen/Qwen3-8B')),
                    ];
                    setLocal(() {
                      items = list;
                      loading = false;
                    });
                  } else {
                    final list = await ProviderManager.listModels(cfg);
                    setLocal(() {
                      items = list;
                      loading = false;
                    });
                  }
                } catch (e) {
                  setLocal(() {
                    items = [];
                    loading = false;
                    error = e.toString();
                  });
                }
              });
            }

            final query = filterCtrl.text.trim().toLowerCase();
            final filtered = <ModelInfo>[
              for (final m in items)
                if (m is ModelInfo && (query.isEmpty || m.id.toLowerCase().contains(query) || m.displayName.toLowerCase().contains(query))) m
            ];

            // Group models
            final Map<String, List<ModelInfo>> grouped = {};
            for (final m in filtered) {
              final g = _groupForModel(m, l10n);
              (grouped[g] ??= []).add(m);
            }
            final groupKeys = grouped.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: size.width * 0.65,
                  maxHeight: size.height * 0.75,
                ),
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.providerDetailPageFetchModelsButton,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                              ),
                              _IconBtn(
                                icon: Lucide.X,
                                color: cs.onSurface,
                                onTap: () => Navigator.of(ctx).pop(),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.12)),

                        // Search field
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: TextField(
                            controller: filterCtrl,
                            onChanged: (_) => setLocal(() {}),
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: l10n.providerDetailPageFilterHint,
                              filled: true,
                              fillColor: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFEBECF0),
                              prefixIcon: Icon(Lucide.Search, size: 18, color: cs.onSurface.withOpacity(0.7)),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tooltip(
                                    message: filtered.isNotEmpty && filtered.every((m) => selected.contains(m.id)) 
                                      ? l10n.mcpAssistantSheetClearAll
                                      : l10n.mcpAssistantSheetSelectAll,
                                    child: _IconBtn(
                                      icon: filtered.isNotEmpty && filtered.every((m) => selected.contains(m.id))
                                        ? Lucide.Square
                                        : Lucide.CheckSquare,
                                      color: cs.onSurface.withOpacity(0.7),
                                      onTap: () async {
                                        if (filtered.isEmpty) return;
                                        final allSelected = filtered.every((m) => selected.contains(m.id));
                                        if (allSelected) {
                                          // Deselect all filtered
                                          for (final m in filtered) {
                                            selected.remove(m.id);
                                          }
                                        } else {
                                          // Select all filtered
                                          for (final m in filtered) {
                                            selected.add(m.id);
                                          }
                                        }
                                        await sp.setProviderConfig(widget.keyName, cfg.copyWith(models: selected.toList()));
                                        setLocal(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Tooltip(
                                    message: l10n.modelFetchInvertTooltip,
                                    child: _IconBtn(
                                      icon: Lucide.Repeat,
                                      color: cs.onSurface.withOpacity(0.7),
                                      onTap: () async {
                                        if (filtered.isEmpty) return;
                                        for (final m in filtered) {
                                          if (selected.contains(m.id)) {
                                            selected.remove(m.id);
                                          } else {
                                            selected.add(m.id);
                                          }
                                        }
                                        await sp.setProviderConfig(widget.keyName, cfg.copyWith(models: selected.toList()));
                                        setLocal(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: cs.primary.withOpacity(0.4)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                          ),
                        ),

                        // Content
                        Expanded(
                          child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : error.isNotEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      error,
                                      style: TextStyle(color: cs.error),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                  itemCount: groupKeys.length,
                                  itemBuilder: (c, i) {
                                    final g = groupKeys[i];
                                    final models = grouped[g]!;
                                    return _DesktopModelGroup(
                                      groupName: g,
                                      models: models,
                                      selected: selected,
                                      onToggleGroup: () async {
                                        final allAdded = models.every((m) => selected.contains(m.id));
                                        if (allAdded) {
                                          for (final m in models) {
                                            selected.remove(m.id);
                                          }
                                        } else {
                                          for (final m in models) {
                                            if (!selected.contains(m.id)) {
                                              selected.add(m.id);
                                            }
                                          }
                                        }
                                        await sp.setProviderConfig(widget.keyName, cfg.copyWith(models: selected.toList()));
                                        setLocal(() {});
                                      },
                                      onToggleModel: (modelId) async {
                                        if (selected.contains(modelId)) {
                                          selected.remove(modelId);
                                        } else {
                                          selected.add(modelId);
                                        }
                                        await sp.setProviderConfig(widget.keyName, cfg.copyWith(models: selected.toList()));
                                        setLocal(() {});
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
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

  String _groupForModel(ModelInfo m, AppLocalizations l10n) {
    final id = m.id.toLowerCase();
    // Embeddings first
    if (m.type == ModelType.embedding || id.contains('embedding') || id.contains('embed')) {
      return l10n.providerDetailPageEmbeddingsGroupTitle;
    }
    // GPT models
    if (id.contains('gpt') || RegExp(r'(^|[^a-z])o[134]').hasMatch(id)) return 'GPT';
    // Gemini
    if (id.contains('gemini-2.0')) return 'Gemini 2.0';
    if (id.contains('gemini-2.5')) return 'Gemini 2.5';
    if (id.contains('gemini-1.5')) return 'Gemini 1.5';
    if (id.contains('gemini')) return 'Gemini';
    // Claude
    if (id.contains('claude-3.5')) return 'Claude 3.5';
    if (id.contains('claude-3')) return 'Claude 3';
    if (id.contains('claude-4')) return 'Claude 4';
    if (id.contains('claude-sonnet')) return 'Claude Sonnet';
    if (id.contains('claude-opus')) return 'Claude Opus';
    // Others
    if (id.contains('deepseek')) return 'DeepSeek';
    if (RegExp(r'qwen|qwq|qvq|dashscope').hasMatch(id)) return 'Qwen';
    if (RegExp(r'doubao|ark|volc').hasMatch(id)) return 'Doubao';
    if (id.contains('glm') || id.contains('zhipu')) return 'GLM';
    if (id.contains('mistral')) return 'Mistral';
    if (id.contains('grok') || id.contains('xai')) return 'Grok';
    return l10n.providerDetailPageOtherModelsGroupTitle;
  }

  Future<void> _shareProvider(BuildContext context) async {
    await showShareProviderSheet(context, widget.keyName);
  }

  Future<void> _deleteProvider(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.providerDetailPageDeleteProviderTitle),
        content: Text(l10n.providerDetailPageDeleteProviderContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.providerDetailPageCancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.providerDetailPageDeleteButton),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<SettingsProvider>().removeProviderConfig(widget.keyName);
      if (mounted) {
        // In embedded mode, use callback to go back; in dialog mode, pop navigator
        if (widget.embedded && widget.onBack != null) {
          widget.onBack!();
        } else {
          Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> _showMultiKeyDialog(BuildContext context) async {
    // On desktop, show as centered dialog instead of full-page route.
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final theme = Theme.of(context);
      final size = MediaQuery.of(context).size;
      final width = size.width.clamp(800.0, 1100.0);
      final height = size.height.clamp(520.0, 820.0);

      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'multi-key-manager-dialog',
        barrierColor: Colors.black.withOpacity(0.25),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, _, __) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width * 0.8,
                maxHeight: height * 0.8,
              ),
              child: Material(
                color: theme.colorScheme.surface,
                elevation: 16,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: MultiKeyManagerPage(
                  providerKey: widget.keyName,
                  providerDisplayName: widget.displayName,
                ),
              ),
            ),
          );
        },
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultiKeyManagerPage(
          providerKey: widget.keyName,
          providerDisplayName: widget.displayName,
        ),
      ),
    );
  }

  Future<void> _importServiceAccountJson(BuildContext context) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (res != null && res.files.isNotEmpty && mounted) {
      final file = res.files.first;
      final content = String.fromCharCodes(file.bytes ?? []);
      final sp = context.read<SettingsProvider>();
      final cfg = sp.getProviderConfig(widget.keyName, defaultName: widget.displayName);

      String projectId = cfg.projectId ?? '';
      try {
        final obj = jsonDecode(content);
        projectId = (obj['project_id'] as String?)?.trim() ?? projectId;
      } catch (_) {}

      await sp.setProviderConfig(
        widget.keyName,
        cfg.copyWith(
          serviceAccountJson: content,
          projectId: projectId,
        ),
      );
    }
  }

}

// ========== Helper Widgets ==========

Widget _sectionLabel(BuildContext context, String text, {bool bold = false}) {
  final cs = Theme.of(context).colorScheme;
  return Text(
    text,
    style: TextStyle(
      fontSize: 13,
      color: cs.onSurface.withOpacity(0.8),
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    ),
  );
}

class _GreyCapsule extends StatelessWidget {
  const _GreyCapsule({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF2F3F5);
    final fg = Theme.of(context).colorScheme.onSurface.withOpacity(0.85);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

class _IconBtn extends StatefulWidget {
  const _IconBtn({super.key, required this.icon, required this.onTap, this.color});
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover
        ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05))
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Icon(widget.icon, size: 18, color: widget.color ?? cs.onSurface),
        ),
      ),
    );
  }
}

class _DeskButton extends StatefulWidget {
  const _DeskButton({required this.label, required this.filled, required this.onTap});
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  State<_DeskButton> createState() => _DeskButtonState();
}

class _DeskButtonState extends State<_DeskButton> {
  bool _pressed = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = cs.primary;
    final textColor = widget.filled ? cs.onPrimary : baseColor;
    final baseBg = widget.filled ? baseColor : (isDark ? Colors.white10 : Colors.transparent);

    final bg = _pressed
        ? (widget.filled ? baseColor.withOpacity(0.85) : baseBg)
        : _hover
            ? (widget.filled ? baseColor.withOpacity(0.92) : (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06)))
            : baseBg;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: widget.filled ? null : Border.all(color: cs.outlineVariant.withOpacity(0.3)),
          ),
          child: Text(
            widget.label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
          ),
        ),
      ),
    );
  }
}

class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({super.key, required this.name, this.size = 22, this.customAvatarPath, this.providerKey});
  final String name;
  final double size;
  final String? customAvatarPath;
  final String? providerKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check if custom avatar exists
    if (customAvatarPath != null && customAvatarPath!.isNotEmpty) {
      // Check if emoji (single character)
      if (customAvatarPath!.length <= 4 && customAvatarPath!.runes.length == 1) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : cs.primary.withOpacity(0.10),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            customAvatarPath!,
            style: TextStyle(fontSize: size * 0.55),
          ),
        );
      }

      // Check if file exists (use FutureBuilder for async path resolution)
      return FutureBuilder<String?>(
        future: ProviderAvatarManager.getAvatarPath(customAvatarPath!),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            final file = File(snapshot.data!);
            final exists = file.existsSync();
            if (exists) {
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: FileImage(file),
                    fit: BoxFit.cover,
                  ),
                ),
              );
            }
          }
          // Fallback if file doesn't exist or not loaded yet
          return _buildFallbackAvatar(context, size);
        },
      );
    }

    return _buildFallbackAvatar(context, size);
  }

  Widget _buildFallbackAvatar(BuildContext context, double size) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Fallback to brand asset or initial (use providerKey if available)
    final lookupName = providerKey ?? name;
    final asset = BrandAssets.assetForName(lookupName);
    Widget inner;
    if (asset == null) {
      inner = Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.45,
        ),
      );
    } else if (asset.endsWith('.svg')) {
      inner = SvgPicture.asset(asset, width: size * 0.62, height: size * 0.62, fit: BoxFit.contain);
    } else {
      inner = Image.asset(asset, width: size * 0.62, height: size * 0.62, fit: BoxFit.contain);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withOpacity(0.10),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}

// Model group accordion (default expanded)
class _ModelGroupAccordion extends StatefulWidget {
  const _ModelGroupAccordion({
    required this.group,
    required this.modelIds,
    required this.providerKey,
  });

  final String group;
  final List<String> modelIds;
  final String providerKey;

  @override
  State<_ModelGroupAccordion> createState() => _ModelGroupAccordionState();
}

class _ModelGroupAccordionState extends State<_ModelGroupAccordion> {
  bool _open = true; // Default expanded

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.03)
                      : Colors.black.withOpacity(0.02),
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: _open ? 0.25 : 0.0, // right (0) -> down (0.25)
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Icon(Lucide.ChevronRight, size: 16, color: cs.onSurface.withOpacity(0.9)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.group,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    _GreyCapsule(label: '${widget.modelIds.length}'),
                  ],
                ),
              ),
            ),
          ),
          // Content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                for (final id in widget.modelIds)
                  _ModelRow(modelId: id, providerKey: widget.providerKey),
              ],
            ),
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

// Model row - simplified version
class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.modelId, required this.providerKey});
  final String modelId;
  final String providerKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sp = context.watch<SettingsProvider>();
    final cfg = sp.getProviderConfig(providerKey);
    
    // Get model info with capabilities (including user overrides)
    final ModelInfo modelInfo = _getEffectiveModelInfo(modelId, cfg);
    
    // Build capability icons
    final caps = <Widget>[];
    Widget pillCapsule(Widget icon, Color color) {
      final bg = isDark ? color.withOpacity(0.20) : color.withOpacity(0.16);
      final bd = color.withOpacity(0.25);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: bd, width: 0.5),
        ),
        child: icon,
      );
    }
    
    // Vision input
    if (modelInfo.input.contains(Modality.image)) {
      caps.add(pillCapsule(Icon(Lucide.Eye, size: 11, color: cs.secondary), cs.secondary));
    }
    // Image output
    if (modelInfo.output.contains(Modality.image)) {
      caps.add(pillCapsule(Icon(Lucide.Image, size: 11, color: cs.tertiary), cs.tertiary));
    }
    // Abilities
    for (final ab in modelInfo.abilities) {
      if (ab == ModelAbility.tool) {
        caps.add(pillCapsule(Icon(Lucide.Hammer, size: 11, color: cs.primary), cs.primary));
      } else if (ab == ModelAbility.reasoning) {
        caps.add(pillCapsule(
          SvgPicture.asset('assets/icons/deepthink.svg', width: 11, height: 11, colorFilter: ColorFilter.mode(cs.secondary, BlendMode.srcIn)), 
          cs.secondary,
        ));
      }
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              modelId,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          ...caps.map((w) => Padding(padding: const EdgeInsets.only(left: 4), child: w)),
          const SizedBox(width: 8),
          // Settings button
          _IconBtn(
            icon: Lucide.Settings2,
            onTap: () {
              showDesktopModelEditDialog(context, modelId: modelId, providerKey: providerKey);
            },
          ),
          const SizedBox(width: 6),
          // Delete button
          _IconBtn(
            icon: Lucide.Trash2,
            color: cs.error,
            onTap: () async {
              final l10n = AppLocalizations.of(context)!;
              final ok = await showDialog<bool>(
                context: context,
                builder: (dctx) => AlertDialog(
                  backgroundColor: cs.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text(l10n.providerDetailPageConfirmDeleteTitle),
                  content: Text(l10n.providerDetailPageConfirmDeleteContent),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dctx).pop(false),
                      child: Text(l10n.providerDetailPageCancelButton),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dctx).pop(true),
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                      child: Text(l10n.providerDetailPageDeleteButton),
                    ),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              
              final settings = context.read<SettingsProvider>();
              final old = settings.getProviderConfig(providerKey);
              final prevList = List<String>.from(old.models);
              final prevOverrides = Map<String, dynamic>.from(old.modelOverrides);
              final newList = prevList.where((e) => e != modelId).toList();
              final newOverrides = Map<String, dynamic>.from(prevOverrides)..remove(modelId);
              await settings.setProviderConfig(providerKey, old.copyWith(models: newList, modelOverrides: newOverrides));
            },
          ),
        ],
      ),
    );
  }
}

// ========== Desktop Provider Settings Dialog ==========

/// Desktop-style settings dialog for provider configuration
/// Includes Name, Avatar, Provider Type, Multi-Key, Response API, Vertex AI, and Network Proxy
Future<void> showDesktopProviderSettingsDialog(
  BuildContext context, {
  required String providerKey,
  required String displayName,
}) async {
  final cs = Theme.of(context).colorScheme;
  final sp = context.read<SettingsProvider>();
  final l10n = AppLocalizations.of(context)!;
  final cfg = sp.getProviderConfig(providerKey, defaultName: displayName);

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'provider-settings-dialog',
    barrierColor: Colors.black.withOpacity(0.25),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) {
      final nameCtrl = TextEditingController(text: cfg.name);
      final proxyHostCtrl = TextEditingController(text: cfg.proxyHost ?? '');
      final proxyPortCtrl = TextEditingController(text: cfg.proxyPort ?? '8080');
      final proxyUserCtrl = TextEditingController(text: cfg.proxyUsername ?? '');
      final proxyPassCtrl = TextEditingController(text: cfg.proxyPassword ?? '');

      return Dialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Consumer<SettingsProvider>(
            builder: (c, spWatch, _) {
              final cfgNow = spWatch.getProviderConfig(providerKey, defaultName: displayName);

              // IME-friendly sync: avoid overwriting while composing
              void syncCtrl(TextEditingController ctrl, String text) {
                final v = ctrl.value;
                if (v.composing.isValid) return;
                if (ctrl.text != text) {
                  ctrl.value = TextEditingValue(
                    text: text,
                    selection: TextSelection.collapsed(offset: text.length),
                  );
                }
              }

              syncCtrl(nameCtrl, cfgNow.name);
              syncCtrl(proxyHostCtrl, cfgNow.proxyHost ?? '');
              syncCtrl(proxyPortCtrl, cfgNow.proxyPort ?? '8080');
              syncCtrl(proxyUserCtrl, cfgNow.proxyUsername ?? '');
              syncCtrl(proxyPassCtrl, cfgNow.proxyPassword ?? '');

              final kindNow = cfgNow.providerType ?? ProviderConfig.classify(cfgNow.id, explicitType: cfgNow.providerType);
              final multiNow = cfgNow.multiKeyEnabled ?? false;
              final respNow = cfgNow.useResponseApi ?? false;
              final vertexNow = cfgNow.vertexAI ?? false;
              final proxyEnabledNow = cfgNow.proxyEnabled ?? false;

              Widget row(String label, Widget trailing) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.9)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(width: 280, child: trailing),
                      ],
                    ),
                  );

              InputDecoration inputDeco(BuildContext context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final cs = Theme.of(context).colorScheme;
                return InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.12), width: 0.6),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.12), width: 0.6),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: cs.primary.withOpacity(0.35), width: 0.8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              cfgNow.name.isNotEmpty ? cfgNow.name : providerKey,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                          _IconBtn(
                            icon: Lucide.X,
                            onTap: () => Navigator.of(ctx).maybePop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.12)),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1) Name
                        row(
                          l10n.providerDetailPageNameLabel,
                          Focus(
                            onFocusChange: (has) async {
                              if (!has) {
                                final v = nameCtrl.text.trim();
                                final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                await spWatch.setProviderConfig(providerKey, old.copyWith(name: v.isEmpty ? displayName : v));
                              }
                            },
                            child: TextField(
                              controller: nameCtrl,
                              style: const TextStyle(fontSize: 14),
                              decoration: inputDeco(ctx),
                              onChanged: (_) async {
                                if (nameCtrl.value.composing.isValid) return;
                                final v = nameCtrl.text.trim();
                                final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                await spWatch.setProviderConfig(providerKey, old.copyWith(name: v.isEmpty ? displayName : v));
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // 2) Custom Avatar
                        row(
                          'Custom Avatar',
                          _AvatarEditButton(
                            providerKey: providerKey,
                            displayName: displayName,
                            customAvatarPath: cfgNow.customAvatarPath,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // 3) Provider Type
                        row(
                          l10n.providerDetailPageProviderTypeTitle,
                          _ProviderTypeDropdown(
                            value: kindNow,
                            onChanged: (k) async {
                              final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                              await spWatch.setProviderConfig(providerKey, old.copyWith(providerType: k));
                            },
                          ),
                        ),
                        const SizedBox(height: 4),

                        // 4) Multi-Key
                        row(
                          l10n.providerDetailPageMultiKeyModeTitle,
                          Align(
                            alignment: Alignment.centerRight,
                            child: IosSwitch(
                              value: multiNow,
                              onChanged: (v) async {
                                final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                await spWatch.setProviderConfig(providerKey, old.copyWith(multiKeyEnabled: v));
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // 5) Response API (OpenAI) or Vertex AI (Google)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: () {
                            if (kindNow == ProviderKind.openai) {
                              return KeyedSubtree(
                                key: const ValueKey('openai-resp'),
                                child: row(
                                  l10n.providerDetailPageResponseApiTitle,
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IosSwitch(
                                      value: respNow,
                                      onChanged: (v) async {
                                        final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                        await spWatch.setProviderConfig(providerKey, old.copyWith(useResponseApi: v));
                                      },
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (kindNow == ProviderKind.google) {
                              return KeyedSubtree(
                                key: const ValueKey('google-vertex'),
                                child: row(
                                  l10n.providerDetailPageVertexAiTitle,
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IosSwitch(
                                      value: vertexNow,
                                      onChanged: (v) async {
                                        final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                        await spWatch.setProviderConfig(providerKey, old.copyWith(vertexAI: v));
                                      },
                                    ),
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink(key: ValueKey('none'));
                          }(),
                        ),
                        const SizedBox(height: 4),

                        // 6) Network Proxy
                        row(
                          l10n.providerDetailPageNetworkTab,
                          Align(
                            alignment: Alignment.centerRight,
                            child: IosSwitch(
                              value: proxyEnabledNow,
                              onChanged: (v) async {
                                final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                await spWatch.setProviderConfig(providerKey, old.copyWith(proxyEnabled: v));
                              },
                            ),
                          ),
                        ),
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                row(
                                  l10n.providerDetailPageHostLabel,
                                  Focus(
                                    onFocusChange: (has) async {
                                      if (!has) {
                                        final v = proxyHostCtrl.text.trim();
                                        final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                        await spWatch.setProviderConfig(providerKey, old.copyWith(proxyHost: v));
                                      }
                                    },
                                    child: TextField(
                                      controller: proxyHostCtrl,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: inputDeco(ctx).copyWith(hintText: '127.0.0.1'),
                                      onChanged: (_) async {
                                        if (proxyHostCtrl.value.composing.isValid) return;
                                        final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                        await spWatch.setProviderConfig(providerKey, old.copyWith(proxyHost: proxyHostCtrl.text.trim()));
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                row(
                                  l10n.providerDetailPagePortLabel,
                                  Focus(
                                    onFocusChange: (has) async {
                                      if (!has) {
                                        final v = proxyPortCtrl.text.trim();
                                        final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                        await spWatch.setProviderConfig(providerKey, old.copyWith(proxyPort: v));
                                      }
                                    },
                                    child: TextField(
                                      controller: proxyPortCtrl,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: inputDeco(ctx).copyWith(hintText: '8080'),
                                      onChanged: (_) async {
                                        if (proxyPortCtrl.value.composing.isValid) return;
                                        final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                        await spWatch.setProviderConfig(providerKey, old.copyWith(proxyPort: proxyPortCtrl.text.trim()));
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                row(
                                  l10n.providerDetailPageUsernameOptionalLabel,
                                  Focus(
                                    onFocusChange: (has) async {
                                      if (!has) {
                                        final v = proxyUserCtrl.text.trim();
                                        final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                        await spWatch.setProviderConfig(providerKey, old.copyWith(proxyUsername: v));
                                      }
                                    },
                                    child: TextField(
                                      controller: proxyUserCtrl,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: inputDeco(ctx),
                                      onChanged: (_) async {
                                        if (proxyUserCtrl.value.composing.isValid) return;
                                        final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                        await spWatch.setProviderConfig(providerKey, old.copyWith(proxyUsername: proxyUserCtrl.text.trim()));
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                row(
                                  l10n.providerDetailPagePasswordOptionalLabel,
                                  Focus(
                                    onFocusChange: (has) async {
                                      if (!has) {
                                        final v = proxyPassCtrl.text.trim();
                                        final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                        await spWatch.setProviderConfig(providerKey, old.copyWith(proxyPassword: v));
                                      }
                                    },
                                    child: TextField(
                                      controller: proxyPassCtrl,
                                      style: const TextStyle(fontSize: 13),
                                      obscureText: true,
                                      decoration: inputDeco(ctx),
                                      onChanged: (_) async {
                                        if (proxyPassCtrl.value.composing.isValid) return;
                                        final old = spWatch.getProviderConfig(providerKey, defaultName: displayName);
                                        await spWatch.setProviderConfig(providerKey, old.copyWith(proxyPassword: proxyPassCtrl.text.trim()));
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          crossFadeState: proxyEnabledNow ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 180),
                          sizeCurve: Curves.easeOutCubic,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
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

// Avatar edit button in settings dialog
class _AvatarEditButton extends StatefulWidget {
  const _AvatarEditButton({
    required this.providerKey,
    required this.displayName,
    required this.customAvatarPath,
  });

  final String providerKey;
  final String displayName;
  final String? customAvatarPath;

  @override
  State<_AvatarEditButton> createState() => _AvatarEditButtonState();
}

class _AvatarEditButtonState extends State<_AvatarEditButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasCustom = widget.customAvatarPath != null && widget.customAvatarPath!.isNotEmpty;
    final bg = _hover
        ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04))
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showDesktopAvatarPickerDialog(
          context,
          providerKey: widget.providerKey,
          displayName: widget.displayName,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              _BrandAvatar(
                key: ValueKey(widget.customAvatarPath),
                name: widget.displayName,
                providerKey: widget.providerKey,
                size: 32,
                customAvatarPath: widget.customAvatarPath,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasCustom ? 'Custom' : 'Default',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Icon(Lucide.Edit, size: 16, color: cs.onSurface.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

// Provider Type Dropdown
class _ProviderTypeDropdown extends StatefulWidget {
  const _ProviderTypeDropdown({required this.value, required this.onChanged});
  final ProviderKind value;
  final ValueChanged<ProviderKind> onChanged;

  @override
  State<_ProviderTypeDropdown> createState() => _ProviderTypeDropdownState();
}

class _ProviderTypeDropdownState extends State<_ProviderTypeDropdown> {
  bool _hover = false;
  bool _open = false;
  final GlobalKey _key = GlobalKey();
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  void _openMenu() {
    if (_entry != null) return;
    final rb = _key.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox = Overlay.of(context)?.context.findRenderObject() as RenderBox?;
    if (rb == null || overlayBox == null) return;

    final size = rb.size;
    const items = [
      (ProviderKind.openai, 'OpenAI'),
      (ProviderKind.google, 'Google'),
      (ProviderKind.claude, 'Claude'),
    ];

    _entry = OverlayEntry(
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final content = Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.12), width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (c, i) {
                final k = items[i].$1;
                final label = items[i].$2;
                final selected = widget.value == k;
                return _DropdownMenuItem(
                  label: label,
                  selected: selected,
                  onTap: () {
                    widget.onChanged(k);
                    _close();
                  },
                );
              },
            ),
          ),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _close,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              offset: Offset(0, size.height + 6),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: size.width, maxWidth: size.width),
                child: content,
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context)?.insert(_entry!);
    setState(() => _open = true);
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = switch (widget.value) {
      ProviderKind.openai => 'OpenAI',
      ProviderKind.google => 'Google',
      ProviderKind.claude => 'Claude',
    };

    final bg = _hover
        ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04))
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: CompositedTransformTarget(
        link: _link,
        child: GestureDetector(
          key: _key,
          onTap: _openMenu,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 13)),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Lucide.ChevronDown, size: 16, color: cs.onSurface.withOpacity(0.6)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownMenuItem extends StatefulWidget {
  const _DropdownMenuItem({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DropdownMenuItem> createState() => _DropdownMenuItemState();
}

class _DropdownMenuItemState extends State<_DropdownMenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = widget.selected
        ? cs.primary.withOpacity(0.12)
        : _hover
            ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04))
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
              color: widget.selected ? cs.primary : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ========== Provider Header Section (Avatar + Name) ==========

class _ProviderHeaderSection extends StatefulWidget {
  const _ProviderHeaderSection({
    required this.providerKey,
    required this.displayName,
    required this.customAvatarPath,
    required this.currentName,
    required this.onAvatarTap,
  });

  final String providerKey;
  final String displayName;
  final String? customAvatarPath;
  final String currentName;
  final void Function(GlobalKey) onAvatarTap;

  @override
  State<_ProviderHeaderSection> createState() => _ProviderHeaderSectionState();
}

class _ProviderHeaderSectionState extends State<_ProviderHeaderSection> {
  bool _isEditing = false;
  late TextEditingController _nameController;
  late FocusNode _focusNode;
  final GlobalKey _avatarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _saveName();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ProviderHeaderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && widget.currentName != oldWidget.currentName) {
      _nameController.text = widget.currentName;
    }
  }

  void _saveName() {
    if (!mounted) return;
    setState(() => _isEditing = false);
    final newName = _nameController.text.trim();
    if (newName.isNotEmpty && newName != widget.currentName) {
      final sp = context.read<SettingsProvider>();
      final oldCfg = sp.getProviderConfig(widget.providerKey, defaultName: widget.displayName);
      sp.setProviderConfig(widget.providerKey, oldCfg.copyWith(name: newName));
    } else {
      _nameController.text = widget.currentName;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Read real-time config to get latest customAvatarPath
    final sp = context.watch<SettingsProvider>();
    final cfg = sp.getProviderConfig(widget.providerKey, defaultName: widget.displayName);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          // Avatar - clickable (larger size)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: _avatarKey,
              onTap: () => widget.onAvatarTap(_avatarKey),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cs.primary.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: _BrandAvatar(
                  key: ValueKey(cfg.customAvatarPath),
                  name: cfg.name.isNotEmpty ? cfg.name : widget.displayName,
                  providerKey: widget.providerKey,
                  size: 56,
                  customAvatarPath: cfg.customAvatarPath,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Name - inline editable
          Expanded(
            child: _isEditing
                ? TextField(
                    controller: _nameController,
                    focusNode: _focusNode,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFEBECF0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: cs.primary.withOpacity(0.5), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onSubmitted: (_) => _saveName(),
                  )
                : MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _isEditing = true);
                        Future.delayed(const Duration(milliseconds: 50), () {
                          _focusNode.requestFocus();
                          _nameController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _nameController.text.length,
                          );
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.currentName,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ========== Helper Dialog Functions ==========

Future<String?> showDesktopEmojiPickerDialog(BuildContext context) async {
  final controller = TextEditingController();
  final l10n = AppLocalizations.of(context)!;
  String value = '';
  bool validGrapheme(String s) {
    final trimmed = s.characters.take(1).toString().trim();
    return trimmed.isNotEmpty && trimmed == s.trim();
  }

  final List<String> quick = const [
    '😀', '😁', '😂', '🤣', '😃', '😄', '😅', '😊', '😍', '😘',
    '😗', '😙', '😚', '🙂', '🤗', '🤩', '🫶', '🤝', '👍', '👎',
    '👋', '🙏', '💪', '🔥', '✨', '🌟', '💡', '🎉', '🎊', '🎈',
    '🌈', '☀️', '🌙', '⭐', '⚡', '☁️', '❄️', '🌧️', '🍎', '🍊',
    '🍋', '🍉', '🍇', '🍓', '🍒', '🍑', '🥭', '🍍', '🥝', '🍅',
    '🥕', '🌽', '🍞', '🧀', '🍔', '🍟', '🍕', '🌮', '🌯', '🍣',
    '🍜', '🍰', '🍪', '🍩', '🍫', '🍻', '☕', '🧋', '🥤', '⚽',
    '🏀', '🏈', '🎾', '🏐', '🎮', '🎧', '🎸', '🎹', '🎺', '📚',
    '✏️', '💼', '💻', '🖥️', '📱', '🛩️', '✈️', '🚗', '🚕', '🚙',
    '🚌', '🚀', '🛰️', '🧠', '🫀', '💊', '🩺', '🐶', '🐱', '🐭',
    '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷',
    '🐸', '🐵',
  ];

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            scrollable: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: cs.surface,
            title: Text(l10n.sideDrawerEmojiDialogTitle),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Preview
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      value.isEmpty ? '🙂' : value.characters.take(1).toString(),
                      style: const TextStyle(fontSize: 40),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Input
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (v) => setState(() => value = v),
                    onSubmitted: (_) {
                      if (validGrapheme(value)) {
                        Navigator.of(ctx).pop(value.characters.take(1).toString());
                      }
                    },
                    decoration: InputDecoration(
                      hintText: l10n.sideDrawerEmojiDialogHint,
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF2F3F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.primary.withOpacity(0.4)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Grid
                  SizedBox(
                    height: 200,
                    child: GridView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 8,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: quick.length,
                      itemBuilder: (c, i) {
                        final e = quick[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.of(ctx).pop(e),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(e, style: const TextStyle(fontSize: 20)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.sideDrawerCancel),
              ),
              TextButton(
                onPressed: validGrapheme(value)
                    ? () => Navigator.of(ctx).pop(value.characters.take(1).toString())
                    : null,
                child: Text(
                  l10n.sideDrawerOK,
                  style: TextStyle(
                    color: validGrapheme(value) ? cs.primary : cs.onSurface.withOpacity(0.38),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  return result;
}

Future<String?> showDesktopTextInputDialog(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: cs.surface,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFEBECF0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.18)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.18)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.primary.withOpacity(0.5), width: 1.2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('确定', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      );
    },
  );
  return result;
}

Future<String?> showDesktopQQInputDialog(BuildContext context) async {
  final controller = TextEditingController();
  String value = '';
  bool isValid(String s) => RegExp(r'^[0-9]{5,12}$').hasMatch(s.trim());

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: cs.surface,
            title: const Text('导入QQ头像'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '输入QQ号 (5-12位数字)',
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFEBECF0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.18)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.18)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.primary.withOpacity(0.5), width: 1.2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (v) => setState(() => value = v),
              onSubmitted: (_) {
                if (isValid(value)) Navigator.of(ctx).pop(value.trim());
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: isValid(value)
                    ? () => Navigator.of(ctx).pop(value.trim())
                    : null,
                child: Text(
                  '导入',
                  style: TextStyle(
                    color: isValid(value) ? cs.primary : cs.onSurface.withOpacity(0.38),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  return result;
}

// ========== Desktop Connection Test Dialog ==========

/// Desktop Connection Test Dialog
class _DesktopConnectionTestDialog extends StatefulWidget {
  const _DesktopConnectionTestDialog({
    required this.providerKey,
    required this.displayName,
  });

  final String providerKey;
  final String displayName;

  @override
  State<_DesktopConnectionTestDialog> createState() => _DesktopConnectionTestDialogState();
}

enum _TestState { idle, loading, success, error }

class _DesktopConnectionTestDialogState extends State<_DesktopConnectionTestDialog> {
  String? _selectedModelId;
  _TestState _state = _TestState.idle;
  String _errorMessage = '';
  bool _selectorOpen = false;
  final TextEditingController _selectorSearchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canTest = _selectedModelId != null && _state != _TestState.loading;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(width: 40),
                  Expanded(
                    child: Center(
                      child: Text(
                        l10n.providerDetailPageTestConnectionTitle,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: IconButton(
                      icon: Icon(Lucide.X, size: 18, color: cs.onSurface.withOpacity(0.7)),
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: l10n.providerDetailPageCancelButton,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildBody(context, cs, l10n),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.providerDetailPageCancelButton),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: canTest ? _doTest : null,
                    child: Text(l10n.providerDetailPageTestButton),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _selectorSearchCtrl.dispose();
    super.dispose();
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    switch (_state) {
      case _TestState.idle:
        return _buildIdle(context, cs, l10n);
      case _TestState.loading:
        return _buildLoading(context, cs, l10n);
      case _TestState.success:
        return _buildResult(
          context,
          cs,
          l10n,
          success: true,
          message: l10n.providerDetailPageTestSuccessMessage,
        );
      case _TestState.error:
        return _buildResult(
          context,
          cs,
          l10n,
          success: false,
          message: _errorMessage,
        );
    }
  }

  Widget _buildIdle(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _modelSelectorField(context, cs, l10n, enabled: true),
      ],
    );
  }

  Widget _buildLoading(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _modelSelectorField(context, cs, l10n, enabled: false),
        const SizedBox(height: 16),
        const LinearProgressIndicator(minHeight: 4),
        const SizedBox(height: 12),
        Text(
          l10n.providerDetailPageTestingMessage,
          style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildResult(
    BuildContext context,
    ColorScheme cs,
    AppLocalizations l10n, {
    required bool success,
    required String message,
  }) {
    final color = success ? Colors.green : cs.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _modelSelectorField(context, cs, l10n, enabled: true),
        const SizedBox(height: 14),
        Text(
          message,
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _modelSelectorField(BuildContext context, ColorScheme cs, AppLocalizations l10n, {bool enabled = true}) {
    final sp = context.watch<SettingsProvider>();
    final cfg = sp.getProviderConfig(widget.providerKey, defaultName: widget.displayName);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final all = cfg.models;
    final q = _selectorSearchCtrl.text.trim().toLowerCase();
    final list = [
      for (final id in all)
        if (q.isEmpty || id.toLowerCase().contains(q) || ModelRegistry.infer(ModelInfo(id: id, displayName: id)).displayName.toLowerCase().contains(q))
          id,
    ];

    final borderColor = cs.outlineVariant.withOpacity(isDark ? 0.25 : 0.4);
    final hoverBg = isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03);
    final selectedBg = isDark ? cs.primary.withOpacity(0.10) : cs.primary.withOpacity(0.08);

    Widget fieldContent() {
      final id = _selectedModelId;
      final name = id == null ? null : ModelRegistry.infer(ModelInfo(id: id, displayName: id)).displayName;
      return Row(
        children: [
          if (id != null) _BrandAvatar(name: id, size: 20) else Icon(Lucide.BadgeInfo, size: 18, color: cs.onSurface.withOpacity(0.6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              id == null ? l10n.providerDetailPageSelectModelButton : name ?? id,
              style: TextStyle(color: cs.onSurface, fontWeight: id == null ? FontWeight.w400 : FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(_selectorOpen ? Lucide.ChevronUp : Lucide.ChevronDown, size: 18, color: cs.onSurface.withOpacity(0.6)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: enabled ? () => setState(() => _selectorOpen = !_selectorOpen) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
              color: isDark ? Colors.white.withOpacity(0.02) : const Color(0xFFF6F7F9),
            ),
            child: fieldContent(),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _selectorSearchCtrl,
                  onChanged: (_) => setState(() {}),
                  enabled: enabled,
                  decoration: InputDecoration(
                    hintText: l10n.providerDetailPageSelectModelButton,
                    prefixIcon: Icon(Lucide.Search, size: 18, color: cs.onSurface.withOpacity(0.6)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    filled: true,
                    fillColor: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF6F7F9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.primary.withOpacity(0.35))),
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF151517) : Colors.white,
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        if (!isDark)
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: Scrollbar(
                        thickness: 4,
                        radius: const Radius.circular(999),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: list.length,
                          itemBuilder: (ctx, i) {
                            final id = list[i];
                            final selected = _selectedModelId == id;
                            final info = _getEffectiveModelInfo(id, cfg);
                            final caps = <Widget>[];
                            Widget pill(Widget icon, Color color) {
                              final bg = isDark ? color.withOpacity(0.18) : color.withOpacity(0.14);
                              final bd = color.withOpacity(0.22);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: bd, width: 0.5),
                              ),
                              child: icon,
                            );
                          }
                          if (info.input.contains(Modality.image)) {
                            caps.add(pill(Icon(Lucide.Eye, size: 11, color: cs.secondary), cs.secondary));
                          }
                          if (info.output.contains(Modality.image)) {
                            caps.add(pill(Icon(Lucide.Image, size: 11, color: cs.tertiary), cs.tertiary));
                          }
                          for (final ab in info.abilities) {
                            if (ab == ModelAbility.tool) {
                              caps.add(pill(Icon(Lucide.Hammer, size: 11, color: cs.primary), cs.primary));
                            } else if (ab == ModelAbility.reasoning) {
                              caps.add(pill(
                                SvgPicture.asset('assets/icons/deepthink.svg', width: 11, height: 11, colorFilter: ColorFilter.mode(cs.secondary, BlendMode.srcIn)),
                                cs.secondary,
                              ));
                            }
                          }
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: enabled
                                  ? () => setState(() {
                                        _selectedModelId = id;
                                        _state = _TestState.idle;
                                        _errorMessage = '';
                                        _selectorOpen = false;
                                      })
                                  : null,
                              hoverColor: hoverBg,
                              splashColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected ? selectedBg : Colors.transparent,
                                  border: Border(
                                    top: BorderSide(color: i == 0 ? Colors.transparent : borderColor.withOpacity(0.6)),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _BrandAvatar(name: id, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        info.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                                      ),
                                    ),
                                    ...caps.take(3).map((w) => Padding(padding: const EdgeInsets.only(left: 4), child: w)),
                                    const SizedBox(width: 6),
                                    if (selected) Icon(Lucide.Check, size: 16, color: cs.primary),
                                  ],
                                ),
                              ),
                            ),
                          );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          crossFadeState: _selectorOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
    );
  }

  Future<void> _doTest() async {
    if (_selectedModelId == null) return;
    setState(() {
      _state = _TestState.loading;
      _errorMessage = '';
    });
    try {
      final cfg = context.read<SettingsProvider>().getProviderConfig(
        widget.providerKey,
        defaultName: widget.displayName,
      );
      await ProviderManager.testConnection(cfg, _selectedModelId!);
      if (!mounted) return;
      setState(() => _state = _TestState.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _TestState.error;
        _errorMessage = e.toString();
      });
    }
  }
}

// ========== Desktop Model Group Widget ==========

/// Desktop Model Group Widget
class _DesktopModelGroup extends StatefulWidget {
  const _DesktopModelGroup({
    required this.groupName,
    required this.models,
    required this.selected,
    required this.onToggleGroup,
    required this.onToggleModel,
  });

  final String groupName;
  final List<ModelInfo> models;
  final Set<String> selected;
  final VoidCallback onToggleGroup;
  final void Function(String modelId) onToggleModel;

  @override
  State<_DesktopModelGroup> createState() => _DesktopModelGroupState();
}

class _DesktopModelGroupState extends State<_DesktopModelGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allSelected = widget.models.every((m) => widget.selected.contains(m.id));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              child: Material(
                color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        AnimatedRotation(
                          turns: _expanded ? 0.25 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Lucide.ChevronRight,
                            size: 16,
                            color: cs.onSurface.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.groupName,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        _GreyCapsule(label: '${widget.models.length}'),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: allSelected ? 'Remove All' : 'Add All',
                          child: _IconBtn(
                            icon: allSelected ? Lucide.Minus : Lucide.Plus,
                            color: cs.onSurface.withOpacity(0.7),
                            onTap: widget.onToggleGroup,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Content
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: [
                  for (final model in widget.models)
                    _DesktopModelRow(
                      model: model,
                      isSelected: widget.selected.contains(model.id),
                      onToggle: () => widget.onToggleModel(model.id),
                    ),
                ],
              ),
              crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

// ========== Desktop Model Row Widget ==========

/// Desktop Model Row Widget
class _DesktopModelRow extends StatefulWidget {
  const _DesktopModelRow({
    required this.model,
    required this.isSelected,
    required this.onToggle,
  });

  final ModelInfo model;
  final bool isSelected;
  final VoidCallback onToggle;

  @override
  State<_DesktopModelRow> createState() => _DesktopModelRowState();
}

class _DesktopModelRowState extends State<_DesktopModelRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover
        ? (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02))
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              top: BorderSide(color: cs.outlineVariant.withOpacity(0.1)),
            ),
          ),
          child: Row(
            children: [
              _BrandAvatar(name: widget.model.id, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.model.displayName,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _IconBtn(
                icon: widget.isSelected ? Lucide.CheckSquare : Lucide.Square,
                color: widget.isSelected ? cs.primary : cs.onSurface.withOpacity(0.5),
                onTap: widget.onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
