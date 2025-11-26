import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../icons/lucide_adapter.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/assistant_provider.dart';
import '../core/services/search/search_service.dart';
import '../utils/brand_assets.dart';
import '../l10n/app_localizations.dart';
import '../shared/widgets/ios_switch.dart';
import 'desktop_popover.dart';

/// Show desktop search provider selection popover with full settings
Future<void> showDesktopSearchProviderPopover(
  BuildContext context, {
  required GlobalKey anchorKey,
}) async {
  // Obtain a programmatic close callback from the generic popover helper
  // and wire it into the content so that selecting an option
  // automatically dismisses the popover (matches remote behaviour).
  VoidCallback close = () {};
  close = await showDesktopPopover(
    context,
    anchorKey: anchorKey,
    child: _SearchProviderContent(onDone: () => close()),
    maxHeight: 520,
  );
}

class _SearchProviderContent extends StatelessWidget {
  const _SearchProviderContent({required this.onDone});

  final VoidCallback onDone;

  bool _supportsBuiltInSearch(SettingsProvider settings, AssistantProvider ap) {
    final a = ap.currentAssistant;
    final providerKey = a?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = a?.chatModelId ?? settings.currentModelId;
    if (providerKey == null || (modelId ?? '').isEmpty) return false;
    final cfg = settings.getProviderConfig(providerKey);
    final isOfficialGemini =
        cfg.providerType == ProviderKind.google && (cfg.vertexAI != true);
    final isClaude = cfg.providerType == ProviderKind.claude;
    final isOpenAIResponses =
        cfg.providerType == ProviderKind.openai && (cfg.useResponseApi == true);
    final isGrok = _isGrokModel(cfg, modelId!);
    return isOfficialGemini || isClaude || isOpenAIResponses || isGrok;
  }

  bool _hasBuiltInSearchEnabled(SettingsProvider settings, AssistantProvider ap) {
    final a = ap.currentAssistant;
    final providerKey = a?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = a?.chatModelId ?? settings.currentModelId;
    if (providerKey == null || (modelId ?? '').isEmpty) return false;
    final cfg = settings.getProviderConfig(providerKey);
    final ov = cfg.modelOverrides[modelId!] as Map?;
    final list = (ov?['builtInTools'] as List?) ?? const <dynamic>[];
    return list.map((e) => e.toString().toLowerCase()).contains('search');
  }

  Future<void> _toggleBuiltInSearch(
      BuildContext context, bool value, String providerKey, String modelId) async {
    final sp = context.read<SettingsProvider>();
    final cfg = sp.getProviderConfig(providerKey);
    final overrides = Map<String, dynamic>.from(cfg.modelOverrides);
    final mo = Map<String, dynamic>.from((overrides[modelId] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v)) ??
        const <String, dynamic>{});
    final list = List<String>.from(
        ((mo['builtInTools'] as List?) ?? const <dynamic>[]).map((e) => e.toString()));
    if (value) {
      if (!list.map((e) => e.toLowerCase()).contains('search')) list.add('search');
    } else {
      list.removeWhere((e) => e.toLowerCase() == 'search');
    }
    mo['builtInTools'] = list;
    overrides[modelId] = mo;
    await sp.setProviderConfig(providerKey, cfg.copyWith(modelOverrides: overrides));
    if (value) {
      await sp.setSearchEnabled(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SettingsProvider>();
    final ap = context.watch<AssistantProvider>();
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final a = ap.currentAssistant;
    final providerKey = a?.chatModelProvider ?? sp.currentModelProvider;
    final modelId = a?.chatModelId ?? sp.currentModelId;
    final services = sp.searchServices;
    final selected = sp.searchServiceSelected.clamp(0, services.isNotEmpty ? services.length - 1 : 0);
    final enabled = sp.searchEnabled;
    final supportsBuiltIn = _supportsBuiltInSearch(sp, ap);
    final builtInEnabled = _hasBuiltInSearchEnabled(sp, ap);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Built-in search toggle
          if (supportsBuiltIn && providerKey != null && modelId != null) ...[
              _SettingRow(
              icon: Lucide.Search,
              label: l10n.searchSettingsSheetBuiltinSearchTitle,
              value: builtInEnabled,
              onChanged: (v) => _toggleBuiltInSearch(context, v, providerKey, modelId),
            ),
            const SizedBox(height: 8),
          ],

          // Web search toggle
          if (!builtInEnabled) ...[
              _SettingRow(
              icon: Lucide.Globe,
              label: l10n.searchSettingsSheetWebSearchTitle,
              value: enabled,
              onChanged: (v) => sp.setSearchEnabled(v),
            ),
            const SizedBox(height: 8),
          ],

          // Service list
          if (!builtInEnabled && services.isNotEmpty) ...[
            ...services.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              final svc = SearchService.getService(s);
              final name = svc.name;
              final isSelected = i == selected;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: PopoverRowItem(
                  leading: _BrandIcon(name: name, color: cs.onSurface),
                  label: name,
                  selected: isSelected,
                  onTap: () async {
                    await sp.setSearchServiceSelected(i);
                    if (!enabled) await sp.setSearchEnabled(true);
                    onDone();
                  },
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _SettingRow extends StatefulWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<_SettingRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hovered
        ? (isDark ? Colors.white : Colors.black).withOpacity(isDark ? 0.08 : 0.05)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              IosSwitch(
                value: widget.value,
                onChanged: widget.onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandIcon extends StatelessWidget {
  const _BrandIcon({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final asset = BrandAssets.assetForName(name);
    if (asset == null) {
      return Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 14),
      );
    }
    if (asset.endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        width: 16,
        height: 16,
        colorFilter: asset.contains('color')
            ? null
            : ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return Image.asset(
      asset,
      width: 16,
      height: 16,
      color: asset.endsWith('.png') ? null : color,
      colorBlendMode: asset.endsWith('.png') ? null : BlendMode.srcIn,
      fit: BoxFit.contain,
    );
  }
}

// Helper function to detect Grok models with robust checking
bool _isGrokModel(ProviderConfig cfg, String modelId) {
  // Check logical model ID
  final logicalModel = modelId.toLowerCase();

  // Check API model ID (if different from logical ID)
  String apiModel = logicalModel;
  try {
    final ov = cfg.modelOverrides[modelId];
    if (ov is Map<String, dynamic>) {
      final raw = (ov['apiModelId'] ?? ov['api_model_id'])?.toString().trim();
      if (raw != null && raw.isNotEmpty) {
        apiModel = raw.toLowerCase();
      }
    }
  } catch (_) {}

  // Check common Grok model name patterns
  final grokPatterns = ['grok', 'xai-'];
  for (final pattern in grokPatterns) {
    if (apiModel.contains(pattern) || logicalModel.contains(pattern)) {
      return true;
    }
  }

  return false;
}
