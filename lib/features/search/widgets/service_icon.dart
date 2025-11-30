import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../utils/brand_assets.dart';

/// Search service provider icon widget
class ServiceIcon extends StatelessWidget {
  const ServiceIcon({
    super.key,
    required this.type,
    required this.name,
    this.size = 40,
  });

  final String type;  // Service type like 'bing_local', 'tavily', etc.
  final String name;  // Display name for fallback
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use type for matching, not the localized name
    final matchName = _getMatchName(type);
    final asset = BrandAssets.assetForName(matchName);
    final bg = isDark ? Colors.white10 : cs.primary.withOpacity(0.1);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: asset != null
          ? _buildAssetIcon(asset, size, isDark)
          : _buildLetterIcon(name, size, cs),
    );
  }

  Widget _buildAssetIcon(String asset, double size, bool isDark) {
    final iconSize = size * 0.62;
    if (asset.endsWith('.svg')) {
      final isColorful = asset.contains('color');
      final ColorFilter? tint = (isDark && !isColorful)
          ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
          : null;
      return SvgPicture.asset(
        asset,
        width: iconSize,
        height: iconSize,
        colorFilter: tint,
      );
    } else {
      return Image.asset(
        asset,
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
      );
    }
  }

  Widget _buildLetterIcon(String name, double size, ColorScheme cs) {
    return Text(
      name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
      style: TextStyle(
        color: cs.primary,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.42,
      ),
    );
  }

  // Map service type to name for BrandAssets matching
  String _getMatchName(String type) {
    switch (type) {
      case 'bing_local':
        return 'bing';
      case 'tavily':
        return 'tavily';
      case 'exa':
        return 'exa';
      case 'zhipu':
        return 'zhipu';
      case 'searxng':
        return 'searxng';
      case 'linkup':
        return 'linkup';
      case 'brave':
        return 'brave';
      case 'metaso':
        return 'metaso';
      case 'jina':
        return 'jina';
      case 'ollama':
        return 'ollama';
      case 'bocha':
        return 'bocha';
      default:
        return type;
    }
  }
}
