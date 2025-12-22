import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_svg/flutter_svg.dart';
import '../../../utils/brand_assets.dart';
import '../../../utils/provider_avatar_manager.dart';
import '../../../utils/platform_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/services/http/dio_client.dart';
import '../../../core/providers/model_provider.dart';
import '../../model/widgets/model_detail_sheet.dart';
import '../../model/widgets/model_select_sheet.dart';
import '../../../desktop/model_fetch_dialog.dart'
    if (dart.library.html) '../../../desktop/model_fetch_dialog_stub.dart';
import '../../../desktop/model_edit_dialog.dart'
    if (dart.library.html) '../../../desktop/model_edit_dialog_stub.dart';
import '../widgets/share_provider_sheet.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../shared/widgets/ios_checkbox.dart';
import '../../../shared/widgets/pop_confirm.dart';
import '../../../shared/widgets/ios_switch.dart';
import 'multi_key_manager_page.dart';
import 'provider_network_page.dart';
import '../../../core/services/haptics.dart';
import '../../../desktop/window_title_bar.dart'
    if (dart.library.html) '../../../desktop/window_title_bar_stub.dart';
import '../widgets/bottom_tabs.dart';
import '../widgets/tactile_widgets.dart';
import '../widgets/brand_avatar.dart';
import '../widgets/model_tag_wrap.dart';
import '../services/provider_test_service.dart';

/// Get effective ModelInfo with user overrides applied
/// Delegates to ProviderTestService.getEffectiveModelInfo
ModelInfo _getEffectiveModelInfo(String modelId, ProviderConfig cfg) =>
    ProviderTestService.getEffectiveModelInfo(modelId, cfg);

class ProviderDetailPage extends StatefulWidget {
  const ProviderDetailPage({super.key, required this.keyName, required this.displayName});
  final String keyName;
  final String displayName;

  @override
  State<ProviderDetailPage> createState() => _ProviderDetailPageState();
}

class _ProviderDetailPageState extends State<ProviderDetailPage> {
  final PageController _pc = PageController();
  int _index = 0;
  // ❌ Removed: late ProviderConfig _cfg; - use Provider directly for reactive updates
  late ProviderKind _kind;
  final _nameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _baseCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  // Google Vertex AI extras
  final _locationCtrl = TextEditingController();
  final _projectCtrl = TextEditingController();
  final _saJsonCtrl = TextEditingController();
  bool _enabled = true;
  bool _useResp = false; // openai
  bool _vertexAI = false; // google
  bool _showApiKey = false; // toggle visibility
  bool _multiKeyEnabled = false; // single/multi key mode
  // network proxy (per provider)
  bool _proxyEnabled = false;
  final _proxyHostCtrl = TextEditingController();
  final _proxyPortCtrl = TextEditingController(text: '8080');
  final _proxyUserCtrl = TextEditingController();
  final _proxyPassCtrl = TextEditingController();
  // Model grouping state
  final Set<String> _collapsedGroups = {};


  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    _kind = ProviderConfig.classify(widget.keyName, explicitType: cfg.providerType);
    _enabled = cfg.enabled;
    _nameCtrl.text = cfg.name;
    _keyCtrl.text = cfg.apiKey;
    _baseCtrl.text = cfg.baseUrl;
    _pathCtrl.text = cfg.chatPath ?? '/chat/completions';
    _useResp = cfg.useResponseApi ?? false;
    _vertexAI = cfg.vertexAI ?? false;
    _locationCtrl.text = cfg.location ?? '';
    _projectCtrl.text = cfg.projectId ?? '';
    _saJsonCtrl.text = cfg.serviceAccountJson ?? '';
    // proxy
    _proxyEnabled = cfg.proxyEnabled ?? false;
    _proxyHostCtrl.text = cfg.proxyHost ?? '';
    _proxyPortCtrl.text = cfg.proxyPort ?? '8080';
    _proxyUserCtrl.text = cfg.proxyUsername ?? '';
    _proxyPassCtrl.text = cfg.proxyPassword ?? '';
    _multiKeyEnabled = cfg.multiKeyEnabled ?? false;
  }

  @override
  void dispose() {
    _pc.dispose();
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    _baseCtrl.dispose();
    _pathCtrl.dispose();
    _locationCtrl.dispose();
    _projectCtrl.dispose();
    _saJsonCtrl.dispose();
    _proxyHostCtrl.dispose();
    _proxyPortCtrl.dispose();
    _proxyUserCtrl.dispose();
    _proxyPassCtrl.dispose();
    super.dispose();
  }

  // Group models by prefix (/, :, -)
  Map<String, List<String>> _groupModels(List<String> models) {
    final map = <String, List<String>>{};
    for (final m in models) {
      var g = m;
      // Special handling for Gemini models
      if (m.toLowerCase().contains('gemini-3')) {
        g = 'Gemini 3';
      } else if (m.toLowerCase().contains('gemini-2.5') || m.toLowerCase().contains('gemini-2-5')) {
        g = 'Gemini 2.5';
      } else if (m.toLowerCase().contains('gemini')) {
        g = 'Gemini';
      } else if (m.contains('/')) {
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

  @override
  Widget build(BuildContext context) {
    // ✅ Read latest config from Provider for reactive updates (especially for avatar)
    final settings = context.watch<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);

    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    bool _isUserAdded(String key) {
      const fixed = {
        'KelivoIN', 'OpenAI', 'Gemini', 'SiliconFlow', 'OpenRouter',
        'DeepSeek', 'Tensdaq', 'Aliyun', 'Zhipu AI', 'Claude', 'Grok', 'ByteDance',
      };
      return !fixed.contains(key);
    }

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: ProviderTactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            semanticLabel: l10n.settingsPageBackButton,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Row(
          children: [
            BrandAvatar(
              key: ValueKey(cfg.customAvatarPath),
              name: (_nameCtrl.text.isEmpty ? widget.displayName : _nameCtrl.text),
              size: 22,
              customAvatarPath: cfg.customAvatarPath,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _nameCtrl.text.isEmpty ? widget.displayName : _nameCtrl.text,
                style: const TextStyle(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: l10n.providerDetailPageTestButton,
            child: ProviderTactileIconButton(
              icon: Lucide.HeartPulse,
              color: cs.onSurface,
              semanticLabel: l10n.providerDetailPageTestButton,
              size: 22,
              onTap: _openTestDialog,
            ),
          ),
          Tooltip(
            message: l10n.providerDetailPageShareTooltip,
            child: ProviderTactileIconButton(
              icon: Lucide.Share2,
              color: cs.onSurface,
              semanticLabel: l10n.providerDetailPageShareTooltip,
              size: 22,
              onTap: () async {
                await showShareProviderSheet(context, widget.keyName);
              },
            ),
          ),
          if (_isUserAdded(widget.keyName))
            Builder(
              builder: (btnContext) {
                final deleteProviderKey = GlobalKey();
                return Tooltip(
                  message: l10n.providerDetailPageDeleteProviderTooltip,
                  child: ProviderTactileIconButton(
                    key: deleteProviderKey,
                    icon: Lucide.Trash2,
                    color: cs.error,
                    semanticLabel: l10n.providerDetailPageDeleteProviderTooltip,
                    size: 22,
                    onTap: () async {
                      final confirm = await showPopConfirm(
                        context,
                        anchorKey: deleteProviderKey,
                        title: l10n.providerDetailPageDeleteProviderTitle,
                        subtitle: l10n.providerDetailPageDeleteProviderContent,
                        confirmText: l10n.providerDetailPageDeleteButton,
                        cancelText: l10n.providerDetailPageCancelButton,
                        icon: Lucide.Trash2,
                      );
                      if (confirm) {
                        // Clear assistant-level model selections that reference this provider
                        try {
                          final ap = context.read<AssistantProvider>();
                          for (final a in ap.assistants) {
                            if (a.chatModelProvider == widget.keyName) {
                              await ap.updateAssistant(a.copyWith(clearChatModel: true));
                            }
                          }
                        } catch (_) {}

                        // Remove provider config and related selections/pins
                        await context.read<SettingsProvider>().removeProviderConfig(widget.keyName);
                        if (!mounted) return;
                        Navigator.of(context).maybePop();
                        showAppSnackBar(
                          context,
                          message: l10n.providerDetailPageProviderDeletedSnackbar,
                          type: NotificationType.success,
                        );
                      }
                    },
                  ),
                );
              },
            ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
            const WindowCaptionActions(),
          const SizedBox(width: 12),
        ],
      ),
      body: PageView(
        controller: _pc,
        onPageChanged: (i) => setState(() => _index = i),
        children: [
          _buildConfigTab(context, cs, l10n),
          _buildModelsTab(context, cs, l10n),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: ProviderBottomTabs(
            index: _index,
            leftIcon: Lucide.Settings2,
            leftLabel: l10n.providerDetailPageConfigTab,
            rightIcon: Lucide.Boxes,
            rightLabel: l10n.providerDetailPageModelsTab,
            onSelect: (i) {
              setState(() => _index = i);
              _pc.animateToPage(
                i,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildConfigTab(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        if (widget.keyName.toLowerCase() == 'kelivoin') ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary.withOpacity(0.35)),
            ),
            child: Text.rich(
              TextSpan(
                text: 'Powered by ',
                style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
                children: [
                  TextSpan(
                    text: 'Pollinations AI',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () async {
                        final uri = Uri.parse('https://pollinations.ai');
                        try {
                          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                          if (!ok) {
                            await launchUrl(uri);
                          }
                        } catch (_) {
                          await launchUrl(uri);
                        }
                      },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.keyName.toLowerCase() == 'tensdaq') ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '革命性竞价 AI MaaS 平台，价格由市场供需决定，告别高成本固定定价。',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    text: '官网：',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
                    children: [
                      TextSpan(
                        text: 'https://dashboard.x-aio.com',
                        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () async {
                            final uri = Uri.parse('https://dashboard.x-aio.com');
                            try {
                              final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                              if (!ok) {
                                await launchUrl(uri);
                              }
                            } catch (_) {
                              await launchUrl(uri);
                            }
                          },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.keyName.toLowerCase() == 'siliconflow') ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已内置硅基流动的免费模型，无需 API Key。若需更强大的模型，请申请并在此配置你自己的 API Key。',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    text: '官网：',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
                    children: [
                      TextSpan(
                        text: 'https://siliconflow.cn',
                        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () async {
                            final uri = Uri.parse('https://siliconflow.cn');
                            try {
                              final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                              if (!ok) { await launchUrl(uri); }
                            } catch (_) { await launchUrl(uri); }
                          },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        // 顶部管理分组标题（左侧缩进以对齐卡片内容）
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            l10n.providerDetailPageManageSectionTitle,
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8)),
          ),
        ),
        const SizedBox(height: 6),
        // Top iOS-style section card for key settings
        _iosSectionCard(children: [
          if (widget.keyName.toLowerCase() != 'kelivoin') _providerKindRow(context),
          _iosRow(
            context,
            label: l10n.providerDetailPageEnabledTitle,
            trailing: IosSwitch(value: _enabled, onChanged: (v) { setState(() => _enabled = v); _save(); }),
          ),
          _iosRow(
            context,
            label: l10n.providerDetailPageMultiKeyModeTitle,
            trailing: IosSwitch(value: _multiKeyEnabled, onChanged: (v) { setState(() => _multiKeyEnabled = v); _save(); }),
          ),
          if (_multiKeyEnabled)
          ProviderTactileRow(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MultiKeyManagerPage(
                    providerKey: widget.keyName,
                    providerDisplayName: widget.displayName,
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
            builder: (pressed) {
              final base = Theme.of(context).colorScheme.onSurface;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final target = pressed ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base) : base;
              return TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: target),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, color, _) {
                  final c = color ?? base;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(child: Text(l10n.providerDetailPageManageKeysButton, style: TextStyle(fontSize: 15, color: c))),
                        Icon(Lucide.ChevronRight, size: 16, color: c),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          if (_kind == ProviderKind.openai)
            _iosRow(
              context,
              label: l10n.providerDetailPageResponseApiTitle,
              trailing: IosSwitch(value: _useResp, onChanged: (v) { setState(() => _useResp = v); _save(); }),
            ),
          if (_kind == ProviderKind.google)
            _iosRow(
              context,
              label: l10n.providerDetailPageVertexAiTitle,
              trailing: IosSwitch(value: _vertexAI, onChanged: (v) { setState(() => _vertexAI = v); _save(); }),
            ),
          ProviderTactileRow(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProviderNetworkPage(
                    providerKey: widget.keyName,
                    providerDisplayName: widget.displayName,
                  ),
                ),
              );
              final settings = context.read<SettingsProvider>();
              final latest = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
              setState(() {
                _proxyEnabled = latest.proxyEnabled ?? false;
                _proxyHostCtrl.text = latest.proxyHost ?? '';
                _proxyPortCtrl.text = latest.proxyPort ?? '8080';
              });
            },
            builder: (pressed) {
              final cs2 = Theme.of(context).colorScheme;
              final base = cs2.onSurface;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final target = pressed ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base) : base;
              return TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: target),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, color, _) {
                  final c = color ?? base;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(child: Text(l10n.providerDetailPageNetworkTab, style: TextStyle(fontSize: 15, color: c))),
                        Icon(Lucide.ChevronRight, size: 16, color: c),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ]),
        const SizedBox(height: 12),
        _inputRow(
          context,
          label: l10n.providerDetailPageNameLabel,
          controller: _nameCtrl,
          hint: widget.displayName,
          enabled: widget.keyName.toLowerCase() != 'kelivoin',
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 12),
        // Custom Avatar
        _buildAvatarRow(context),
        const SizedBox(height: 12),
        if (!(_kind == ProviderKind.google && _vertexAI)) ...[
          if (widget.keyName.toLowerCase() != 'kelivoin' && !_multiKeyEnabled) ...[
            _inputRow(
              context,
              label: 'API Key',
              controller: _keyCtrl,
              hint: l10n.providerDetailPageApiKeyHint,
              obscure: !_showApiKey,
              suffix: IconButton(
                tooltip: _showApiKey ? l10n.providerDetailPageHideTooltip : l10n.providerDetailPageShowTooltip,
                icon: Icon(_showApiKey ? Lucide.EyeOff : Lucide.Eye, color: cs.onSurface.withOpacity(0.7), size: 18),
                onPressed: () => setState(() => _showApiKey = !_showApiKey),
              ),
              onChanged: (_) => _save(),
            ),
            const SizedBox(height: 12),
          ],
          _inputRow(
            context,
            label: 'API Base URL',
            controller: _baseCtrl,
            hint: ProviderConfig.defaultsFor(widget.keyName, displayName: widget.displayName).baseUrl,
            enabled: widget.keyName.toLowerCase() != 'kelivoin',
            onChanged: (_) => _save(),
          ),
        ],
        if (_kind == ProviderKind.openai && widget.keyName.toLowerCase() != 'kelivoin' && !_useResp) ...[
          const SizedBox(height: 12),
          _inputRow(
            context,
            label: l10n.providerDetailPageApiPathLabel,
            controller: _pathCtrl,
            enabled: widget.keyName.toLowerCase() != 'openai' && widget.keyName.toLowerCase() != 'tensdaq',
            hint: '/chat/completions',
            onChanged: (_) => _save(),
          ),
        ],
        if (_kind == ProviderKind.google) ...[
          const SizedBox(height: 12),
          if (_vertexAI) ...[
            const SizedBox(height: 12),
            _inputRow(context, label: l10n.providerDetailPageLocationLabel, controller: _locationCtrl, hint: 'us-central1', onChanged: (_) => _save()),
            const SizedBox(height: 12),
            _inputRow(context, label: l10n.providerDetailPageProjectIdLabel, controller: _projectCtrl, hint: 'my-project-id', onChanged: (_) => _save()),
            const SizedBox(height: 12),
            _multilineRow(
              context,
              label: l10n.providerDetailPageServiceAccountJsonLabel,
              controller: _saJsonCtrl,
              hint: '{\n  "type": "service_account", ...\n}',
              actions: [
                TextButton.icon(
                  onPressed: _importServiceAccountJson,
                  icon: Icon(Lucide.Upload, size: 16),
                  label: Text(l10n.providerDetailPageImportJsonButton),
                ),
              ],
              onChanged: (_) => _save(),
            ),
          ],
        ],
        const SizedBox(height: 12),
        if (widget.keyName.toLowerCase() == 'siliconflow') ...[
          const SizedBox(height: 6),
          Center(
            child: Image.asset(
              Theme.of(context).brightness == Brightness.dark
                  ? 'assets/icons/Powered-by-dark.png'
                  : 'assets/icons/Powered-by-light.png',
              height: 64,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModelsTab(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    final cfg = context.watch<SettingsProvider>().providerConfigs[widget.keyName];
    if (cfg == null) {
      // Provider has been removed; avoid recreating it via getProviderConfig.
      return Center(
        child: Text(l10n.providerDetailPageProviderRemovedMessage, style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
      );
    }
    final models = cfg.models;
    
    if (models.isEmpty) {
      return Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.providerDetailPageNoModelsTitle, style: TextStyle(fontSize: 18, color: cs.onSurface)),
                const SizedBox(height: 6),
                Text(
                  l10n.providerDetailPageNoModelsSubtitle,
                  style: TextStyle(fontSize: 13, color: cs.primary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          _buildFloatingButtons(context, cs, l10n),
        ],
      );
    }
    
    // Group models by prefix
    final grouped = _groupModels(models);
    final groupKeys = grouped.keys.toList();
    
    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: groupKeys.length,
          itemBuilder: (context, groupIndex) {
            final groupName = groupKeys[groupIndex];
            final groupModels = grouped[groupName]!;
            final isCollapsed = _collapsedGroups.contains(groupName);
            
            return _MobileModelGroup(
              key: ValueKey('group-$groupName'),
              groupName: groupName,
              modelIds: groupModels,
              providerKey: widget.keyName,
              isCollapsed: isCollapsed,
              onToggle: () {
                setState(() {
                  if (isCollapsed) {
                    _collapsedGroups.remove(groupName);
                  } else {
                    _collapsedGroups.add(groupName);
                  }
                });
              },
              onDelete: (modelId) => _deleteModel(modelId, cfg),
              onReorder: (oldIdx, newIdx) => _reorderModelsInGroup(groupName, oldIdx, newIdx, cfg),
            );
          },
        ),
        _buildFloatingButtons(context, cs, l10n),
      ],
    );
  }

  Widget _buildFloatingButtons(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 12 + MediaQuery.of(context).padding.bottom,
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Color.alphaBlend(Colors.white.withOpacity(0.12), cs.surface)
                : const Color(0xFFF2F3F5),
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProviderTactileRow(
                pressedScale: 0.97,
                haptics: false,
                onTap: () => _showModelPicker(context),
                builder: (pressed) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.primary.withOpacity(0.35)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Lucide.Boxes, size: 20, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(l10n.providerDetailPageFetchModelsButton, style: TextStyle(color: cs.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              ProviderTactileRow(
                pressedScale: 0.97,
                haptics: false,
                onTap: () async {
                  final isDesktop = !kIsWeb &&
                      (defaultTargetPlatform == TargetPlatform.windows ||
                          defaultTargetPlatform == TargetPlatform.macOS ||
                          defaultTargetPlatform == TargetPlatform.linux);
                  if (isDesktop) {
                    await showDesktopCreateModelDialog(context, providerKey: widget.keyName);
                    return;
                  }
                  await showCreateModelSheet(context, providerKey: widget.keyName);
                },
                builder: (pressed) {
                  return Container(
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Lucide.Plus, size: 20, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(l10n.providerDetailPageAddNewModelButton, style: TextStyle(color: cs.primary, fontSize: 14)),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteModel(String modelId, ProviderConfig cfg) async {
    final l10n = AppLocalizations.of(context)!;

    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    final prevList = List<String>.from(old.models);
    final prevOverrides = Map<String, dynamic>.from(old.modelOverrides);
    final removeIndex = prevList.indexOf(modelId);
    final newList = prevList.where((e) => e != modelId).toList();
    final newOverrides = Map<String, dynamic>.from(prevOverrides)..remove(modelId);
    await settings.setProviderConfig(widget.keyName, old.copyWith(models: newList, modelOverrides: newOverrides));
    
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: l10n.providerDetailPageModelDeletedSnackbar,
      type: NotificationType.info,
      actionLabel: l10n.providerDetailPageUndoButton,
      onAction: () {
        Future(() async {
          final cfg2 = context.read<SettingsProvider>().getProviderConfig(widget.keyName, defaultName: widget.displayName);
          final restoredList = List<String>.from(cfg2.models);
          if (!restoredList.contains(modelId)) {
            if (removeIndex >= 0 && removeIndex <= restoredList.length) {
              restoredList.insert(removeIndex, modelId);
            } else {
              restoredList.add(modelId);
            }
          }
          final restoredOverrides = Map<String, dynamic>.from(cfg2.modelOverrides);
          if (!restoredOverrides.containsKey(modelId) && prevOverrides.containsKey(modelId)) {
            restoredOverrides[modelId] = prevOverrides[modelId];
          }
          await settings.setProviderConfig(widget.keyName, cfg2.copyWith(models: restoredList, modelOverrides: restoredOverrides));
        });
      },
    );
  }

  Future<void> _reorderModelsInGroup(String groupName, int oldIdx, int newIdx, ProviderConfig cfg) async {
    if (newIdx > oldIdx) newIdx -= 1;
    
    // Get all models in order
    final allModels = List<String>.from(cfg.models);
    final grouped = _groupModels(allModels);
    final groupModels = List<String>.from(grouped[groupName]!);
    
    // Reorder within group
    final item = groupModels.removeAt(oldIdx);
    groupModels.insert(newIdx, item);
    
    // Rebuild full model list with new order
    final newAllModels = <String>[];
    for (final key in grouped.keys) {
      if (key == groupName) {
        newAllModels.addAll(groupModels);
      } else {
        newAllModels.addAll(grouped[key]!);
      }
    }
    
    await context.read<SettingsProvider>().setProviderConfig(
      widget.keyName,
      cfg.copyWith(models: newAllModels),
    );
  }

  // Legacy network tab removed (replaced by ProviderNetworkPage)

  Widget _switchRow({required IconData icon, required String title, required bool value, required ValueChanged<bool> onChanged}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: cs.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          margin: const EdgeInsets.only(right: 12),
          child: Icon(icon, size: 20, color: cs.primary),
        ),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
        IosSwitch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildAvatarRow(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    // ✅ Read latest config from Provider for reactive avatar display
    final settings = context.watch<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    final hasCustomAvatar = cfg.customAvatarPath != null && cfg.customAvatarPath!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Text(
            '自定义头像',  // TODO: Add to l10n
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.03)
                : cs.primary.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Avatar preview
              BrandAvatar(
                key: ValueKey(cfg.customAvatarPath),
                name: _nameCtrl.text.isEmpty ? widget.displayName : _nameCtrl.text,
                size: 48,
                customAvatarPath: cfg.customAvatarPath,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  hasCustomAvatar
                      ? '已设置自定义头像'
                      : '使用默认品牌图标',
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
              // Action buttons
              if (hasCustomAvatar) ...[
                IconButton(
                  icon: Icon(Lucide.Trash2, size: 18, color: cs.error),
                  tooltip: '删除自定义头像',
                  onPressed: () => _deleteCustomAvatar(),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                icon: Icon(Lucide.Upload, size: 18, color: cs.primary),
                tooltip: hasCustomAvatar ? '更换头像' : '上传头像',
                onPressed: () => _showAvatarPicker(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAvatarPicker() async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final maxH = MediaQuery.of(ctx).size.height * 0.8;

        Widget row(String text, Future<void> Function() action) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await Future<void>.delayed(const Duration(milliseconds: 100));
                  await action();
                },
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      text,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: cs.onSurface),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                    const SizedBox(height: 16),
                    row('选择本地图片', () async => _pickLocalImage()),
                    row('选择表情', () async => _pickEmoji()),
                    row('输入图片链接', () async => _inputAvatarUrl()),
                    row('删除自定义头像', () async => _deleteCustomAvatar()),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickLocalImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null && file.path == null) {
        showAppSnackBar(context, message: '无法读取图片文件', type: NotificationType.error);
        return;
      }

      final Uint8List bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else {
        final raw = file.path;
        final b = raw != null ? await PlatformUtils.readFileBytes(raw) : null;
        if (b == null) {
          showAppSnackBar(context, message: 'Unable to read image file', type: NotificationType.error);
          return;
        }
        bytes = Uint8List.fromList(b);
      }

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('处理图片中...'),
                ],
              ),
            ),
          ),
        ),
      );

      final settings = context.read<SettingsProvider>();
      final accessCode = settings.getProviderConfig(settings.currentModelProvider ?? widget.keyName).apiKey;
      final avatarPath = await ProviderAvatarManager.saveAvatar(widget.keyName, bytes, accessCode: accessCode);

      if (!mounted) return;
      Navigator.of(context).pop();

      // Clear image cache before updating to force reload
      try {
        imageCache.clear();
        imageCache.clearLiveImages();
      } catch (_) {}

      // ✅ Update Provider directly - no need for setState, notifyListeners will trigger rebuild
      final cfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
      await settings.setProviderConfig(
        widget.keyName,
        cfg.copyWith(customAvatarPath: avatarPath),
      );

      showAppSnackBar(context, message: '头像已更新', type: NotificationType.success);
    } catch (e) {
      if (!mounted) return;
      try {
        Navigator.of(context).pop();
      } catch (_) {}
      showAppSnackBar(context, message: '处理图片失败: $e', type: NotificationType.error);
    }
  }

  Future<void> _pickEmoji() async {
    final emoji = await showDialog<String>(
      context: context,
      builder: (context) {
        final emojis = [
          '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
          '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚',
          '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🤩',
          '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '☹️', '😣',
          '😖', '😫', '😩', '🥺', '😢', '😭', '😤', '😠', '😡', '🤬',
          '🤯', '😳', '🥵', '🥶', '😱', '😨', '😰', '😥', '😓', '🤗',
          '🤔', '🤭', '🤫', '🤥', '😶', '😐', '😑', '😬', '🙄', '😯',
          '🤐', '🥱', '😪', '😴', '😌', '😷', '🤒', '🤕', '🤢', '🤮',
          '🤧', '🥴', '😵', '🤠', '🥳', '🥸', '😎', '🤓', '🧐', '😕',
          '👻', '👽', '🤖', '💩', '😺', '😸', '😹', '😻', '😼', '😽',
        ];

        return AlertDialog(
          title: const Text('选择表情'),
          content: SizedBox(
            width: 300,
            height: 400,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, index) {
                return InkWell(
                  onTap: () => Navigator.of(context).pop(emojis[index]),
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: Text(
                      emojis[index],
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    if (emoji != null) {
      // ✅ Update Provider directly
      final settings = context.read<SettingsProvider>();
      final cfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
      await settings.setProviderConfig(
        widget.keyName,
        cfg.copyWith(customAvatarPath: emoji),
      );
      showAppSnackBar(context, message: '头像已更新', type: NotificationType.success);
    }
  }

  Future<void> _inputAvatarUrl() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: cs.surface,
          title: const Text('输入图片链接'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'https://example.com/avatar.png',
              filled: true,
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      final url = controller.text.trim();
      if (url.isEmpty) return;

      try {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('下载图片中...'),
                  ],
                ),
              ),
            ),
          ),
        );

        // Download image from URL
        final response = await simpleDio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        if (response.statusCode != 200) {
          throw Exception('下载失败: HTTP ${response.statusCode}');
        }

        final bytes = Uint8List.fromList(response.data ?? []);
        final avatarPath = await ProviderAvatarManager.saveAvatar(widget.keyName, bytes);

        if (!mounted) return;
        Navigator.of(context).pop();

        // Clear image cache before updating to force reload
        try {
          imageCache.clear();
          imageCache.clearLiveImages();
        } catch (_) {}

        // ✅ Update Provider directly
        final settings = context.read<SettingsProvider>();
        final cfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
        await settings.setProviderConfig(
          widget.keyName,
          cfg.copyWith(customAvatarPath: avatarPath),
        );

        showAppSnackBar(context, message: '头像已更新', type: NotificationType.success);
      } catch (e) {
        if (!mounted) return;
        try {
          Navigator.of(context).pop();
        } catch (_) {}
        showAppSnackBar(context, message: '下载图片失败: $e', type: NotificationType.error);
      }
    }
  }

  Future<void> _deleteCustomAvatar() async {
    try {
      await ProviderAvatarManager.deleteAvatar(widget.keyName);

      // Clear image cache before updating to force reload
      try {
        imageCache.clear();
        imageCache.clearLiveImages();
      } catch (_) {}

      // ✅ Update Provider directly
      final settings = context.read<SettingsProvider>();
      final cfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
      await settings.setProviderConfig(
        widget.keyName,
        cfg.copyWith(customAvatarPath: ''),
      );

      showAppSnackBar(context, message: '已删除自定义头像', type: NotificationType.success);
    } catch (e) {
      showAppSnackBar(context, message: '删除失败: $e', type: NotificationType.error);
    }
  }

  Widget _inputRow(BuildContext context, {required String label, required TextEditingController controller, String? hint, bool obscure = false, bool enabled = true, Widget? suffix, ValueChanged<String>? onChanged}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8))),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark ? Colors.white10 : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }

  Widget _checkboxRow(BuildContext context, {required String title, required bool value, required ValueChanged<bool> onChanged}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          // iOS-style circular checkbox
          IosCheckbox(value: value, onChanged: onChanged),
          Text(title, style: TextStyle(fontSize: 14, color: cs.onSurface)),
        ],
      ),
    );
  }

  // --- iOS style helpers (consistent with MultiKeyManagerPage) ---

  Widget _iosSectionCard({required List<Widget> children}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final Color base = cs.surface;
    final Color bg = isDark ? Color.lerp(base, Colors.white, 0.06)! : Color.lerp(base, Colors.white, 0.92)!;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06), width: 0.6),
        // boxShadow: [
        //   if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 1)),
        // ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _iosRow(
    BuildContext context, {
    required String label,
    Widget? trailing,
    GestureTapCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ProviderTactileRow(
      onTap: onTap,
      builder: (pressed) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final base = cs.onSurface;
        final target = pressed ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base) : base;
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: target),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, color, _) {
            final c = color ?? base;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c))),
                  if (trailing != null) trailing,
                ],
              ),
            );
          },
        );
      },
    );
  }

  

  Widget _providerKindRow(BuildContext context) {
    String labelFor(ProviderKind k) {
      switch (k) {
        case ProviderKind.google:
          return 'Gemini';
        case ProviderKind.claude:
          return 'Claude';
        case ProviderKind.openai:
        default:
          return 'OpenAI';
      }
    }
    return ProviderTactileRow(
      onTap: _showProviderKindSheet,
      builder: (pressed) {
        final cs = Theme.of(context).colorScheme;
        final base = cs.onSurface;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final target = pressed ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base) : base;
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: target),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, color, _) {
            final c = color ?? base;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(child: Text(AppLocalizations.of(context)!.providerDetailPageProviderTypeTitle, style: TextStyle(fontSize: 15, color: c))),
                  Text(labelFor(_kind), style: TextStyle(fontSize: 15, color: c)),
                  const SizedBox(width: 6),
                  Icon(Lucide.ChevronRight, size: 16, color: c),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showProviderKindSheet() async {
    final cs = Theme.of(context).colorScheme;
    final selected = await showModalBottomSheet<ProviderKind>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999)),
                ),
                const SizedBox(height: 12),
                _providerKindTile(ctx, ProviderKind.openai, label: 'OpenAI'),
                _providerKindTile(ctx, ProviderKind.google, label: 'Gemini'),
                _providerKindTile(ctx, ProviderKind.claude, label: 'Claude'),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) {
      setState(() => _kind = selected);
      await _save();
    }
  }

  Widget _providerKindTile(BuildContext ctx, ProviderKind k, {required String label}) {
    final cs = Theme.of(ctx).colorScheme;
    final selected = _kind == k;
    return ProviderTactileRow(
      pressedScale: 1.00,
      haptics: false,
      onTap: () => Navigator.of(ctx).pop(k),
      builder: (pressed) {
        final base = cs.onSurface;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final target = pressed ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base) : base;
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: target),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          builder: (context, color, _) {
            final c = color ?? base;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c))),
                  if (selected) Icon(Icons.check, color: cs.primary),
                ],
              ),
            );
          },
        );
      },
    );
  }


  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    String projectId = _projectCtrl.text.trim();
    if ((_kind == ProviderKind.google) && _vertexAI && projectId.isEmpty) {
      try {
        final obj = jsonDecode(_saJsonCtrl.text) as Map<String, dynamic>;
        projectId = (obj['project_id'] as String?)?.trim() ?? '';
      } catch (_) {}
    }
    final updated = old.copyWith(
      enabled: _enabled,
      name: _nameCtrl.text.trim().isEmpty ? widget.displayName : _nameCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      baseUrl: ProviderTestService.sanitizeUrl(_baseCtrl.text),
      providerType: _kind,  // Save the selected provider type
      chatPath: _kind == ProviderKind.openai ? ProviderTestService.sanitizeUrl(_pathCtrl.text) : old.chatPath,
      useResponseApi: _kind == ProviderKind.openai ? _useResp : old.useResponseApi,
      vertexAI: _kind == ProviderKind.google ? _vertexAI : old.vertexAI,
      location: _kind == ProviderKind.google ? _locationCtrl.text.trim() : old.location,
      projectId: _kind == ProviderKind.google ? projectId : old.projectId,
      serviceAccountJson: _kind == ProviderKind.google ? _saJsonCtrl.text.trim() : old.serviceAccountJson,
      multiKeyEnabled: _multiKeyEnabled,
      // ✅ Preserve custom avatar from old config (already in Provider state)
      customAvatarPath: old.customAvatarPath,
      // preserve models and modelOverrides and proxy fields implicitly via copyWith
    );
    await settings.setProviderConfig(widget.keyName, updated);
    if (!mounted) return;
    // Silent auto-save (no snackbar) for immediate-save UX
  }

  Widget _multilineRow(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? hint,
    List<Widget>? actions,
    ValueChanged<String>? onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8))),
              ),
            ),
            if (actions != null) ...actions,
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: 8,
          minLines: 4,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            alignLabelWithHint: true,
            fillColor: isDark ? Colors.white10 : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Future<void> _importServiceAccountJson() async {
    try {
      // Lazy import to avoid hard dependency errors in web
      // ignore: avoid_dynamic_calls
      // ignore: import_of_legacy_library_into_null_safe
      // Using file_picker which is already in pubspec
      // import placed at top-level of this file
      final picker = await _pickJsonFile();
      if (picker == null) return;
      _saJsonCtrl.text = picker;
      // Auto-fill projectId if available
      try {
        final obj = jsonDecode(_saJsonCtrl.text) as Map<String, dynamic>;
        final pid = (obj['project_id'] as String?)?.trim();
        if ((pid ?? '').isNotEmpty && _projectCtrl.text.trim().isEmpty) {
          _projectCtrl.text = pid!;
        }
      } catch (_) {}
      if (mounted) {
        setState(() {});
        await _save();
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: '$e',
        type: NotificationType.error,
      );
    }
  }

  Future<String?> _pickJsonFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.single;
      if (file.bytes != null) {
        return utf8.decode(file.bytes!, allowMalformed: true);
      }
      final path = file.path;
      if (path == null) return null;
      final bytes = await PlatformUtils.readFileBytes(path);
      if (bytes == null) return null;
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      return null;
    }
  }

  Future<void> _openTestDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ConnectionTestDialog(providerKey: widget.keyName, providerDisplayName: widget.displayName),
    );
  }

  // _saveNetwork moved to ProviderNetworkPage

  Widget _buildProviderTypeSelector(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _kind = ProviderKind.openai;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: _kind == ProviderKind.openai 
                    ? cs.primary.withOpacity(0.15) 
                    : Theme.of(context).brightness == Brightness.dark 
                        ? Colors.white10 
                        : const Color(0xFFF7F7F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _kind == ProviderKind.openai 
                      ? cs.primary.withOpacity(0.5) 
                      : cs.outlineVariant.withOpacity(0.2),
                  width: _kind == ProviderKind.openai ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'OpenAI',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _kind == ProviderKind.openai ? FontWeight.w600 : FontWeight.w500,
                      color: _kind == ProviderKind.openai ? cs.primary : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _kind = ProviderKind.google;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: _kind == ProviderKind.google 
                    ? cs.primary.withOpacity(0.15) 
                    : Theme.of(context).brightness == Brightness.dark 
                        ? Colors.white10 
                        : const Color(0xFFF7F7F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _kind == ProviderKind.google 
                      ? cs.primary.withOpacity(0.5) 
                      : cs.outlineVariant.withOpacity(0.2),
                  width: _kind == ProviderKind.google ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Gemini',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _kind == ProviderKind.google ? FontWeight.w600 : FontWeight.w500,
                      color: _kind == ProviderKind.google ? cs.primary : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _kind = ProviderKind.claude;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: _kind == ProviderKind.claude 
                    ? cs.primary.withOpacity(0.15) 
                    : Theme.of(context).brightness == Brightness.dark 
                        ? Colors.white10 
                        : const Color(0xFFF7F7F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _kind == ProviderKind.claude 
                      ? cs.primary.withOpacity(0.5) 
                      : cs.outlineVariant.withOpacity(0.2),
                  width: _kind == ProviderKind.claude ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Claude',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _kind == ProviderKind.claude ? FontWeight.w600 : FontWeight.w500,
                      color: _kind == ProviderKind.claude ? cs.primary : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showModelPicker(BuildContext context) async {
    // Platform-specific UI: dialog for desktop, bottom sheet for mobile
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      // Desktop: use dialog
      await showDesktopModelFetchDialog(
        context,
        providerKey: widget.keyName,
        providerDisplayName: widget.displayName,
      );
    } else {
      // Mobile: use bottom sheet with capability icons
      await _showMobileModelPickerSheet(context);
    }
  }

  Future<void> _showMobileModelPickerSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final settings = context.read<SettingsProvider>();
    final rawCfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    // Clean URLs before using config for API calls
    final cfg = rawCfg.copyWith(
      baseUrl: ProviderTestService.sanitizeUrl(rawCfg.baseUrl),
      chatPath: rawCfg.chatPath != null ? ProviderTestService.sanitizeUrl(rawCfg.chatPath!) : null,
    );
    final bool _isDefaultSilicon = widget.keyName.toLowerCase() == 'siliconflow';
    final bool _hasUserKey = (cfg.multiKeyEnabled == true && (cfg.apiKeys?.isNotEmpty == true)) || cfg.apiKey.trim().isNotEmpty;
    final bool _restrictToFree = _isDefaultSilicon && !_hasUserKey;
    final controller = TextEditingController();
    List<dynamic> items = const [];
    List<ModelInfo> unavailableItems = const []; // Models in cfg.models but not in API response
    bool loading = true;
    String error = '';
    final Map<String, bool> collapsed = <String, bool>{};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          final l10n = AppLocalizations.of(ctx)!;
          Future<void> _load() async {
            try {
              List<ModelInfo> availableModels;
              if (_restrictToFree) {
                availableModels = <ModelInfo>[
                  ModelRegistry.infer(ModelInfo(id: 'THUDM/GLM-4-9B-0414', displayName: 'THUDM/GLM-4-9B-0414')),
                  ModelRegistry.infer(ModelInfo(id: 'Qwen/Qwen3-8B', displayName: 'Qwen/Qwen3-8B')),
                ];
              } else {
                availableModels = await ProviderManager.listModels(cfg);
              }

              // Find unavailable models (in cfg.models but not in API response)
              final availableIds = availableModels.map((m) => m.id).toSet();
              final unavailableIds = cfg.models.where((id) => !availableIds.contains(id)).toList();

              // Create ModelInfo for unavailable models
              final unavailableModelsList = unavailableIds.map((id) {
                return ModelInfo(id: id, displayName: id);
              }).toList();

              setLocal(() {
                items = availableModels;
                unavailableItems = unavailableModelsList;
                loading = false;
              });
            } catch (e) {
              setLocal(() {
                items = const [];
                unavailableItems = const [];
                loading = false;
                error = '$e';
              });
            }
          }

          if (loading) {
            Future.microtask(_load);
          }

          final selected = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName).models.toSet();
          final query = controller.text.trim().toLowerCase();

          // Filter available models
          final filtered = <ModelInfo>[
            for (final m in items)
              if (m is ModelInfo && (query.isEmpty || m.id.toLowerCase().contains(query) || m.displayName.toLowerCase().contains(query))) m
          ];

          // Filter unavailable models
          final filteredUnavailable = <ModelInfo>[
            for (final m in unavailableItems)
              if (query.isEmpty || m.id.toLowerCase().contains(query) || m.displayName.toLowerCase().contains(query)) m
          ];

          String _groupFor(ModelInfo m) {
            final id = m.id.toLowerCase();
            if (m.type == ModelType.embedding || id.contains('embedding') || id.contains('embed')) {
              return l10n.providerDetailPageEmbeddingsGroupTitle;
            }
            if (id.contains('gpt') || RegExp(r'(^|[^a-z])o[134]').hasMatch(id)) return 'GPT';
            if (id.contains('gemini-2.0')) return 'Gemini 2.0';
            if (id.contains('gemini-2.5')) return 'Gemini 2.5';
            if (id.contains('gemini-1.5')) return 'Gemini 1.5';
            if (id.contains('gemini')) return 'Gemini';
            if (id.contains('claude-3.5')) return 'Claude 3.5';
            if (id.contains('claude-3')) return 'Claude 3';
            if (id.contains('claude-4')) return 'Claude 4';
            if (id.contains('deepseek')) return 'DeepSeek';
            if (RegExp(r'qwen|qwq|qvq|dashscope').hasMatch(id)) return 'Qwen';
            if (RegExp(r'doubao|ark|volc').hasMatch(id)) return 'Doubao';
            if (id.contains('glm') || id.contains('zhipu')) return 'GLM';
            if (id.contains('mistral')) return 'Mistral';
            if (id.contains('grok') || id.contains('xai')) return 'Grok';
            return l10n.providerDetailPageOtherModelsGroupTitle;
          }

          // Build model row with capability icons
          Widget _buildModelRow(ModelInfo m, {bool isUnavailable = false}) {
            final eff = _effectiveFor(context, widget.keyName, widget.displayName, m);
            final added = selected.contains(m.id);
            // Build capability capsules
            final caps = <Widget>[];
            Widget pillCapsule(Widget icon, Color color) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
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
            if (eff.input.contains(Modality.image)) {
              caps.add(pillCapsule(Icon(Lucide.Eye, size: 11, color: cs.secondary), cs.secondary));
            }
            // Image output
            if (eff.output.contains(Modality.image)) {
              caps.add(pillCapsule(Icon(Lucide.Image, size: 11, color: cs.tertiary), cs.tertiary));
            }
            // Abilities
            for (final ab in eff.abilities) {
              if (ab == ModelAbility.tool) {
                caps.add(pillCapsule(Icon(Lucide.Hammer, size: 11, color: cs.primary), cs.primary));
              } else if (ab == ModelAbility.reasoning) {
                caps.add(pillCapsule(
                  SvgPicture.asset('assets/icons/deepthink.svg', width: 11, height: 11, colorFilter: ColorFilter.mode(cs.secondary, BlendMode.srcIn)), 
                  cs.secondary,
                ));
              }
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ProviderTactileRow(
                pressedScale: 0.98,
                haptics: false,
                onTap: () async {
                  final old = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                  final list = old.models.toList();
                  if (added) {
                    list.removeWhere((e) => e == m.id);
                  } else {
                    list.add(m.id);
                  }
                  await settings.setProviderConfig(widget.keyName, old.copyWith(models: list));
                  setLocal(() {});
                },
                builder: (_) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isUnavailable
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Colors.red.withOpacity(0.08)
                          : Colors.red.withOpacity(0.05))
                      : (added ? cs.primary.withOpacity(0.06) : Colors.transparent),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      if (isUnavailable) ...[
                        Icon(Lucide.TriangleAlert, size: 18, color: Colors.orange.withOpacity(0.8)),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          eff.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: added ? FontWeight.w600 : FontWeight.w500,
                            color: isUnavailable
                              ? cs.onSurface.withOpacity(0.5)
                              : (added ? cs.primary : cs.onSurface),
                            decoration: isUnavailable ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!isUnavailable) ...[
                        ...caps.map((w) => Padding(padding: const EdgeInsets.only(left: 4), child: w)),
                        const SizedBox(width: 8),
                      ],
                      Icon(
                        added ? (isUnavailable ? Lucide.Minus : Lucide.Check) : Lucide.Plus,
                        size: 20,
                        color: isUnavailable
                          ? Colors.red.withOpacity(0.7)
                          : (added ? cs.primary : cs.onSurface.withOpacity(0.5)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final Map<String, List<ModelInfo>> grouped = {};
          for (final m in filtered) {
            final eff = _effectiveFor(context, widget.keyName, widget.displayName, m);
            final g = _groupFor(eff);
            (grouped[g] ??= []).add(eff);
          }
          final groupKeys = grouped.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          // Add unavailable models as a separate group if any exist
          if (filteredUnavailable.isNotEmpty) {
            final unavailableGroupKey = '⚠️ ${l10n.providerDetailPageUnavailableModelsGroupTitle}';
            grouped[unavailableGroupKey] = filteredUnavailable;
            groupKeys.add(unavailableGroupKey);
          }

          return SafeArea(
            top: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.7,
                maxChildSize: 0.8,
                minChildSize: 0.4,
                builder: (c, scrollController) {
                  return Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999))),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: controller,
                          onChanged: (_) => setLocal(() {}),
                          decoration: InputDecoration(
                            hintText: l10n.providerDetailPageFilterHint,
                            filled: true,
                            fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : error.isNotEmpty
                                ? Center(child: Text(error, style: TextStyle(color: cs.error)))
                                : ListView(
                                    controller: scrollController,
                                    padding: const EdgeInsets.only(bottom: 16),
                                    children: [
                                      for (final g in groupKeys) ...[
                                        // Group header
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                                          child: Text(g, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                        ),
                                        // Models
                                        for (final m in grouped[g]!)
                                          _buildModelRow(
                                            m,
                                            isUnavailable: unavailableItems.any((um) => um.id == m.id),
                                          ),
                                      ],
                                    ],
                                  ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        });
      },
    );
  }

  Widget _capPill(BuildContext context, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: cs.primary),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.primary)),
      ]),
    );
  }
}

Widget _buildDismissBg(BuildContext context, {required bool alignStart}) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  return Container(
    decoration: BoxDecoration(
      color: cs.error.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
    child: Row(
      mainAxisAlignment: alignStart ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: [
        Icon(Lucide.Trash2, color: cs.error, size: 20),
        const SizedBox(width: 6),
        Text(
          l10n.providerDetailPageDeleteText,
          style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.providerKey, required this.modelId, required this.reorderIndex});
  final String providerKey;
  final String modelId;
  final int reorderIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return ProviderTactileRow(
      pressedScale: 0.98,
      haptics: false,
      onTap: null,
      builder: (pressed) {
        return Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 左侧内容区域：头像和名称（不包含拖动监听器，避免重复）
                Expanded(
                  child: Row(
                    children: [
                      BrandAvatar(name: modelId, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onLongPress: () {
                                Haptics.light();
                                Clipboard.setData(ClipboardData(text: modelId));
                                showAppSnackBar(context, message: '已复制: $modelId');
                              },
                              child: Text(_displayName(context), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 4),
                            buildModelTagWrap(context, _effective(context)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 右侧按钮区域 - 增加间距和更明确的布局
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 设置按钮 - 使用 Ink 而不是 Container 避免背景色与 InkWell 叠加
                    Material(
                      color: Colors.transparent,
                      child: Ink(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            final isDesktop = !kIsWeb &&
                                (defaultTargetPlatform == TargetPlatform.windows ||
                                    defaultTargetPlatform == TargetPlatform.macOS ||
                                    defaultTargetPlatform == TargetPlatform.linux);
                            if (isDesktop) {
                              await showDesktopModelEditDialog(context, providerKey: providerKey, modelId: modelId);
                              return;
                            }
                            await showModelDetailSheet(context, providerKey: providerKey, modelId: modelId);
                          },
                          child: Center(
                            child: Icon(
                              Lucide.Settings2,
                              size: 18,
                              color: cs.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 拖动手柄按钮 - 移除背景色避免与 DragStartListener 的交互层叠加
                    ReorderableDragStartListener(
                      index: reorderIndex,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: Center(
                            child: Icon(
                              Lucide.GripHorizontal,
                              size: 18,
                              color: cs.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  ModelInfo _infer(String id) {
    // build a minimal ModelInfo and let registry infer
    return ModelRegistry.infer(ModelInfo(id: id, displayName: id));
  }

  ModelInfo _effective(BuildContext context) {
    final base = _infer(modelId);
    final cfg = context.watch<SettingsProvider>().getProviderConfig(providerKey);
    final ov = cfg.modelOverrides[modelId] as Map?;
    if (ov == null) return base;
    ModelType? type;
    final t = (ov['type'] as String?) ?? '';
    if (t == 'embedding') type = ModelType.embedding; else if (t == 'chat') type = ModelType.chat;
    List<Modality>? input;
    if (ov['input'] is List) {
      input = [
        for (final e in (ov['input'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)
      ];
    }
    List<Modality>? output;
    if (ov['output'] is List) {
      output = [
        for (final e in (ov['output'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)
      ];
    }
    List<ModelAbility>? abilities;
    if (ov['abilities'] is List) {
      abilities = [
        for (final e in (ov['abilities'] as List)) (e.toString() == 'reasoning' ? ModelAbility.reasoning : ModelAbility.tool)
      ];
    }
    return base.copyWith(
      displayName: (ov['name'] as String?)?.isNotEmpty == true ? ov['name'] as String : base.displayName,
      type: type ?? base.type,
      input: input ?? base.input,
      output: output ?? base.output,
      abilities: abilities ?? base.abilities,
    );
  }

  String _displayName(BuildContext context) {
    final cfg = context.watch<SettingsProvider>().getProviderConfig(providerKey);
    final ov = cfg.modelOverrides[modelId] as Map?;
    if (ov != null) {
      final n = (ov['name'] as String?)?.trim();
      if (n != null && n.isNotEmpty) return n;
    }
    return modelId;
  }

  Widget _pill(BuildContext context, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: cs.primary),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.primary)),
      ]),
    );
  }
}

class _ConnectionTestDialog extends StatefulWidget {
  const _ConnectionTestDialog({required this.providerKey, required this.providerDisplayName});
  final String providerKey;
  final String providerDisplayName;

  @override
  State<_ConnectionTestDialog> createState() => _ConnectionTestDialogState();
}

enum _TestState { idle, loading, success, error }

class _ConnectionTestDialogState extends State<_ConnectionTestDialog> {
  String? _selectedModelId;
  _TestState _state = _TestState.idle;
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final title = l10n.providerDetailPageTestConnectionTitle;
    final canTest = _selectedModelId != null && _state != _TestState.loading;
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              const SizedBox(height: 16),
              _buildBody(context, cs, l10n),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.providerDetailPageCancelButton)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: canTest ? _doTest : null,
                    style: TextButton.styleFrom(foregroundColor: canTest ? cs.primary : cs.onSurface.withOpacity(0.4)),
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

  

  Widget _buildBody(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    switch (_state) {
      case _TestState.idle:
        return _buildIdle(context, cs, l10n);
      case _TestState.loading:
        return _buildLoading(context, cs, l10n);
      case _TestState.success:
        return _buildResult(context, cs, l10n, success: true, message: l10n.providerDetailPageTestSuccessMessage);
      case _TestState.error:
        return _buildResult(context, cs, l10n, success: false, message: _errorMessage);
    }
  }

  Widget _buildIdle(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedModelId == null)
          TextButton(
            onPressed: _pickModel,
            child: Text(l10n.providerDetailPageSelectModelButton),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BrandAvatar(name: _selectedModelId!, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _selectedModelId!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              TextButton(onPressed: _pickModel, child: Text(l10n.providerDetailPageChangeButton)),
            ],
          ),
      ],
    );
  }

  Widget _buildLoading(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedModelId != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BrandAvatar(name: _selectedModelId!, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _selectedModelId!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        const LinearProgressIndicator(minHeight: 4),
        const SizedBox(height: 12),
        Text(l10n.providerDetailPageTestingMessage, style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
      ],
    );
  }

  Widget _buildResult(BuildContext context, ColorScheme cs, AppLocalizations l10n, {required bool success, required String message}) {
    final color = success ? Colors.green : cs.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedModelId != null)
          ProviderTactileRow(
            pressedScale: 0.98,
            haptics: false,
            onTap: _pickModel,
            builder: (_) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    BrandAvatar(name: _selectedModelId!, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedModelId!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Lucide.ChevronDown, size: 16, color: cs.onSurface.withOpacity(0.7)),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 14),
        // Show icon with result
        Icon(
          success ? Lucide.CheckCircle : Lucide.XCircle,
          size: 32,
          color: color,
        ),
        const SizedBox(height: 12),
        // Error message with selectable text for easy copying
        if (!success && message.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.error.withOpacity(0.3), width: 1),
            ),
            child: SelectableText(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          Text(
            message,
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Future<void> _pickModel() async {
    final selected = await showModelPickerForTest(context, widget.providerKey, widget.providerDisplayName);
    if (selected != null) {
      setState(() {
        _selectedModelId = selected;
        _state = _TestState.idle;
        _errorMessage = '';
      });
    }
  }

  Future<void> _doTest() async {
    if (_selectedModelId == null) return;
    setState(() {
      _state = _TestState.loading;
      _errorMessage = '';
    });
    
    final result = await ProviderTestService.testConnection(
      context: context,
      providerKey: widget.providerKey,
      providerDisplayName: widget.providerDisplayName,
      modelId: _selectedModelId!,
    );
    
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _state = _TestState.success;
      } else if (result.isError) {
        _state = _TestState.error;
        _errorMessage = result.errorMessage ?? '';
      }
    });
  }
}

Future<String?> showModelPickerForTest(BuildContext context, String providerKey, String providerDisplayName) async {
  final cs = Theme.of(context).colorScheme;
  final settings = context.read<SettingsProvider>();
  final cfg = settings.getProviderConfig(providerKey, defaultName: providerDisplayName);
  final sel = await showModelSelector(context, limitProviderKey: providerKey);
  return sel?.modelId;
}

ModelInfo _effectiveFor(BuildContext context, String providerKey, String providerDisplayName, ModelInfo base) {
  final cfg = context.read<SettingsProvider>().getProviderConfig(providerKey, defaultName: providerDisplayName);
  final ov = cfg.modelOverrides[base.id] as Map?;
  if (ov == null) return base;
  ModelType? type;
  final t = (ov['type'] as String?) ?? '';
  if (t == 'embedding') type = ModelType.embedding; else if (t == 'chat') type = ModelType.chat;
  List<Modality>? input;
  if (ov['input'] is List) {
    input = [
      for (final e in (ov['input'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)
    ];
  }
  List<Modality>? output;
  if (ov['output'] is List) {
    output = [
      for (final e in (ov['output'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)
    ];
  }
  List<ModelAbility>? abilities;
  if (ov['abilities'] is List) {
    abilities = [
      for (final e in (ov['abilities'] as List)) (e.toString() == 'reasoning' ? ModelAbility.reasoning : ModelAbility.tool)
    ];
  }
  return base.copyWith(
    type: type ?? base.type,
    input: input ?? base.input,
    output: output ?? base.output,
    abilities: abilities ?? base.abilities,
  );
}


// Using flutter_slidable for reliable swipe actions with confirm + undo.

// Legacy page-based implementations removed in favor of swipeable PageView tabs.


// Mobile model group widget with collapsible header
class _MobileModelGroup extends StatelessWidget {
  const _MobileModelGroup({
    super.key,
    required this.groupName,
    required this.modelIds,
    required this.providerKey,
    required this.isCollapsed,
    required this.onToggle,
    required this.onDelete,
    required this.onReorder,
  });

  final String groupName;
  final List<String> modelIds;
  final String providerKey;
  final bool isCollapsed;
  final VoidCallback onToggle;
  final Function(String) onDelete;
  final Function(int, int) onReorder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Group header
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.03) : cs.primary.withOpacity(0.04),
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: isCollapsed ? 0.0 : 0.25, // right -> down
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Lucide.ChevronRight,
                    size: 18,
                    color: cs.onSurface.withOpacity(0.8),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    groupName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE8E9EC),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${modelIds.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withOpacity(0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Models list
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            buildDefaultDragHandles: false,
            itemCount: modelIds.length,
            onReorder: onReorder,
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final t = Curves.easeOut.transform(animation.value);
                  return Transform.scale(
                    scale: 0.98 + 0.02 * t,
                    child: child,
                  );
                },
                child: child,
              );
            },
            itemBuilder: (c, i) {
              final id = modelIds[i];
              final l10n = AppLocalizations.of(context)!;
              return KeyedSubtree(
                key: ValueKey('reorder-model-$id-$groupName'),
                child: Slidable(
                  key: ValueKey('model-$id'),
                  endActionPane: ActionPane(
                    motion: const StretchMotion(),
                    extentRatio: 0.42,
                    children: [
                      CustomSlidableAction(
                        autoClose: true,
                        backgroundColor: Colors.transparent,
                        child: Container(
                          width: double.infinity,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: isDark ? cs.error.withOpacity(0.22) : cs.error.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cs.error.withOpacity(0.35)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Lucide.Trash2, color: cs.error, size: 18),
                                const SizedBox(width: 6),
                                Text(l10n.providerDetailPageDeleteModelButton, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                        onPressed: (_) => onDelete(id),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    child: _ModelCard(providerKey: providerKey, modelId: id, reorderIndex: i),
                  ),
                ),
              );
            },
          ),
          crossFadeState: isCollapsed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
    );
  }
}
