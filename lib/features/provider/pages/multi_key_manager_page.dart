import 'dart:async';
import 'dart:io' show HttpException;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import 'package:flutter/cupertino.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/models/api_keys.dart';
import '../../../core/services/api_key_manager.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../model/widgets/model_select_sheet.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../core/services/haptics.dart';

class MultiKeyManagerPage extends StatefulWidget {
  const MultiKeyManagerPage({super.key, required this.providerKey, required this.providerDisplayName});
  final String providerKey;
  final String providerDisplayName;

  @override
  State<MultiKeyManagerPage> createState() => _MultiKeyManagerPageState();
}

class _MultiKeyManagerPageState extends State<MultiKeyManagerPage> {
  String? _detectModelId;
  bool _detecting = false;
  final Set<String> _hiddenKeyIds = <String>{};
  ApiKeyStatus? _filterStatus;

  String _revealToken(ApiKeyConfig k, int index) => '${k.id}_$index';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fixDuplicateIds();
    });
  }

  void _fixDuplicateIds() {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final rawKeys = cfg.apiKeys ?? const <ApiKeyConfig>[];
    final seenIds = <String>{};
    final apiKeys = <ApiKeyConfig>[];
    bool needsFixing = false;
    int fixCounter = 0;

    for (final key in rawKeys) {
      if (seenIds.add(key.id)) {
        apiKeys.add(key);
      } else {
        print('[MultiKey] WARNING: Duplicate ID "${key.id}" found');
        final ts = DateTime.now().millisecondsSinceEpoch;
        final rnd = (DateTime.now().microsecondsSinceEpoch % 1000000000).toRadixString(36);
        final newId = 'key_${ts}_${rnd}_fix$fixCounter';
        fixCounter++;
        apiKeys.add(key.copyWith(id: newId));
        seenIds.add(newId);
        needsFixing = true;
      }
    }

    if (needsFixing) {
      settings.setProviderConfig(widget.providerKey, cfg.copyWith(apiKeys: apiKeys));
    }
  }

  ApiKeyStatus _getKeyStatus(String keyId) {
    final state = ApiKeyManager().getKeyState(keyId);
    final status = state?.status ?? 'active';
    switch (status) {
      case 'active': return ApiKeyStatus.active;
      case 'disabled': return ApiKeyStatus.disabled;
      case 'error': return ApiKeyStatus.error;
      case 'rateLimited': return ApiKeyStatus.rateLimited;
      default: return ApiKeyStatus.active;
    }
  }

  String? _getKeyError(String keyId) {
    return ApiKeyManager().getKeyState(keyId)?.lastError;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    
    final apiKeys = cfg.apiKeys ?? const <ApiKeyConfig>[];
    final total = apiKeys.length;
    final normal = apiKeys.where((k) {
      final state = ApiKeyManager().getKeyState(k.id);
      return state?.status == 'active' || state?.status == null;
    }).length;
    final errors = apiKeys.where((k) {
      final state = ApiKeyManager().getKeyState(k.id);
      return state?.status == 'error';
    }).length;

    final filteredKeys = _filterStatus == null
        ? apiKeys
        : apiKeys.where((k) => _getKeyStatus(k.id) == _filterStatus).toList();

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.multiKeyPageTitle),
        actions: [
          Tooltip(
            message: l10n.translatePageCopyResult,
            child: _TactileIconButton(
              icon: Lucide.Copy,
              color: cs.onSurface,
              semanticLabel: l10n.translatePageCopyResult,
              onTap: _copyAllKeys,
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Lucide.MoreVertical, color: cs.onSurface),
            tooltip: l10n.providerDetailPageManageSectionTitle,
            onSelected: (v) {
              if (v == 'enable_all') _onEnableAll();
              if (v == 'disable_all') _onDisableAll();
              if (v == 'delete_errors') _onDeleteAllErrorKeys();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'enable_all',
                child: Row(children: [
                  Icon(Lucide.circleDot, size: 18, color: cs.primary),
                  const SizedBox(width: 12),
                  const Text('启用所有'),
                ]),
              ),
              PopupMenuItem(
                value: 'disable_all',
                child: Row(children: [
                  Icon(Lucide.CircleX, size: 18, color: cs.onSurface.withOpacity(0.7)),
                  const SizedBox(width: 12),
                  const Text('禁用所有'),
                ]),
              ),
              PopupMenuItem(
                value: 'delete_errors',
                child: Row(children: [
                  Icon(Lucide.Trash2, size: 18, color: cs.error),
                  const SizedBox(width: 12),
                  Text(l10n.multiKeyPageDeleteErrorsTooltip, style: TextStyle(color: cs.error)),
                ]),
              ),
            ],
          ),
          if (_detecting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
              ),
            )
          else
            Tooltip(
              message: l10n.multiKeyPageDetect,
              child: _TactileIconButton(
                icon: Lucide.HeartPulse,
                color: cs.onSurface,
                semanticLabel: l10n.multiKeyPageDetect,
                onTap: _onDetect,
                onLongPress: _onPickDetectModel,
              ),
            ),
          Tooltip(
            message: l10n.multiKeyPageAdd,
            child: _TactileIconButton(
              icon: Lucide.Plus,
              color: cs.onSurface,
              semanticLabel: l10n.multiKeyPageAdd,
              onTap: _onAddKeys,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(context, total, normal, errors),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _iosSectionCard(children: [
                  _strategyRow(context, cfg),
                ]),
                const SizedBox(height: 12),
                _keysList(context, filteredKeys),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, int total, int normal, int errors) {
    final cs = Theme.of(context).colorScheme;
    
    Widget chip(String label, int count, ApiKeyStatus? status, Color color) {
      final isSelected = _filterStatus == status;
      return FilterChip(
        label: Text('$label ($count)'),
        selected: isSelected,
        onSelected: (_) => setState(() => _filterStatus = isSelected ? null : status),
        backgroundColor: cs.surfaceContainerHighest.withOpacity(0.5),
        selectedColor: color.withOpacity(0.15),
        checkmarkColor: color,
        labelStyle: TextStyle(
          color: isSelected ? color : cs.onSurface,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        visualDensity: VisualDensity.compact,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip('全部', total, null, cs.primary),
            const SizedBox(width: 8),
            chip('正常', normal, ApiKeyStatus.active, Colors.green),
            const SizedBox(width: 8),
            chip('错误', errors, ApiKeyStatus.error, cs.error),
          ],
        ),
      ),
    );
  }

  String _strategyLabel(BuildContext context, LoadBalanceStrategy s) {
    final l10n = AppLocalizations.of(context)!;
    switch (s) {
      case LoadBalanceStrategy.priority:
        return l10n.multiKeyPageStrategyPriority;
      case LoadBalanceStrategy.leastUsed:
        return l10n.multiKeyPageStrategyLeastUsed;
      case LoadBalanceStrategy.random:
        return l10n.multiKeyPageStrategyRandom;
      case LoadBalanceStrategy.roundRobin:
      default:
        return l10n.multiKeyPageStrategyRoundRobin;
    }
  }

  Widget _strategyRow(BuildContext context, ProviderConfig cfg) {
    final cs = Theme.of(context).colorScheme;
    final strategy = cfg.keyManagement?.strategy ?? LoadBalanceStrategy.roundRobin;

    // Desktop: inline dropdown instead of sheet
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final all = LoadBalanceStrategy.values;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.multiKeyPageStrategyTitle,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final s in all)
                      ChoiceChip(
                        label: Text(
                          _strategyLabel(context, s),
                          style: TextStyle(
                            fontSize: 12,
                            color: strategy == s ? cs.onPrimary : cs.onSurface,
                          ),
                        ),
                        selected: strategy == s,
                        selectedColor: cs.primary,
                        backgroundColor: cs.surfaceVariant,
                        shape: StadiumBorder(
                          side: BorderSide(color: cs.outline.withOpacity(0.4)),
                        ),
                        onSelected: (selected) async {
                          if (!selected || s == strategy) return;
                          final settings = context.read<SettingsProvider>();
                          final old = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
                          final km = (old.keyManagement ?? const KeyManagementConfig()).copyWith(strategy: s);
                          await settings.setProviderConfig(widget.providerKey, old.copyWith(keyManagement: km));
                        },
                      ),
                  ],
                ),
              ],
            ),
            if (strategy == LoadBalanceStrategy.priority)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 6),
                child: Text(
                  '💡 优先级规则：数字越小优先级越高（1最高，10最低）',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return _TactileRow(
      pressedScale: 1.00,
      onTap: _showStrategySheet,
      builder: (pressed) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final base = cs.onSurface;
        final target = pressed
            ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base)
            : base;
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: target),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, color, _) {
            final c = color ?? base;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  Expanded(child: Text(AppLocalizations.of(context)!.multiKeyPageStrategyTitle, style: TextStyle(fontSize: 15, color: c))),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _strategyLabel(context, strategy),
                        style: TextStyle(fontSize: 15, color: c),
                      ),
                      const SizedBox(width: 6),
                      Icon(Lucide.ChevronRight, size: 16, color: c),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _keysList(BuildContext context, List<ApiKeyConfig> keys) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    
    if (keys.isEmpty) {
      return _iosSectionCard(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Column(
              children: [
                Icon(Lucide.Search, size: 32, color: cs.onSurface.withOpacity(0.3)),
                const SizedBox(height: 8),
                Text(l10n.multiKeyPageNoKeys, style: TextStyle(color: cs.onSurface.withOpacity(0.5))),
              ],
            ),
          ),
        )
      ]);
    }

    Color statusColor(ApiKeyStatus st) {
      switch (st) {
        case ApiKeyStatus.active:
          return Colors.green;
        case ApiKeyStatus.disabled:
          return cs.onSurface.withOpacity(0.5);
        case ApiKeyStatus.error:
          return cs.error;
        case ApiKeyStatus.rateLimited:
          return Colors.orange;
      }
    }

    String statusText(ApiKeyStatus st) {
      switch (st) {
        case ApiKeyStatus.active:
          return l10n.multiKeyPageStatusActive;
        case ApiKeyStatus.disabled:
          return l10n.multiKeyPageStatusDisabled;
        case ApiKeyStatus.error:
          return l10n.multiKeyPageStatusError;
        case ApiKeyStatus.rateLimited:
          return l10n.multiKeyPageStatusRateLimited;
      }
    }

    final canReorder = _filterStatus == null;

    return _iosSectionCard(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: canReorder
            ? ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: keys.length,
                onReorder: (oldIndex, newIndex) => _onReorderKeys(oldIndex, newIndex, keys),
                itemBuilder: (context, index) {
                  final key = keys[index];
                  return _keyRow(context, key, index, statusColor, statusText, canReorder: true);
                },
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: keys.length,
                itemBuilder: (context, index) => _keyRow(context, keys[index], index, statusColor, statusText, canReorder: false),
              ),
        ),
      ],
    );
  }

  Future<void> _onReorderKeys(int oldIndex, int newIndex, List<ApiKeyConfig> keys) async {
    if (oldIndex == newIndex) return;

    // Adjust newIndex if moving down
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final list = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);

    // Move the item
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    // Update sortIndex to reflect new order
    for (int i = 0; i < list.length; i++) {
      list[i] = list[i].copyWith(sortIndex: i);
    }

    await settings.setProviderConfig(widget.providerKey, cfg.copyWith(apiKeys: list));
  }

  Widget _keyRow(
    BuildContext context,
    ApiKeyConfig k,
    int index,
    Color Function(ApiKeyStatus) statusColor,
    String Function(ApiKeyStatus) statusText,
    {required bool canReorder}
  ) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final keyStatus = _getKeyStatus(k.id);
    final keyError = _getKeyError(k.id);
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows || 
                      defaultTargetPlatform == TargetPlatform.linux || 
                      defaultTargetPlatform == TargetPlatform.macOS;

    String mask(String key) {
      if (key.length <= 8) return key;
      return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
    }

    final token = _revealToken(k, index);
    final bool isHidden = _hiddenKeyIds.contains(token);
    final alias = (k.name ?? '').trim();
    final keyLabel = isHidden ? mask(k.key) : k.key;
    final hasAlias = alias.isNotEmpty;
    final display = hasAlias ? alias : keyLabel;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: statusColor(keyStatus),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        display,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (k.priority <= 10) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('P${k.priority}', style: TextStyle(color: cs.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                if (hasAlias) ...[
                  const SizedBox(height: 2),
                  Text(
                    keyLabel,
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6), fontFamily: 'monospace'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      statusText(keyStatus),
                      style: TextStyle(color: statusColor(keyStatus), fontSize: 12),
                    ),
                    if (keyError != null) ...[
                      const SizedBox(width: 4),
                      Icon(Lucide.info, size: 12, color: statusColor(keyStatus)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: l10n.multiKeyPageCopy,
            child: _TactileIconButton(
              icon: Lucide.Copy,
              color: cs.onSurface.withOpacity(0.4),
              size: 16,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: k.key));
                if (!context.mounted) return;
                showAppSnackBar(context, message: l10n.multiKeyPageCopy, type: NotificationType.success);
              },
            ),
          ),
          const SizedBox(width: 4),
          _TactileIconButton(
            icon: isHidden ? Lucide.Eye : Lucide.EyeOff,
            color: cs.onSurface.withOpacity(0.4),
            size: 16,
            onTap: () {
              setState(() {
                if (isHidden) {
                  _hiddenKeyIds.remove(token);
                } else {
                  _hiddenKeyIds.add(token);
                }
              });
            },
          ),
          const SizedBox(width: 8),
          IosSwitch(
            value: k.isEnabled,
            onChanged: (v) async {
              await _updateKey(k.copyWith(isEnabled: v));
            },
            width: 40,
            height: 24,
          ),
          if (isDesktop) ...[
            const SizedBox(width: 4),
            _TactileIconButton(
              icon: Lucide.Pencil,
              color: cs.primary,
              size: 16,
              semanticLabel: l10n.multiKeyPageEdit,
              onTap: () async {
                await _editKey(k);
              },
            ),
            const SizedBox(width: 4),
            _TactileIconButton(
              icon: Lucide.Trash2,
              color: cs.error,
              size: 16,
              semanticLabel: l10n.multiKeyPageDelete,
              onTap: () async {
                await _deleteKey(k);
              },
            ),
          ],
          if (canReorder) ...[
            const SizedBox(width: 8),
            ReorderableDragStartListener(
              index: index,
              child: Icon(Lucide.GripVertical, color: cs.onSurface.withOpacity(0.2), size: 20),
            ),
          ],
        ],
      ),
    );

    if (isDesktop) {
      return InkWell(
        key: ValueKey(k.id),
        onTap: () => _editKey(k),
        onLongPress: () => _testSingleKeyInteractive(k),
        child: content,
      );
    }

    return Dismissible(
      key: ValueKey(k.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: cs.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Lucide.Trash2, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.multiKeyPageDelete),
            content: Text(l10n.multiKeyPageDeleteErrorsConfirmTitle),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.multiKeyPageCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: cs.error),
                child: Text(l10n.multiKeyPageDelete),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => _deleteKey(k),
      child: InkWell(
        onTap: () => _editKey(k),
        onLongPress: () => _testSingleKeyInteractive(k),
        child: content,
      ),
    );
  }

  Future<void> _onEnableAll() async {
    await _updateAllKeys((k) => k.copyWith(isEnabled: true));
  }

  Future<void> _onDisableAll() async {
    await _updateAllKeys((k) => k.copyWith(isEnabled: false));
  }

  Future<void> _updateAllKeys(ApiKeyConfig Function(ApiKeyConfig) updateFn) async {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final keys = List<ApiKeyConfig>.from(cfg.apiKeys ?? []);
    for (int i = 0; i < keys.length; i++) {
      keys[i] = updateFn(keys[i]);
    }
    await settings.setProviderConfig(widget.providerKey, cfg.copyWith(apiKeys: keys));
  }

  // iOS-style section container
  Widget _iosSectionCard({required List<Widget> children}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    // Blend with surface to better match page background while retaining a card feel
    final Color base = cs.surface;
    final Color bg = isDark
        ? Color.lerp(base, Colors.white, 0.06)!
        : Color.lerp(base, Colors.white, 0.92)!;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06),
          width: 0.6,
        ),
        // boxShadow: [
        //   if (!isDark)
        //     BoxShadow(
        //       color: Colors.black.withOpacity(0.02),
        //       blurRadius: 6,
        //       offset: const Offset(0, 1),
        //     ),
        // ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  // Single row with label-left and custom trailing
  Widget _iosRow(
    BuildContext context, {
    required String label,
    Widget? trailing,
    GestureTapCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          if (trailing != null) DefaultTextStyle.merge(
            style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
            child: trailing,
          ),
        ],
      ),
    );
    if (onTap != null) {
      return _TactileScale(child: row, onTap: onTap);
    }
    return row;
  }

  Widget _divider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(height: 0.6, color: cs.outlineVariant.withOpacity(0.25));
  }

  Future<void> _copyAllKeys() async {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final keys = (cfg.apiKeys ?? const <ApiKeyConfig>[])
        .where((k) {
          final st = _getKeyStatus(k.id);
          return k.isEnabled && (st == ApiKeyStatus.active || st == ApiKeyStatus.rateLimited);
        })
        .map((k) => k.key.trim())
        .where((k) => k.isNotEmpty)
        .toList();
    if (keys.isEmpty) return;

    final joined = keys.join(',');
    await Clipboard.setData(ClipboardData(text: joined));

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(
      context,
      message: l10n.translatePageCopyResult,
      type: NotificationType.success,
    );
  }

  Future<void> _updateKey(ApiKeyConfig updated) async {
    print('[MultiKey] _updateKey called - Key ID: ${updated.id}, Priority: ${updated.priority}');
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final list = List<ApiKeyConfig>.from(old.apiKeys ?? const <ApiKeyConfig>[]);
    final idx = list.indexWhere((e) => e.id == updated.id);
    print('[MultiKey] Found key at index: $idx');
    if (idx >= 0) {
      final before = list[idx];
      print('[MultiKey] Before update - Priority: ${before.priority}');
      list[idx] = updated;
      print('[MultiKey] After update - Priority: ${list[idx].priority}');
      await settings.setProviderConfig(widget.providerKey, old.copyWith(apiKeys: list));
      print('[MultiKey] Saved to settings');

      // Verify it was saved
      final verified = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
      final verifiedKey = verified.apiKeys?.firstWhere((e) => e.id == updated.id);
      print('[MultiKey] Verification - Priority in settings: ${verifiedKey?.priority}');
    }
  }

  Future<void> _deleteKey(ApiKeyConfig k) async {
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final list = List<ApiKeyConfig>.from(old.apiKeys ?? const <ApiKeyConfig>[]);
    final idx = list.indexWhere((e) => e.id == k.id);
    if (idx < 0) return;
    final removed = list.removeAt(idx);
    await settings.setProviderConfig(widget.providerKey, old.copyWith(apiKeys: list));
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: AppLocalizations.of(context)!.multiKeyPageDeleteSnackbarDeletedOne,
      type: NotificationType.info,
      actionLabel: AppLocalizations.of(context)!.multiKeyPageUndo,
      onAction: () async {
        // Re-insert if user taps undo
        final latest = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
        final cur = List<ApiKeyConfig>.from(latest.apiKeys ?? const <ApiKeyConfig>[]);
        final insertIndex = idx <= cur.length ? idx : cur.length;
        cur.insert(insertIndex, removed);
        await settings.setProviderConfig(widget.providerKey, latest.copyWith(apiKeys: cur));
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: AppLocalizations.of(context)!.multiKeyPageUndoRestored,
          type: NotificationType.success,
          duration: const Duration(seconds: 2),
        );
      },
    );
  }

  Future<void> _editKey(ApiKeyConfig k) async {
    final updated = await _showEditKeySheet(k);
    if (updated == null) return;
    // Optional: prevent duplicate keys if key changed
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final list = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final duplicate = list.any((e) => e.id != k.id && e.key.trim() == updated.key.trim());
    if (duplicate) {
      showAppSnackBar(context, message: AppLocalizations.of(context)!.multiKeyPageDuplicateKeyWarning, type: NotificationType.warning);
      return;
    }
    await _updateKey(updated);
  }

  Future<void> _onAddKeys() async {
    final l10n = AppLocalizations.of(context)!;
    final added = await _showAddKeysSheet();
    if (added == null) return;
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final existing = (cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final existingSet = existing.map((e) => e.key.trim()).toSet();
    // 新增列表内部也要去重，保证 key 在本次添加和历史中都是唯一
    final newSet = <String>{};
    for (final raw in added) {
      final k = raw.trim();
      if (k.isEmpty) continue;
      if (existingSet.contains(k)) continue;
      if (newSet.contains(k)) continue;
      newSet.add(k);
    }
    if (newSet.isEmpty) {
      showAppSnackBar(context, message: l10n.multiKeyPageImportedSnackbar(0));
      return;
    }
    final newKeys = [
      ...existing,
      for (final s in newSet) ApiKeyConfig.create(s),
    ];
    await settings.setProviderConfig(widget.providerKey, cfg.copyWith(apiKeys: newKeys, multiKeyEnabled: true));
    if (!mounted) return;
    showAppSnackBar(context, message: l10n.multiKeyPageImportedSnackbar(newSet.length), type: NotificationType.success);
  }

  List<String> _splitKeys(String raw) {
    final s = raw.replaceAll(',', ' ').trim();
    return s.split(RegExp(r'\s+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> _onDetect() async {
    if (_detecting) return;
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final models = cfg.models;
    
    // Check if provider has models
    if (models.isEmpty) {
      if (!mounted) return;
      showAppSnackBar(context, message: AppLocalizations.of(context)!.multiKeyPagePleaseAddModel, type: NotificationType.warning);
      return;
    }
    
    // Show combined model selector and detection UI
    await _showDetectionUI();
  }

  Future<void> _onPickDetectModel() async {
    final sel = await showModelSelector(context, limitProviderKey: widget.providerKey);
    if (sel != null) {
      setState(() => _detectModelId = sel.modelId);
    }
  }

  Future<void> _onDeleteAllErrorKeys() async {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final keys = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final errorKeys = keys.where((e) => _getKeyStatus(e.id) == ApiKeyStatus.error).toList();
    if (errorKeys.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.multiKeyPageDeleteErrorsConfirmTitle),
          content: Text(l10n.multiKeyPageDeleteErrorsConfirmContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.multiKeyPageCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: Text(l10n.multiKeyPageDelete),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final remain = keys.where((e) => _getKeyStatus(e.id) != ApiKeyStatus.error).toList();
    await settings.setProviderConfig(widget.providerKey, cfg.copyWith(apiKeys: remain));
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: AppLocalizations.of(context)!.multiKeyPageDeletedErrorsSnackbar(errorKeys.length),
      type: NotificationType.success,
    );
  }

  Future<void> _chooseDetectModel() async {
    final sel = await showModelSelector(context, limitProviderKey: widget.providerKey);
    if (sel != null) setState(() => _detectModelId = sel.modelId);
  }

  Future<void> _showStrategySheet() async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final current = old.keyManagement?.strategy ?? LoadBalanceStrategy.roundRobin;
    String labelFor(LoadBalanceStrategy s) {
      switch (s) {
        case LoadBalanceStrategy.priority:
          return l10n.multiKeyPageStrategyPriority;
        case LoadBalanceStrategy.leastUsed:
          return l10n.multiKeyPageStrategyLeastUsed;
        case LoadBalanceStrategy.random:
          return l10n.multiKeyPageStrategyRandom;
        case LoadBalanceStrategy.roundRobin:
        default:
          return l10n.multiKeyPageStrategyRoundRobin;
      }
    }

    final selected = await showModalBottomSheet<LoadBalanceStrategy>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                for (final s in LoadBalanceStrategy.values) ...[
                  _TactileRow(
                    pressedScale: 1.00,
                    onTap: () => Navigator.of(ctx).pop(s),
                    builder: (pressed) {
                      final base = cs.onSurface;
                      final isDark = Theme.of(ctx).brightness == Brightness.dark;
                      final target = pressed ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base) : base;
                      return TweenAnimationBuilder<Color?>(
                        tween: ColorTween(end: target),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        builder: (context, color, _) {
                          final c = color ?? base;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(child: Text(labelFor(s), style: TextStyle(fontSize: 15, color: c))),
                                if (s == current) Icon(Icons.check, color: cs.primary),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                  if (s == LoadBalanceStrategy.priority && current == LoadBalanceStrategy.priority)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(
                        '💡 优先级规则：数字越小优先级越高（1最高，10最低）',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && selected != current) {
      final km = (old.keyManagement ?? const KeyManagementConfig()).copyWith(strategy: selected);
      await settings.setProviderConfig(widget.providerKey, old.copyWith(keyManagement: km));
    }
  }

  Future<List<String>?> _showAddKeysSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputCtrl = TextEditingController();

    if (defaultTargetPlatform == TargetPlatform.windows) {
      final result = await showDialog<List<String>?>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: cs.surface,
            title: Text(l10n.multiKeyPageAdd),
            content: TextField(
              controller: inputCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: l10n.multiKeyPageAddHint,
                filled: true,
                fillColor: isDark ? Colors.white10 : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(l10n.multiKeyPageCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(_splitKeys(inputCtrl.text)),
                child: Text(l10n.multiKeyPageAdd),
              ),
            ],
          );
        },
      );
      return result;
    }

    final result = await showModalBottomSheet<List<String>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999)))),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Text(l10n.multiKeyPageAdd, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _TactileIconButton(
                          icon: Lucide.X,
                          color: cs.onSurface,
                          onTap: () => Navigator.of(ctx).maybePop(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: inputCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: l10n.multiKeyPageAddHint,
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: IosTileButton(
                    label: l10n.multiKeyPageAdd,
                    icon: Lucide.Plus,
                    backgroundColor: cs.primary,
                    onTap: () => Navigator.of(ctx).pop(_splitKeys(inputCtrl.text)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return result;
  }

  Future<ApiKeyConfig?> _showEditKeySheet(ApiKeyConfig k) async {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final aliasCtrl = TextEditingController(text: k.name ?? '');
    final keyCtrl = TextEditingController(text: k.key);
    final priCtrl = TextEditingController(text: k.priority.toString());

    if (defaultTargetPlatform == TargetPlatform.windows) {
      final updated = await showDialog<ApiKeyConfig?>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: cs.surface,
            title: Text(l10n.multiKeyPageEdit),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: aliasCtrl,
                  decoration: InputDecoration(
                    hintText: l10n.multiKeyPageAlias,
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keyCtrl,
                  decoration: InputDecoration(
                    hintText: l10n.multiKeyPageKey,
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: l10n.multiKeyPagePriority,
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(l10n.multiKeyPageCancel),
              ),
              TextButton(
                onPressed: () {
                  final p = int.tryParse(priCtrl.text.trim()) ?? k.priority;
                  final clamped = p.clamp(1, 10) as int;
                  Navigator.of(ctx).pop(
                    k.copyWith(
                      name: aliasCtrl.text.trim().isEmpty ? null : aliasCtrl.text.trim(),
                      key: keyCtrl.text.trim(),
                      priority: clamped,
                    ),
                  );
                },
                child: Text(l10n.multiKeyPageSave),
              ),
            ],
          );
        },
      );
      return updated;
    }
    final updated = await showModalBottomSheet<ApiKeyConfig?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999)))),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Text(l10n.multiKeyPageEdit, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _TactileIconButton(
                          icon: Lucide.X,
                          color: cs.onSurface,
                          onTap: () => Navigator.of(ctx).maybePop(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: aliasCtrl,
                  decoration: InputDecoration(
                    hintText: l10n.multiKeyPageAlias,
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyCtrl,
                  decoration: InputDecoration(
                    hintText: l10n.multiKeyPageKey,
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: l10n.multiKeyPagePriority,
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: IosTileButton(
                    label: l10n.multiKeyPageSave,
                    icon: Lucide.Check,
                    backgroundColor: cs.primary,
                    onTap: () {
                      final p = int.tryParse(priCtrl.text.trim()) ?? k.priority;
                      final clamped = p.clamp(1, 10) as int;
                      Navigator.of(ctx).pop(
                        k.copyWith(
                          name: aliasCtrl.text.trim().isEmpty ? null : aliasCtrl.text.trim(),
                          key: keyCtrl.text.trim(),
                          priority: clamped,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return updated;
  }

  Future<void> _detectOnly({required List<String> keys}) async {
    final cfg = context.read<SettingsProvider>().getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final models = cfg.models;
    if (_detectModelId == null) {
      if (models.isEmpty) {
        showAppSnackBar(context, message: AppLocalizations.of(context)!.multiKeyPagePleaseAddModel, type: NotificationType.warning);
        return;
      }
      _detectModelId = models.first;
    }
    
    // 传入的是 key 字符串，按 key 本身匹配，而不是 id
    final normalized = keys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final fullList = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final toTest = fullList.where((k) => normalized.contains(k.key.trim())).toList();
    
    await _testKeysAndSave(fullList, toTest, _detectModelId!, null);
  }

  Future<void> _detectAllForModel(String modelId) async {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final list = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    await _testKeysAndSave(list, list, modelId, null);
  }

  /// 交互式单 Key 测试：先选模型，再只测试这一条 Key
  Future<void> _testSingleKeyInteractive(ApiKeyConfig key) async {
    if (_detecting) return;

    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);

    // 没有模型就直接提示
    if (cfg.models.isEmpty) {
      showAppSnackBar(
        context,
        message: l10n.multiKeyPagePleaseAddModel,
        type: NotificationType.warning,
      );
      return;
    }

    // 选择模型（复用统一模型选择器）
    final sel = await showModelSelector(context, limitProviderKey: widget.providerKey);
    if (sel == null) return; // 用户取消

    final modelId = sel.modelId;

    // 取最新的 key 列表，避免使用过期引用
    final latestCfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final fullList = List<ApiKeyConfig>.from(latestCfg.apiKeys ?? const <ApiKeyConfig>[]);
    final toTest = fullList.where((e) => e.id == key.id).toList();
    if (toTest.isEmpty) {
      return; // key 已被删除
    }

    setState(() => _detecting = true);
    try {
      await _testKeysAndSave(fullList, toTest, modelId, null);
      if (!mounted) return;
      // 结果通过状态标签和错误详情展示
    } finally {
      if (mounted) {
        setState(() => _detecting = false);
      }
    }
  }

  Future<void> _testKeysAndSave(List<ApiKeyConfig> fullList, List<ApiKeyConfig> toTest, String modelId, Function(int tested, int total)? onProgress) async {
    final settings = context.read<SettingsProvider>();
    final base = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);

    int tested = 0;
    final total = toTest.length;

    for (int i = 0; i < toTest.length; i++) {
      final k = toTest[i];
      print('[TEST KEY] Testing key ${i + 1}/$total: ${k.name ?? k.key.substring(0, 8)}...');

      final (ok, error) = await _testSingleKey(base, modelId, k);

      print('[TEST KEY] Result: ${ok ? 'SUCCESS' : 'FAILED'} ${error != null ? '- $error' : ''}');

      // Update key status via ApiKeyManager
      await ApiKeyManager().updateKeyStatus(
        k.id,
        ok,
        error: error,
        maxFailuresBeforeDisable: base.keyManagement?.maxFailuresBeforeDisable ?? 3,
      );

      tested++;
      if (onProgress != null) {
        onProgress(tested, total);
      }

      // Small delay between tests to avoid rate limiting
      if (i < toTest.length - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    // No need to save apiKeys config - runtime state is in ApiKeyManager
  }

  Future<(bool success, String? error)> _testSingleKey(ProviderConfig baseCfg, String modelId, ApiKeyConfig key) async {
    try {
      final cfg2 = baseCfg.copyWith(apiKey: key.key);
      await ProviderManager.testConnection(cfg2, modelId)
          .timeout(const Duration(seconds: 60));
      return (true, null);
    } on TimeoutException {
      return (false, 'Timeout: API response exceeded 60 seconds');
    } on HttpException catch (e) {
      // Parse HTTP error for meaningful messages
      final msg = e.message;
      if (msg.contains('401')) {
        return (false, 'Unauthorized: Invalid API key');
      } else if (msg.contains('403')) {
        return (false, 'Forbidden: Access denied or quota exceeded');
      } else if (msg.contains('429')) {
        return (false, 'Rate limited: Too many requests');
      } else if (msg.contains('404')) {
        return (false, 'Not found: Model or endpoint not available');
      } else if (msg.contains('500') || msg.contains('502') || msg.contains('503')) {
        return (false, 'Server error: Provider service unavailable');
      }
      // Extract meaningful part of error
      if (msg.length > 200) {
        return (false, msg.substring(0, 200) + '...');
      }
      return (false, msg);
    } catch (e) {
      // Clean up error message
      final errStr = e.toString();
      if (errStr.startsWith('Exception: ')) {
        return (false, errStr.substring(11));
      }
      if (errStr.length > 200) {
        return (false, errStr.substring(0, 200) + '...');
      }
      return (false, errStr);
    }
  }
  
  Future<void> _showErrorDetails(ApiKeyConfig key) async {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final state = ApiKeyManager().getKeyState(key.id);
    final error = state?.lastError ?? 'Unknown error';
    final alias = key.name?.isNotEmpty == true ? key.name! : 'API Key';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Lucide.info, color: cs.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$alias - Error Details',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cs.error.withOpacity(0.2),
                ),
              ),
              child: SelectableText(
                error,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Last tested: ${_formatTimestamp(state?.updatedAt ?? DateTime.now().millisecondsSinceEpoch)}',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withOpacity(0.6),
              ),
            ),
            if (state != null && state.totalRequests > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Success rate: ${(state.successfulRequests * 100 / state.totalRequests).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            icon: Icon(Lucide.Copy, size: 16),
            label: Text('Copy Error'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: error));
              Navigator.of(ctx).pop();
              showAppSnackBar(
                context,
                message: 'Error message copied to clipboard',
                type: NotificationType.success,
                duration: const Duration(seconds: 2),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.multiKeyPageCancel ?? 'Close'),
          ),
        ],
      ),
    );
  }
  
  String _formatTimestamp(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
  
  Future<void> _showDetectionUI() async {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final l10n = AppLocalizations.of(context)!;

    // 如果没有配置模型，直接提示
    if (cfg.models.isEmpty) {
      showAppSnackBar(context, message: l10n.multiKeyPagePleaseAddModel, type: NotificationType.warning);
      return;
    }

    // 第一步：用统一的模型选择器选择测试模型（和单Key测试连接完全一致的UI）
    final sel = await showModelSelector(context, limitProviderKey: widget.providerKey);
    if (sel == null) return; // 用户取消

    final selectedModelId = sel.modelId;
    _detectModelId = selectedModelId;

    // 第二步：弹出仅显示进度和取消按钮的对话框
    final keys = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    if (keys.isEmpty) {
      showAppSnackBar(context, message: l10n.multiKeyPageNoKeys, type: NotificationType.warning);
      return;
    }

    int tested = 0;
    final total = keys.length;
    bool cancelled = false;
    bool started = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 首次构建时启动检测流程
          if (!started) {
            started = true;
            _testKeysAndSave(
              keys,
              keys,
              selectedModelId,
              (testedCount, totalCount) {
                if (!cancelled && ctx.mounted) {
                  setDialogState(() {
                    tested = testedCount;
                  });
                }
              },
            ).then((_) {
              if (!cancelled && ctx.mounted) {
                Navigator.of(ctx).pop();
                if (mounted) {
                  showAppSnackBar(
                    context,
                    message: '${l10n.multiKeyPageDetect} $tested ${l10n.multiKeyPageKey}',
                    type: NotificationType.success,
                  );
                }
              }
            });
          }

          final cs = Theme.of(context).colorScheme;

          return AlertDialog(
            title: Text(l10n.multiKeyPageDetect),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.providerDetailPageSelectModelButton}:',
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7)),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedModelId,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Text('${tested.clamp(0, total)} / $total'),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: total > 0 ? tested.clamp(0, total) / total : null),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.of(ctx).pop();
                },
                child: Text(l10n.multiKeyPageCancel),
              ),
            ],
          );
        },
      ),
    );
  }
}

// A scale-on-tap wrapper for iOS-like lightweight feedback (no ripple)
class _TactileScale extends StatefulWidget {
  const _TactileScale({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_TactileScale> createState() => _TactileScaleState();
}

class _TactileScaleState extends State<_TactileScale> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (context.read<SettingsProvider>().hapticsOnListItemTap) Haptics.soft();
              widget.onTap!.call();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

// Icon-only, no-border, iOS-like tactile icon button
class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.size = 22,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final double size;

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
        onTap: () {
          // Haptics.light();
          widget.onTap();
        },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                 Haptics.light();
                widget.onLongPress!.call();
              },
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: icon,
          ),
        ),
      ),
    );
  }
}

// Builder-based tactile wrapper to expose pressed state and optional scale
class _TactileRow extends StatefulWidget {
  const _TactileRow({required this.builder, this.onTap, this.pressedScale = 0.97});
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final double pressedScale;

  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              Haptics.soft();
              widget.onTap!.call();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.builder(_pressed),
      ),
    );
  }
}
