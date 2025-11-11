import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../core/services/haptics.dart';
import '../../../utils/brand_assets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../pages/provider_detail_page.dart';

/// Show provider detail settings sheet
Future<void> showProviderDetailSheet(
  BuildContext context, {
  required String keyName,
  required String displayName,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ProviderDetailSheet(
      keyName: keyName,
      displayName: displayName,
    ),
  );
}

class _ProviderDetailSheet extends StatefulWidget {
  const _ProviderDetailSheet({
    required this.keyName,
    required this.displayName,
  });

  final String keyName;
  final String displayName;

  @override
  State<_ProviderDetailSheet> createState() => _ProviderDetailSheetState();
}

class _ProviderDetailSheetState extends State<_ProviderDetailSheet> {
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _baseUrlCtrl;
  bool _showApiKey = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    _apiKeyCtrl = TextEditingController(text: cfg.apiKey);
    _baseUrlCtrl = TextEditingController(text: cfg.baseUrl);
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    final isDark = theme.brightness == Brightness.dark;

    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Header with avatar and name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _BrandAvatar(
                    name: cfg.name.isNotEmpty ? cfg.name : widget.displayName,
                    size: 48,
                    customAvatarPath: cfg.customAvatarPath,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cfg.name.isNotEmpty ? cfg.name : widget.displayName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${cfg.models.length} ${l10n.providerDetailPageModelsTabTitle}',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Close button
                  IconButton(
                    icon: Icon(Lucide.X, size: 22, color: cs.onSurface),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: l10n.searchServicesPageDone,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Enable/Disable toggle
                    IosCardPress(
                      borderRadius: BorderRadius.circular(14),
                      baseColor: cs.surface,
                      duration: const Duration(milliseconds: 260),
                      onTap: () {
                        Haptics.light();
                        context.read<SettingsProvider>().setProviderConfig(
                          widget.keyName,
                          cfg.copyWith(enabled: !cfg.enabled),
                        );
                      },
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            cfg.enabled ? Lucide.Check : Lucide.X,
                            size: 22,
                            color: cfg.enabled ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.providerDetailPageEnableToggleLabel,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IosSwitch(
                            value: cfg.enabled,
                            onChanged: (v) {
                              context.read<SettingsProvider>().setProviderConfig(
                                widget.keyName,
                                cfg.copyWith(enabled: v),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // API Key section
                    Text(
                      l10n.providerDetailPageApiKeyLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _apiKeyCtrl,
                      obscureText: !_showApiKey,
                      onChanged: (value) {
                        // Auto-save on change with debounce would be better,
                        // but for simplicity we save on focus loss
                      },
                      onSubmitted: (value) {
                        context.read<SettingsProvider>().setProviderConfig(
                          widget.keyName,
                          cfg.copyWith(apiKey: value),
                        );
                      },
                      decoration: InputDecoration(
                        hintText: l10n.providerDetailPageApiKeyHint,
                        filled: true,
                        fillColor: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.4),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.4),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: cs.primary.withOpacity(0.6),
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showApiKey ? Lucide.EyeOff : Lucide.Eye,
                            size: 20,
                            color: cs.onSurface.withOpacity(0.5),
                          ),
                          onPressed: () {
                            setState(() {
                              _showApiKey = !_showApiKey;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Base URL section
                    Text(
                      l10n.providerDetailPageBaseUrlLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _baseUrlCtrl,
                      onSubmitted: (value) {
                        context.read<SettingsProvider>().setProviderConfig(
                          widget.keyName,
                          cfg.copyWith(baseUrl: value),
                        );
                      },
                      decoration: InputDecoration(
                        hintText: l10n.providerDetailPageBaseUrlHint,
                        filled: true,
                        fillColor: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.4),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.4),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: cs.primary.withOpacity(0.6),
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              // Save changes
                              context.read<SettingsProvider>().setProviderConfig(
                                widget.keyName,
                                cfg.copyWith(
                                  apiKey: _apiKeyCtrl.text,
                                  baseUrl: _baseUrlCtrl.text,
                                ),
                              );
                              Navigator.of(context).pop();
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: cs.outline),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              l10n.providerDetailPageSaveButton,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              // Navigate to full detail page for advanced settings
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ProviderDetailPage(
                                    keyName: widget.keyName,
                                    displayName: widget.displayName,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              l10n.providerDetailPageAdvancedButton,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Brand avatar widget (copied from providers_page for consistency)
class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({
    required this.name,
    this.size = 24,
    this.customAvatarPath,
  });

  final String name;
  final double size;
  final String? customAvatarPath;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Custom avatar takes precedence
    if (customAvatarPath != null && customAvatarPath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(
          customAvatarPath!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultAvatar(cs, isDark),
        ),
      );
    }

    // Use BrandAssets to get the icon path
    final asset = BrandAssets.assetForName(name);
    if (asset != null) {
      final isColorful = asset.contains('color');
      final ColorFilter? tint = (isDark && !isColorful)
          ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
          : null;

      if (asset.endsWith('.svg')) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.08) : cs.primary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            asset,
            width: size * 0.62,
            height: size * 0.62,
            colorFilter: tint,
          ),
        );
      } else {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.08) : cs.primary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Image.asset(
            asset,
            width: size * 0.62,
            height: size * 0.62,
            fit: BoxFit.contain,
          ),
        );
      }
    }

    return _defaultAvatar(cs, isDark);
  }

  Widget _defaultAvatar(ColorScheme cs, bool isDark) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : cs.primary.withOpacity(0.08),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}
