import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../icons/lucide_adapter.dart' as lucide;
import '../l10n/app_localizations.dart';
import '../utils/brand_assets.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/assistant_provider.dart';
import '../core/services/api/chat_api_service.dart';
import '../shared/widgets/snackbar.dart';
import '../features/settings/widgets/language_select_sheet.dart'
    show LanguageOption, supportedLanguages;
import '../features/model/widgets/model_select_sheet.dart' show showModelSelector;

/// Desktop translate page with two-pane layout (input left, output right).
/// Maintains state via IndexedStack in DesktopHomePage.
class DesktopTranslatePage extends StatefulWidget {
  const DesktopTranslatePage({super.key});

  @override
  State<DesktopTranslatePage> createState() => _DesktopTranslatePageState();
}

class _DesktopTranslatePageState extends State<DesktopTranslatePage> {
  // Controllers
  final TextEditingController _source = TextEditingController();
  final TextEditingController _output = TextEditingController();

  // State
  LanguageOption? _targetLang;
  String? _modelProviderKey;
  String? _modelId;
  StreamSubscription? _subscription;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDefaults());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _source.dispose();
    _output.dispose();
    super.dispose();
  }

  void _initDefaults() {
    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;

    // Default language based on locale: Chinese users → English, others → Simplified Chinese
    final lc = Localizations.localeOf(context).languageCode.toLowerCase();
    setState(() {
      if (lc.startsWith('zh')) {
        _targetLang = supportedLanguages.firstWhere(
          (e) => e.code == 'en',
          orElse: () => supportedLanguages.first,
        );
      } else {
        _targetLang = supportedLanguages.firstWhere(
          (e) => e.code == 'zh-CN',
          orElse: () => supportedLanguages.first,
        );
      }

      // Model fallback chain: translateModel → assistant.chatModel → globalDefault
      _modelProviderKey = settings.translateModelProvider ??
          assistant?.chatModelProvider ??
          settings.currentModelProvider;
      _modelId = settings.translateModelId ??
          assistant?.chatModelId ??
          settings.currentModelId;
    });
  }

  String _displayNameFor(AppLocalizations l10n, String code) {
    switch (code) {
      case 'zh-CN':
        return l10n.languageDisplaySimplifiedChinese;
      case 'en':
        return l10n.languageDisplayEnglish;
      case 'zh-TW':
        return l10n.languageDisplayTraditionalChinese;
      case 'ja':
        return l10n.languageDisplayJapanese;
      case 'ko':
        return l10n.languageDisplayKorean;
      case 'fr':
        return l10n.languageDisplayFrench;
      case 'de':
        return l10n.languageDisplayGerman;
      case 'it':
        return l10n.languageDisplayItalian;
      case 'es':
        return l10n.languageDisplaySpanish;
      default:
        return code;
    }
  }

  Future<void> _startTranslate() async {
    final l10n = AppLocalizations.of(context)!;
    final txt = _source.text.trim();

    // Validate input not empty
    if (txt.isEmpty) return;

    final pk = _modelProviderKey;
    final mid = _modelId;

    // Validate model configured
    if (pk == null || mid == null) {
      showAppSnackBar(
        context,
        message: l10n.homePagePleaseSetupTranslateModel,
        type: NotificationType.warning,
      );
      return;
    }

    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(pk);
    final targetLangName = _displayNameFor(
      l10n,
      (_targetLang ?? supportedLanguages.first).code,
    );
    final prompt = settings.translatePrompt
        .replaceAll('{source_text}', txt)
        .replaceAll('{target_lang}', targetLangName);

    setState(() {
      _translating = true;
      _output.text = '';
    });

    try {
      final stream = ChatApiService.sendMessageStream(
        config: cfg,
        modelId: mid,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );

      _subscription = stream.listen(
        (chunk) {
          final s = chunk.content;
          if (_output.text.isEmpty) {
            // Trim leading whitespace on first chunk
            final cleaned = s.replaceFirst(RegExp(r'^\s+'), '');
            _output.text = cleaned;
          } else {
            _output.text += s;
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _translating = false);
          showAppSnackBar(
            context,
            message: l10n.homePageTranslateFailed(e.toString()),
            type: NotificationType.error,
          );
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _translating = false);
        },
        cancelOnError: true,
      );
    } catch (e) {
      setState(() => _translating = false);
      showAppSnackBar(
        context,
        message: l10n.homePageTranslateFailed(e.toString()),
        type: NotificationType.error,
      );
    }
  }

  Future<void> _stopTranslate() async {
    try {
      await _subscription?.cancel();
    } catch (_) {}
    if (mounted) setState(() => _translating = false);
  }

  void _clearAll() {
    _source.clear();
    _output.clear();
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: AppLocalizations.of(context)!.chatMessageWidgetCopiedToClipboard,
      type: NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top bar with title
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                l10n.desktopNavTranslateTooltip,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),

          // Control row: language dropdown, translate button, spacer, model picker
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                // Language dropdown
                _LanguageDropdown(
                  value: _targetLang,
                  enabled: !_translating,
                  displayNameFor: _displayNameFor,
                  onChanged: (lang) {
                    if (lang != null) setState(() => _targetLang = lang);
                  },
                ),
                const SizedBox(width: 12),

                // Translate/Stop button
                _TranslateButton(
                  translating: _translating,
                  onTranslate: _startTranslate,
                  onStop: _stopTranslate,
                ),

                const Spacer(),

                // Model picker
                _ModelPickerButton(
                  modelId: _modelId,
                  enabled: !_translating,
                  onTap: () async {
                    if (_translating) return;
                    final sel = await showModelSelector(context);
                    if (!mounted || sel == null) return;
                    setState(() {
                      _modelProviderKey = sel.providerKey;
                      _modelId = sel.modelId;
                    });
                    await context
                        .read<SettingsProvider>()
                        .setTranslateModel(sel.providerKey, sel.modelId);
                  },
                ),
              ],
            ),
          ),

          // Two-pane row: input (left) and output (right)
          Expanded(
            child: Row(
              children: [
                // Input pane
                Expanded(
                  child: _PaneContainer(
                    actionIcon: lucide.Lucide.Eraser,
                    actionLabel: l10n.translatePageClearAll,
                    onAction: _clearAll,
                    child: TextField(
                      controller: _source,
                      keyboardType: TextInputType.multiline,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      decoration: InputDecoration(
                        hintText: l10n.translatePageInputHint,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Output pane
                Expanded(
                  child: _PaneContainer(
                    actionIcon: lucide.Lucide.Copy,
                    actionLabel: l10n.translatePageCopyResult,
                    onAction: _copyOutput,
                    child: TextField(
                      controller: _output,
                      readOnly: true,
                      keyboardType: TextInputType.multiline,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      decoration: InputDecoration(
                        hintText: l10n.translatePageOutputHint,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}


/// Pane container with rounded border and action button overlay
class _PaneContainer extends StatefulWidget {
  const _PaneContainer({
    required this.child,
    this.actionIcon,
    this.actionLabel,
    this.onAction,
  });

  final Widget child;
  final IconData? actionIcon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_PaneContainer> createState() => _PaneContainerState();
}

class _PaneContainerState extends State<_PaneContainer> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(0.3),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: widget.child),
            // Action button overlay (bottom-right)
            if (widget.actionIcon != null && widget.onAction != null)
              Positioned(
                right: 8,
                bottom: 8,
                child: AnimatedOpacity(
                  opacity: _hovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: _PaneActionButton(
                    icon: widget.actionIcon!,
                    label: widget.actionLabel,
                    onTap: widget.onAction!,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Action button for pane (clear/copy)
class _PaneActionButton extends StatefulWidget {
  const _PaneActionButton({
    required this.icon,
    this.label,
    required this.onTap,
  });

  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  @override
  State<_PaneActionButton> createState() => _PaneActionButtonState();
}

class _PaneActionButtonState extends State<_PaneActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered
                ? cs.surfaceContainerHighest
                : cs.surfaceContainerHigh.withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: cs.onSurface.withOpacity(_hovered ? 1.0 : 0.7),
              ),
              if (widget.label != null) ...[
                const SizedBox(width: 6),
                Text(
                  widget.label!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withOpacity(_hovered ? 1.0 : 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Language dropdown with overlay menu
class _LanguageDropdown extends StatefulWidget {
  const _LanguageDropdown({
    required this.value,
    required this.onChanged,
    required this.displayNameFor,
    this.enabled = true,
  });

  final LanguageOption? value;
  final ValueChanged<LanguageOption?>? onChanged;
  final String Function(AppLocalizations, String) displayNameFor;
  final bool enabled;

  @override
  State<_LanguageDropdown> createState() => _LanguageDropdownState();
}

class _LanguageDropdownState extends State<_LanguageDropdown> {
  bool _hovered = false;
  bool _menuOpen = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void _showMenu() {
    if (!widget.enabled || _menuOpen) return;
    setState(() => _menuOpen = true);

    _overlayEntry = OverlayEntry(
      builder: (context) => _LangDropdownOverlay(
        layerLink: _layerLink,
        languages: supportedLanguages,
        selectedCode: widget.value?.code,
        displayNameFor: widget.displayNameFor,
        onSelect: (lang) {
          _hideMenu();
          widget.onChanged?.call(lang);
        },
        onDismiss: _hideMenu,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _menuOpen = false);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final lang = widget.value ?? supportedLanguages.first;
    final displayName = widget.displayNameFor(l10n, lang.code);

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor:
            widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: _showMenu,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (_hovered || _menuOpen) && widget.enabled
                    ? cs.primary.withOpacity(0.5)
                    : cs.outlineVariant.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Opacity(
              opacity: widget.enabled ? 1.0 : 0.5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(lang.flag, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _menuOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      lucide.Lucide.ChevronDown,
                      size: 16,
                      color: cs.onSurface.withOpacity(0.6),
                    ),
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

/// Overlay menu for language dropdown
class _LangDropdownOverlay extends StatelessWidget {
  const _LangDropdownOverlay({
    required this.layerLink,
    required this.languages,
    required this.selectedCode,
    required this.displayNameFor,
    required this.onSelect,
    required this.onDismiss,
  });

  final LayerLink layerLink;
  final List<LanguageOption> languages;
  final String? selectedCode;
  final String Function(AppLocalizations, String) displayNameFor;
  final ValueChanged<LanguageOption> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Stack(
      children: [
        // Dismiss layer
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        // Menu
        CompositedTransformFollower(
          link: layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: Material(
            color: cs.surface,
            elevation: 8,
            shadowColor: Colors.black.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.outlineVariant.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: languages.map((lang) {
                    return _LangOptionTile(
                      lang: lang,
                      selected: lang.code == selectedCode,
                      displayName: displayNameFor(l10n, lang.code),
                      onTap: () => onSelect(lang),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Single language option tile
class _LangOptionTile extends StatefulWidget {
  const _LangOptionTile({
    required this.lang,
    required this.selected,
    required this.displayName,
    required this.onTap,
  });

  final LanguageOption lang;
  final bool selected;
  final String displayName;
  final VoidCallback onTap;

  @override
  State<_LangOptionTile> createState() => _LangOptionTileState();
}

class _LangOptionTileState extends State<_LangOptionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _hovered ? cs.surfaceContainerHighest : Colors.transparent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.lang.flag, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Text(
                widget.displayName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                  color: widget.selected ? cs.primary : cs.onSurface,
                ),
              ),
              if (widget.selected) ...[
                const SizedBox(width: 8),
                Icon(lucide.Lucide.Check, size: 14, color: cs.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


/// Translate/Stop button with animated state switch
class _TranslateButton extends StatefulWidget {
  const _TranslateButton({
    required this.translating,
    required this.onTranslate,
    required this.onStop,
  });

  final bool translating;
  final VoidCallback onTranslate;
  final VoidCallback onStop;

  @override
  State<_TranslateButton> createState() => _TranslateButtonState();
}

class _TranslateButtonState extends State<_TranslateButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.translating ? widget.onStop : widget.onTranslate,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? cs.primary.withOpacity(0.9)
                : cs.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: widget.translating
                ? Row(
                    key: const ValueKey('stop'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/stop.svg',
                        width: 18,
                        height: 18,
                        colorFilter: ColorFilter.mode(
                          isDark ? Colors.black : Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.chatMessageWidgetStopTooltip,
                        style: TextStyle(
                          color: isDark ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('translate'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        lucide.Lucide.Languages,
                        size: 18,
                        color: isDark ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.chatMessageWidgetTranslateTooltip,
                        style: TextStyle(
                          color: isDark ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
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

/// Model picker button showing brand icon and model ID
class _ModelPickerButton extends StatefulWidget {
  const _ModelPickerButton({
    required this.modelId,
    required this.onTap,
    this.enabled = true,
  });

  final String? modelId;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_ModelPickerButton> createState() => _ModelPickerButtonState();
}

class _ModelPickerButtonState extends State<_ModelPickerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final asset = widget.modelId != null
        ? BrandAssets.assetForName(widget.modelId!)
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered && widget.enabled
                  ? cs.primary.withOpacity(0.5)
                  : cs.outlineVariant.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Opacity(
            opacity: widget.enabled ? 1.0 : 0.5,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Brand icon
                if (asset != null && asset.toLowerCase().endsWith('.svg'))
                  SvgPicture.asset(asset, width: 20, height: 20)
                else if (asset != null)
                  Image.asset(asset, width: 20, height: 20)
                else
                  Icon(
                    lucide.Lucide.Bot,
                    size: 20,
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                const SizedBox(width: 8),
                // Model ID text
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    widget.modelId ?? 'Select Model',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface.withOpacity(_hovered ? 1.0 : 0.8),
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
