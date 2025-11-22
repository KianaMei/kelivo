import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';

import '../icons/lucide_adapter.dart' as lucide;
import '../l10n/app_localizations.dart';
import '../theme/palettes.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/assistant_provider.dart';
import '../shared/widgets/ios_switch.dart';
import '../features/assistant/pages/assistant_settings_page.dart';
import '../features/provider/pages/providers_page.dart';
import 'desktop_provider_detail_page.dart';
import 'setting/desktop_default_model_pane.dart';
import '../features/search/pages/search_services_page.dart';
import 'setting/desktop_mcp_pane.dart';
import '../features/quick_phrase/pages/quick_phrases_page.dart';
import '../features/settings/pages/tts_services_page.dart';
import '../features/backup/pages/backup_page.dart';
import 'desktop_backup_pane.dart';
import '../features/settings/pages/about_page.dart';
import '../features/settings/pages/google_fonts_picker_page.dart';
import '../features/settings/pages/google_fonts_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:characters/characters.dart';
import 'dart:io' show File, Platform;
import '../core/models/assistant.dart';
import '../utils/avatar_cache.dart';
import '../utils/sandbox_path_resolver.dart';
import '../utils/platform_utils.dart';
import '../shared/widgets/snackbar.dart';
import '../features/assistant/pages/assistant_settings_edit_page.dart' show showAssistantDesktopDialog;
import '_sidebar_resize_handle.dart';

/// Desktop settings layout: left menu + vertical divider + right content.
/// All settings pages are now implemented.
class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage({super.key});

  @override
  State<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

enum _SettingsMenuItem {
  display,
  assistant,
  providers,
  defaultModel,
  search,
  mcp,
  quickPhrases,
  tts,
  backup,
  about,
}

class _DesktopSettingsPageState extends State<DesktopSettingsPage> {
  _SettingsMenuItem _selected = _SettingsMenuItem.display;
  double _menuWidth = 256;
  static const double _menuMinWidth = 200;
  static const double _menuMaxWidth = 480;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final sp = context.read<SettingsProvider>();
        setState(() {
          _menuWidth = sp.desktopSettingsSidebarWidth.clamp(_menuMinWidth, _menuMaxWidth);
        });
      } catch (_) {}
    });
  }

  Widget _buildBody(_SettingsMenuItem item) {
    switch (item) {
      case _SettingsMenuItem.display:
        return const _DisplaySettingsBody(key: ValueKey('display'));
      case _SettingsMenuItem.assistant:
        return const _DesktopAssistantsBody(key: ValueKey('assistant'));
      case _SettingsMenuItem.providers:
        return const _ProvidersSettingsBody(key: ValueKey('providers'));
      case _SettingsMenuItem.defaultModel:
        return const _DefaultModelSettingsBody(key: ValueKey('defaultModel'));
      case _SettingsMenuItem.search:
        return const _SearchSettingsBody(key: ValueKey('search'));
      case _SettingsMenuItem.mcp:
        return const _McpSettingsBody(key: ValueKey('mcp'));
      case _SettingsMenuItem.quickPhrases:
        return const _QuickPhrasesSettingsBody(key: ValueKey('quickPhrases'));
      case _SettingsMenuItem.tts:
        return const _TtsSettingsBody(key: ValueKey('tts'));
      case _SettingsMenuItem.backup:
        return const _BackupSettingsBody(key: ValueKey('backup'));
      case _SettingsMenuItem.about:
        return const _AboutSettingsBody(key: ValueKey('about'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    String titleFor(_SettingsMenuItem it) {
      switch (it) {
        case _SettingsMenuItem.assistant:
          return l10n.settingsPageAssistant;
        case _SettingsMenuItem.providers:
          return l10n.settingsPageProviders;
        case _SettingsMenuItem.display:
          return l10n.settingsPageDisplay;
        case _SettingsMenuItem.defaultModel:
          return l10n.settingsPageDefaultModel;
        case _SettingsMenuItem.search:
          return l10n.settingsPageSearch;
        case _SettingsMenuItem.mcp:
          return l10n.settingsPageMcp;
        case _SettingsMenuItem.quickPhrases:
          return l10n.settingsPageQuickPhrase;
        case _SettingsMenuItem.tts:
          return l10n.settingsPageTts;
        case _SettingsMenuItem.backup:
          return l10n.settingsPageBackup;
        case _SettingsMenuItem.about:
          return l10n.settingsPageAbout;
      }
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topBar = SizedBox(
      height: 36,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, top: 8),
          child: Text(
            l10n.settingsPageTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          topBar,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsMenu(
                  width: _menuWidth,
                  selected: _selected,
                  onSelect: (it) => setState(() => _selected = it),
                ),
                SidebarResizeHandle(
                  onDrag: (dx) {
                    setState(() {
                      _menuWidth = (_menuWidth + dx).clamp(_menuMinWidth, _menuMaxWidth);
                    });
                  },
                  onDragEnd: () {
                    try {
                      context.read<SettingsProvider>().setDesktopSettingsSidebarWidth(_menuWidth);
                    } catch (_) {}
                  },
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOutCubic,
                    child: _buildBody(_selected),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({
    required this.width,
    required this.selected,
    required this.onSelect,
  });
  final double width;
  final _SettingsMenuItem selected;
  final ValueChanged<_SettingsMenuItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = [
      (_SettingsMenuItem.display, lucide.Lucide.Monitor, l10n.settingsPageDisplay),
      (_SettingsMenuItem.assistant, lucide.Lucide.Bot, l10n.settingsPageAssistant),
      (_SettingsMenuItem.providers, lucide.Lucide.Boxes, l10n.settingsPageProviders),
      (_SettingsMenuItem.defaultModel, lucide.Lucide.Heart, l10n.settingsPageDefaultModel),
      (_SettingsMenuItem.search, lucide.Lucide.Earth, l10n.settingsPageSearch),
      (_SettingsMenuItem.mcp, lucide.Lucide.Terminal, l10n.settingsPageMcp),
      (_SettingsMenuItem.quickPhrases, lucide.Lucide.Zap, l10n.settingsPageQuickPhrase),
      (_SettingsMenuItem.tts, lucide.Lucide.Volume2, l10n.settingsPageTts),
      (_SettingsMenuItem.backup, lucide.Lucide.Database, l10n.settingsPageBackup),
      (_SettingsMenuItem.about, lucide.Lucide.BadgeInfo, l10n.settingsPageAbout),
    ];
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _MenuItem(
              icon: items[i].$2,
              label: items[i].$3,
              selected: selected == items[i].$1,
              onTap: () => onSelect(items[i].$1),
              color: cs.onSurface.withOpacity(0.9),
              selectedColor: cs.primary,
              hoverBg: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
            ),
            if (i != items.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
    required this.selectedColor,
    required this.hoverBg,
  });

    final IconData icon;
    final String label;
    final bool selected;
    final VoidCallback onTap;
    final Color color;
    final Color selectedColor;
    final Color hoverBg;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = widget.selected
        ? cs.primary.withOpacity(0.10)
        : _hover
            ? widget.hoverBg
            : Colors.transparent;
    final fg = widget.selected ? widget.selectedColor : widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, color: fg, decoration: TextDecoration.none),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingSoonBody extends StatelessWidget {
  const _ComingSoonBody({required this.selected});
  final _SettingsMenuItem selected;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.25)),
        ),
        child: Text(
          'Coming soon',
          style: TextStyle(fontSize: 16, color: cs.onSurface.withOpacity(0.7), fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ===== Display Settings Body =====

class _DisplaySettingsBody extends StatelessWidget {
  const _DisplaySettingsBody({super.key});
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

class _CardPress extends StatefulWidget {
  const _CardPress({required this.builder, this.onTap, this.pressedScale = 0.98});
  final Widget Function(bool pressed, Color overlay) builder;
  final VoidCallback? onTap;
  final double pressedScale;
  @override
  State<_CardPress> createState() => _CardPressState();
}

class _CardPressState extends State<_CardPress> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlay = _pressed
        ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04))
        : Colors.transparent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: widget.builder(_pressed, overlay),
        ),
      ),
    );
  }
}

// ===== Assistants (Desktop right content) =====

class _DesktopAssistantsBody extends StatelessWidget {
  const _DesktopAssistantsBody({super.key});
  @override
  Widget build(BuildContext context) {
    final assistants = context.watch<AssistantProvider>().assistants;
    final cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                child: Row(
                  children: [
                    Text(
                      AppLocalizations.of(context)!.settingsPageAssistant,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    _AddAssistantButton(),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.12)),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(0.0),
                  ),
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: EdgeInsets.zero,
                    itemCount: assistants.length,
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) newIndex -= 1;
                      await context.read<AssistantProvider>().reorderAssistants(oldIndex, newIndex);
                    },
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          final t = Curves.easeOutCubic.transform(animation.value);
                          return Transform.scale(
                            scale: 0.98 + 0.02 * t,
                            child: Material(
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                              child: child,
                            ),
                          );
                        },
                      );
                    },
                    itemBuilder: (context, index) {
                      final item = assistants[index];
                      return KeyedSubtree(
                        key: ValueKey('desktop-assistant-${item.id}'),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ReorderableDragStartListener(
                            index: index,
                            child: _DesktopAssistantCard(
                              item: item,
                              onTap: () => showAssistantDesktopDialog(context, assistantId: item.id),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddAssistantButton extends StatefulWidget {
  @override
  State<_AddAssistantButton> createState() => _AddAssistantButtonState();
}

class _AddAssistantButtonState extends State<_AddAssistantButton> {
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
        onTap: () async {
          final name = await _showAddAssistantDesktopDialog(context);
          if (name == null || name.trim().isEmpty) return;
          await context.read<AssistantProvider>().addAssistant(name: name.trim(), context: context);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Icon(lucide.Lucide.Plus, size: 16, color: cs.primary),
        ),
      ),
    );
  }
}

Future<String?> _showAddAssistantDesktopDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  final controller = TextEditingController();
  String? result;
  await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(l10n.assistantSettingsAddSheetTitle, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                        icon: const Icon(lucide.Lucide.X, size: 18),
                        color: cs.onSurface,
                        onPressed: () => Navigator.of(ctx).maybePop(),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: l10n.assistantSettingsAddSheetHint,
                        filled: true,
                        fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF7F7F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.primary.withOpacity(0.4)),
                        ),
                      ),
                      onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _DeskIosButton(
                          label: l10n.assistantSettingsAddSheetCancel,
                          filled: false,
                          dense: true,
                          onTap: () => Navigator.of(ctx).pop(),
                        ),
                        const SizedBox(width: 8),
                        _DeskIosButton(
                          label: l10n.assistantSettingsAddSheetSave,
                          filled: true,
                          dense: true,
                          onTap: () => Navigator.of(ctx).pop(controller.text.trim()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  ).then((v) => result = v);
  final s = (result ?? '').trim();
  if (s.isEmpty) return null;
  return s;
}

class _DeleteAssistantIcon extends StatefulWidget {
  const _DeleteAssistantIcon({required this.onConfirm});
  final Future<void> Function() onConfirm;
  @override
  State<_DeleteAssistantIcon> createState() => _DeleteAssistantIconState();
}

class _DeleteAssistantIconState extends State<_DeleteAssistantIcon> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover ? (isDark ? cs.error.withOpacity(0.18) : cs.error.withOpacity(0.14)) : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onConfirm(),
        child: Container(
          margin: const EdgeInsets.only(left: 8),
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(lucide.Lucide.Trash2, size: 15, color: cs.error),
        ),
      ),
    );
  }
}

Future<bool?> _confirmDeleteDesktop(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'assistant-delete',
    barrierColor: Colors.black.withOpacity(0.15),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, __) {
      final dialog = Material(
        color: Colors.transparent,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: cs.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Theme.of(ctx).brightness == Brightness.dark
                        ? Colors.white.withOpacity(0.08)
                        : cs.outlineVariant.withOpacity(0.25),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.assistantSettingsDeleteDialogTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                            icon: const Icon(lucide.Lucide.X, size: 18),
                            color: cs.onSurface,
                            onPressed: () => Navigator.of(ctx).maybePop(false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.12)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.assistantSettingsDeleteDialogContent,
                          style: TextStyle(color: cs.onSurface.withOpacity(0.9), fontSize: 13.5),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _DeskIosButton(
                              label: l10n.assistantSettingsDeleteDialogCancel,
                              filled: false,
                              dense: true,
                              onTap: () => Navigator.of(ctx).pop(false),
                            ),
                            const SizedBox(width: 8),
                            _DeskIosButton(
                              label: l10n.assistantSettingsDeleteDialogConfirm,
                              filled: true,
                              danger: true,
                              dense: true,
                              onTap: () => Navigator.of(ctx).pop(true),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return dialog;
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _DeskIosButton extends StatefulWidget {
  const _DeskIosButton({required this.label, required this.onTap, this.filled = false, this.danger = false, this.dense = false});
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool danger;
  final bool dense;
  @override
  State<_DeskIosButton> createState() => _DeskIosButtonState();
}

class _DeskIosButtonState extends State<_DeskIosButton> {
  bool _pressed = false;
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = widget.danger ? cs.error : cs.primary;
    final textColor = widget.filled ? (widget.danger ? cs.onError : cs.onPrimary) : baseColor;
    final baseBg = widget.filled ? baseColor : (isDark ? Colors.white10 : Colors.transparent);
    final hoverBg = widget.filled
        ? baseColor.withOpacity(0.92)
        : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04));
    final bg = _hover ? hoverBg : baseBg;
    final borderColor = widget.filled ? Colors.transparent : baseColor.withOpacity(isDark ? 0.6 : 0.5);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: widget.dense ? 8 : 12, horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Text(widget.label, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: widget.dense ? 13 : 14)),
        ),
      ),
      ),
    );
  }
}

class _DesktopAssistantCard extends StatefulWidget {
  const _DesktopAssistantCard({required this.item, required this.onTap});
  final Assistant item;
  final VoidCallback onTap;
  @override
  State<_DesktopAssistantCard> createState() => _DesktopAssistantCardState();
}

class _DesktopAssistantCardState extends State<_DesktopAssistantCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    final borderColor = _hover ? cs.primary.withOpacity(isDark ? 0.35 : 0.45) : cs.outlineVariant.withOpacity(isDark ? 0.12 : 0.08);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: _CardPress(
        onTap: widget.onTap,
        pressedScale: 1.0,
        builder: (pressed, overlay) => Container(
          decoration: BoxDecoration(
            color: Color.alphaBlend(overlay, baseBg),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _AssistantAvatarDesktop(item: widget.item, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (!widget.item.deletable)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: cs.primary.withOpacity(0.35)),
                              ),
                              child: Text(
                                AppLocalizations.of(context)!.assistantSettingsDefaultTag,
                                style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w700),
                              ),
                            ),
                          _DeleteAssistantIcon(
                            onConfirm: () async {
                              final l10n = AppLocalizations.of(context)!;
                              final count = context.read<AssistantProvider>().assistants.length;
                              if (count <= 1) {
                                showAppSnackBar(
                                  context,
                                  message: l10n.assistantSettingsAtLeastOneAssistantRequired,
                                  type: NotificationType.warning,
                                );
                                return;
                              }
                              final ok = await _confirmDeleteDesktop(context);
                              if (ok == true) {
                                await context.read<AssistantProvider>().deleteAssistant(widget.item.id);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (widget.item.systemPrompt.trim().isEmpty
                            ? AppLocalizations.of(context)!.assistantSettingsNoPromptPlaceholder
                            : widget.item.systemPrompt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7), height: 1.25),
                      ),
                    ],
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

class _AssistantAvatarDesktop extends StatelessWidget {
  const _AssistantAvatarDesktop({required this.item, this.size = 40});
  final Assistant item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final av = (item.avatar ?? '').trim();
    if (av.isNotEmpty) {
      if (av.startsWith('http')) {
        return FutureBuilder<String?>(
          future: AvatarCache.getPath(av),
          builder: (ctx, snap) {
            final p = snap.data;
            if (p != null && !kIsWeb && File(p).existsSync()) {
              return ClipOval(
                child: Image(
                  image: FileImage(File(p)),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              );
            }
            if (p != null && kIsWeb && p.startsWith('data:')) {
              return ClipOval(
                child: Image.network(p, width: size, height: size, fit: BoxFit.cover),
              );
            }
            return ClipOval(
              child: Image.network(
                av,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => _initial(cs),
              ),
            );
          },
        );
      } else if (!kIsWeb && (av.startsWith('/') || av.contains(':') || av.contains('/'))) {
        // Local file path (absolute or relative)
        return FutureBuilder<String?>(
          future: AssistantProvider.resolveToAbsolutePath(av),
          builder: (ctx, snap) {
            if (!snap.hasData || snap.data == null) return _initial(cs);
            final absPath = snap.data!;
            return ClipOval(
              child: Image(
                image: FileImage(File(absPath)),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => _initial(cs),
              ),
            );
          },
        );
      } else {
        return _emoji(cs, av);
      }
    }
    return _initial(cs);
  }

  Widget _initial(ColorScheme cs) {
    final letter = item.name.isNotEmpty ? item.name.characters.first : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }

  Widget _emoji(ColorScheme cs, String emoji) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(emoji.characters.take(1).toString(), style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

// ===== Providers Settings Body =====

class _ProvidersSettingsBody extends StatefulWidget {
  const _ProvidersSettingsBody({super.key});

  @override
  State<_ProvidersSettingsBody> createState() => _ProvidersSettingsBodyState();
}

class _ProvidersSettingsBodyState extends State<_ProvidersSettingsBody> {
  String? _selectedProviderKey;
  String? _selectedProviderName;

  void _onProviderTap(String providerKey, String displayName) {
    setState(() {
      _selectedProviderKey = providerKey;
      _selectedProviderName = displayName;
    });
  }

  void _onBackToList() {
    setState(() {
      _selectedProviderKey = null;
      _selectedProviderName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showDetail = _selectedProviderKey != null && _selectedProviderName != null;

    // Animated page switching with fade + slide transition
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        // Slide transition: detail slides in from right, list slides out to left
        final offsetAnimation = Tween<Offset>(
          begin: showDetail ? const Offset(0.05, 0) : const Offset(-0.05, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ));

        return SlideTransition(
          position: offsetAnimation,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: showDetail
          ? DesktopProviderDetailPage(
              key: ValueKey(_selectedProviderKey), // Key for AnimatedSwitcher
              keyName: _selectedProviderKey!,
              displayName: _selectedProviderName!,
              embedded: true,
              onBack: _onBackToList,
            )
          : ProvidersPage(
              key: const ValueKey('providers-list'), // Key for AnimatedSwitcher
              embedded: true,
              onProviderTap: _onProviderTap,
            ),
    );
  }
}

// ===== Default Model Settings Body =====

class _DefaultModelSettingsBody extends StatelessWidget {
  const _DefaultModelSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    // Use desktop default model pane
    return const DesktopDefaultModelPane();
  }
}

// ===== Search Settings Body =====

class _SearchSettingsBody extends StatelessWidget {
  const _SearchSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    // Embed SearchServicesPage content directly without navigation
    return const SearchServicesPage(embedded: true);
  }
}

// ===== MCP Settings Body =====

class _McpSettingsBody extends StatelessWidget {
  const _McpSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    // Use desktop MCP pane
    return const DesktopMcpPane();
  }
}

// ===== Quick Phrases Settings Body =====

class _QuickPhrasesSettingsBody extends StatelessWidget {
  const _QuickPhrasesSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    // Embed QuickPhrasesPage content directly without navigation
    return const QuickPhrasesPage(embedded: true);
  }
}

// ===== TTS Settings Body =====

class _TtsSettingsBody extends StatelessWidget {
  const _TtsSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    // Embed TtsServicesPage content directly without navigation
    return const TtsServicesPage(embedded: true);
  }
}

// ===== Backup Settings Body =====

class _BackupSettingsBody extends StatelessWidget {
  const _BackupSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    // Use desktop backup pane with inline WebDAV settings
    return const DesktopBackupPane();
  }
}

// ===== About Settings Body =====

class _AboutSettingsBody extends StatelessWidget {
  const _AboutSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    // Embed AboutPage content directly without navigation
    return const AboutPage(embedded: true);
  }
}

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

// --- Topic position (desktop) ---
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

