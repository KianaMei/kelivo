// Desktop Display Settings Pane
// Extracted from desktop_settings_page.dart

import 'dart:ui';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:system_fonts/system_fonts.dart';
import '../../l10n/app_localizations.dart';
import '../../core/providers/settings_provider.dart';
import '../../theme/palettes.dart';
import '../../shared/widgets/ios_switch.dart';
import '../../icons/lucide_adapter.dart' as lucide;
import '../../utils/platform_utils.dart';
import '../../features/settings/pages/google_fonts_picker_page.dart';
import '../../features/settings/pages/google_fonts_dialog.dart';

class DisplaySettingsBody extends StatelessWidget {
  const DisplaySettingsBody({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                child: Text(
                  l10n.settingsPageDisplay,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.12)),
              const SizedBox(height: 8),
              _SettingsCard(
                title: l10n.settingsPageDisplay,
                children: [
                  _ColorModeRow(),
                  _RowDivider(),
                  _ThemeColorRow(),
                  _RowDivider(),
                  _ToggleRowPureBackground(),
                  _RowDivider(),
                  _ChatMessageBackgroundRow(),
                  _RowDivider(),
                  _ChatBubbleOpacityRow(),
                  _RowDivider(),
                  _TopicPositionRow(),
                  _RowDivider(),
                  _DesktopContentWidthRow(),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: l10n.desktopSettingsFontsTitle,
                children: [
                  _AppFontRow(),
                  _RowDivider(),
                  _CodeFontRow(),
                  _RowDivider(),
                  _AppLanguageRow(),
                  _RowDivider(),
                  _GlobalFontScaleRow(),
                  _RowDivider(),
                  _ChatFontSizeRow(),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: l10n.displaySettingsPageChatItemDisplayTitle,
                children: [
                  _ToggleRowShowUserAvatar(),
                  _RowDivider(),
                  _ToggleRowShowUserNameTs(),
                  _RowDivider(),
                  _ToggleRowShowUserMsgActions(),
                  _RowDivider(),
                  _ToggleRowShowModelIcon(),
                  _RowDivider(),
                  _ToggleRowShowModelNameTs(),
                  _RowDivider(),
                  _ToggleRowShowTokenStats(),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: l10n.displaySettingsPageRenderingSettingsTitle,
                children: [
                  _ToggleRowDollarLatex(),
                  _RowDivider(),
                  _ToggleRowMathRendering(),
                  _RowDivider(),
                  _ToggleRowUserMarkdown(),
                  _RowDivider(),
                  _ToggleRowReasoningMarkdown(),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: l10n.displaySettingsPageBehaviorStartupTitle,
                children: [
                  _ToggleRowAutoCollapseThinking(),
                  _RowDivider(),
                  _ToggleRowShowUpdates(),
                  _RowDivider(),
                  _ToggleRowMsgNavButtons(),
                  _RowDivider(),
                  _ToggleRowShowChatListDate(),
                  _RowDivider(),
                  _ToggleRowNewChatOnLaunch(),
                  _RowDivider(),
                  _ToggleRowCloseToTray(),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: l10n.displaySettingsPageOtherSettingsTitle,
                children: [
                  _AutoScrollDelayRow(),
                  _RowDivider(),
                  _DisableAutoScrollRow(),
                  _RowDivider(),
                  _BackgroundMaskRow(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          width: 0.5,
          color: isDark ? Colors.white.withOpacity(0.06) : cs.outlineVariant.withOpacity(0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: Text(
                title,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Divider(
        height: 1,
        thickness: 0.5,
        indent: 8,
        endIndent: 8,
        color: cs.outlineVariant.withOpacity(0.12),
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.trailing});
  final String label;
  final Widget trailing;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: cs.onSurface, decoration: TextDecoration.none),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: trailing,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Color Mode ---
class _ColorModeRow extends StatelessWidget {
  const _ColorModeRow();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _LabeledRow(
      label: l10n.settingsPageColorMode,
      trailing: const _ThemeModeSegmented(),
    );
  }
}

class _ThemeModeSegmented extends StatefulWidget {
  const _ThemeModeSegmented();
  @override
  State<_ThemeModeSegmented> createState() => _ThemeModeSegmentedState();
}

class _ThemeModeSegmentedState extends State<_ThemeModeSegmented> {
  int _hover = -1;
  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SettingsProvider>();
    final mode = sp.themeMode;
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final items = [
      (ThemeMode.light, l10n.settingsPageLightMode, lucide.Lucide.Sun),
      (ThemeMode.dark, l10n.settingsPageDarkMode, lucide.Lucide.Moon),
      (ThemeMode.system, l10n.settingsPageSystemMode, lucide.Lucide.Monitor),
    ];

    final trackBg = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04);
    return Container(
      decoration: BoxDecoration(color: trackBg, borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            MouseRegion(
              onEnter: (_) => setState(() => _hover = i),
              onExit: (_) => setState(() => _hover = -1),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => context.read<SettingsProvider>().setThemeMode(items[i].$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: () {
                      final selected = mode == items[i].$1;
                      if (selected) return cs.primary.withOpacity(isDark ? 0.18 : 0.14);
                      if (_hover == i) return isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.06);
                      return Colors.transparent;
                    }(),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        items[i].$3,
                        size: 16,
                        color: (mode == items[i].$1)
                            ? cs.primary
                            : cs.onSurface.withOpacity(0.74),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        items[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: (mode == items[i].$1)
                              ? cs.primary
                              : cs.onSurface.withOpacity(0.82),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (i != items.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _HoverPill extends StatelessWidget {
  const _HoverPill({
    required this.hovered,
    required this.selected,
    required this.onHover,
    required this.onTap,
    required this.label,
    required this.icon,
  });
  final bool hovered;
  final bool selected;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected
        ? cs.primary.withOpacity(0.12)
        : hovered
            ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04))
            : Colors.transparent;
    final fg = selected ? cs.primary : cs.onSurface.withOpacity(0.86);
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? cs.primary.withOpacity(0.35) : cs.outlineVariant.withOpacity(0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: fg, decoration: TextDecoration.none)),
              const SizedBox(width: 8),
              Icon(icon, size: 16, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopContentWidthRow extends StatelessWidget {
  const _DesktopContentWidthRow();
  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    final bool wide = sp.desktopWideContent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ToggleRow(
          label: l10n.desktopDisplayWideModeTitle,
          value: wide,
          onChanged: (v) => context.read<SettingsProvider>().setDesktopWideContent(v),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          child: wide
              ? const SizedBox.shrink()
              : _DesktopWidthSlider(
                  key: const ValueKey('narrow_width_slider'),
                  value: sp.desktopNarrowContentWidth,
                ),
        ),
      ],
    );
  }
}

class _DesktopWidthSlider extends StatefulWidget {
  const _DesktopWidthSlider({super.key, required this.value});
  final double value;

  @override
  State<_DesktopWidthSlider> createState() => _DesktopWidthSliderState();
}

class _DesktopWidthSliderState extends State<_DesktopWidthSlider> {
  static const double _min = 720;
  static const double _max = 1600;
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value.clamp(_min, _max);
  }

  @override
  void didUpdateWidget(covariant _DesktopWidthSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value.clamp(_min, _max);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.desktopDisplayNarrowWidthLabel(_value.toStringAsFixed(0)),
            style: TextStyle(fontSize: 13.5, color: cs.onSurface.withOpacity(0.75)),
          ),
          Slider(
            min: _min,
            max: _max,
            divisions: ((_max - _min) / 20).round(),
            label: _value.toStringAsFixed(0),
            value: _value,
            onChanged: (v) {
              setState(() => _value = v);
            },
            onChangeEnd: (v) {
              context.read<SettingsProvider>().setDesktopNarrowContentWidth(v);
            },
          ),
        ],
      ),
    );
  }
}
// --- Theme Color ---
class _ThemeColorRow extends StatelessWidget {
  const _ThemeColorRow();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _LabeledRow(
      label: l10n.displaySettingsPageThemeColorTitle,
      trailing: const _ThemeDots(),
    );
  }
}

class _ThemeDots extends StatelessWidget {
  const _ThemeDots();
  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SettingsProvider>();
    final selected = sp.themePaletteId;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final p in ThemePalettes.all)
          _ThemeDot(
            color: p.light.primary,
            selected: selected == p.id,
            onTap: () => context.read<SettingsProvider>().setThemePalette(p.id),
          ),
      ],
    );
  }
}

class _ThemeDot extends StatefulWidget {
  const _ThemeDot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  @override
  State<_ThemeDot> createState() => _ThemeDotState();
}

class _ThemeDotState extends State<_ThemeDot> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: _hover
                ? [BoxShadow(color: widget.color.withOpacity(0.45), blurRadius: 14, spreadRadius: 1)]
                : [],
            border: Border.all(
              color: widget.selected ? cs.onSurface.withOpacity(0.85) : Colors.white,
              width: widget.selected ? 2 : 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleRowPureBackground extends StatelessWidget {
  const _ToggleRowPureBackground();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.themeSettingsPageUsePureBackgroundTitle,
      value: sp.usePureBackground,
      onChanged: (v) => context.read<SettingsProvider>().setUsePureBackground(v),
    );
  }
}

class _ChatMessageBackgroundRow extends StatelessWidget {
  const _ChatMessageBackgroundRow();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _LabeledRow(
      label: l10n.displaySettingsPageChatMessageBackgroundTitle,
      trailing: const _BackgroundStyleDropdown(),
    );
  }
}

class _ChatBubbleOpacityRow extends StatelessWidget {
  const _ChatBubbleOpacityRow();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final v = context.watch<SettingsProvider>().chatMessageBubbleOpacity;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.displaySettingsPageChatBubbleOpacityTitle,
                  style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.9)),
                ),
              ),
              const SizedBox(width: 8),
              Text('${(v * 100).round()}%', style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7))),
            ],
          ),
          Slider(
            min: 0.0,
            max: 1.0,
            divisions: 20,
            label: '${(v * 100).round()}%',
            value: v.clamp(0.0, 1.0),
            onChanged: (nv) => context.read<SettingsProvider>().setChatMessageBubbleOpacity(nv),
          ),
        ],
      ),
    );
  }
}

class _BackgroundStyleDropdown extends StatefulWidget {
  const _BackgroundStyleDropdown();
  @override
  State<_BackgroundStyleDropdown> createState() => _BackgroundStyleDropdownState();
}

class _BackgroundStyleDropdownState extends State<_BackgroundStyleDropdown> {
  bool _hover = false;
  bool _open = false;
  final LayerLink _link = LayerLink();
  final GlobalKey _triggerKey = GlobalKey();
  OverlayEntry? _entry;

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openMenu();
    }
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  String _labelFor(BuildContext context, ChatMessageBackgroundStyle s) {
    final l10n = AppLocalizations.of(context)!;
    switch (s) {
      case ChatMessageBackgroundStyle.frosted:
        return l10n.displaySettingsPageChatMessageBackgroundFrosted;
      case ChatMessageBackgroundStyle.solid:
        return l10n.displaySettingsPageChatMessageBackgroundSolid;
      case ChatMessageBackgroundStyle.defaultStyle:
      default:
        return l10n.displaySettingsPageChatMessageBackgroundDefault;
    }
  }

  void _openMenu() {
    if (_entry != null) return;
    final rb = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null) return;
    final triggerSize = rb.size;
    final triggerWidth = triggerSize.width;

    _entry = OverlayEntry(builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final usePure = Provider.of<SettingsProvider>(ctx, listen: false).usePureBackground;
      final bgColor = usePure ? (isDark ? Colors.black : Colors.white) : (isDark ? const Color(0xFF1C1C1E) : Colors.white);
      final sp = Provider.of<SettingsProvider>(ctx, listen: false);

      return Stack(children: [
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
          offset: Offset(0, triggerSize.height + 6),
          child: _BackgroundStyleOverlay(
            width: triggerWidth,
            backgroundColor: bgColor,
            selected: sp.chatMessageBackgroundStyle,
            onSelected: (style) async {
              await sp.setChatMessageBackgroundStyle(style);
              _close();
            },
          ),
        ),
      ]);
    });
    Overlay.of(context)?.insert(_entry!);
    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sp = context.watch<SettingsProvider>();
    final label = _labelFor(context, sp.chatMessageBackgroundStyle);

    final baseBorder = cs.outlineVariant.withOpacity(0.18);
    final hoverBorder = cs.primary;
    final borderColor = _open || _hover ? hoverBorder : baseBorder;

    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            key: _triggerKey,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            constraints: const BoxConstraints(minWidth: 100, minHeight: 34),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141414) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: _open
                  ? [BoxShadow(color: cs.primary.withOpacity(0.10), blurRadius: 0, spreadRadius: 2)]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.88)),
                      ),
                    ),
                    const SizedBox(width: 24),
                  ],
                ),
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedRotation(
                      turns: _open ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Icon(lucide.Lucide.ChevronDown, size: 16, color: cs.onSurface.withOpacity(0.7)),
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
}

class _BackgroundStyleOverlay extends StatefulWidget {
  const _BackgroundStyleOverlay({
    required this.width,
    required this.backgroundColor,
    required this.selected,
    required this.onSelected,
  });
  final double width;
  final Color backgroundColor;
  final ChatMessageBackgroundStyle selected;
  final ValueChanged<ChatMessageBackgroundStyle> onSelected;
  @override
  State<_BackgroundStyleOverlay> createState() => _BackgroundStyleOverlayState();
}

class _BackgroundStyleOverlayState extends State<_BackgroundStyleOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, -0.06), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.forward());
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = cs.outlineVariant.withOpacity(0.12);

    final items = <(ChatMessageBackgroundStyle, String)>[
      (ChatMessageBackgroundStyle.defaultStyle, AppLocalizations.of(context)!.displaySettingsPageChatMessageBackgroundDefault),
      (ChatMessageBackgroundStyle.frosted, AppLocalizations.of(context)!.displaySettingsPageChatMessageBackgroundFrosted),
      (ChatMessageBackgroundStyle.solid, AppLocalizations.of(context)!.displaySettingsPageChatMessageBackgroundSolid),
    ];

    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(minWidth: widget.width, maxWidth: widget.width),
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 0.5),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.32 : 0.08), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final it in items)
                  _SimpleOptionTile(
                    label: it.$2,
                    selected: widget.selected == it.$1,
                    onTap: () => widget.onSelected(it.$1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SimpleOptionTile extends StatefulWidget {
  const _SimpleOptionTile({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  State<_SimpleOptionTile> createState() => _SimpleOptionTileState();
}

class _SimpleOptionTileState extends State<_SimpleOptionTile> {
  bool _hover = false;
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = widget.selected
        ? cs.primary.withOpacity(0.12)
        : (_hover ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04)) : Colors.transparent);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _active = true),
        onTapCancel: () => setState(() => _active = false),
        onTapUp: (_) => setState(() => _active = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _active ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.88), fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
                const SizedBox(width: 8),
                Opacity(
                  opacity: widget.selected ? 1 : 0,
                  child: Icon(lucide.Lucide.Check, size: 14, color: cs.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Fonts: language + chat font size ---
class _AppLanguageRow extends StatefulWidget {
  const _AppLanguageRow();
  @override
  State<_AppLanguageRow> createState() => _AppLanguageRowState();
}

class _AppLanguageRowState extends State<_AppLanguageRow> {
  bool _hover = false;
  bool _open = false;
  final GlobalKey _key = GlobalKey();
  OverlayEntry? _entry;
  final LayerLink _link = LayerLink();

  void _openDropdownOverlay() {
    if (_entry != null) return;
    final rb = _key.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox = Overlay.of(context)?.context.findRenderObject() as RenderBox?;
    if (rb == null || overlayBox == null) return;
    final size = rb.size;
    final triggerW = size.width;
    final maxW = 280.0;
    final minW = triggerW;
    _entry = OverlayEntry(builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      // measure desired content width for centering under trigger
      double measureContentWidth() {
        final style = const TextStyle(fontSize: 16);
        final labels = <String>[
          AppLocalizations.of(ctx)!.settingsPageSystemMode,
          AppLocalizations.of(ctx)!.displaySettingsPageLanguageChineseLabel,
          AppLocalizations.of(ctx)!.languageDisplayTraditionalChinese,
          AppLocalizations.of(ctx)!.displaySettingsPageLanguageEnglishLabel,
        ];
        double maxText = 0;
        for (final s in labels) {
          final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
          if (tp.width > maxText) maxText = tp.width;
        }
        // item padding (12*2) + check icon (16) + gap (10) + list padding (8*2)
        return maxText + 12 * 2 + 16 + 10 + 8 * 2;
      }
      final contentW = measureContentWidth();
      final width = contentW.clamp(minW, maxW);
      final dx = (triggerW - width) / 2;
      return Stack(children: [
        // tap outside to close
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _closeDropdownOverlay,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: Offset(dx, size.height + 6),
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: width, maxWidth: width),
              child: _LanguageDropdown(onClose: _closeDropdownOverlay),
            ),
          ),
        ),
      ]);
    });
    Overlay.of(context)?.insert(_entry!);
    setState(() => _open = true);
  }

  void _closeDropdownOverlay() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    String labelFor(Locale l) {
      if (l.languageCode == 'zh') {
        if ((l.scriptCode ?? '').toLowerCase() == 'hant') return l10n.languageDisplayTraditionalChinese;
        return l10n.displaySettingsPageLanguageChineseLabel;
      }
      return l10n.displaySettingsPageLanguageEnglishLabel;
    }
    final current = sp.isFollowingSystemLocale ? l10n.settingsPageSystemMode : labelFor(sp.appLocale);
    return _LabeledRow(
      label: l10n.displaySettingsPageLanguageTitle,
      trailing: CompositedTransformTarget(
        link: _link,
        child: _HoverDropdownButton(
          key: _key,
          hovered: _hover,
          open: _open,
          label: current,
          onHover: (v) => setState(() => _hover = v),
          onTap: () {
            if (_open) {
              _closeDropdownOverlay();
            } else {
              _openDropdownOverlay();
            }
          },
        ),
      ),
    );
  }
}

class _HoverDropdownButton extends StatelessWidget {
  const _HoverDropdownButton({super.key, required this.hovered, required this.open, required this.label, required this.onHover, required this.onTap});
  final bool hovered;
  final bool open;
  final String label;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = hovered || open ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)) : Colors.transparent;
    final angle = open ? 3.1415926 : 0.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.2), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 16, color: cs.onSurface.withOpacity(0.9), fontWeight: FontWeight.w400)),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: angle / (2 * 3.1415926),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Icon(lucide.Lucide.ChevronDown, size: 16, color: cs.onSurface.withOpacity(0.8)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageDropdown extends StatefulWidget {
  const _LanguageDropdown({required this.onClose});
  final VoidCallback onClose;
  @override
  State<_LanguageDropdown> createState() => _LanguageDropdownState();
}

class _LanguageDropdownState extends State<_LanguageDropdown> {
  double _opacity = 0;
  Offset _slide = const Offset(0, -0.02);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() { _opacity = 1; _slide = Offset.zero; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    final items = <(_LangItem, bool)>[
      (_LangItem(flag: 'SYS', label: l10n.settingsPageSystemMode, tag: 'system'), sp.isFollowingSystemLocale),
      (_LangItem(flag: 'CN', label: l10n.displaySettingsPageLanguageChineseLabel, tag: 'zh_CN'), (!sp.isFollowingSystemLocale && sp.appLocale.languageCode == 'zh' && (sp.appLocale.scriptCode ?? '').isEmpty)),
      (_LangItem(flag: 'TW', label: l10n.languageDisplayTraditionalChinese, tag: 'zh_Hant'), (!sp.isFollowingSystemLocale && sp.appLocale.languageCode == 'zh' && (sp.appLocale.scriptCode ?? '').toLowerCase() == 'hant')) ,
      (_LangItem(flag: 'EN', label: l10n.displaySettingsPageLanguageEnglishLabel, tag: 'en_US'), (!sp.isFollowingSystemLocale && sp.appLocale.languageCode == 'en')),
    ];
    final maxH = MediaQuery.of(context).size.height * 0.5;
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _slide,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.12), width: 0.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 6)),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final ent in items)
                      _LanguageDropdownItem(
                        item: ent.$1,
                        checked: ent.$2,
                        onTap: () async {
                          switch (ent.$1.tag) {
                            case 'system':
                              await context.read<SettingsProvider>().setAppLocaleFollowSystem();
                              break;
                            case 'zh_CN':
                              await context.read<SettingsProvider>().setAppLocale(const Locale('zh', 'CN'));
                              break;
                            case 'zh_Hant':
                              await context.read<SettingsProvider>().setAppLocale(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'));
                              break;
                            case 'en_US':
                            default:
                              await context.read<SettingsProvider>().setAppLocale(const Locale('en', 'US'));
                          }
                          if (!mounted) return;
                          widget.onClose();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LangItem {
  final String flag;
  final String label;
  final String tag; // 'system' | 'zh_CN' | 'zh_Hant' | 'en_US'
  const _LangItem({required this.flag, required this.label, required this.tag});
}

class _LanguageDropdownItem extends StatefulWidget {
  const _LanguageDropdownItem({required this.item, this.checked = false, required this.onTap});
  final _LangItem item;
  final bool checked;
  final VoidCallback onTap;
  @override
  State<_LanguageDropdownItem> createState() => _LanguageDropdownItemState();
}

class _LanguageDropdownItemState extends State<_LanguageDropdownItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hover ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text(widget.item.flag, style: const TextStyle(fontSize: 16, decoration: TextDecoration.none)),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.item.label, style: TextStyle(fontSize: 14, color: cs.onSurface, decoration: TextDecoration.none))),
              if (widget.checked) ...[
                const SizedBox(width: 10),
                Icon(lucide.Lucide.Check, size: 16, color: cs.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// --- Global Font Scale Row (Desktop only) ---
class _GlobalFontScaleRow extends StatefulWidget {
  const _GlobalFontScaleRow();
  @override
  State<_GlobalFontScaleRow> createState() => _GlobalFontScaleRowState();
}

class _GlobalFontScaleRowState extends State<_GlobalFontScaleRow> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    final sp = context.read<SettingsProvider>();
    _controller = TextEditingController(text: '${(sp.desktopGlobalFontScale * 100).round()}');
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(String text) {
    final val = double.tryParse(text.trim());
    if (val == null) {
      final sp = context.read<SettingsProvider>();
      _controller.text = '${(sp.desktopGlobalFontScale * 100).round()}';
      return;
    }
    final clamped = (val / 100.0).clamp(0.85, 1.3);
    context.read<SettingsProvider>().setDesktopGlobalFontScale(clamped);
    _controller.text = '${(clamped * 100).round()}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return _LabeledRow(
      label: l10n.desktopSettingsGlobalFontScaleTitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 36, maxWidth: 72),
              child: _BorderInput(
                controller: _controller,
                onSubmitted: _commit,
                onFocusLost: _commit,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('%', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 14, decoration: TextDecoration.none)),
        ],
      ),
    );
  }
}

class _ChatFontSizeRow extends StatefulWidget {
  const _ChatFontSizeRow();
  @override
  State<_ChatFontSizeRow> createState() => _ChatFontSizeRowState();
}

class _ChatFontSizeRowState extends State<_ChatFontSizeRow> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    final scale = context.read<SettingsProvider>().chatFontScale;
    _controller = TextEditingController(text: '${(scale * 100).round()}');
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(String text) {
    final v = text.trim();
    final n = double.tryParse(v);
    if (n == null) return;
    final clamped = (n / 100.0).clamp(0.8, 1.5);
    context.read<SettingsProvider>().setChatFontScale(clamped);
    _controller.text = '${(clamped * 100).round()}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return _LabeledRow(
      label: l10n.displaySettingsPageChatFontSizeTitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 36, maxWidth: 72),
              child: _BorderInput(
                controller: _controller,
                onSubmitted: _commit,
                onFocusLost: _commit,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('%', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 14, decoration: TextDecoration.none)),
        ],
      ),
    );
  }
}

// --- App Font Row ---
class _AppFontRow extends StatelessWidget {
  const _AppFontRow();
  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SettingsProvider>();
    final current = sp.appFontFamily;
    final displayText = (current == null || current.isEmpty)
        ? AppLocalizations.of(context)!.desktopFontFamilySystemDefault
        : current;
    return _LabeledRow(
      label: AppLocalizations.of(context)!.displaySettingsPageAppFontTitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DesktopFontDropdownButton(
            display: displayText,
            onTap: () async {
              final fam = await _showDesktopFontChooserDialog(
                context,
                title: AppLocalizations.of(context)!.displaySettingsPageAppFontTitle,
                initial: sp.appFontFamily,
              );
              if (fam == null) return;
              if (fam == '__SYSTEM__') {
                await context.read<SettingsProvider>().clearAppFont();
              } else {
                await context.read<SettingsProvider>().setAppFontFamily(fam, isGoogle: false);
              }
            },
          ),
          const SizedBox(width: 8),
          _IconBtn(
            icon: lucide.Lucide.RotateCw,
            onTap: () async {
              await context.read<SettingsProvider>().clearAppFont();
            },
          ),
        ],
      ),
    );
  }
}

// --- Code Font Row ---
class _CodeFontRow extends StatelessWidget {
  const _CodeFontRow();
  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SettingsProvider>();
    final current = sp.codeFontFamily;
    final displayText = (current == null || current.isEmpty)
        ? AppLocalizations.of(context)!.desktopFontFamilySystemDefault
        : current;
    return _LabeledRow(
      label: AppLocalizations.of(context)!.displaySettingsPageCodeFontTitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DesktopFontDropdownButton(
            display: displayText,
            onTap: () async {
              final fam = await _showDesktopFontChooserDialog(
                context,
                title: AppLocalizations.of(context)!.displaySettingsPageCodeFontTitle,
                initial: sp.codeFontFamily,
              );
              if (fam == null) return;
              if (fam == '__MONO__') {
                await context.read<SettingsProvider>().clearCodeFont();
              } else {
                await context.read<SettingsProvider>().setCodeFontFamily(fam, isGoogle: false);
              }
            },
          ),
          const SizedBox(width: 8),
          _IconBtn(
            icon: lucide.Lucide.RotateCw,
            onTap: () async {
              await context.read<SettingsProvider>().clearCodeFont();
            },
          ),
        ],
      ),
    );
  }
}

// --- Desktop Font Dropdown Button ---
class _DesktopFontDropdownButton extends StatefulWidget {
  const _DesktopFontDropdownButton({required this.display, required this.onTap});
  final String display;
  final VoidCallback onTap;
  @override
  State<_DesktopFontDropdownButton> createState() => _DesktopFontDropdownButtonState();
}

class _DesktopFontDropdownButtonState extends State<_DesktopFontDropdownButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05)) : Colors.transparent;
  return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.28), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  widget.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.onSurface, decoration: TextDecoration.none),
                ),
              ),
              const SizedBox(width: 8),
              Icon(lucide.Lucide.ChevronDown, size: 16, color: cs.onSurface.withOpacity(0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BorderInput extends StatefulWidget {
  const _BorderInput({required this.controller, required this.onSubmitted, required this.onFocusLost});
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onFocusLost;
  @override
  State<_BorderInput> createState() => _BorderInputState();
}

class _BorderInputState extends State<_BorderInput> {
  late FocusNode _focus;
  bool _hover = false;
  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(() {
      // Rebuild border color on focus change
      if (mounted) setState(() {});
      if (!_focus.hasFocus) widget.onFocusLost(widget.controller.text);
    });
  }
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // hover to change border color (not background)
    final active = _focus.hasFocus || _hover;
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.28), width: 0.8),
    );
    final hoverBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.38), width: 0.9),
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.primary, width: 1.0),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: isDark ? Colors.white10 : Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          border: baseBorder,
          enabledBorder: _focus.hasFocus ? focusBorder : (_hover ? hoverBorder : baseBorder),
          focusedBorder: focusBorder,
          hoverColor: Colors.transparent,
        ),
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

// --- Toggles Groups ---
class _ToggleRowShowUserAvatar extends StatelessWidget {
  const _ToggleRowShowUserAvatar();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageShowUserAvatarTitle,
      value: sp.showUserAvatar,
      onChanged: (v) => context.read<SettingsProvider>().setShowUserAvatar(v),
    );
  }
}

class _ToggleRowShowUserNameTs extends StatelessWidget {
  const _ToggleRowShowUserNameTs();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageShowUserNameTimestampTitle,
      value: sp.showUserNameTimestamp,
      onChanged: (v) => context.read<SettingsProvider>().setShowUserNameTimestamp(v),
    );
  }
}

class _ToggleRowShowUserMsgActions extends StatelessWidget {
  const _ToggleRowShowUserMsgActions();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageShowUserMessageActionsTitle,
      value: sp.showUserMessageActions,
      onChanged: (v) => context.read<SettingsProvider>().setShowUserMessageActions(v),
    );
  }
}

class _ToggleRowShowModelIcon extends StatelessWidget {
  const _ToggleRowShowModelIcon();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageChatModelIconTitle,
      value: sp.showModelIcon,
      onChanged: (v) => context.read<SettingsProvider>().setShowModelIcon(v),
    );
  }
}

class _ToggleRowShowModelNameTs extends StatelessWidget {
  const _ToggleRowShowModelNameTs();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageShowModelNameTimestampTitle,
      value: sp.showModelNameTimestamp,
      onChanged: (v) => context.read<SettingsProvider>().setShowModelNameTimestamp(v),
    );
  }
}

class _ToggleRowShowTokenStats extends StatelessWidget {
  const _ToggleRowShowTokenStats();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageShowTokenStatsTitle,
      value: sp.showTokenStats,
      onChanged: (v) => context.read<SettingsProvider>().setShowTokenStats(v),
    );
  }
}

class _ToggleRowDollarLatex extends StatelessWidget {
  const _ToggleRowDollarLatex();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageEnableDollarLatexTitle,
      value: sp.enableDollarLatex,
      onChanged: (v) => context.read<SettingsProvider>().setEnableDollarLatex(v),
    );
  }
}

class _ToggleRowMathRendering extends StatelessWidget {
  const _ToggleRowMathRendering();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageEnableMathTitle,
      value: sp.enableMathRendering,
      onChanged: (v) => context.read<SettingsProvider>().setEnableMathRendering(v),
    );
  }
}

class _ToggleRowUserMarkdown extends StatelessWidget {
  const _ToggleRowUserMarkdown();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageEnableUserMarkdownTitle,
      value: sp.enableUserMarkdown,
      onChanged: (v) => context.read<SettingsProvider>().setEnableUserMarkdown(v),
    );
  }
}

class _ToggleRowReasoningMarkdown extends StatelessWidget {
  const _ToggleRowReasoningMarkdown();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageEnableReasoningMarkdownTitle,
      value: sp.enableReasoningMarkdown,
      onChanged: (v) => context.read<SettingsProvider>().setEnableReasoningMarkdown(v),
    );
  }
}

class _ToggleRowAutoCollapseThinking extends StatelessWidget {
  const _ToggleRowAutoCollapseThinking();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageAutoCollapseThinkingTitle,
      value: sp.autoCollapseThinking,
      onChanged: (v) => context.read<SettingsProvider>().setAutoCollapseThinking(v),
    );
  }
}

class _ToggleRowShowUpdates extends StatelessWidget {
  const _ToggleRowShowUpdates();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageShowUpdatesTitle,
      value: sp.showAppUpdates,
      onChanged: (v) => context.read<SettingsProvider>().setShowAppUpdates(v),
    );
  }
}

class _ToggleRowMsgNavButtons extends StatelessWidget {
  const _ToggleRowMsgNavButtons();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageMessageNavButtonsTitle,
      value: sp.showMessageNavButtons,
      onChanged: (v) => context.read<SettingsProvider>().setShowMessageNavButtons(v),
    );
  }
}

class _ToggleRowShowChatListDate extends StatelessWidget {
  const _ToggleRowShowChatListDate();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageShowChatListDateTitle,
      value: sp.showChatListDate,
      onChanged: (v) => context.read<SettingsProvider>().setShowChatListDate(v),
    );
  }
}

class _ToggleRowNewChatOnLaunch extends StatelessWidget {
  const _ToggleRowNewChatOnLaunch();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageNewChatOnLaunchTitle,
      value: sp.newChatOnLaunch,
      onChanged: (v) => context.read<SettingsProvider>().setNewChatOnLaunch(v),
    );
  }
}

class _ToggleRowCloseToTray extends StatelessWidget {
  const _ToggleRowCloseToTray();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    // Only show on desktop platforms
    if (!PlatformUtils.isDesktop) {
      return const SizedBox.shrink();
    }
    return _ToggleRow(
      label: l10n.desktopCloseToTrayTitle,
      value: sp.desktopCloseToTray,
      onChanged: (v) => context.read<SettingsProvider>().setDesktopCloseToTray(v),
    );
  }
}

class _ToggleRowHapticsGlobal extends StatelessWidget {
  const _ToggleRowHapticsGlobal();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageHapticsGlobalTitle,
      value: sp.hapticsGlobalEnabled,
      onChanged: (v) => context.read<SettingsProvider>().setHapticsGlobalEnabled(v),
    );
  }
}

class _ToggleRowHapticsSwitch extends StatelessWidget {
  const _ToggleRowHapticsSwitch();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageHapticsIosSwitchTitle,
      value: sp.hapticsIosSwitch,
      onChanged: (v) => context.read<SettingsProvider>().setHapticsIosSwitch(v),
    );
  }
}

class _ToggleRowHapticsSidebar extends StatelessWidget {
  const _ToggleRowHapticsSidebar();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageHapticsOnSidebarTitle,
      value: sp.hapticsOnDrawer,
      onChanged: (v) => context.read<SettingsProvider>().setHapticsOnDrawer(v),
    );
  }
}

class _ToggleRowHapticsListItem extends StatelessWidget {
  const _ToggleRowHapticsListItem();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageHapticsOnListItemTapTitle,
      value: sp.hapticsOnListItemTap,
      onChanged: (v) => context.read<SettingsProvider>().setHapticsOnListItemTap(v),
    );
  }
}

class _ToggleRowHapticsCardTap extends StatelessWidget {
  const _ToggleRowHapticsCardTap();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageHapticsOnCardTapTitle,
      value: sp.hapticsOnCardTap,
      onChanged: (v) => context.read<SettingsProvider>().setHapticsOnCardTap(v),
    );
  }
}

class _ToggleRowHapticsGenerate extends StatelessWidget {
  const _ToggleRowHapticsGenerate();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return _ToggleRow(
      label: l10n.displaySettingsPageHapticsOnGenerateTitle,
      value: sp.hapticsOnGenerate,
      onChanged: (v) => context.read<SettingsProvider>().setHapticsOnGenerate(v),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: cs.onSurface.withOpacity(0.96), decoration: TextDecoration.none),
            ),
          ),
          IosSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// --- Others: inputs ---
class _AutoScrollDelayRow extends StatefulWidget {
  const _AutoScrollDelayRow();
  @override
  State<_AutoScrollDelayRow> createState() => _AutoScrollDelayRowState();
}

class _AutoScrollDelayRowState extends State<_AutoScrollDelayRow> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    final seconds = context.read<SettingsProvider>().autoScrollIdleSeconds;
    _controller = TextEditingController(text: '${seconds.round()}');
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _commit(String text) {
    final v = text.trim();
    final n = int.tryParse(v);
    if (n == null) return;
    final clamped = n.clamp(2, 64);
    context.read<SettingsProvider>().setAutoScrollIdleSeconds(clamped);
    _controller.text = '$clamped';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _LabeledRow(
      label: l10n.displaySettingsPageAutoScrollIdleTitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 36, maxWidth: 72),
              child: _BorderInput(controller: _controller, onSubmitted: _commit, onFocusLost: _commit),
            ),
          ),
          const SizedBox(width: 8),
          Text('s', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 14, decoration: TextDecoration.none)),
        ],
      ),
    );
  }
}

class _DisableAutoScrollRow extends StatelessWidget {
  const _DisableAutoScrollRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final disableAutoScroll = context.watch<SettingsProvider>().disableAutoScroll;
    return _LabeledRow(
      label: l10n.displaySettingsPageDisableAutoScrollTitle,
      trailing: Switch(
        value: disableAutoScroll,
        onChanged: (v) => context.read<SettingsProvider>().setDisableAutoScroll(v),
      ),
    );
  }
}

class _BackgroundMaskRow extends StatefulWidget {
  const _BackgroundMaskRow();
  @override
  State<_BackgroundMaskRow> createState() => _BackgroundMaskRowState();
}

class _BackgroundMaskRowState extends State<_BackgroundMaskRow> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    final v = context.read<SettingsProvider>().chatBackgroundMaskStrength;
    _controller = TextEditingController(text: '${(v * 100).round()}');
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _commit(String text) {
    final v = text.trim();
    final n = double.tryParse(v);
    if (n == null) return;
    final clamped = (n / 100.0).clamp(0.0, 1.0);
    context.read<SettingsProvider>().setChatBackgroundMaskStrength(clamped);
    _controller.text = '${(clamped * 100).round()}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _LabeledRow(
      label: l10n.displaySettingsPageChatBackgroundMaskTitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 36, maxWidth: 72),
              child: _BorderInput(controller: _controller, onSubmitted: _commit, onFocusLost: _commit),
            ),
          ),
          const SizedBox(width: 8),
          Text('%', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 14, decoration: TextDecoration.none)),
        ],
      ),
    );
  }
}


class _TopicPositionRow extends StatelessWidget {
  const _TopicPositionRow();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _LabeledRow(
      label: l10n.desktopDisplaySettingsTopicPositionTitle,
      trailing: const _TopicPositionDropdown(),
    );
  }
}

class _TopicPositionDropdown extends StatefulWidget {
  const _TopicPositionDropdown();
  @override
  State<_TopicPositionDropdown> createState() => _TopicPositionDropdownState();
}

class _TopicPositionDropdownState extends State<_TopicPositionDropdown> {
  bool _hover = false;
  bool _open = false;
  final LayerLink _link = LayerLink();
  final GlobalKey _triggerKey = GlobalKey();
  OverlayEntry? _entry;

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openMenu();
    }
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  String _labelFor(BuildContext context, DesktopTopicPosition pos) {
    final l10n = AppLocalizations.of(context)!;
    switch (pos) {
      case DesktopTopicPosition.right:
        return l10n.desktopDisplaySettingsTopicPositionRight;
      case DesktopTopicPosition.left:
      default:
        return l10n.desktopDisplaySettingsTopicPositionLeft;
    }
  }

  void _openMenu() {
    if (_entry != null) return;
    final rb = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null) return;
    final triggerSize = rb.size;
    final triggerWidth = triggerSize.width;

    _entry = OverlayEntry(builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final usePure = Provider.of<SettingsProvider>(ctx, listen: false).usePureBackground;
      final bgColor = usePure ? (isDark ? Colors.black : Colors.white) : (isDark ? const Color(0xFF1C1C1E) : Colors.white);
      final sp = Provider.of<SettingsProvider>(ctx, listen: false);

      return Stack(children: [
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
          offset: Offset(0, triggerSize.height + 6),
          child: _TopicPositionOverlay(
            width: triggerWidth,
            backgroundColor: bgColor,
            selected: sp.desktopTopicPosition,
            onSelected: (pos) async {
              await sp.setDesktopTopicPosition(pos);
              _close();
            },
          ),
        ),
      ]);
    });
    Overlay.of(context)?.insert(_entry!);
    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sp = context.watch<SettingsProvider>();
    final label = _labelFor(context, sp.desktopTopicPosition);

    final baseBorder = cs.outlineVariant.withOpacity(0.18);
    final hoverBorder = cs.primary;
    final borderColor = _open || _hover ? hoverBorder : baseBorder;

    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            key: _triggerKey,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            constraints: const BoxConstraints(minWidth: 100, minHeight: 34),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141414) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: _open
                  ? [BoxShadow(color: cs.primary.withOpacity(0.10), blurRadius: 0, spreadRadius: 2)]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.88)),
                      ),
                    ),
                    const SizedBox(width: 24),
                  ],
                ),
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedRotation(
                      turns: _open ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Icon(lucide.Lucide.ChevronDown, size: 16, color: cs.onSurface.withOpacity(0.7)),
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
}

class _TopicPositionOverlay extends StatefulWidget {
  const _TopicPositionOverlay({
    required this.width,
    required this.backgroundColor,
    required this.selected,
    required this.onSelected,
  });
  final double width;
  final Color backgroundColor;
  final DesktopTopicPosition selected;
  final ValueChanged<DesktopTopicPosition> onSelected;
  @override
  State<_TopicPositionOverlay> createState() => _TopicPositionOverlayState();
}

class _TopicPositionOverlayState extends State<_TopicPositionOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, -0.06), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.forward());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = cs.outlineVariant.withOpacity(0.12);

    // Align style with chat message background dropdown: no leading icons,
    // selected item gets a highlighted background.
    final items = <(DesktopTopicPosition, String)>[
      (DesktopTopicPosition.left, AppLocalizations.of(context)!.desktopDisplaySettingsTopicPositionLeft),
      (DesktopTopicPosition.right, AppLocalizations.of(context)!.desktopDisplaySettingsTopicPositionRight),
    ];

    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(minWidth: widget.width, maxWidth: widget.width),
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 0.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(isDark ? 0.32 : 0.08), blurRadius: 16, offset: const Offset(0, 6)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final it in items)
                  _SimpleOptionTile(
                    label: it.$2,
                    selected: widget.selected == it.$1,
                    onTap: () => widget.onSelected(it.$1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}




// ========== Font Chooser (moved from main) ==========

// ===== Font Chooser Dialog (from kelivo-remote with Timer-based loading) =====

/// Show desktop font chooser dialog with system fonts list
Future<String?> _showDesktopFontChooserDialog(
  BuildContext context, {
  required String title,
  String? initial,
}) async {
  final cs = Theme.of(context).colorScheme;
  final ctrl = TextEditingController();
  String? result;

  Future<List<String>> _fetchSystemFonts() async {
    try {
      final sf = SystemFonts();
      // First try a cheap list of names (fast on Windows)
      final alt = await sf.getFontList();
      final out = List<String>.from(alt ?? const <String>[]);
      if (out.isEmpty) {
        // Fallback to full load for preview, but cap the time
        final loaded = await sf.loadAllFonts().timeout(const Duration(seconds: 2));
        final list = List<String>.from(loaded);
        if (list.isNotEmpty) {
          list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return list;
        }
      } else {
        out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return out;
      }
    } catch (_) {/* ignore and fallback */}
    return <String>[
      'System UI', 'Segoe UI', 'SF Pro Text', 'San Francisco', 'Helvetica Neue', 'Arial', 'Roboto', 'PingFang SC', 'Microsoft YaHei', 'SimHei', 'Noto Sans SC', 'Noto Serif', 'Courier New', 'JetBrains Mono', 'Fira Code', 'monospace'
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  // Show loading dialog only if fetch takes time, and ensure it closes
  bool loadingShown = false;
  Timer? loadingTimer;
  loadingTimer = Timer(const Duration(milliseconds: 200), () {
    loadingShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
        final cs2 = Theme.of(ctx).colorScheme;
        return Dialog(
          elevation: 0,
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const CupertinoActivityIndicator(radius: 12),
                const SizedBox(height: 12),
                Text(
                  'Loading fonts...',
                  style: TextStyle(color: cs2.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  });
  final fonts = await _fetchSystemFonts();
  if (loadingTimer?.isActive ?? false) loadingTimer?.cancel();
  if (loadingShown) {
    try { Navigator.of(context, rootNavigator: true).pop(); } catch (_) {}
  }
  await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: StatefulBuilder(builder: (context, setState) {
              String q = ctrl.text.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? fonts
                  : fonts.where((f) => f.toLowerCase().contains(q)).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                    _IconBtn(icon: lucide.Lucide.X, onTap: () => Navigator.of(ctx).maybePop()),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      hintText: 'Search fonts...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.12), width: 0.6),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.12), width: 0.6),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.35), width: 0.8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final fam = filtered[i];
                          final selected = fam == initial;
                          return _FontRowItem(
                            family: fam,
                            selected: selected,
                            onTap: () => Navigator.of(ctx).pop(fam),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      );
    },
  ).then((v) => result = v);
  return result;
}

class _FontRowItem extends StatefulWidget {
  const _FontRowItem({required this.family, required this.onTap, this.selected = false});
  final String family;
  final VoidCallback onTap;
  final bool selected;
  @override
  State<_FontRowItem> createState() => _FontRowItemState();
}

class _FontRowItemState extends State<_FontRowItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)) : Colors.transparent;
    final sample = 'AaBbCc';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.family,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: cs.onSurface, decoration: TextDecoration.none),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(sample, style: TextStyle(fontFamily: widget.family, fontSize: 16, color: cs.onSurface, decoration: TextDecoration.none)),
                  ],
                ),
              ),
              if (widget.selected) ...[
                const SizedBox(width: 10),
                Icon(lucide.Lucide.Check, size: 16, color: cs.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatefulWidget {
  const _IconBtn({super.key, required this.icon, required this.onTap, this.onLongPress, this.color});
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
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
    final bg = _hover ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05)) : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
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