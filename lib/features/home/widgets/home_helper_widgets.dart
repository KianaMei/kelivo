import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui' as ui;

import '../../../l10n/app_localizations.dart';
import '../../../utils/brand_assets.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/services/haptics.dart';

/// Icon widget that displays the current model's brand icon or fallback.
class CurrentModelIcon extends StatelessWidget {
  const CurrentModelIcon({
    super.key,
    required this.providerKey,
    required this.modelId,
    this.size = 28,
    this.withBackground = true,
    this.backgroundColor,
  });

  final String? providerKey;
  final String? modelId;
  final double size;
  final bool withBackground;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (providerKey == null || modelId == null) return const SizedBox.shrink();
    String? asset = BrandAssets.assetForName(modelId!);
    asset ??= BrandAssets.assetForName(providerKey!);
    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final ColorFilter? tint =
            (Theme.of(context).brightness == Brightness.dark && !isColorful)
                ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
                : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.5,
          height: size * 0.5,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(asset,
            width: size * 0.5, height: size * 0.5, fit: BoxFit.contain);
      }
    } else {
      inner = Text(
        modelId!.isNotEmpty ? modelId!.characters.first.toUpperCase() : '?',
        style: TextStyle(
            color: cs.primary, fontWeight: FontWeight.w700, fontSize: size * 0.43),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: withBackground
            ? (backgroundColor ??
                (isDark ? Colors.white10 : cs.primary.withOpacity(0.1)))
            : Colors.transparent,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: size * 0.64,
        height: size * 0.64,
        child: Center(
            child: inner is SvgPicture || inner is Image
                ? inner
                : FittedBox(child: inner)),
      ),
    );
  }
}


/// Toolbar for selection mode with cancel and confirm buttons.
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({
    super.key,
    required this.onCancel,
    required this.onConfirm,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassCircleButtonSmall(
          icon: Lucide.X,
          color: cs.onSurface,
          onTap: onCancel,
          semanticLabel: AppLocalizations.of(context)!.homePageCancel,
        ),
        const SizedBox(width: 14),
        GlassCircleButtonSmall(
          icon: Lucide.Check,
          color: cs.primary,
          onTap: onConfirm,
          semanticLabel: AppLocalizations.of(context)!.homePageDone,
        ),
      ],
    );
  }
}

/// Animated container that slides/fades in/out.
class AnimatedSelectionBar extends StatelessWidget {
  const AnimatedSelectionBar({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: IgnorePointer(ignoring: !visible, child: child),
      ),
    );
  }
}

/// iOS-style glass capsule button.
class GlassCapsuleButton extends StatefulWidget {
  const GlassCapsuleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<GlassCapsuleButton> createState() => _GlassCapsuleButtonState();
}

class _GlassCapsuleButtonState extends State<GlassCapsuleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final glassBase =
        isDark ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.65);
    final overlay =
        isDark ? Colors.black.withOpacity(0.06) : Colors.black.withOpacity(0.05);
    final tileColor = _pressed ? Color.alphaBlend(overlay, glassBase) : glassBase;
    final borderColor = cs.outlineVariant.withOpacity(isDark ? 0.35 : 0.40);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.0),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 16, color: widget.color),
                  const SizedBox(width: 6),
                  Text(
                    widget.label,
                    style: TextStyle(
                        color: widget.color,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact icon-only glass button.
class GlassCircleButtonSmall extends StatefulWidget {
  const GlassCircleButtonSmall({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    this.semanticLabel,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? semanticLabel;
  final double size;

  @override
  State<GlassCircleButtonSmall> createState() => _GlassCircleButtonSmallState();
}

class _GlassCircleButtonSmallState extends State<GlassCircleButtonSmall> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final glassBase =
        isDark ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.06);
    final overlay =
        isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);
    final tileColor = _pressed ? Color.alphaBlend(overlay, glassBase) : glassBase;
    final borderColor = cs.outlineVariant.withOpacity(isDark ? 0.10 : 0.10);

    final child = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(child: Icon(widget.icon, size: 18, color: widget.color)),
    );

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: tileColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
