import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../utils/brand_assets.dart';

/// Provider brand avatar widget
/// Supports custom avatar (URL, file path, emoji), brand assets, or initials
class BrandAvatar extends StatelessWidget {
  const BrandAvatar({
    super.key,
    required this.name,
    this.size = 20,
    this.customAvatarPath,
  });

  final String name;
  final double size;
  final String? customAvatarPath;

  bool _preferMonochromeWhite(String n) {
    final k = n.toLowerCase();
    if (RegExp(r'openai|gpt|o\d').hasMatch(k)) return true;
    if (RegExp(r'grok|xai').hasMatch(k)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white10 : cs.primary.withOpacity(0.1);

    // Priority 1: Custom avatar
    if (customAvatarPath != null && customAvatarPath!.isNotEmpty) {
      final av = customAvatarPath!.trim();

      // 1. URL - Network image
      if (av.startsWith('http')) {
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: bg,
          child: ClipOval(
            child: Image.network(
              av,
              key: ValueKey(av),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildBrandAvatar(cs, isDark),
            ),
          ),
        );
      }
      // 2. File path (contains / or :)
      else if (av.startsWith('/') || av.contains(':') || av.contains('/')) {
        return FutureBuilder<String?>(
          key: ValueKey(av),
          future: AssistantProvider.resolveToAbsolutePath(av),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              final file = File(snapshot.data!);
              if (file.existsSync()) {
                return CircleAvatar(
                  radius: size / 2,
                  backgroundColor: bg,
                  child: ClipOval(
                    child: Image.file(
                      file,
                      key: ValueKey(file.path),
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildBrandAvatar(cs, isDark),
                    ),
                  ),
                );
              }
            }
            return _buildBrandAvatar(cs, isDark);
          },
        );
      }
      // 3. Emoji - Display as text
      else {
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: bg,
          child: Text(
            av,
            style: TextStyle(
              fontSize: size * 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }
    }

    return _buildBrandAvatar(cs, isDark);
  }

  Widget _buildBrandAvatar(ColorScheme cs, bool isDark) {
    final asset = BrandAssets.assetForName(name);
    final lower = name.toLowerCase();
    final bool mono = isDark && (RegExp(r'openai|gpt|o\\d').hasMatch(lower) || RegExp(r'grok|xai').hasMatch(lower) || RegExp(r'openrouter').hasMatch(lower));
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: isDark ? Colors.white10 : cs.primary.withOpacity(0.1),
      child: asset == null
          ? Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(color: cs.primary, fontSize: size * 0.5, fontWeight: FontWeight.w700))
          : (asset.endsWith('.svg')
              ? SvgPicture.asset(
                  asset,
                  width: size * 0.7,
                  height: size * 0.7,
                  colorFilter: mono ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null,
                )
              : Image.asset(
                  asset,
                  width: size * 0.7,
                  height: size * 0.7,
                  fit: BoxFit.contain,
                  color: mono ? Colors.white : null,
                  colorBlendMode: mono ? BlendMode.srcIn : null,
                )),
    );
  }
}
