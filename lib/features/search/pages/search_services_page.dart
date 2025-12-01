import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/services/search/search_service.dart';
import '../services/search_service_factory.dart';
import '../services/search_service_names.dart';
import '../widgets/service_form_fields.dart';
import 'key_management_widgets.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/models/api_keys.dart';
import '../../../core/services/api_key_manager.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../core/services/haptics.dart';
import '../../../utils/safe_tooltip.dart';
import '../../../shared/widgets/tactile_widgets.dart';
// Extracted widgets
import '../widgets/service_icon.dart';
import '../widgets/brand_badge.dart';
import '../editors/generic_service_editor.dart';

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
    final isMultiKey = SearchServiceFactory.supportsMultiKey(service);
    final serviceName = SearchService.getService(service).name;
    
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // 桌面端：使用 Dialog
      if (isMultiKey) {
        // 多Key服务使用 KeyManagementDialog（和 Provider 一致）
        showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'key-management',
          barrierColor: Colors.black.withOpacity(0.25),
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (ctx, a1, a2) {
            return KeyManagementDialog(
              service: service,
              serviceName: serviceName,
              onSave: (updated) {
                setState(() {
                  _services[index] = updated;
                });
                _saveChanges();
              },
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
        // 非多Key服务使用原有的 _EditServiceDialog
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
      }
    } else {
      // 移动端：使用 Sheet
      final cs = Theme.of(context).colorScheme;
      // 只有 BingLocal、SearXNG、DuckDuckGo 使用旧的编辑界面，其他都用多Key管理
      final useSimpleEditor = service is BingLocalOptions || 
                              service is SearXNGOptions || 
                              service is DuckDuckGoOptions;
      if (!useSimpleEditor) {
        // 多Key服务使用 KeyManagementSheet（和 Provider 一致）
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => KeyManagementSheet(
            service: service,
            serviceName: serviceName,
            onSave: (updated) {
              setState(() {
                _services[index] = updated;
              });
              _saveChanges();
            },
          ),
        );
      } else {
        // 非多Key服务使用原有的 _EditServiceSheet
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
                  child: SharedTactileIconButton(
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
          child: SharedTactileIconButton(
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
            child: SharedTactileIconButton(
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
      SharedTactileRow(
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
      SharedTactileRow(
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
    return SharedTactileRow(
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
                    SizedBox(width: 36, child: Center(child: BrandBadge.forService(s, size: 22))),
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
                          child: SharedTactileIconButton(
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
    final types = SearchServiceFactory.allTypes;
    return ListView.builder(
      key: const ValueKey('service_list'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shrinkWrap: true,
      itemCount: types.length,
      itemBuilder: (context, index) {
        final type = types[index];
        final name = getSearchServiceName(type, l10n);
        return Column(children: [
          _sheetOption(
            context,
            icon: Lucide.Globe,
            label: name,
            leading: ServiceIcon(type: type, name: name, size: 36),
            bgOnPress: false,
            onTap: () {
              setState(() => _selectedType = type);
            },
          ),
          if (index != types.length - 1) _sheetDivider(context),
        ]);
      },
    );
  }

  String _getServiceName(String type) => getSearchServiceName(type, AppLocalizations.of(context)!);

  Widget _buildFormView() {
    final l10n = AppLocalizations.of(context)!;
    
    return SingleChildScrollView(
      key: const ValueKey('form_view'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            ServiceFormFields(type: _selectedType!, controllers: _controllers),
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

  SearchServiceOptions _createService() {
    return SearchServiceFactory.create(
      type: _selectedType!,
      apiKey: _controllers['apiKey']?.text,
      url: _controllers['url']?.text,
      engines: _controllers['engines']?.text,
      language: _controllers['language']?.text,
      username: _controllers['username']?.text,
      password: _controllers['password']?.text,
      region: _controllers['region']?.text,
    );
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
  late SearchServiceOptions _current;
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final GlobalKey<GenericServiceEditorState> _genericKey = GlobalKey<GenericServiceEditorState>();

  @override
  void initState() {
    super.initState();
    _current = widget.service;
    _initControllers();
  }

  void _initControllers() {
    final service = widget.service;
    if (service is SearXNGOptions) {
      _controllers['url'] = TextEditingController(text: service.url);
      _controllers['engines'] = TextEditingController(text: service.engines);
      _controllers['language'] = TextEditingController(text: service.language);
      _controllers['username'] = TextEditingController(text: service.username);
      _controllers['password'] = TextEditingController(text: service.password);
    } else if (service is DuckDuckGoOptions) {
      _controllers['region'] = TextEditingController(text: service.region);
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
    // 注意：多Key服务现在使用独立的 KeyManagementSheet，此 Widget 只处理非多Key服务

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Center(
                child: Text(
                  searchService.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            // 多Key服务现在使用独立的 KeyManagementSheet，这里只处理非多Key服务
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

    Widget buildTextField({
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
    } else if (service is SearXNGOptions) {
      return [
        buildTextField(
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
        buildTextField(
          key: 'engines',
          label: l10n.searchServicesEditDialogEnginesOptional,
          hint: 'google,duckduckgo',
        ),
        const SizedBox(height: 12),
        buildTextField(
          key: 'language',
          label: l10n.searchServicesEditDialogLanguageOptional,
          hint: 'en-US',
        ),
        const SizedBox(height: 12),
        buildTextField(
          key: 'username',
          label: l10n.searchServicesEditDialogUsernameOptional,
        ),
        const SizedBox(height: 12),
        buildTextField(
          key: 'password',
          label: l10n.searchServicesEditDialogPasswordOptional,
          obscureText: true,
        ),
      ];
    } else if (service is DuckDuckGoOptions) {
      return [
        buildTextField(
          key: 'region',
          label: 'Region (optional)',
          hint: 'wt-wt',
        ),
      ];
    }

    return [];
  }

  SearchServiceOptions _updateService() {
    final service = widget.service;
    if (service is SearXNGOptions) {
      return SearXNGOptions(
        id: service.id,
        url: _controllers['url']!.text,
        engines: _controllers['engines']!.text,
        language: _controllers['language']!.text,
        username: _controllers['username']!.text,
        password: _controllers['password']!.text,
      );
    } else if (service is DuckDuckGoOptions) {
      return DuckDuckGoOptions(
        id: service.id,
        region: _controllers['region']?.text ?? 'wt-wt',
      );
    }
    return service; // Multi-key services handled via _current
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
  final GlobalKey<GenericServiceEditorState> _genericKey = GlobalKey<GenericServiceEditorState>();

  @override
  void initState() {
    super.initState();
    _current = widget.service;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 注意：多Key服务现在使用独立的 KeyManagementDialog，此 Widget 只处理非多Key服务
    const double w = 520;
    const double h = 600;
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
                    child: GenericServiceEditor(key: _genericKey, initial: _current),
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
                          final updated = _genericKey.currentState?.buildUpdated();
                          if (updated != null) _current = updated;
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

// --- iOS-style tactile + section helpers (local copy to avoid ripple) ---

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
  return SharedTactileRow(
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
    final types = SearchServiceFactory.allTypes;

    return ListView.builder(
      key: const ValueKey('service_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      shrinkWrap: true,
      itemCount: types.length,
      itemBuilder: (context, index) {
        final type = types[index];
        final name = getSearchServiceName(type, l10n);
        final cs = Theme.of(context).colorScheme;

        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _selectedType = type);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                ServiceIcon(type: type, name: name, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
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
                child: ServiceFormFields(type: _selectedType!, controllers: _controllers),
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

  String _getServiceName(String type) => getSearchServiceName(type, AppLocalizations.of(context)!);

  SearchServiceOptions _createService() {
    return SearchServiceFactory.create(
      type: _selectedType!,
      apiKey: _controllers['apiKey']?.text,
      url: _controllers['url']?.text,
      engines: _controllers['engines']?.text,
      language: _controllers['language']?.text,
      username: _controllers['username']?.text,
      password: _controllers['password']?.text,
      region: _controllers['region']?.text,
    );
  }
}
