import 'dart:ui' as ui;
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

/// Show provider detail settings dialog with backdrop blur
Future<void> showProviderDetailSheet(
  BuildContext context, {
  required String keyName,
  required String displayName,
}) async {
  await showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.5),
    barrierDismissible: true,
    builder: (ctx) => _BlurredBackdropDialog(
      child: _ProviderDetailDialog(
        keyName: keyName,
        displayName: displayName,
      ),
    ),
  );
}

/// Dialog wrapper with blurred backdrop
class _BlurredBackdropDialog extends StatelessWidget {
  const _BlurredBackdropDialog({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: child,
      ),
    );
  }
}

class _ProviderDetailDialog extends StatefulWidget {
  const _ProviderDetailDialog({
    required this.keyName,
    required this.displayName,
  });

  final String keyName;
  final String displayName;

  @override
  State<_ProviderDetailDialog> createState() => _ProviderDetailDialogState();
}

class _ProviderDetailDialogState extends State<_ProviderDetailDialog> {
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

    return Container(
      constraints: const BoxConstraints(
        maxWidth: 600,
        maxHeight: 700,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with avatar and name
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                _BrandAvatar(
                  name: cfg.name.isNotEmpty ? cfg.name : widget.displayName,
                  size: 52,
                  customAvatarPath: cfg.customAvatarPath,
                ),
                const SizedBox(width: 14),
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

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Enable/Disable toggle
                  IosCardPress(
                    borderRadius: BorderRadius.circular(14),
                    baseColor: isDark ? Colors.white.withOpacity(0.08) : cs.surface,
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
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: (cfg.enabled ? Colors.green : Colors.orange).withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            cfg.enabled ? Lucide.Check : Lucide.X,
                            size: 20,
                            color: cfg.enabled ? Colors.green : Colors.orange,
                          ),
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
                  const SizedBox(height: 18),

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
                    onSubmitted: (value) {
                      context.read<SettingsProvider>().setProviderConfig(
                        widget.keyName,
                        cfg.copyWith(apiKey: value),
                      );
                    },
                    decoration: InputDecoration(
                      hintText: l10n.providerDetailPageApiKeyHint,
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF5F5F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: cs.outlineVariant.withOpacity(0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: cs.outlineVariant.withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: cs.primary,
                          width: 1.8,
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
                  const SizedBox(height: 18),

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
                      fillColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF5F5F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: cs.outlineVariant.withOpacity(0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: cs.outlineVariant.withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: cs.primary,
                          width: 1.8,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

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
                            side: BorderSide(color: cs.outline.withOpacity(0.5)),
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
                            elevation: 0,
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
