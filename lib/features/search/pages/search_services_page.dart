import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/search/search_service.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/models/api_keys.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../utils/brand_assets.dart';
import '../../../core/services/haptics.dart';
import 'key_management_widgets.dart';

class SearchServicesPage extends StatefulWidget {
  const SearchServicesPage({super.key, this.embedded = false});

  /// Whether this page is embedded in a desktop settings layout (no Scaffold/AppBar)
  final bool embedded;

  @override
  State<SearchServicesPage> createState() => _SearchServicesPageState();
}

class _SearchServicesPageState extends State<SearchServicesPage> {
  List<SearchServiceOptions> _services = [];
  int _selectedIndex = 0;
  final Map<String, bool> _testing = <String, bool>{}; // serviceId -> testing
  // Use SettingsProvider for connection results; keep only local testing spinner state

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _services = List.from(settings.searchServices);
    _selectedIndex = settings.searchServiceSelected;
    // Do not auto test here; rely on app-start tests. Users can test manually.
  }

  void _addService() {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // 桌面端：使用Dialog
      showDialog(
        context: context,
        builder: (context) => _AddServiceDialog(
          onAdd: (service) {
            setState(() {
              _services.add(service);
            });
            _saveChanges();
          },
        ),
      );
    } else {
      // 移动端：使用BottomSheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        backgroundColor: Colors.transparent,
        builder: (context) => _AddServiceBottomSheet(
          onAdd: (service) {
            setState(() {
              _services.add(service);
            });
            _saveChanges();
          },
        ),
      );
    }
  }

  void _editService(int index) {
    final service = _services[index];
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'edit-service',
        barrierColor: Colors.black.withOpacity(0.25),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, a1, a2) {
          return Center(
            child: _EditServiceDialog(
              service: service,
              onSave: (updated) {
                setState(() {
                  _services[index] = updated;
                });
                _saveChanges();
              },
            ),
          );
        },
        transitionBuilder: (ctx, anim, sec, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      );
    } else {
      final cs = Theme.of(context).colorScheme;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => _EditServiceSheet(
          service: service,
          onSave: (updated) {
            setState(() {
              _services[index] = updated;
            });
            _saveChanges();
          },
        ),
      );
    }
  }

  Future<void> _deleteService(int index) async {
    if (_services.length <= 1) {
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.searchServicesPageAtLeastOneServiceRequired,
        type: NotificationType.warning,
      );
      return;
    }

    final service = _services[index];
    final serviceName = SearchService.getService(service).name;
    final l10n = AppLocalizations.of(context)!;
    
    // 显示确认对话框
    final confirm = await _showDeleteConfirmDialog(context, serviceName);
    if (confirm != true) return;
    
    setState(() {
      _services.removeAt(index);
      if (_selectedIndex >= _services.length) {
        _selectedIndex = _services.length - 1;
      } else if (_selectedIndex > index) {
        _selectedIndex--;
      }
    });
    _saveChanges();
  }

  void _selectService(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _saveChanges();
  }

  void _saveChanges() {
    final settings = context.read<SettingsProvider>();
    context.read<SettingsProvider>().updateSettings(
      settings.copyWith(
        searchServices: _services,
        searchServiceSelected: _selectedIndex,
      ),
    );
  }

  Future<bool?> _showDeleteConfirmDialog(BuildContext context, String serviceName) async {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // 桌面端：使用AlertDialog
      return showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cs.surface,
          title: Text('删除搜索服务'),
          content: Text('确定要删除 "$serviceName" 搜索服务吗？\n\n此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      // 移动端：使用BottomSheet确认对话框
      return showModalBottomSheet<bool>(
        context: context,
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖拽条
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 警告图标
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning,
                      color: Colors.red,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 标题
                  Text(
                    '删除搜索服务',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // 内容
                  Text(
                    '确定要删除 "$serviceName" 搜索服务吗？\n\n此操作无法撤销。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 按钮
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('删除', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('取消'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  Future<void> _testConnection(int index) async {
    if (index < 0 || index >= _services.length) return;
    final s = _services[index];
    final id = s.id;
    setState(() {
      _testing[id] = true;
    });
    try {
      final svc = SearchService.getService(s);
      final settings = context.read<SettingsProvider>();
      // Use a tiny search to validate connectivity
      final common = SearchCommonOptions(
        resultSize: 1,
        timeout: settings.searchCommonOptions.timeout,
      );
      await svc.search(
        query: 'connectivity test',
        commonOptions: common,
        serviceOptions: s,
      );
      settings.setSearchConnection(id, true);
    } catch (_) {
      context.read<SettingsProvider>().setSearchConnection(id, false);
    } finally {
      setState(() {
        _testing[id] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final bodyContent = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _sectionHeader(l10n.searchServicesPageSearchProviders, cs, first: true),
        _iosSectionCard(children: [
          for (int i = 0; i < _services.length; i++) ...[
            _iosProviderRow(context, index: i),
            if (i != _services.length - 1) _iosDivider(context),
          ],
        ]),
        const SizedBox(height: 16),
        _sectionHeader(l10n.searchServicesPageGeneralOptions, cs),
        _buildCommonOptionsSection(context),
      ],
    );

    // If embedded, return body content directly with inline toolbar
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  l10n.searchServicesPageTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: l10n.searchServicesPageAddProvider,
                  child: _TactileIconButton(
                    icon: Lucide.Plus,
                    color: cs.onSurface,
                    size: 22,
                    onTap: _addService,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.12)),
          Expanded(child: bodyContent),
        ],
      );
    }

    // Otherwise, return full page with Scaffold and AppBar
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.searchServicesPageBackTooltip,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.searchServicesPageTitle),
        actions: [
          Tooltip(
            message: l10n.searchServicesPageAddProvider,
            child: _TactileIconButton(
              icon: Lucide.Plus,
              color: cs.onSurface,
              size: 22,
              onTap: _addService,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: bodyContent,
    );
  }

  Widget _sectionHeader(String text, ColorScheme cs, {bool first = false}) => Padding(
        padding: EdgeInsets.fromLTRB(12, first ? 2 : 18, 12, 6),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.8))),
      );

  Widget _buildCommonOptionsSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final common = settings.searchCommonOptions;
    final l10n = AppLocalizations.of(context)!;
    
    Widget stepper({required int value, required VoidCallback onMinus, required VoidCallback onPlus, String? unit}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SmallTactileIcon(
            icon: Lucide.Minus,
            onTap: onMinus,
            enabled: true,
          ),
          const SizedBox(width: 8),
          Text(unit == null ? '$value' : '$value$unit', style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.8))),
          const SizedBox(width: 8),
          _SmallTactileIcon(
            icon: Lucide.Plus,
            onTap: onPlus,
            enabled: true,
          ),
        ],
      );
    }

    return _iosSectionCard(children: [
      _TactileRow(
        onTap: null, // no navigation, so no chevron
        pressedScale: 1.00,
        haptics: false,
        builder: (pressed) {
          final baseColor = cs.onSurface.withOpacity(0.9);
          return _AnimatedPressColor(
            pressed: pressed,
            base: baseColor,
            builder: (c) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    SizedBox(width: 36, child: Icon(Lucide.ListOrdered, size: 18, color: c)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l10n.searchServicesPageMaxResults, style: TextStyle(fontSize: 15, color: c))),
                    stepper(
                      value: common.resultSize,
                      onMinus: common.resultSize > 1
                          ? () => context.read<SettingsProvider>().updateSettings(
                                settings.copyWith(
                                  searchCommonOptions: SearchCommonOptions(resultSize: common.resultSize - 1, timeout: common.timeout),
                                ),
                              )
                          : () {},
                      onPlus: common.resultSize < 20
                          ? () => context.read<SettingsProvider>().updateSettings(
                                settings.copyWith(
                                  searchCommonOptions: SearchCommonOptions(resultSize: common.resultSize + 1, timeout: common.timeout),
                                ),
                              )
                          : () {},
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      _iosDivider(context),
      _TactileRow(
        onTap: null,
        pressedScale: 1.00,
        haptics: false,
        builder: (pressed) {
          final baseColor = cs.onSurface.withOpacity(0.9);
          return _AnimatedPressColor(
            pressed: pressed,
            base: baseColor,
            builder: (c) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    SizedBox(width: 36, child: Icon(Lucide.History, size: 18, color: c)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l10n.searchServicesPageTimeoutSeconds, style: TextStyle(fontSize: 15, color: c))),
                    stepper(
                      value: common.timeout ~/ 1000,
                      onMinus: common.timeout > 1000
                          ? () => context.read<SettingsProvider>().updateSettings(
                                settings.copyWith(
                                  searchCommonOptions: SearchCommonOptions(resultSize: common.resultSize, timeout: common.timeout - 1000),
                                ),
                              )
                          : () {},
                      onPlus: common.timeout < 30000
                          ? () => context.read<SettingsProvider>().updateSettings(
                                settings.copyWith(
                                  searchCommonOptions: SearchCommonOptions(resultSize: common.resultSize, timeout: common.timeout + 1000),
                                ),
                              )
                          : () {},
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ]);
  }

  Widget _iosProviderRow(BuildContext context, {required int index}) {
    final s = _services[index];
    final cs = Theme.of(context).colorScheme;
    final name = SearchService.getService(s).name;
    final selected = index == _selectedIndex;
    // Connection/testing status for capsule
    final l10n = AppLocalizations.of(context)!;
    final testing = _testing[s.id] == true;
    final conn = context.watch<SettingsProvider>().searchConnection[s.id];
    String statusText;
    Color statusBg;
    Color statusFg;
    if (testing) {
      statusText = l10n.searchServicesPageTestingStatus;
      statusBg = cs.primary.withOpacity(0.12);
      statusFg = cs.primary;
    } else if (conn == true) {
      statusText = l10n.searchServicesPageConnectedStatus;
      statusBg = Colors.green.withOpacity(0.12);
      statusFg = Colors.green;
    } else if (conn == false) {
      statusText = l10n.searchServicesPageFailedStatus;
      statusBg = Colors.orange.withOpacity(0.12);
      statusFg = Colors.orange;
    } else {
      statusText = l10n.searchServicesPageNotTestedStatus;
      statusBg = cs.onSurface.withOpacity(0.06);
      statusFg = cs.onSurface.withOpacity(0.7);
    }
    return _TactileRow(
      onTap: () {
        // Tap to edit (bottom sheet)
        _editService(index);
      },
      pressedScale: 1.00,
      haptics: false,
      builder: (pressed) {
        final base = cs.onSurface.withOpacity(0.9);
        return _AnimatedPressColor(
          pressed: pressed,
          base: base,
          builder: (c) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: widget.embedded ? null : () => _showServiceActions(context, index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    SizedBox(width: 36, child: Center(child: _BrandBadge.forService(s, size: 22))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: c, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (s is! BingLocalOptions && statusText.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: statusFg),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    // 桌面端显示删除按钮，移动端显示箭头
                    if (widget.embedded) ...[
                      // 桌面端：删除按钮
                      if (_services.length > 1)
                        Tooltip(
                          message: '删除服务',
                          child: _TactileIconButton(
                            icon: Lucide.Trash2,
                            color: cs.error.withOpacity(0.8),
                            size: 18,
                            onTap: () => _deleteService(index),
                          ),
                        ),
                    ] else ...[
                      // 移动端：箭头图标
                      Icon(Lucide.ChevronRight, size: 16, color: c),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showServiceActions(BuildContext context, int index) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetOption(ctx, icon: Lucide.Activity, label: l10n.searchServicesPageTestConnectionTooltip, onTap: () {
                  Navigator.of(ctx).pop();
                  _testConnection(index);
                }),
                _sheetDivider(ctx),
                _sheetOption(ctx, icon: Lucide.Trash2, label: l10n.providerDetailPageDeleteButton, onTap: () {
                  Navigator.of(ctx).pop();
                  _deleteService(index);
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getServiceIcon(SearchServiceOptions service) {
    if (service is BingLocalOptions) return Lucide.Search;
    if (service is TavilyOptions) return Lucide.Sparkles;
    if (service is ExaOptions) return Lucide.Brain;
    if (service is ZhipuOptions) return Lucide.Languages;
    if (service is SearXNGOptions) return Lucide.Shield;
    if (service is LinkUpOptions) return Lucide.Link2;
    if (service is BraveOptions) return Lucide.Shield;
    if (service is MetasoOptions) return Lucide.Compass;
    if (service is JinaOptions) return Lucide.Sparkles;
    if (service is PerplexityOptions) return Lucide.Search;
    if (service is BochaOptions) return Lucide.Search;
    return Lucide.Search;
  }

  String? _getServiceStatus(SearchServiceOptions service) {
    final l10n = AppLocalizations.of(context)!;
    if (service is BingLocalOptions) return null;
    if (service is TavilyOptions) {
      final enabledCount = service.apiKeys.where((k) => k.isEnabled).length;
      if (enabledCount == 0) return l10n.searchServicesPageApiKeyRequiredStatus;
      return enabledCount == 1 ? l10n.searchServicesPageConfiguredStatus : '$enabledCount keys';
    }
    if (service is ExaOptions) {
      final enabledCount = service.apiKeys.where((k) => k.isEnabled).length;
      if (enabledCount == 0) return l10n.searchServicesPageApiKeyRequiredStatus;
      return enabledCount == 1 ? l10n.searchServicesPageConfiguredStatus : '$enabledCount keys';
    }
    if (service is ZhipuOptions) {
      final enabledCount = service.apiKeys.where((k) => k.isEnabled).length;
      if (enabledCount == 0) return l10n.searchServicesPageApiKeyRequiredStatus;
      return enabledCount == 1 ? l10n.searchServicesPageConfiguredStatus : '$enabledCount keys';
    }
    if (service is SearXNGOptions) return service.url.isNotEmpty ? l10n.searchServicesPageConfiguredStatus : l10n.searchServicesPageUrlRequiredStatus;
    if (service is LinkUpOptions) {
      final enabledCount = service.apiKeys.where((k) => k.isEnabled).length;
      if (enabledCount == 0) return l10n.searchServicesPageApiKeyRequiredStatus;
      return enabledCount == 1 ? l10n.searchServicesPageConfiguredStatus : '$enabledCount keys';
    }
    if (service is BraveOptions) {
      final enabledCount = service.apiKeys.where((k) => k.isEnabled).length;
      if (enabledCount == 0) return l10n.searchServicesPageApiKeyRequiredStatus;
      return enabledCount == 1 ? l10n.searchServicesPageConfiguredStatus : '$enabledCount keys';
    }
    if (service is MetasoOptions) {
      final enabledCount = service.apiKeys.where((k) => k.isEnabled).length;
      if (enabledCount == 0) return l10n.searchServicesPageApiKeyRequiredStatus;
      return enabledCount == 1 ? l10n.searchServicesPageConfiguredStatus : '$enabledCount keys';
    }
    if (service is OllamaOptions) {
      final enabledCount = service.apiKeys.where((k) => k.isEnabled).length;
      if (enabledCount == 0) return l10n.searchServicesPageApiKeyRequiredStatus;
      return enabledCount == 1 ? l10n.searchServicesPageConfiguredStatus : '$enabledCount keys';
    }
    if (service is JinaOptions) {
      final enabledCount = service.apiKeys.where((k) => k.isEnabled).length;
      if (enabledCount == 0) return l10n.searchServicesPageApiKeyRequiredStatus;
      return enabledCount == 1 ? l10n.searchServicesPageConfiguredStatus : '$enabledCount keys';
    }
    if (service is PerplexityOptions) {
      final enabledCount = service.apiKeys.where((k) => k.isEnabled).length;
      if (enabledCount == 0) return l10n.searchServicesPageApiKeyRequiredStatus;
      return enabledCount == 1 ? l10n.searchServicesPageConfiguredStatus : '$enabledCount keys';
    }
    if (service is BochaOptions) {
      final enabledCount = service.apiKeys.where((k) => k.isEnabled).length;
      if (enabledCount == 0) return l10n.searchServicesPageApiKeyRequiredStatus;
      return enabledCount == 1 ? l10n.searchServicesPageConfiguredStatus : '$enabledCount keys';
    }
    return null;
  }

  // Brand badge for known services using assets/icons; falls back to letter if unknown
  // ignore: unused_element
  Widget _brandBadgeForName(String name, {double size = 20}) => _BrandBadge(name: name, size: size);
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.name, this.size = 20});
  final String name;
  final double size;

  static Widget forService(SearchServiceOptions s, {double size = 24}) {
    final n = _nameForService(s);
    return _BrandBadge(name: n, size: size);
  }

  static String _nameForService(SearchServiceOptions s) {
    if (s is BingLocalOptions) return 'bing';
    if (s is TavilyOptions) return 'tavily';
    if (s is ExaOptions) return 'exa';
    if (s is ZhipuOptions) return 'zhipu';
    if (s is SearXNGOptions) return 'searxng';
    if (s is LinkUpOptions) return 'linkup';
    if (s is BraveOptions) return 'brave';
    if (s is MetasoOptions) return 'metaso';
    if (s is OllamaOptions) return 'ollama';
    if (s is JinaOptions) return 'jina';
    if (s is PerplexityOptions) return 'perplexity';
    if (s is BochaOptions) return 'bocha';
    return 'search';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use BrandAssets to get the icon path
    final asset = BrandAssets.assetForName(name);
    final bg = isDark ? Colors.white10 : cs.primary.withOpacity(0.1);
    if (asset != null) {
      if (asset!.endsWith('.svg')) {
        final isColorful = asset!.contains('color');
        final ColorFilter? tint = (isDark && !isColorful) ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: SvgPicture.asset(asset!, width: size * 0.62, height: size * 0.62, colorFilter: tint),
        );
      } else {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Image.asset(asset!, width: size * 0.62, height: size * 0.62, fit: BoxFit.contain),
        );
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: size * 0.42)),
    );
  }
}

// Add Service Bottom Sheet - iOS Style
class _AddServiceBottomSheet extends StatefulWidget {
  final Function(SearchServiceOptions) onAdd;

  const _AddServiceBottomSheet({required this.onAdd});

  @override
  State<_AddServiceBottomSheet> createState() => _AddServiceBottomSheetState();
}

class _AddServiceBottomSheetState extends State<_AddServiceBottomSheet> {
  String? _selectedType;
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title with animation
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
                child: Padding(
                  key: ValueKey<String?>(_selectedType),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Text(
                    _selectedType == null ? l10n.searchServicesAddDialogTitle : _getServiceName(_selectedType!),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              
              // Service type selection or form with fade animation
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: _selectedType == null
                      ? _buildServiceTypeList()
                      : _buildFormView(),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildServiceTypeList() {
    final l10n = AppLocalizations.of(context)!;
    final services = [
      {'type': 'bing_local', 'name': l10n.searchServiceNameBingLocal},
      {'type': 'tavily', 'name': l10n.searchServiceNameTavily},
      {'type': 'exa', 'name': l10n.searchServiceNameExa},
      {'type': 'zhipu', 'name': l10n.searchServiceNameZhipu},
      {'type': 'searxng', 'name': l10n.searchServiceNameSearXNG},
      {'type': 'linkup', 'name': l10n.searchServiceNameLinkUp},
      {'type': 'brave', 'name': l10n.searchServiceNameBrave},
      {'type': 'metaso', 'name': l10n.searchServiceNameMetaso},
      {'type': 'jina', 'name': l10n.searchServiceNameJina},
      {'type': 'ollama', 'name': l10n.searchServiceNameOllama},
      {'type': 'perplexity', 'name': l10n.searchServiceNamePerplexity},
      {'type': 'bocha', 'name': l10n.searchServiceNameBocha},
    ];
    return ListView.builder(
      key: const ValueKey('service_list'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shrinkWrap: true,
      itemCount: services.length,
      itemBuilder: (context, index) {
        final item = services[index];
        return Column(children: [
          _sheetOption(
            context,
            icon: Lucide.Globe,
            label: item['name'] as String,
            leading: _ServiceIcon(type: item['type'] as String, name: item['name'] as String, size: 36),
            bgOnPress: false,
            onTap: () {
              setState(() => _selectedType = item['type'] as String);
            },
          ),
          if (index != services.length - 1) _sheetDivider(context),
        ]);
      },
    );
  }

  String _getServiceName(String type) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case 'bing_local': return l10n.searchServiceNameBingLocal;
      case 'tavily': return l10n.searchServiceNameTavily;
      case 'exa': return l10n.searchServiceNameExa;
      case 'zhipu': return l10n.searchServiceNameZhipu;
      case 'searxng': return l10n.searchServiceNameSearXNG;
      case 'linkup': return l10n.searchServiceNameLinkUp;
      case 'brave': return l10n.searchServiceNameBrave;
      case 'metaso': return l10n.searchServiceNameMetaso;
      case 'jina': return l10n.searchServiceNameJina;
      case 'ollama': return l10n.searchServiceNameOllama;
      case 'perplexity': return l10n.searchServiceNamePerplexity;
      case 'bocha': return l10n.searchServiceNameBocha;
      default: return '';
    }
  }

  Widget _buildFormView() {
    final l10n = AppLocalizations.of(context)!;
    
    return SingleChildScrollView(
      key: const ValueKey('form_view'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            ..._buildFieldsForType(_selectedType!),
            const SizedBox(height: 20),
            // Add button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final service = _createService();
                    widget.onAdd(service);
                    Navigator.pop(context);
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  l10n.searchServicesAddDialogAdd,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFieldsForType(String type) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Widget _buildTextField({
      required String key,
      required String label,
      String? hint,
      bool obscureText = false,
      String? Function(String?)? validator,
    }) {
      _controllers[key] ??= TextEditingController();
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextFormField(
          controller: _controllers[key],
          obscureText: obscureText,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: validator,
        ),
      );
    }
    
    switch (type) {
      case 'bing_local':
        return [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Lucide.Search, size: 20, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.searchServiceNameBingLocal,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withOpacity(0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ];
      case 'tavily':
      case 'exa':
      case 'zhipu':
      case 'linkup':
      case 'brave':
      case 'metaso':
      case 'jina':
      case 'ollama':
      case 'perplexity':
      case 'bocha':
        return [
          _buildTextField(
            key: 'apiKey',
            label: 'API Key',
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.searchServicesAddDialogApiKeyRequired;
              }
              return null;
            },
          ),
        ];
      case 'searxng':
        return [
          _buildTextField(
            key: 'url',
            label: l10n.searchServicesAddDialogInstanceUrl,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.searchServicesAddDialogUrlRequired;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildTextField(
            key: 'engines',
            label: l10n.searchServicesAddDialogEnginesOptional,
            hint: 'google,duckduckgo',
          ),
          const SizedBox(height: 12),
          _buildTextField(
            key: 'language',
            label: l10n.searchServicesAddDialogLanguageOptional,
            hint: 'en-US',
          ),
          const SizedBox(height: 12),
          _buildTextField(
            key: 'username',
            label: l10n.searchServicesAddDialogUsernameOptional,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            key: 'password',
            label: l10n.searchServicesAddDialogPasswordOptional,
            obscureText: true,
          ),
        ];
      default:
        return [];
    }
  }

  SearchServiceOptions _createService() {
    final uuid = Uuid();
    final id = uuid.v4().substring(0, 8);
    
    switch (_selectedType) {
      case 'bing_local':
        return BingLocalOptions(id: id);
      case 'tavily':
        return TavilyOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'exa':
        return ExaOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'zhipu':
        return ZhipuOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'searxng':
        return SearXNGOptions(
          id: id,
          url: _controllers['url']!.text,
          engines: _controllers['engines']!.text,
          language: _controllers['language']!.text,
          username: _controllers['username']!.text,
          password: _controllers['password']!.text,
        );
      case 'linkup':
        return LinkUpOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'brave':
        return BraveOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'metaso':
        return MetasoOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'jina':
        return JinaOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'ollama':
        return OllamaOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'perplexity':
        return PerplexityOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'bocha':
        return BochaOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      default:
        return BingLocalOptions(id: id);
    }
  }
}

// Edit Service Bottom Sheet (iOS style)
class _EditServiceSheet extends StatefulWidget {
  final SearchServiceOptions service;
  final Function(SearchServiceOptions) onSave;

  const _EditServiceSheet({
    required this.service,
    required this.onSave,
  });

  @override
  State<_EditServiceSheet> createState() => _EditServiceSheetState();
}

class _EditServiceSheetState extends State<_EditServiceSheet> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final service = widget.service;
    if (service is TavilyOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKeys.isNotEmpty ? service.apiKeys.first.key : '');
    } else if (service is ExaOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKeys.isNotEmpty ? service.apiKeys.first.key : '');
    } else if (service is ZhipuOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKeys.isNotEmpty ? service.apiKeys.first.key : '');
    } else if (service is SearXNGOptions) {
      _controllers['url'] = TextEditingController(text: service.url);
      _controllers['engines'] = TextEditingController(text: service.engines);
      _controllers['language'] = TextEditingController(text: service.language);
      _controllers['username'] = TextEditingController(text: service.username);
      _controllers['password'] = TextEditingController(text: service.password);
    } else if (service is LinkUpOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKeys.isNotEmpty ? service.apiKeys.first.key : '');
    } else if (service is BraveOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKeys.isNotEmpty ? service.apiKeys.first.key : '');
    } else if (service is MetasoOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKeys.isNotEmpty ? service.apiKeys.first.key : '');
    } else if (service is OllamaOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKeys.isNotEmpty ? service.apiKeys.first.key : '');
    } else if (service is JinaOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKeys.isNotEmpty ? service.apiKeys.first.key : '');
    } else if (service is PerplexityOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKeys.isNotEmpty ? service.apiKeys.first.key : '');
    } else if (service is BochaOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKeys.isNotEmpty ? service.apiKeys.first.key : '');
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final searchService = SearchService.getService(widget.service);
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999)),
              ),
            ),
            // Title (match Add sheet style: centered name)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Center(
                child: Text(
                  searchService.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _buildFields(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final updated = _updateService();
                    widget.onSave(updated);
                    Navigator.of(context).pop();
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(l10n.searchServicesEditDialogSave, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFields() {
    final l10n = AppLocalizations.of(context)!;
    final service = widget.service;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget _buildTextField({
      required String key,
      required String label,
      String? hint,
      bool obscureText = false,
      String? Function(String?)? validator,
    }) {
      _controllers[key] = _controllers[key] ?? TextEditingController();
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextFormField(
          controller: _controllers[key],
          obscureText: obscureText,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: validator,
        ),
      );
    }

    if (service is BingLocalOptions) {
      return [Text(l10n.searchServicesEditDialogBingLocalNoConfig)];
    } else if (service is TavilyOptions ||
        service is ExaOptions ||
        service is ZhipuOptions ||
        service is LinkUpOptions ||
        service is BraveOptions ||
        service is MetasoOptions ||
        service is OllamaOptions ||
        service is JinaOptions ||
        service is BochaOptions) {
      return [
        _buildTextField(
          key: 'apiKey',
          label: 'API Key',
          validator: (value) {
            if (value == null || value.isEmpty) {
              return l10n.searchServicesEditDialogApiKeyRequired;
            }
            return null;
          },
        ),
      ];
    } else if (service is SearXNGOptions) {
      return [
        _buildTextField(
          key: 'url',
          label: l10n.searchServicesEditDialogInstanceUrl,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return l10n.searchServicesEditDialogUrlRequired;
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        _buildTextField(
          key: 'engines',
          label: l10n.searchServicesEditDialogEnginesOptional,
          hint: 'google,duckduckgo',
        ),
        const SizedBox(height: 12),
        _buildTextField(
          key: 'language',
          label: l10n.searchServicesEditDialogLanguageOptional,
          hint: 'en-US',
        ),
        const SizedBox(height: 12),
        _buildTextField(
          key: 'username',
          label: l10n.searchServicesEditDialogUsernameOptional,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          key: 'password',
          label: l10n.searchServicesEditDialogPasswordOptional,
          obscureText: true,
        ),
      ];
    }

    return [];
  }

  SearchServiceOptions _updateService() {
    final service = widget.service;
    
    if (service is TavilyOptions) {
      return TavilyOptions.single(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is ExaOptions) {
      return ExaOptions.single(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is ZhipuOptions) {
      return ZhipuOptions.single(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is SearXNGOptions) {
      return SearXNGOptions(
        id: service.id,
        url: _controllers['url']!.text,
        engines: _controllers['engines']!.text,
        language: _controllers['language']!.text,
        username: _controllers['username']!.text,
        password: _controllers['password']!.text,
      );
    } else if (service is LinkUpOptions) {
      return LinkUpOptions.single(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is BraveOptions) {
      return BraveOptions.single(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is MetasoOptions) {
      return MetasoOptions.single(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is OllamaOptions) {
      return OllamaOptions.single(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is JinaOptions) {
      return JinaOptions.single(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is PerplexityOptions) {
      return PerplexityOptions.single(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
        country: service.country,
        searchDomainFilter: service.searchDomainFilter,
        maxTokensPerPage: service.maxTokensPerPage,
      );
    } else if (service is BochaOptions) {
      return BochaOptions.single(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
        freshness: service.freshness,
        summary: service.summary,
        include: service.include,
        exclude: service.exclude,
      );
    }
    
    return service;
  }
}

class _EditServiceDialog extends StatefulWidget {
  const _EditServiceDialog({required this.service, required this.onSave});
  final SearchServiceOptions service;
  final Function(SearchServiceOptions) onSave;

  @override
  State<_EditServiceDialog> createState() => _EditServiceDialogState();
}

class _EditServiceDialogState extends State<_EditServiceDialog> {
  late SearchServiceOptions _current;
  final GlobalKey<_GenericServiceEditorState> _genericKey = GlobalKey<_GenericServiceEditorState>();

  @override
  void initState() {
    super.initState();
    _current = widget.service;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMultiKey = _current is TavilyOptions || 
                      _current is ExaOptions || 
                      _current is ZhipuOptions || 
                      _current is LinkUpOptions || 
                      _current is BraveOptions || 
                      _current is MetasoOptions || 
                      _current is OllamaOptions || 
                      _current is JinaOptions || 
                      _current is PerplexityOptions || 
                      _current is BochaOptions;
    final double w = isMultiKey ? 680 : 520;
    final double h = isMultiKey ? 720 : 600;
    final bg = Color.alphaBlend(cs.primary.withOpacity(isDark ? 0.06 : 0.03), cs.surface);

    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: w, height: h),
      child: Material(
        color: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? Colors.white.withOpacity(0.08) : cs.outlineVariant.withOpacity(0.25), width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              color: bg,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          SearchService.getService(_current).name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: isMultiKey
                        ? _MultiKeyEditor(
                            initial: _current,
                            onChanged: (v) => setState(() => _current = v),
                          )
                        : _GenericServiceEditor(key: _genericKey, initial: _current),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          if (!isMultiKey) {
                            final updated = _genericKey.currentState?.buildUpdated();
                            if (updated != null) _current = updated;
                          }
                          widget.onSave(_current);
                          Navigator.of(context).maybePop();
                        },
                        child: const Text('保存'),
                      ),
                    ],
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

class _MultiKeyEditor extends StatefulWidget {
  const _MultiKeyEditor({required this.initial, required this.onChanged});
  final SearchServiceOptions initial;
  final ValueChanged<SearchServiceOptions> onChanged;

  @override
  State<_MultiKeyEditor> createState() => _MultiKeyEditorState();
}

class _MultiKeyEditorState extends State<_MultiKeyEditor> {
  late List<ApiKeyConfig> _keys;
  late LoadBalanceStrategy _strategy;
  int? _editingIndex;
  bool _adding = false;
  final TextEditingController _editKeyController = TextEditingController();
  final TextEditingController _editNameController = TextEditingController();
  final TextEditingController _editLimitController = TextEditingController();
  int _editPriority = 5;
  bool _editUnlimited = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    
    // 获取 apiKeys 和 strategy
    if (initial is TavilyOptions) {
      _keys = initial.apiKeys.map((k) => k).toList();
      _strategy = initial.strategy;
    } else if (initial is ExaOptions) {
      _keys = initial.apiKeys.map((k) => k).toList();
      _strategy = initial.strategy;
    } else if (initial is ZhipuOptions) {
      _keys = initial.apiKeys.map((k) => k).toList();
      _strategy = initial.strategy;
    } else if (initial is LinkUpOptions) {
      _keys = initial.apiKeys.map((k) => k).toList();
      _strategy = initial.strategy;
    } else if (initial is BraveOptions) {
      _keys = initial.apiKeys.map((k) => k).toList();
      _strategy = initial.strategy;
    } else if (initial is MetasoOptions) {
      _keys = initial.apiKeys.map((k) => k).toList();
      _strategy = initial.strategy;
    } else if (initial is OllamaOptions) {
      _keys = initial.apiKeys.map((k) => k).toList();
      _strategy = initial.strategy;
    } else if (initial is JinaOptions) {
      _keys = initial.apiKeys.map((k) => k).toList();
      _strategy = initial.strategy;
    } else if (initial is PerplexityOptions) {
      _keys = initial.apiKeys.map((k) => k).toList();
      _strategy = initial.strategy;
    } else if (initial is BochaOptions) {
      _keys = initial.apiKeys.map((k) => k).toList();
      _strategy = initial.strategy;
    } else {
      // 默认值（不应该发生）
      _keys = [];
      _strategy = LoadBalanceStrategy.roundRobin;
    }
  }

  void _emit() {
    final initial = widget.initial;
    SearchServiceOptions updated;
    
    if (initial is TavilyOptions) {
      updated = TavilyOptions(id: initial.id, apiKeys: _keys, strategy: _strategy);
    } else if (initial is ExaOptions) {
      updated = ExaOptions(id: initial.id, apiKeys: _keys, strategy: _strategy);
    } else if (initial is ZhipuOptions) {
      updated = ZhipuOptions(id: initial.id, apiKeys: _keys, strategy: _strategy);
    } else if (initial is LinkUpOptions) {
      updated = LinkUpOptions(id: initial.id, apiKeys: _keys, strategy: _strategy);
    } else if (initial is BraveOptions) {
      updated = BraveOptions(id: initial.id, apiKeys: _keys, strategy: _strategy);
    } else if (initial is MetasoOptions) {
      updated = MetasoOptions(id: initial.id, apiKeys: _keys, strategy: _strategy);
    } else if (initial is OllamaOptions) {
      updated = OllamaOptions(id: initial.id, apiKeys: _keys, strategy: _strategy);
    } else if (initial is JinaOptions) {
      updated = JinaOptions(id: initial.id, apiKeys: _keys, strategy: _strategy);
    } else if (initial is PerplexityOptions) {
      updated = PerplexityOptions(
        id: initial.id, 
        apiKeys: _keys, 
        strategy: _strategy,
        country: initial.country,
        searchDomainFilter: initial.searchDomainFilter,
        maxTokensPerPage: initial.maxTokensPerPage,
      );
    } else if (initial is BochaOptions) {
      updated = BochaOptions(
        id: initial.id, 
        apiKeys: _keys, 
        strategy: _strategy,
        freshness: initial.freshness,
        summary: initial.summary,
        include: initial.include,
        exclude: initial.exclude,
      );
    } else {
      return; // Should not happen
    }
    
    widget.onChanged(updated);
  }

  @override
  void dispose() {
    _editKeyController.dispose();
    _editNameController.dispose();
    _editLimitController.dispose();
    super.dispose();
  }

  void _beginEdit(int index) {
    final k = _keys[index];
    _editingIndex = index;
    _adding = false;
    _editKeyController.text = k.key;
    _editNameController.text = k.name ?? '';
    _editLimitController.text = k.maxRequestsPerMinute?.toString() ?? '';
    _editUnlimited = k.maxRequestsPerMinute == null || k.maxRequestsPerMinute == 0;
    _editPriority = k.priority;
    setState(() {});
  }

  void _beginAdd() {
    _editingIndex = -1;
    _adding = true;
    _editKeyController.text = '';
    _editNameController.text = '';
    _editLimitController.text = '';
    _editUnlimited = true;
    _editPriority = 5;
    setState(() {});
  }

  void _cancelEdit() {
    _editingIndex = null;
    _adding = false;
    setState(() {});
  }

  void _commitEdit() {
    final key = _editKeyController.text.trim();
    if (key.isEmpty) return;
    final rpmText = _editLimitController.text.trim();
    final rpm = (!_editUnlimited && rpmText.isNotEmpty) ? int.tryParse(rpmText) : null;
    final clampedPri = _editPriority.clamp(1, 10);
    if (_adding) {
      final cfg = ApiKeyConfig.create(key).copyWith(
        name: _editNameController.text.trim().isEmpty ? null : _editNameController.text.trim(),
        maxRequestsPerMinute: (rpm == null || rpm <= 0) ? null : rpm,
        priority: clampedPri,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      setState(() {
        _keys.add(cfg);
        _emit();
        _cancelEdit();
      });
    } else if (_editingIndex != null && _editingIndex! >= 0 && _editingIndex! < _keys.length) {
      final old = _keys[_editingIndex!];
      final cfg = old.copyWith(
        key: key,
        name: _editNameController.text.trim().isEmpty ? null : _editNameController.text.trim(),
        maxRequestsPerMinute: (rpm == null || rpm <= 0) ? null : rpm,
        priority: clampedPri,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      setState(() {
        _keys[_editingIndex!] = cfg;
        _emit();
        _cancelEdit();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<LoadBalanceStrategy>(
          segments: const <ButtonSegment<LoadBalanceStrategy>>[
            ButtonSegment(
              value: LoadBalanceStrategy.roundRobin,
              icon: Icon(Lucide.RotateCw, size: 16),
              label: Text('轮询'),
            ),
            ButtonSegment(
              value: LoadBalanceStrategy.random,
              icon: Icon(Lucide.Shuffle, size: 16),
              label: Text('随机'),
            ),
            ButtonSegment(
              value: LoadBalanceStrategy.leastUsed,
              icon: Icon(Lucide.ListOrdered, size: 16),
              label: Text('最少使用'),
            ),
            ButtonSegment(
              value: LoadBalanceStrategy.priority,
              icon: Icon(Lucide.Sparkles, size: 16),
              label: Text('优先级'),
            ),
          ],
          selected: <LoadBalanceStrategy>{_strategy},
          onSelectionChanged: (s) {
            if (s.isNotEmpty) {
              setState(() => _strategy = s.first);
              _emit();
            }
          },
          showSelectedIcon: false,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _keys.length + (_adding ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (_adding && i == _keys.length) {
                return _newKeyCard(cs, isDark);
              }
              return _keyCard(context, i, cs, isDark);
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _beginAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加 Key'),
            ),
            const Spacer(),
            Text('${_keys.length} 个 Key', style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
          ],
        ),
      ],
    );
  }

  Widget _keyCard(BuildContext context, int index, ColorScheme cs, bool isDark) {
    final k = _keys[index];
    final bg = Color.alphaBlend(cs.primary.withOpacity(isDark ? 0.05 : 0.03), cs.surface);
    final border = cs.outlineVariant.withOpacity(isDark ? 0.16 : 0.18);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch(value: k.isEnabled, onChanged: (v) {
                setState(() {
                  _keys[index] = k.copyWith(isEnabled: v, updatedAt: DateTime.now().millisecondsSinceEpoch);
                  _emit();
                });
              }),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k.name ?? 'API Key ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Lucide.Activity, size: 14, color: cs.primary),
                        const SizedBox(width: 6),
                        Text('已使用 ${k.usage.totalRequests}', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                        const SizedBox(width: 12),
                        Icon(k.maxRequestsPerMinute == null ? Lucide.Repeat : Lucide.Thermometer, size: 14, color: cs.primary),
                        const SizedBox(width: 6),
                        Text(k.maxRequestsPerMinute == null ? '无限制' : '限流 ${k.maxRequestsPerMinute}/分', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                      ],
                    ),
                  ],
                ),
              ),
              if (_editingIndex != index) ...[
                IconButton(
                  onPressed: _testingKeys.contains(index) ? null : () => _testSingleKey(index), 
                  icon: _testingKeys.contains(index) 
                    ? SizedBox(
                        width: 18, 
                        height: 18, 
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                        ),
                      )
                    : const Icon(Lucide.HeartPulse, size: 18),
                  tooltip: _testingKeys.contains(index) ? '正在测试...' : '测试连接',
                ),
                IconButton(onPressed: () => _beginEdit(index), icon: const Icon(Icons.edit, size: 18))
              ] else
                const SizedBox.shrink(),
              IconButton(onPressed: () => _deleteKey(index), icon: const Icon(Icons.delete, size: 18)),
            ],
          ),
          if (_editingIndex == index) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _editNameController,
              decoration: const InputDecoration(labelText: '名称（可选）', hintText: '例如：google / 备用Key'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _editKeyController,
              decoration: const InputDecoration(labelText: 'API Key'),
            ),
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('无限制')),
                ButtonSegment(value: 1, label: Text('自定义')),
              ],
              selected: {_editUnlimited ? 0 : 1},
              onSelectionChanged: (s) {
                if (s.isNotEmpty) setState(() => _editUnlimited = s.first == 0);
              },
              showSelectedIcon: false,
            ),
            const SizedBox(height: 8),
            if (!_editUnlimited)
              TextField(
                controller: _editLimitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '每分钟限流',
                  hintText: '例如 60',
                  helperText: '留空或 0 表示无限制。示例：60 表示每分钟最多 60 次请求。',
                  suffixText: '/分',
                ),
              ),
            if (!_editUnlimited) const SizedBox(height: 10),
            Row(
              children: [
                const Text('优先级'),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '$_editPriority',
                    value: _editPriority.toDouble(),
                    onChanged: (v) => setState(() => _editPriority = v.round().clamp(1, 10)),
                  ),
                ),
                Text('$_editPriority'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _cancelEdit, child: const Text('取消')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _commitEdit, child: const Text('保存')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _newKeyCard(ColorScheme cs, bool isDark) {
    final bg = Color.alphaBlend(cs.primary.withOpacity(isDark ? 0.05 : 0.03), cs.surface);
    final border = cs.outlineVariant.withOpacity(isDark ? 0.16 : 0.18);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('添加新的 API Key', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: _editNameController,
            decoration: const InputDecoration(labelText: '名称（可选）', hintText: '例如：google / 备用Key'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _editKeyController,
            decoration: const InputDecoration(labelText: 'API Key'),
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('无限制')),
              ButtonSegment(value: 1, label: Text('自定义')),
            ],
            selected: {_editUnlimited ? 0 : 1},
            onSelectionChanged: (s) {
              if (s.isNotEmpty) setState(() => _editUnlimited = s.first == 0);
            },
            showSelectedIcon: false,
          ),
          const SizedBox(height: 8),
          if (!_editUnlimited)
            TextField(
              controller: _editLimitController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每分钟限流',
                hintText: '例如 60',
                helperText: '留空或 0 表示无限制。示例：60 表示每分钟最多 60 次请求。',
                suffixText: '/分',
              ),
            ),
          if (!_editUnlimited) const SizedBox(height: 10),
          Row(
            children: [
              const Text('优先级'),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '$_editPriority',
                  value: _editPriority.toDouble(),
                  onChanged: (v) => setState(() => _editPriority = v.round().clamp(1, 10)),
                ),
              ),
              Text('$_editPriority'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _cancelEdit, child: const Text('取消')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _commitEdit, child: const Text('添加')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showKeyDialog(BuildContext context, int? editIndex) async {
    final keyController = TextEditingController();
    final nameController = TextEditingController();
    final limitController = TextEditingController();
    final priorityController = TextEditingController(text: '5');
    if (editIndex != null) {
      final c = _keys[editIndex];
      keyController.text = c.key;
      nameController.text = c.name ?? '';
      limitController.text = c.maxRequestsPerMinute?.toString() ?? '';
      priorityController.text = c.priority.toString();
    }
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(editIndex == null ? '添加 API Key' : '编辑 API Key'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: keyController, decoration: const InputDecoration(labelText: 'API Key')),
                const SizedBox(height: 12),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: '名称（可选）')),
                const SizedBox(height: 12),
                TextField(controller: limitController, decoration: const InputDecoration(labelText: '每分钟限流（可选）'), keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                TextField(
                  controller: priorityController,
                  decoration: const InputDecoration(labelText: '优先级 1-10（可选，默认5，数字越小优先级越高）'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final key = keyController.text.trim();
                if (key.isEmpty) return;
                final pr = int.tryParse(priorityController.text.trim());
                final clampedPri = pr == null ? null : pr.clamp(1, 10) as int;
                final cfg = (editIndex == null ? ApiKeyConfig.create(key) : _keys[editIndex!])
                    .copyWith(
                      key: key,
                      name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
                      maxRequestsPerMinute: limitController.text.trim().isEmpty ? null : int.tryParse(limitController.text.trim()),
                      priority: clampedPri ?? (editIndex == null ? 5 : _keys[editIndex!].priority),
                      updatedAt: DateTime.now().millisecondsSinceEpoch,
                    );
                setState(() {
                  if (editIndex == null) {
                    _keys.add(cfg);
                  } else {
                    _keys[editIndex!] = cfg;
                  }
                  _emit();
                });
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  void _deleteKey(int index) {
    if (_keys.length <= 1) return;
    setState(() {
      _keys.removeAt(index);
      _emit();
    });
  }

  // 添加测试状态跟踪
  final Set<int> _testingKeys = <int>{};

  Future<void> _testSingleKey(int index) async {
    if (index < 0 || index >= _keys.length || _testingKeys.contains(index)) return;
    final k = _keys[index];
    final initial = widget.initial;
    
    // 标记正在测试
    setState(() {
      _testingKeys.add(index);
    });
    
    // 显示测试开始的消息
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('开始测试 Key "${k.name ?? k.key.substring(0, 8)}..."'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
    
    try {
      // 创建一个临时的服务配置，只使用这一个Key
      SearchServiceOptions testConfig;
      if (initial is TavilyOptions) {
        testConfig = TavilyOptions(id: initial.id, apiKeys: [k], strategy: LoadBalanceStrategy.roundRobin);
      } else if (initial is ExaOptions) {
        testConfig = ExaOptions(id: initial.id, apiKeys: [k], strategy: LoadBalanceStrategy.roundRobin);
      } else if (initial is ZhipuOptions) {
        testConfig = ZhipuOptions(id: initial.id, apiKeys: [k], strategy: LoadBalanceStrategy.roundRobin);
      } else if (initial is LinkUpOptions) {
        testConfig = LinkUpOptions(id: initial.id, apiKeys: [k], strategy: LoadBalanceStrategy.roundRobin);
      } else if (initial is BraveOptions) {
        testConfig = BraveOptions(id: initial.id, apiKeys: [k], strategy: LoadBalanceStrategy.roundRobin);
      } else if (initial is MetasoOptions) {
        testConfig = MetasoOptions(id: initial.id, apiKeys: [k], strategy: LoadBalanceStrategy.roundRobin);
      } else if (initial is OllamaOptions) {
        testConfig = OllamaOptions(id: initial.id, apiKeys: [k], strategy: LoadBalanceStrategy.roundRobin);
      } else if (initial is JinaOptions) {
        testConfig = JinaOptions(id: initial.id, apiKeys: [k], strategy: LoadBalanceStrategy.roundRobin);
      } else if (initial is PerplexityOptions) {
        testConfig = PerplexityOptions(
          id: initial.id, 
          apiKeys: [k], 
          strategy: LoadBalanceStrategy.roundRobin,
          country: initial.country,
          searchDomainFilter: initial.searchDomainFilter,
          maxTokensPerPage: initial.maxTokensPerPage,
        );
      } else if (initial is BochaOptions) {
        testConfig = BochaOptions(
          id: initial.id, 
          apiKeys: [k], 
          strategy: LoadBalanceStrategy.roundRobin,
          freshness: initial.freshness,
          summary: initial.summary,
          include: initial.include,
          exclude: initial.exclude,
        );
      } else {
        return; // 不支持的服务类型
      }
      
      // 执行真实的搜索测试
      final svc = SearchService.getService(testConfig);
      final results = await svc.search(
        query: 'test connectivity',
        commonOptions: const SearchCommonOptions(
          resultSize: 1, 
          timeout: 10000, // 10秒超时
        ),
        serviceOptions: testConfig,
      );
      
      // 检查是否真的得到了结果
      if (results.items.isEmpty) {
        throw Exception('API 返回了空结果');
      }
      
      // 测试成功 - 更新Key状态
      setState(() {
        _keys[index] = k.copyWith(
          status: ApiKeyStatus.active,
          usage: k.usage.copyWith(
            totalRequests: k.usage.totalRequests + 1,
            successfulRequests: k.usage.successfulRequests + 1,
            lastUsed: DateTime.now().millisecondsSinceEpoch,
            consecutiveFailures: 0,
          ),
          lastError: null,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        _emit();
      });
      
      // 显示成功弹窗
      if (mounted) {
        await _showTestResultDialog(
          context,
          success: true,
          keyName: k.name ?? k.key.substring(0, 8),
          message: '连接测试成功！\n\n✅ API Key 有效\n✅ 网络连接正常\n✅ 返回了搜索结果',
          details: 'Key: ${k.key.substring(0, 12)}***\n查询: test connectivity\n结果数量: ${results.items.length}',
        );
      }
    } catch (e) {
      // 测试失败 - 更新Key状态
      setState(() {
        _keys[index] = k.copyWith(
          status: ApiKeyStatus.error,
          usage: k.usage.copyWith(
            totalRequests: k.usage.totalRequests + 1,
            failedRequests: k.usage.failedRequests + 1,
            consecutiveFailures: k.usage.consecutiveFailures + 1,
            lastUsed: DateTime.now().millisecondsSinceEpoch,
          ),
          lastError: e.toString(),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        _emit();
      });
      
      // 显示失败弹窗
      if (mounted) {
        await _showTestResultDialog(
          context,
          success: false,
          keyName: k.name ?? k.key.substring(0, 8),
          message: '连接测试失败',
          details: 'Key: ${k.key.substring(0, 12)}***\n错误信息: $e',
        );
      }
    } finally {
      // 清除测试状态
      if (mounted) {
        setState(() {
          _testingKeys.remove(index);
        });
      }
    }
  }

  Future<void> _showTestResultDialog(
    BuildContext context, {
    required bool success,
    required String keyName,
    required String message,
    required String details,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // 桌面端：使用Dialog
      return showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 400),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题行
                  Row(
                    children: [
                      Icon(
                        success ? Icons.check_circle : Icons.error,
                        color: success ? Colors.green : Colors.red,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Key "$keyName"',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // 消息内容
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      color: success ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // 详细信息（可选择和复制）
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: cs.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    child: SelectableText(
                      details,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: cs.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // 按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          // 复制详细信息到剪贴板
                          Clipboard.setData(ClipboardData(text: details));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('详细信息已复制到剪贴板'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Text('复制详情'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    } else {
      // 移动端：使用BottomSheet
      return showModalBottomSheet<void>(
        context: context,
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (BuildContext context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 拖拽条
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 标题行
                  Row(
                    children: [
                      Icon(
                        success ? Icons.check_circle : Icons.error,
                        color: success ? Colors.green : Colors.red,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Key "$keyName"',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // 消息内容
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      color: success ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // 详细信息（可选择和复制）
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: cs.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    child: SelectableText(
                      details,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: cs.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // 按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          // 复制详细信息到剪贴板
                          Clipboard.setData(ClipboardData(text: details));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('详细信息已复制到剪贴板'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Text('复制详情'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }
}

class _GenericServiceEditor extends StatefulWidget {
  const _GenericServiceEditor({super.key, required this.initial});
  final SearchServiceOptions initial;

  @override
  State<_GenericServiceEditor> createState() => _GenericServiceEditorState();
}

class _GenericServiceEditorState extends State<_GenericServiceEditor> {
  final Map<String, TextEditingController> _c = {};

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    // 这些服务现在使用多Key，不应该在这里处理
    if (s is SearXNGOptions) {
      _c['url'] = TextEditingController(text: s.url);
      _c['engines'] = TextEditingController(text: s.engines);
      _c['language'] = TextEditingController(text: s.language);
      _c['username'] = TextEditingController(text: s.username);
      _c['password'] = TextEditingController(text: s.password);
    }
  }

  @override
  void dispose() {
    for (final v in _c.values) v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.initial;

    Widget field(String k, String label, {bool obscure = false, String? hint}) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _c.putIfAbsent(k, () => TextEditingController()),
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        );

    if (s is SearXNGOptions) {
      return SingleChildScrollView(
        child: Column(
          children: [
            field('url', '实例地址'),
            field('engines', '引擎（可选）', hint: 'google,duckduckgo'),
            field('language', '语言（可选）', hint: 'en-US'),
            field('username', '用户名（可选）'),
            field('password', '密码（可选）', obscure: true),
          ],
        ),
      );
    }

    if (s is BingLocalOptions) {
      return Center(child: Text('无额外配置', style: TextStyle(color: cs.onSurface.withOpacity(0.8))));
    }

    // 所有单Key服务都已转换为多Key，这里应该不会执行到
    return const Center(child: Text('此服务应使用多Key编辑器'));
  }

  SearchServiceOptions? buildUpdated() {
    final s = widget.initial;
    // 所有这些服务现在都使用多Key，应该由MultiKeyEditor处理
    if (s is SearXNGOptions) {
      return SearXNGOptions(
        id: s.id,
        url: _c['url']!.text,
        engines: _c['engines']!.text,
        language: _c['language']!.text,
        username: _c['username']!.text,
        password: _c['password']!.text,
      );
    }
    if (s is BingLocalOptions) return s;
    return null;
  }
}

// Service Icon Widget - Uses BrandAssets
class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({
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

// --- iOS-style tactile + section helpers (local copy to avoid ripple) ---

class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.size = 22,
    this.haptics = true,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final double size;
  final bool haptics;
  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final pressColor = base.withOpacity(0.7);
    final icon = Icon(widget.icon, size: widget.size, color: _pressed ? pressColor : base, semanticLabel: widget.semanticLabel);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () { if (widget.haptics) Haptics.light(); widget.onTap(); },
        onLongPress: widget.onLongPress == null ? null : () { if (widget.haptics) Haptics.light(); widget.onLongPress!.call(); },
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: icon),
      ),
    );
  }
}

class _TactileRow extends StatefulWidget {
  const _TactileRow({required this.builder, this.onTap, this.pressedScale = 1.00, this.haptics = true});
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptics;
  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;
  void _setPressed(bool v) { if (_pressed != v) setState(() => _pressed = v); }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null ? null : () {
        if (widget.haptics && context.read<SettingsProvider>().hapticsOnListItemTap) Haptics.soft();
        widget.onTap!.call();
      },
      child: widget.builder(_pressed),
    );
  }
}

class _AnimatedPressColor extends StatelessWidget {
  const _AnimatedPressColor({required this.pressed, required this.base, required this.builder});
  final bool pressed;
  final Color base;
  final Widget Function(Color color) builder;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final target = pressed ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base) : base;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => builder(color ?? base),
    );
  }
}

Widget _iosSectionCard({required List<Widget> children}) {
  return Builder(builder: (context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final Color bg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06), width: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children),
      ),
    );
  });
}

Widget _iosDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(height: 6, thickness: 0.6, indent: 54, endIndent: 12, color: cs.outlineVariant.withOpacity(0.18));
}

// Sheet helpers (align with settings page)
Widget _sheetOption(
  BuildContext context, {
  required String label,
  required VoidCallback onTap,
  IconData? icon,
  Widget? leading,
  bool bgOnPress = true,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return _TactileRow(
    pressedScale: 1.00,
    haptics: true,
    onTap: onTap,
    builder: (pressed) {
      final base = cs.onSurface;
      final bgTarget = (bgOnPress && pressed)
          ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05))
          : Colors.transparent;
      return _AnimatedPressColor(
        pressed: pressed,
        base: base,
        builder: (c) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            color: bgTarget,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 36,
                  child: Center(child: leading ?? Icon(icon ?? Lucide.ChevronRight, size: 20, color: c)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c))),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _sheetDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(height: 1, thickness: 0.6, indent: 56, endIndent: 16, color: cs.outlineVariant.withOpacity(0.18));
}

class _SmallTactileIcon extends StatefulWidget {
  const _SmallTactileIcon({required this.icon, required this.onTap, this.enabled = true});
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  @override
  State<_SmallTactileIcon> createState() => _SmallTactileIconState();
}

class _SmallTactileIconState extends State<_SmallTactileIcon> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = widget.enabled ? cs.onSurface.withOpacity(_pressed ? 0.6 : 0.9) : cs.onSurface.withOpacity(0.3);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.enabled
          ? () {
              Haptics.soft();
              widget.onTap();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Icon(widget.icon, size: 18, color: c),
      ),
    );
  }
}

// 桌面端添加服务Dialog
class _AddServiceDialog extends StatefulWidget {
  final Function(SearchServiceOptions) onAdd;

  const _AddServiceDialog({required this.onAdd});

  @override
  State<_AddServiceDialog> createState() => _AddServiceDialogState();
}

class _AddServiceDialogState extends State<_AddServiceDialog> {
  String? _selectedType;
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedType == null ? l10n.searchServicesAddDialogTitle : _getServiceName(_selectedType!),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            Divider(height: 1, color: cs.outlineVariant.withOpacity(0.2)),
            
            // 内容区域
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
                child: _selectedType == null
                    ? _buildServiceTypeList()
                    : _buildFormView(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceTypeList() {
    final l10n = AppLocalizations.of(context)!;
    final services = [
      {'type': 'bing_local', 'name': l10n.searchServiceNameBingLocal},
      {'type': 'tavily', 'name': l10n.searchServiceNameTavily},
      {'type': 'exa', 'name': l10n.searchServiceNameExa},
      {'type': 'zhipu', 'name': l10n.searchServiceNameZhipu},
      {'type': 'searxng', 'name': l10n.searchServiceNameSearXNG},
      {'type': 'linkup', 'name': l10n.searchServiceNameLinkUp},
      {'type': 'brave', 'name': l10n.searchServiceNameBrave},
      {'type': 'metaso', 'name': l10n.searchServiceNameMetaso},
      {'type': 'jina', 'name': l10n.searchServiceNameJina},
      {'type': 'ollama', 'name': l10n.searchServiceNameOllama},
      {'type': 'perplexity', 'name': l10n.searchServiceNamePerplexity},
      {'type': 'bocha', 'name': l10n.searchServiceNameBocha},
    ];
    
    return ListView.builder(
      key: const ValueKey('service_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      shrinkWrap: true,
      itemCount: services.length,
      itemBuilder: (context, index) {
        final item = services[index];
        final cs = Theme.of(context).colorScheme;
        
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _selectedType = item['type'] as String);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                _ServiceIcon(type: item['type'] as String, name: item['name'] as String, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item['name'] as String,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                Icon(Lucide.ChevronRight, size: 16, color: cs.onSurface.withOpacity(0.5)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormView() {
    final l10n = AppLocalizations.of(context)!;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 返回按钮
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _selectedType = null),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('返回'),
              ),
            ),
            const SizedBox(height: 12),
            
            // 表单字段
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: _buildFieldsForType(_selectedType!),
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // 按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      final service = _createService();
                      widget.onAdd(service);
                      Navigator.pop(context);
                    }
                  },
                  child: Text(l10n.searchServicesAddDialogAdd),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 其他方法保持与BottomSheet版本相同
  String _getServiceName(String type) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case 'bing_local': return l10n.searchServiceNameBingLocal;
      case 'tavily': return l10n.searchServiceNameTavily;
      case 'exa': return l10n.searchServiceNameExa;
      case 'zhipu': return l10n.searchServiceNameZhipu;
      case 'searxng': return l10n.searchServiceNameSearXNG;
      case 'linkup': return l10n.searchServiceNameLinkUp;
      case 'brave': return l10n.searchServiceNameBrave;
      case 'metaso': return l10n.searchServiceNameMetaso;
      case 'jina': return l10n.searchServiceNameJina;
      case 'ollama': return l10n.searchServiceNameOllama;
      case 'perplexity': return l10n.searchServiceNamePerplexity;
      case 'bocha': return l10n.searchServiceNameBocha;
      default: return '';
    }
  }

  List<Widget> _buildFieldsForType(String type) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Widget _buildTextField({
      required String key,
      required String label,
      String? hint,
      bool obscureText = false,
      String? Function(String?)? validator,
    }) {
      _controllers[key] ??= TextEditingController();
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextFormField(
          controller: _controllers[key],
          obscureText: obscureText,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: validator,
        ),
      );
    }
    
    switch (type) {
      case 'bing_local':
        return [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Lucide.Search, size: 20, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.searchServiceNameBingLocal,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withOpacity(0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ];
      case 'tavily':
      case 'exa':
      case 'zhipu':
      case 'linkup':
      case 'brave':
      case 'metaso':
      case 'jina':
      case 'ollama':
      case 'perplexity':
      case 'bocha':
        return [
          _buildTextField(
            key: 'apiKey',
            label: 'API Key',
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.searchServicesAddDialogApiKeyRequired;
              }
              return null;
            },
          ),
        ];
      case 'searxng':
        return [
          _buildTextField(
            key: 'url',
            label: l10n.searchServicesAddDialogInstanceUrl,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.searchServicesAddDialogUrlRequired;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildTextField(
            key: 'engines',
            label: l10n.searchServicesAddDialogEnginesOptional,
            hint: 'google,duckduckgo',
          ),
          const SizedBox(height: 12),
          _buildTextField(
            key: 'language',
            label: l10n.searchServicesAddDialogLanguageOptional,
            hint: 'en-US',
          ),
          const SizedBox(height: 12),
          _buildTextField(
            key: 'username',
            label: l10n.searchServicesAddDialogUsernameOptional,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            key: 'password',
            label: l10n.searchServicesAddDialogPasswordOptional,
            obscureText: true,
          ),
        ];
      default:
        return [];
    }
  }

  SearchServiceOptions _createService() {
    final uuid = const Uuid();
    final id = uuid.v4().substring(0, 8);
    
    switch (_selectedType) {
      case 'bing_local':
        return BingLocalOptions(id: id);
      case 'tavily':
        return TavilyOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'exa':
        return ExaOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'zhipu':
        return ZhipuOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'searxng':
        return SearXNGOptions(
          id: id,
          url: _controllers['url']!.text,
          engines: _controllers['engines']!.text,
          language: _controllers['language']!.text,
          username: _controllers['username']!.text,
          password: _controllers['password']!.text,
        );
      case 'linkup':
        return LinkUpOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'brave':
        return BraveOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'metaso':
        return MetasoOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'jina':
        return JinaOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'ollama':
        return OllamaOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'perplexity':
        return PerplexityOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'bocha':
        return BochaOptions.single(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      default:
        return BingLocalOptions(id: id);
    }
  }
}

// (removed: now implemented as instance method on state)
