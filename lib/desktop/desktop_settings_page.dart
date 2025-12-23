import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons/lucide_adapter.dart' as lucide;
import '../l10n/app_localizations.dart';
import '../core/providers/settings_provider.dart';
import '../features/provider/pages/providers_page.dart';
import 'desktop_provider_detail_page.dart';
import 'setting/desktop_default_model_pane.dart';
import '../features/search/pages/search_services_page.dart';
import 'setting/desktop_mcp_pane.dart';
import '../features/quick_phrase/pages/quick_phrases_page.dart';
import '../features/settings/pages/tts_services_page.dart';
import 'desktop_backup_pane.dart';
import '../features/settings/pages/about_page.dart';
import '_sidebar_resize_handle.dart';
import 'panes/desktop_display_pane.dart';
import 'panes/desktop_assistants_pane.dart';
import 'setting/desktop_network_proxy_pane.dart';

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
  networkProxy,
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
          _selected = _menuItemFromString(sp.desktopSelectedSettingsMenu);
        });
      } catch (_) {}
    });
  }

  _SettingsMenuItem _menuItemFromString(String key) {
    switch (key) {
      case 'display':
        return _SettingsMenuItem.display;
      case 'assistant':
        return _SettingsMenuItem.assistant;
      case 'providers':
        return _SettingsMenuItem.providers;
      case 'defaultModel':
        return _SettingsMenuItem.defaultModel;
      case 'search':
        return _SettingsMenuItem.search;
      case 'mcp':
        return _SettingsMenuItem.mcp;
      case 'quickPhrases':
        return _SettingsMenuItem.quickPhrases;
      case 'tts':
        return _SettingsMenuItem.tts;
      case 'networkProxy':
        return _SettingsMenuItem.networkProxy;
      case 'backup':
        return _SettingsMenuItem.backup;
      case 'about':
        return _SettingsMenuItem.about;
      default:
        return _SettingsMenuItem.display;
    }
  }

  String _menuItemToString(_SettingsMenuItem item) {
    switch (item) {
      case _SettingsMenuItem.display:
        return 'display';
      case _SettingsMenuItem.assistant:
        return 'assistant';
      case _SettingsMenuItem.providers:
        return 'providers';
      case _SettingsMenuItem.defaultModel:
        return 'defaultModel';
      case _SettingsMenuItem.search:
        return 'search';
      case _SettingsMenuItem.mcp:
        return 'mcp';
      case _SettingsMenuItem.quickPhrases:
        return 'quickPhrases';
      case _SettingsMenuItem.tts:
        return 'tts';
      case _SettingsMenuItem.networkProxy:
        return 'networkProxy';
      case _SettingsMenuItem.backup:
        return 'backup';
      case _SettingsMenuItem.about:
        return 'about';
    }
  }

  Widget _buildBody(_SettingsMenuItem item) {
    switch (item) {
      case _SettingsMenuItem.display:
        return const DisplaySettingsBody(key: ValueKey('display'));
      case _SettingsMenuItem.assistant:
        return const DesktopAssistantsBody(key: ValueKey('assistant'));
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
      case _SettingsMenuItem.networkProxy:
        return const _NetworkProxySettingsBody(key: ValueKey('networkProxy'));
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
                  onSelect: (it) {
                    setState(() => _selected = it);
                    try {
                      context.read<SettingsProvider>().setDesktopSelectedSettingsMenu(_menuItemToString(it));
                    } catch (_) {}
                  },
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
      (_SettingsMenuItem.networkProxy, lucide.Lucide.Globe, l10n.settingsPageNetworkProxy),
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
              color: cs.onSurface.withValues(alpha: 0.9),
              selectedColor: cs.primary,
              hoverBg: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
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
        ? cs.primary.withValues(alpha: 0.10)
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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
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
              key: ValueKey(_selectedProviderKey),
              keyName: _selectedProviderKey!,
              displayName: _selectedProviderName!,
              embedded: true,
              onBack: _onBackToList,
            )
          : ProvidersPage(
              key: const ValueKey('providers-list'),
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
    return const DesktopDefaultModelPane();
  }
}

// ===== Search Settings Body =====

class _SearchSettingsBody extends StatelessWidget {
  const _SearchSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const SearchServicesPage(embedded: true);
  }
}

// ===== MCP Settings Body =====

class _McpSettingsBody extends StatelessWidget {
  const _McpSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const DesktopMcpPane();
  }
}

// ===== Quick Phrases Settings Body =====

class _QuickPhrasesSettingsBody extends StatelessWidget {
  const _QuickPhrasesSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const QuickPhrasesPage(embedded: true);
  }
}

// ===== TTS Settings Body =====

class _TtsSettingsBody extends StatelessWidget {
  const _TtsSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const TtsServicesPage(embedded: true);
  }
}

// ===== Network Proxy Settings Body =====

class _NetworkProxySettingsBody extends StatelessWidget {
  const _NetworkProxySettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const DesktopNetworkProxyPane();
  }
}

// ===== Backup Settings Body =====

class _BackupSettingsBody extends StatelessWidget {
  const _BackupSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const DesktopBackupPane();
  }
}

// ===== About Settings Body =====

class _AboutSettingsBody extends StatelessWidget {
  const _AboutSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const AboutPage(embedded: true);
  }
}
