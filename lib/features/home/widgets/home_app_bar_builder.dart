import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../shared/animations/widgets.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../utils/brand_assets.dart';
import '../../../icons/lucide_adapter.dart';

/// Helper class to build AppBar for HomePage
/// This reduces the complexity of home_page.dart while keeping state access
class HomeAppBarBuilder {
  final BuildContext context;
  final String title;
  final String? providerName;
  final String? modelDisplay;
  final ColorScheme cs;
  final GlobalKey miniMapAnchorKey;
  final VoidCallback onToggleSidebar;
  final VoidCallback onRenameConversation;
  final VoidCallback onShowModelSelect;
  final VoidCallback onMiniMapTap;
  final VoidCallback onNewConversation;
  final VoidCallback? onToggleRightSidebar;

  HomeAppBarBuilder({
    required this.context,
    required this.title,
    required this.providerName,
    required this.modelDisplay,
    required this.cs,
    required this.miniMapAnchorKey,
    required this.onToggleSidebar,
    required this.onRenameConversation,
    required this.onShowModelSelect,
    required this.onMiniMapTap,
    required this.onNewConversation,
    this.onToggleRightSidebar,
  });

  bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Build Mobile AppBar
  AppBar buildMobileAppBar() {
    return AppBar(
      systemOverlayStyle: _buildSystemOverlayStyle(),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: _buildAppBarFlexibleSpace(),
      leading: _buildMobileLeading(),
      titleSpacing: 2,
      title: _buildMobileTitle(),
      actions: _buildMobileActions(),
    );
  }

  /// Build Tablet/Desktop AppBar
  AppBar buildTabletAppBar() {
    return AppBar(
      systemOverlayStyle: _buildSystemOverlayStyle(),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: _buildTabletLeading(),
      titleSpacing: 2,
      title: _buildTabletTitle(),
      actions: _buildTabletActions(),
    );
  }

  SystemUiOverlayStyle _buildSystemOverlayStyle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          )
        : const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          );
  }

  Widget _buildAppBarFlexibleSpace() {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.26 : 0.20,
            ),
            border: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withOpacity(0.12),
                width: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLeading() {
    return IosIconButton(
      size: 20,
      padding: const EdgeInsets.all(8),
      minSize: 40,
      builder: (color) => SvgPicture.asset(
        'assets/icons/list.svg',
        width: 14,
        height: 14,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
      onTap: onToggleSidebar,
    );
  }

  Widget _buildTabletLeading() {
    return IconButton(
      onPressed: onToggleSidebar,
      icon: SvgPicture.asset(
        'assets/icons/list.svg',
        width: 14,
        height: 14,
        colorFilter: ColorFilter.mode(
          Theme.of(context).iconTheme.color ?? cs.onSurface,
          BlendMode.srcIn,
        ),
      ),
    );
  }

  Widget _buildMobileTitle() {
    final titleWidget = InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onRenameConversation,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: AnimatedTextSwap(
          text: title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );

    final modelWidget = (providerName != null && modelDisplay != null)
        ? InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onShowModelSelect,
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: _isDesktop ? 4 : 0,
                horizontal: _isDesktop ? 8 : 0,
              ),
              child: AnimatedTextSwap(
                text: '$modelDisplay ($providerName)',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
        : null;

    // Desktop: horizontal layout
    if (_isDesktop && modelWidget != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          titleWidget,
          const SizedBox(width: 12),
          modelWidget,
        ],
      );
    }

    // Mobile: vertical layout
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleWidget,
        if (modelWidget != null) modelWidget,
      ],
    );
  }


  Widget _buildTabletTitle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String? brandAsset = (modelDisplay != null
            ? BrandAssets.assetForName(modelDisplay!)
            : null) ??
        (providerName != null ? BrandAssets.assetForName(providerName!) : null);

    Widget? capsule;
    String? capsuleLabel;
    if (providerName != null && modelDisplay != null) {
      capsuleLabel = '$modelDisplay ($providerName)';
      final Widget brandIcon = AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: (brandAsset != null)
            ? (brandAsset.endsWith('.svg')
                ? SvgPicture.asset(brandAsset,
                    width: 16, height: 16, key: ValueKey('brand:$brandAsset'))
                : Image.asset(brandAsset,
                    width: 16, height: 16, key: ValueKey('brand:$brandAsset')))
            : Icon(Lucide.Boxes,
                size: 16,
                color: cs.onSurface.withOpacity(0.7),
                key: const ValueKey('brand:default')),
      );

      capsule = IosCardPress(
        borderRadius: BorderRadius.circular(20),
        baseColor: Colors.transparent,
        pressedBlendStrength: isDark ? 0.18 : 0.12,
        padding: EdgeInsets.zero,
        onTap: onShowModelSelect,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                brandIcon,
                const SizedBox(width: 6),
                Flexible(
                  child: AnimatedTextSwap(
                    text: capsuleLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      color: isDark
                          ? Colors.white.withOpacity(0.92)
                          : cs.onSurface.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final row = Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedTextSwap(
              text: title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (capsule != null) ...[
          const SizedBox(width: 8),
          Flexible(
            fit: FlexFit.loose,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0.06, 0), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey('cap:${capsuleLabel ?? ''}'),
                  child: capsule!,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
                    .animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(
            key: ValueKey('hdr:$title|${capsuleLabel ?? ''}'), child: row),
      ),
    );
  }

  List<Widget> _buildMobileActions() {
    final l10n = AppLocalizations.of(context)!;
    return [
      // Right sidebar toggle for desktop topics-on-right mode
      Builder(builder: (context) {
        final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux;
        final sp = context.watch<SettingsProvider>();
        final topicsOnRight = sp.desktopTopicPosition == DesktopTopicPosition.right;
        if (!isDesktop || !topicsOnRight || onToggleRightSidebar == null) {
          return const SizedBox.shrink();
        }
        return IosIconButton(
          size: 20,
          padding: const EdgeInsets.all(8),
          minSize: 40,
          icon: Lucide.panelRight,
          onTap: onToggleRightSidebar,
        );
      }),
      // Mini map button
      IosIconButton(
        key: miniMapAnchorKey,
        size: 20,
        minSize: 44,
        onTap: onMiniMapTap,
        semanticLabel: l10n.miniMapTooltip,
        icon: Lucide.Map,
      ),
      // New conversation button
      IosIconButton(
        size: 22,
        minSize: 44,
        onTap: onNewConversation,
        icon: Lucide.MessageCirclePlus,
      ),
      const SizedBox(width: 4),
    ];
  }

  List<Widget> _buildTabletActions() {
    final l10n = AppLocalizations.of(context)!;
    return [
      // Mini map button
      IconButton(
        key: miniMapAnchorKey,
        onPressed: onMiniMapTap,
        tooltip: l10n.miniMapTooltip,
        icon: const Icon(Lucide.Map, size: 22),
      ),
      // New conversation button
      IconButton(
        onPressed: onNewConversation,
        icon: const Icon(Lucide.MessageCirclePlus, size: 22),
      ),
      const SizedBox(width: 6),
    ];
  }
}
