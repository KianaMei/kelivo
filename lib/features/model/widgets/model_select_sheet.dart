import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'model_detail_sheet.dart';
import '../../provider/pages/provider_detail_page.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/brand_assets.dart';
import '../../../shared/widgets/ios_tactile.dart';

class ModelSelection {
  final String providerKey;
  final String modelId;
  ModelSelection(this.providerKey, this.modelId);
}

// Data class for compute function
class _ModelProcessingData {
  final Map<String, dynamic> providerConfigs;
  final Set<String> pinnedModels;
  final String currentModelKey;
  final List<String> providersOrder;
  final String? limitProviderKey;
  
  _ModelProcessingData({
    required this.providerConfigs,
    required this.pinnedModels,
    required this.currentModelKey,
    required this.providersOrder,
    this.limitProviderKey,
  });
}

class _ModelProcessingResult {
  final Map<String, _ProviderGroup> groups;
  final List<_ModelItem> favItems;
  final List<String> orderedKeys;
  
  _ModelProcessingResult({
    required this.groups,
    required this.favItems,
    required this.orderedKeys,
  });
}

// Lightweight brand asset resolver usable in isolates
String? _assetForNameStatic(String n) {
  return BrandAssets.assetForName(n);
}

// Static function for compute - must be top-level
_ModelProcessingResult _processModelsInBackground(_ModelProcessingData data) {
  final providers = data.limitProviderKey == null
      ? data.providerConfigs
      : {
    if (data.providerConfigs.containsKey(data.limitProviderKey))
      data.limitProviderKey!: data.providerConfigs[data.limitProviderKey]!,
  };
  
  // Build data map: providerKey -> (displayName, models)
  final Map<String, _ProviderGroup> groups = {};
  
  providers.forEach((key, cfg) {
    // Skip disabled providers entirely so they can't be selected
    if (!(cfg['enabled'] as bool)) return;
    final models = cfg['models'] as List<dynamic>? ?? [];
    if (models.isEmpty) return;
    
    final name = (cfg['name'] as String?) ?? '';
    final overrides = (cfg['overrides'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? const <String, dynamic>{};
    final list = <_ModelItem>[
      for (final id in models)
        () {
          final String mid = id.toString();
          ModelInfo base = ModelRegistry.infer(ModelInfo(id: mid, displayName: mid));
          final ov = overrides[mid] as Map?;
          if (ov != null) {
            // display name override
            final n = (ov['name'] as String?)?.trim();
            // type override
            ModelType? type;
            final t = (ov['type'] as String?)?.trim();
            if (t != null) {
              type = (t == 'embedding') ? ModelType.embedding : ModelType.chat;
            }
            // modality override
            List<Modality>? input;
            if (ov['input'] is List) {
              input = [
                for (final e in (ov['input'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)
              ];
            }
            List<Modality>? output;
            if (ov['output'] is List) {
              output = [
                for (final e in (ov['output'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)
              ];
            }
            List<ModelAbility>? abilities;
            if (ov['abilities'] is List) {
              abilities = [
                for (final e in (ov['abilities'] as List)) (e.toString() == 'reasoning' ? ModelAbility.reasoning : ModelAbility.tool)
              ];
            }
            base = base.copyWith(
              displayName: (n != null && n.isNotEmpty) ? n : base.displayName,
              type: type ?? base.type,
              input: input ?? base.input,
              output: output ?? base.output,
              abilities: abilities ?? base.abilities,
            );
          }
          return _ModelItem(
            providerKey: key,
            providerName: name.isNotEmpty ? name : key,
            id: mid,
            info: base,
            pinned: data.pinnedModels.contains('$key::$mid'),
            selected: data.currentModelKey == '$key::$mid',
            asset: _assetForNameStatic(mid),
          );
        }()
    ];
    groups[key] = _ProviderGroup(name: name.isNotEmpty ? name : key, items: list);
  });
  
  // Build favorites group (duplicate items)
  final favItems = <_ModelItem>[];
  for (final k in data.pinnedModels) {
    final parts = k.split('::');
    if (parts.length < 2) continue;
    final pk = parts[0];
    final mid = parts.sublist(1).join('::');
    final g = groups[pk];
    if (g == null) continue;
    final found = g.items.firstWhere(
      (e) => e.id == mid,
      orElse: () => _ModelItem(
        providerKey: pk,
        providerName: g.name,
        id: mid,
        info: ModelRegistry.infer(ModelInfo(id: mid, displayName: mid)),
        pinned: true,
        selected: data.currentModelKey == '$pk::$mid',
      ),
    );
    favItems.add(found.copyWith(pinned: true));
  }
  
  // Provider sections ordered by ProvidersPage order
  final orderedKeys = <String>[];
  for (final k in data.providersOrder) {
    if (groups.containsKey(k)) orderedKeys.add(k);
  }
  for (final k in groups.keys) {
    if (!orderedKeys.contains(k)) orderedKeys.add(k);
  }
  
  return _ModelProcessingResult(
    groups: groups,
    favItems: favItems,
    orderedKeys: orderedKeys,
  );
}

Future<ModelSelection?> showModelSelector(BuildContext context, {String? limitProviderKey}) async {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<ModelSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ModelSelectSheet(limitProviderKey: limitProviderKey),
  );
}

Future<void> showModelSelectSheet(BuildContext context, {bool updateAssistant = true}) async {
  final sel = await showModelSelector(context);
  if (sel != null) {
    if (updateAssistant) {
      // Update assistant's model instead of global default
      final assistantProvider = context.read<AssistantProvider>();
      final assistant = assistantProvider.currentAssistant;
      if (assistant != null) {
        await assistantProvider.updateAssistant(
          assistant.copyWith(
            chatModelProvider: sel.providerKey,
            chatModelId: sel.modelId,
          ),
        );
      }
    } else {
      // Only update global default when explicitly requested (e.g., from settings)
      final settings = context.read<SettingsProvider>();
      await settings.setCurrentModel(sel.providerKey, sel.modelId);
    }
  }
}

class _ModelSelectSheet extends StatefulWidget {
  const _ModelSelectSheet({this.limitProviderKey});
  final String? limitProviderKey;
  @override
  State<_ModelSelectSheet> createState() => _ModelSelectSheetState();
}

class _ModelSelectSheetState extends State<_ModelSelectSheet> {
  final TextEditingController _search = TextEditingController();
  final DraggableScrollableController _sheetCtrl = DraggableScrollableController();
  static const double _initialSize = 0.8;
  static const double _maxSize = 0.8;

  // Provider tabs scroll controller
  final ScrollController _providerTabsScrollController = ScrollController();

  // Async loading state
  bool _isLoading = true;
  Map<String, _ProviderGroup> _groups = {};
  List<_ModelItem> _favItems = [];
  List<String> _orderedKeys = [];

  // Current selected tab (provider key or "__fav__" for favorites)
  String? _currentTab;

  // Debounce for wheel events
  DateTime? _lastWheelEvent;
  static const _wheelDebounceMs = 150;

  @override
  void initState() {
    super.initState();
    // Delay loading to allow the sheet to open first
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _loadModelsAsync();
      }
    });
  }

  Future<void> _loadModelsAsync() async {
    try {
      final settings = context.read<SettingsProvider>();
      final assistant = context.read<AssistantProvider>().currentAssistant;

      // Determine current model - use assistant's model if set, otherwise global default
      final currentProvider = assistant?.chatModelProvider ?? settings.currentModelProvider;
      final currentModelId = assistant?.chatModelId ?? settings.currentModelId;
      final currentKey = (currentProvider != null && currentModelId != null)
          ? '$currentProvider::$currentModelId'
          : '';

      // Prepare data for background processing
      final processingData = _ModelProcessingData(
        providerConfigs: Map<String, dynamic>.from(
          settings.providerConfigs.map((key, value) => MapEntry(key, {
            'enabled': value.enabled,
            'name': value.name,
            'models': value.models,
            'overrides': value.modelOverrides,
          })),
        ),
        pinnedModels: settings.pinnedModels,
        currentModelKey: currentKey,
        providersOrder: settings.providersOrder,
        limitProviderKey: widget.limitProviderKey,
      );

      // Process in background isolate
      final result = await compute(_processModelsInBackground, processingData);

      if (mounted) {
        setState(() {
          _groups = result.groups;
          _favItems = result.favItems;
          _orderedKeys = result.orderedKeys;
          _isLoading = false;

          // Initialize current tab: prioritize last selected tab, fall back to current model provider, then first provider
          final lastTab = settings.lastSelectedProviderTab;
          if (lastTab != null && (lastTab == '__fav__' || _orderedKeys.contains(lastTab))) {
            _currentTab = lastTab;
          } else if (currentProvider != null && _orderedKeys.contains(currentProvider)) {
            _currentTab = currentProvider;
          } else if (_orderedKeys.isNotEmpty) {
            // Check if there are favorites first
            _currentTab = (_favItems.isNotEmpty && widget.limitProviderKey == null) ? '__fav__' : _orderedKeys.first;
          }
        });
        // Scroll to the selected tab after UI is built
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollCurrentTabToVisible();
        });
      }
    } catch (e) {
      // If compute fails (e.g., on web), fall back to synchronous processing
      if (mounted) {
        _loadModelsSynchronously();
      }
    }
  }

  void _loadModelsSynchronously() {
    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;

    // Determine current model - use assistant's model if set, otherwise global default
    final currentProvider = assistant?.chatModelProvider ?? settings.currentModelProvider;
    final currentModelId = assistant?.chatModelId ?? settings.currentModelId;
    final currentKey = (currentProvider != null && currentModelId != null)
        ? '$currentProvider::$currentModelId'
        : '';

    final processingData = _ModelProcessingData(
      providerConfigs: Map<String, dynamic>.from(
        settings.providerConfigs.map((key, value) => MapEntry(key, {
          'enabled': value.enabled,
          'name': value.name,
          'models': value.models,
          'overrides': value.modelOverrides,
        })),
      ),
      pinnedModels: settings.pinnedModels,
      currentModelKey: currentKey,
      providersOrder: settings.providersOrder,
      limitProviderKey: widget.limitProviderKey,
    );

    final result = _processModelsInBackground(processingData);

    setState(() {
      _groups = result.groups;
      _favItems = result.favItems;
      _orderedKeys = result.orderedKeys;
      _isLoading = false;

      // Initialize current tab: prioritize last selected tab, fall back to current model provider, then first provider
      final lastTab = settings.lastSelectedProviderTab;
      if (lastTab != null && (lastTab == '__fav__' || _orderedKeys.contains(lastTab))) {
        _currentTab = lastTab;
      } else if (currentProvider != null && _orderedKeys.contains(currentProvider)) {
        _currentTab = currentProvider;
      } else if (_orderedKeys.isNotEmpty) {
        // Check if there are favorites first
        _currentTab = (_favItems.isNotEmpty && widget.limitProviderKey == null) ? '__fav__' : _orderedKeys.first;
      }
    });
    // Scroll to the selected tab after UI is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollCurrentTabToVisible();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _sheetCtrl.dispose();
    _providerTabsScrollController.dispose();
    super.dispose();
  }

  // Match model name/id only (avoid provider key causing false positives)
  bool _matchesSearch(String query, _ModelItem item, String providerName) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return item.id.toLowerCase().contains(q) || item.info.displayName.toLowerCase().contains(q);
  }

  // Check if a provider should be shown based on search query (match display name only)
  bool _providerMatchesSearch(String query, String providerName) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();
    final lowerProviderName = providerName.toLowerCase();
    return lowerProviderName.contains(lowerQuery);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          controller: _sheetCtrl,
          expand: false,
          initialChildSize: _initialSize,
          maxChildSize: _maxSize,
          minChildSize: 0.4,
          builder: (c, controller) {
            return Column(
              children: [
                // Fixed header section with rounded corners
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      // Header drag indicator
                      Column(children: [
                        const SizedBox(height: 8),
                        Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999))),
                        const SizedBox(height: 8),
                      ]),
                      // Fixed search field (iOS-like input style)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          controller: _search,
                          enabled: !_isLoading,
                          onChanged: (_) => setState(() {}),
                          // Ensure high-contrast input text in both themes
                          style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                          cursorColor: cs.primary,
                          decoration: InputDecoration(
                            hintText: l10n.modelSelectSheetSearchHint,
                            prefixIcon: Icon(Lucide.Search, size: 18, color: cs.onSurface.withOpacity(_isLoading ? 0.35 : 0.6)),
                            // Use IconButton for reliable alignment at the far right
                            suffixIcon: (widget.limitProviderKey == null && context.watch<SettingsProvider>().pinnedModels.isNotEmpty)
                                ? Tooltip(
                                    message: l10n.modelSelectSheetFavoritesSection,
                                    child: IconButton(
                                      icon: Icon(Lucide.Bookmark, size: 18, color: cs.onSurface.withOpacity(_isLoading ? 0.35 : 0.7)),
                                      onPressed: () => _switchToTab('__fav__'),
                                      splashColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                      hoverColor: Colors.transparent,
                                      tooltip: l10n.modelSelectSheetFavoritesSection,
                                    ),
                                  )
                                : null,
                            suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            filled: true,
                            fillColor: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withOpacity(0.10)
                                : Colors.white.withOpacity(0.64),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.25)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Scrollable content
                Expanded(
                  child: Container(
                    color: cs.surface, // Ensure background color continuity
                    child: _isLoading 
                      ? const Center(child: CircularProgressIndicator())
                      : _buildContent(context),
                  ),
                ),
                // Fixed bottom tabs
                Container(
                  color: cs.surface, // Ensure background color continuity
                  child: _buildBottomTabs(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final query = _search.text.trim();

    // Search mode: show all matching models across all providers
    if (query.isNotEmpty) {
      return _buildSearchResults(context, query);
    }

    // Tab mode: show only current tab's models
    if (_currentTab == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_currentTab == '__fav__') {
      return _buildFavoritesTab(context);
    }

    // Regular provider tab
    final group = _groups[_currentTab];
    if (group == null || group.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        itemCount: group.items.length,
        itemBuilder: (context, index) {
          return _modelTile(context, group.items[index]);
        },
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context, String query) {
    final matches = <_ModelItem>[];

    // Search across all providers
    for (final pk in _orderedKeys) {
      final g = _groups[pk]!;
      final providerMatches = _providerMatchesSearch(query, g.name);
      if (providerMatches) {
        matches.addAll(g.items);
      } else {
        matches.addAll(g.items.where((e) => _matchesSearch(query, e, g.name)));
      }
    }

    if (matches.isEmpty) {
      return const SizedBox.shrink();
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        itemCount: matches.length,
        itemBuilder: (context, index) {
          return _modelTile(context, matches[index], showProviderLabel: true);
        },
      ),
    );
  }

  Widget _buildFavoritesTab(BuildContext context) {
    // Dynamically build favorites list based on current pinned models
    final pinnedModels = context.watch<SettingsProvider>().pinnedModels;
    final favs = <_ModelItem>[];

    for (final k in pinnedModels) {
      final parts = k.split('::');
      if (parts.length < 2) continue;
      final pk = parts[0];
      final mid = parts.sublist(1).join('::');
      final g = _groups[pk];
      if (g == null) continue;

      final found = g.items.firstWhere(
        (e) => e.id == mid,
        orElse: () => _ModelItem(
          providerKey: pk,
          providerName: g.name,
          id: mid,
          info: ModelRegistry.infer(ModelInfo(id: mid, displayName: mid)),
          pinned: true,
          selected: false,
        ),
      );
      favs.add(found.copyWith(pinned: true));
    }

    if (favs.isEmpty) {
      return const SizedBox.shrink();
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        itemCount: favs.length,
        itemBuilder: (context, index) {
          return _modelTile(context, favs[index], showProviderLabel: true);
        },
      ),
    );
  }

  Widget _buildBottomTabs(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final List<Widget> providerTabs = <Widget>[];

    if (widget.limitProviderKey == null && !_isLoading) {
      // Add favorites tab first if there are any favorites (dynamic check)
      final hasFavorites = context.watch<SettingsProvider>().pinnedModels.isNotEmpty;
      if (hasFavorites) {
        providerTabs.add(_providerTab(
          context,
          '__fav__',
          l10n.modelSelectSheetFavoritesSection,
          selected: _currentTab == '__fav__',
        ));
      }

      // Add provider tabs
      for (final k in _orderedKeys) {
        final g = _groups[k];
        if (g != null) {
          providerTabs.add(_providerTab(context, k, g.name, selected: _currentTab == k));
        }
      }
    }

    if (providerTabs.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: Padding(
        // SafeArea already applies bottom inset; avoid doubling it here.
        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
        child: Listener(
        onPointerSignal: (event) {
          // Windows 滚轮支持 - 切换到下一个/上一个tab
          if (event is PointerScrollEvent && Platform.isWindows) {
            // Debounce: ignore events that come too quickly
            final now = DateTime.now();
            if (_lastWheelEvent != null &&
                now.difference(_lastWheelEvent!).inMilliseconds < _wheelDebounceMs) {
              return;
            }
            _lastWheelEvent = now;

            final delta = event.scrollDelta.dy;
            if (delta > 0) {
              // 向下滚动 - 切换到下一个tab
              _switchToNextTab(1);
            } else if (delta < 0) {
              // 向上滚动 - 切换到上一个tab
              _switchToNextTab(-1);
            }
          }
        },
        child: ScrollConfiguration(
          // Windows 拖动支持
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
            },
          ),
          child: SingleChildScrollView(
            controller: _providerTabsScrollController,
            scrollDirection: Axis.horizontal,
            // 减小回弹幅度
            physics: const ClampingScrollPhysics(),
            child: Row(children: providerTabs),
          ),
        ),
      ),
      ),
    );
  }

  Widget _modelTile(BuildContext context, _ModelItem m, {bool showProviderLabel = false}) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.read<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = m.selected ? (isDark ? cs.primary.withOpacity(0.12) : cs.primary.withOpacity(0.08)) : cs.surface;
    final effective = m.info; // precomputed effective info
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: RepaintBoundary(
        child: IosCardPress(
          baseColor: bg,
          borderRadius: BorderRadius.circular(14),
          pressedBlendStrength: 0.10,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: () => Navigator.of(context).pop(ModelSelection(m.providerKey, m.id)),
          onLongPress: () async {
            await showModelDetailSheet(context, providerKey: m.providerKey, modelId: m.id);
            if (mounted) {
              _isLoading = true;
              setState(() {});
              await _loadModelsAsync();
            }
          },
          child: SizedBox(
            width: double.infinity,
            child: Row(
            children: [
              _BrandAvatar(name: m.id, assetOverride: m.asset, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!showProviderLabel)
                      Text(
                        m.info.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      )
                    else
                      Text.rich(
                        TextSpan(
                          text: m.info.displayName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          children: [
                            TextSpan(
                              text: ' | ${m.providerName}',
                              style: TextStyle(
                                color: cs.onSurface.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    _modelTagWrap(context, effective),
                  ],
                ),
              ),
              Builder(builder: (context) {
                final pinnedNow = context.select<SettingsProvider, bool>((s) => s.isModelPinned(m.providerKey, m.id));
                final icon = pinnedNow ? Icons.favorite : Icons.favorite_border;
                return Tooltip(
                  message: l10n.modelSelectSheetFavoriteTooltip,
                  child: IosIconButton(
                    icon: icon,
                    size: 20,
                    color: cs.primary,
                    onTap: () => settings.togglePinModel(m.providerKey, m.id),
                    padding: const EdgeInsets.all(6),
                    minSize: 36,
                  ),
                );
              }),
            ],
          )),
        ),
      ),
    );
  }

  Widget _providerTab(BuildContext context, String key, String name, {bool selected = false}) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    // Only fetch provider config for non-favorites tab
    final cfg = (key == '__fav__') ? null : settings.getProviderConfig(key, defaultName: name);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: _ProviderChip(
        avatar: _BrandAvatar(
          name: name,
          size: 28,
          customAvatarPath: cfg?.customAvatarPath,
        ),
        label: name,
        selected: selected,
        borderColor: cs.outlineVariant.withOpacity(0.25),
        onTap: () => _switchToTab(key),
        onLongPress: key == '__fav__'
          ? null
          : () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProviderDetailPage(keyName: key, displayName: name)),
              );
              if (mounted) setState(() {});
            },
      ),
    );
  }

  /// Get all tab keys in order: favorites first (if exists), then providers
  List<String> _getAllTabKeys() {
    final tabs = <String>[];
    // Dynamic check for favorites
    if (widget.limitProviderKey == null) {
      try {
        final hasFavorites = context.read<SettingsProvider>().pinnedModels.isNotEmpty;
        if (hasFavorites) {
          tabs.add('__fav__');
        }
      } catch (_) {
        // If context.read fails, fall back to cached check
        if (_favItems.isNotEmpty) {
          tabs.add('__fav__');
        }
      }
    }
    tabs.addAll(_orderedKeys);
    return tabs;
  }

  /// Switch to a specific tab and persist the selection
  void _switchToTab(String tabKey) {
    if (_currentTab == tabKey) return;
    setState(() {
      _currentTab = tabKey;
    });
    // Persist tab selection
    context.read<SettingsProvider>().setLastSelectedProviderTab(tabKey);
    // Scroll to make the selected tab visible
    _scrollCurrentTabToVisible();
  }

  /// Scroll bottom tabs to make the currently selected tab visible
  void _scrollCurrentTabToVisible() {
    if (!_providerTabsScrollController.hasClients || _currentTab == null) {
      return;
    }

    final allTabs = _getAllTabKeys();
    final currentIndex = allTabs.indexOf(_currentTab!);
    if (currentIndex == -1) return;

    // Estimate tab width (avatar + label + padding)
    // Typical: 18px avatar + 6px gap + ~60-80px label + 20px padding = ~100-120px per tab
    const estimatedTabWidth = 110.0;
    final targetOffset = currentIndex * estimatedTabWidth;

    // Get viewport width
    final viewportWidth = _providerTabsScrollController.position.viewportDimension;
    final maxScroll = _providerTabsScrollController.position.maxScrollExtent;

    // Calculate scroll position to center the tab
    double scrollTo = targetOffset - (viewportWidth / 2) + (estimatedTabWidth / 2);

    // Clamp to valid range
    scrollTo = scrollTo.clamp(0.0, maxScroll);

    // Animate to position
    _providerTabsScrollController.animateTo(
      scrollTo,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  /// Switch to next/previous tab (for wheel navigation)
  void _switchToNextTab(int direction) {
    final allTabs = _getAllTabKeys();
    if (allTabs.isEmpty) return;

    final currentIndex = _currentTab != null ? allTabs.indexOf(_currentTab!) : -1;
    int nextIndex = (currentIndex == -1) ? 0 : currentIndex + direction;

    // Wrap around
    if (nextIndex < 0) {
      nextIndex = allTabs.length - 1;
    } else if (nextIndex >= allTabs.length) {
      nextIndex = 0;
    }

    _switchToTab(allTabs[nextIndex]);
  }

}

class _ProviderChip extends StatefulWidget {
  const _ProviderChip({required this.avatar, required this.label, required this.onTap, this.onLongPress, this.borderColor, this.selected = false});
  final Widget avatar;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color? borderColor;
  final bool selected;

  @override
  State<_ProviderChip> createState() => _ProviderChipState();
}

class _ProviderChipState extends State<_ProviderChip> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isSelected = widget.selected;

    // More visible selection state (stronger background)
    final Color baseBg = isSelected
        ? (isDark ? cs.primary.withOpacity(0.20) : cs.primary.withOpacity(0.18))
        : cs.surface;

    // Press overlay (only for pressed state)
    final Color overlay = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);
    final Color bg = _pressed ? Color.alphaBlend(overlay, baseBg) : baseBg;

    // Border: stronger when selected
    final Color borderColor = isSelected
        ? (isDark ? cs.primary.withOpacity(0.4) : cs.primary.withOpacity(0.35))
        : (widget.borderColor ?? cs.outlineVariant.withOpacity(0.25));

    final Color labelColor = cs.onSurface;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        // NO animation for selected state changes - only animate press
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.avatar,
            const SizedBox(width: 9),
            Text(widget.label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: labelColor)),
          ],
        ),
      ),
    );
  }
}

class _ProviderGroup {
  final String name;
  final List<_ModelItem> items;
  _ProviderGroup({required this.name, required this.items});
}

class _ModelItem {
  final String providerKey;
  final String providerName;
  final String id;
  final ModelInfo info;
  final bool pinned;
  final bool selected;
  final String? asset; // pre-resolved avatar asset for performance
  _ModelItem({required this.providerKey, required this.providerName, required this.id, required this.info, this.pinned = false, this.selected = false, this.asset});
  _ModelItem copyWith({bool? pinned, bool? selected}) => _ModelItem(providerKey: providerKey, providerName: providerName, id: id, info: info, pinned: pinned ?? this.pinned, selected: selected ?? this.selected, asset: asset);
}

class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({required this.name, this.size = 20, this.assetOverride, this.customAvatarPath});
  final String name;
  final double size;
  final String? assetOverride;
  final String? customAvatarPath;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white10 : cs.primary.withOpacity(0.1);

    // Priority 1: Custom avatar (for provider tabs)
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
      // 2. File path
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
      // 3. Emoji
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

    // Priority 2 & 3: Brand assets or initials
    return _buildBrandAvatar(cs, isDark);
  }

  Widget _buildBrandAvatar(ColorScheme cs, bool isDark) {
    final asset = assetOverride ?? BrandAssets.assetForName(name);
    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final ColorFilter? tint = (isDark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.62,
          height: size * 0.62,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(asset, width: size * 0.62, height: size * 0.62, fit: BoxFit.contain);
      }
    } else {
      inner = Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: size * 0.42),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}

Widget _modelTagWrap(BuildContext context, ModelInfo m) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  List<Widget> chips = [];
  // type tag
  chips.add(Container(
    decoration: BoxDecoration(
      color: isDark ? cs.primary.withOpacity(0.25) : cs.primary.withOpacity(0.15),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: cs.primary.withOpacity(0.2), width: 0.5),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    child: Text(m.type == ModelType.chat ? l10n.modelSelectSheetChatType : l10n.modelSelectSheetEmbeddingType, style: TextStyle(fontSize: 11, color: isDark ? cs.primary : cs.primary.withOpacity(0.9), fontWeight: FontWeight.w500)),
  ));
  // modality tag capsule with icons (keep consistent with provider detail page)
  chips.add(Container(
    decoration: BoxDecoration(
      color: isDark ? cs.tertiary.withOpacity(0.25) : cs.tertiary.withOpacity(0.15),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: cs.tertiary.withOpacity(0.2), width: 0.5),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      for (final mod in m.input)
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(mod == Modality.text ? Lucide.Type : Lucide.Image, size: 12, color: isDark ? cs.tertiary : cs.tertiary.withOpacity(0.9)),
        ),
      Icon(Lucide.ChevronRight, size: 12, color: isDark ? cs.tertiary : cs.tertiary.withOpacity(0.9)),
      for (final mod in m.output)
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Icon(mod == Modality.text ? Lucide.Type : Lucide.Image, size: 12, color: isDark ? cs.tertiary : cs.tertiary.withOpacity(0.9)),
        ),
    ]),
  ));
  // abilities capsules
  for (final ab in m.abilities) {
    if (ab == ModelAbility.tool) {
      chips.add(Container(
        decoration: BoxDecoration(
          color: isDark ? cs.primary.withOpacity(0.25) : cs.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.primary.withOpacity(0.2), width: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Icon(Lucide.Hammer, size: 12, color: isDark ? cs.primary : cs.primary.withOpacity(0.9)),
      ));
    } else if (ab == ModelAbility.reasoning) {
      chips.add(Container(
        decoration: BoxDecoration(
          color: isDark ? cs.secondary.withOpacity(0.3) : cs.secondary.withOpacity(0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.secondary.withOpacity(0.25), width: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: SvgPicture.asset('assets/icons/deepthink.svg', width: 12, height: 12, colorFilter: ColorFilter.mode(isDark ? cs.secondary : cs.secondary.withOpacity(0.9), BlendMode.srcIn)),
      ));
    }
  }
  return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: chips);
}
