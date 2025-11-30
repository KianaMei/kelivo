import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../../core/services/search/search_service.dart';
import '../../../core/models/api_keys.dart';
import '../../../core/services/api_key_manager.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../services/search_service_factory.dart';

// Windows/Desktop Dialog for multi-key management - 支持所有多Key搜索服务
class KeyManagementDialog extends StatefulWidget {
  final SearchServiceOptions service;
  final String serviceName;
  final ValueChanged<SearchServiceOptions> onSave;

  const KeyManagementDialog({
    super.key,
    required this.service,
    required this.serviceName,
    required this.onSave,
  });

  @override
  State<KeyManagementDialog> createState() => _KeyManagementDialogState();
}

class _KeyManagementDialogState extends State<KeyManagementDialog> {
  ApiKeyStatus? _filterStatus;
  final Set<String> _hiddenKeyIds = <String>{};
  
  // 本地缓存的 apiKeys 列表，用于编辑操作
  late List<ApiKeyConfig> _apiKeys;
  late LoadBalanceStrategy _strategy;

  @override
  void initState() {
    super.initState();
    _apiKeys = List.from(SearchServiceFactory.getApiKeys(widget.service));
    _strategy = SearchServiceFactory.getStrategy(widget.service);
  }

  void _save() {
    final updated = SearchServiceFactory.updateMultiKey(widget.service, _apiKeys, _strategy);
    widget.onSave(updated);
  }

  String _revealToken(ApiKeyConfig k, int index) => '${k.id}_$index';

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final total = _apiKeys.length;
    final normal = _apiKeys.where((k) {
      final state = ApiKeyManager().getKeyState(k.id);
      return state?.status == 'active' || state?.status == null;
    }).length;
    final errors = _apiKeys.where((k) {
      final state = ApiKeyManager().getKeyState(k.id);
      return state?.status == 'error';
    }).length;

    final filteredKeys = _filterStatus == null
        ? _apiKeys
        : _apiKeys.where((k) => _getKeyStatus(k.id) == _filterStatus).toList();

    // 和 Provider 的 MultiKeyManagerPage 使用相同的尺寸比例
    final size = MediaQuery.of(context).size;
    
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: size.width * 0.8,
          maxHeight: size.height * 0.8,
        ),
        child: Material(
          color: cs.surface,
          elevation: 16,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title bar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 4, 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2))),
                ),
                child: Row(
                  children: [
                    Text('多Key管理 - ${widget.serviceName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    // 复制所有 Key
                    Tooltip(
                      message: '复制所有Key',
                      child: IconButton(
                        icon: Icon(Lucide.Copy, color: cs.onSurface, size: 20),
                        onPressed: _copyAllKeys,
                      ),
                    ),
                    // 批量操作菜单
                    PopupMenuButton<String>(
                      icon: Icon(Lucide.MoreVertical, color: cs.onSurface),
                      tooltip: '批量操作',
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 8,
                      color: cs.surface,
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
                            Text('删除错误Key', style: TextStyle(color: cs.error)),
                          ]),
                        ),
                      ],
                    ),
                    // 添加 Key 按钮
                    Tooltip(
                      message: '添加Key',
                      child: IconButton(
                        icon: Icon(Lucide.Plus, color: cs.onSurface, size: 20),
                        onPressed: () => _addKey(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 关闭按钮
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),

              // Filter bar
              _buildFilterBar(context, total, normal, errors),

              // Strategy selection
              _buildStrategyRow(context),

              const Divider(height: 1),

              // Key list - 支持拖拽排序
              Expanded(
                child: _filterStatus == null
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                      buildDefaultDragHandles: false,
                      itemCount: filteredKeys.length,
                      onReorder: _onReorder,
                      itemBuilder: (ctx, index) => _keyRow(context, filteredKeys[index], index, canReorder: true),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                      itemCount: filteredKeys.length,
                      itemBuilder: (ctx, index) => _keyRow(context, filteredKeys[index], index, canReorder: false),
                    ),
              ),
            ],
          ),
        ),
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
        backgroundColor: cs.surfaceContainerHighest,
        selectedColor: color.withOpacity(0.2),
        labelStyle: TextStyle(color: isSelected ? color : cs.onSurface, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
        side: BorderSide(color: isSelected ? color : Colors.transparent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          chip('全部', total, null, cs.primary),
          const SizedBox(width: 8),
          chip('正常', normal, ApiKeyStatus.active, Colors.green),
          const SizedBox(width: 8),
          chip('错误', errors, ApiKeyStatus.error, cs.error),
        ],
      ),
    );
  }

  Widget _buildStrategyRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('负载均衡策略', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              ...LoadBalanceStrategy.values.map((s) {
                final isSelected = _strategy == s;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(_strategyName(s)),
                    selected: isSelected,
                    onSelected: (_) => _updateStrategy(s),
                    backgroundColor: cs.surfaceContainerHighest,
                    selectedColor: cs.primaryContainer,
                    labelStyle: TextStyle(color: isSelected ? cs.onPrimaryContainer : cs.onSurface),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    side: BorderSide(color: isSelected ? cs.primary : Colors.transparent),
                  ),
                );
              }),
            ],
          ),
          if (_strategy == LoadBalanceStrategy.priority) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Lucide.Lightbulb, size: 14, color: Colors.amber.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '优先级规则：数字越小优先级越高（1最高，10最低）',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _updateStrategy(LoadBalanceStrategy s) {
    setState(() => _strategy = s);
    _save();
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _apiKeys.removeAt(oldIndex);
      _apiKeys.insert(newIndex, item);
    });
    _save();
  }

  Widget _keyRow(BuildContext context, ApiKeyConfig k, int index, {required bool canReorder}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _getKeyStatus(k.id);
    final token = _revealToken(k, index);
    final isHidden = !_hiddenKeyIds.contains(token);
    
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case ApiKeyStatus.active:
        statusColor = Colors.green;
        statusIcon = Lucide.CircleCheck;
        break;
      case ApiKeyStatus.error:
        statusColor = cs.error;
        statusIcon = Lucide.CircleX;
        break;
      case ApiKeyStatus.rateLimited:
        statusColor = Colors.orange;
        statusIcon = Lucide.Clock;
        break;
      case ApiKeyStatus.disabled:
        statusColor = cs.onSurface.withOpacity(0.4);
        statusIcon = Lucide.CircleMinus;
        break;
    }

    final realIndex = _apiKeys.indexWhere((key) => key.id == k.id);

    return Material(
      key: ValueKey(k.id),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _editKey(context, realIndex),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2))),
          ),
          child: Row(
            children: [
              // 状态图标
              Icon(statusIcon, size: 20, color: statusColor),
              const SizedBox(width: 12),
              // Key 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_strategy == LoadBalanceStrategy.priority && k.priority <= 10)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('P${k.priority}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer)),
                          ),
                        Expanded(
                          child: Text(
                            k.name?.isNotEmpty == true ? k.name! : 'API Key ${index + 1}',
                            style: TextStyle(fontWeight: FontWeight.w600, color: k.isEnabled ? null : cs.onSurface.withOpacity(0.5)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isHidden ? '••••••••••••••••' : k.key,
                      style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.6)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 显示/隐藏按钮
              IconButton(
                icon: Icon(isHidden ? Lucide.Eye : Lucide.EyeOff, size: 18, color: cs.onSurface.withOpacity(0.5)),
                onPressed: () {
                  setState(() {
                    if (isHidden) {
                      _hiddenKeyIds.add(token);
                    } else {
                      _hiddenKeyIds.remove(token);
                    }
                  });
                },
              ),
              // 开关
              IosSwitch(
                value: k.isEnabled,
                onChanged: (v) {
                  if (realIndex >= 0) _toggleKey(realIndex, v);
                },
                width: 40,
                height: 24,
              ),
              // 拖拽手柄
              if (canReorder) ...[
                const SizedBox(width: 8),
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(Lucide.GripVertical, color: cs.onSurface.withOpacity(0.2), size: 20),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _toggleKey(int index, bool enabled) {
    setState(() {
      _apiKeys[index] = _apiKeys[index].copyWith(isEnabled: enabled);
    });
    _save();
  }

  void _copyAllKeys() {
    final keys = _apiKeys.map((k) => k.key).join('\n');
    Clipboard.setData(ClipboardData(text: keys));
    showAppSnackBar(context, message: '已复制 ${_apiKeys.length} 个Key', type: NotificationType.info);
  }

  void _onEnableAll() {
    setState(() {
      _apiKeys = _apiKeys.map((k) => k.copyWith(isEnabled: true)).toList();
    });
    _save();
    showAppSnackBar(context, message: '已启用所有Key', type: NotificationType.info);
  }

  void _onDisableAll() {
    setState(() {
      _apiKeys = _apiKeys.map((k) => k.copyWith(isEnabled: false)).toList();
    });
    _save();
    showAppSnackBar(context, message: '已禁用所有Key', type: NotificationType.info);
  }

  void _onDeleteAllErrorKeys() {
    final toRemove = _apiKeys.where((k) => _getKeyStatus(k.id) == ApiKeyStatus.error).toList();
    if (toRemove.isEmpty) {
      showAppSnackBar(context, message: '没有错误状态的Key', type: NotificationType.info);
      return;
    }
    setState(() {
      _apiKeys.removeWhere((k) => toRemove.any((r) => r.id == k.id));
    });
    _save();
    showAppSnackBar(context, message: '已删除 ${toRemove.length} 个错误Key', type: NotificationType.info);
  }

  Future<void> _addKey(BuildContext context) async {
    await _showKeyDialog(context: context, editIndex: null);
  }

  Future<void> _editKey(BuildContext context, int index) async {
    if (index < 0) return;
    await _showKeyDialog(context: context, editIndex: index);
  }

  Future<void> _showKeyDialog({required BuildContext context, int? editIndex}) async {
    final keyController = TextEditingController();
    final nameController = TextEditingController();
    final limitController = TextEditingController();
    int priority = 5;

    if (editIndex != null) {
      final config = _apiKeys[editIndex];
      keyController.text = config.key;
      nameController.text = config.name ?? '';
      limitController.text = config.maxRequestsPerMinute?.toString() ?? '';
      priority = config.priority;
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    InputDecoration buildInputDecoration(String label) {
      return InputDecoration(
        labelText: label,
        filled: true,
        fillColor: isDark ? Colors.white10 : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(editIndex == null ? '添加 API Key' : '编辑 API Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyController,
                decoration: buildInputDecoration('API Key'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: buildInputDecoration('名称（可选）'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limitController,
                decoration: buildInputDecoration('每分钟限流（可选）'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('优先级：'),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: priority,
                    items: List.generate(10, (i) => i + 1).map((p) =>
                      DropdownMenuItem(value: p, child: Text('P$p'))
                    ).toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => priority = v);
                    },
                  ),
                  const SizedBox(width: 8),
                  Text('(1最高)', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5))),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final key = keyController.text.trim();
                if (key.isEmpty) return;

                final config = editIndex == null
                    ? ApiKeyConfig.create(
                        key,
                        name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
                      ).copyWith(
                        maxRequestsPerMinute: limitController.text.trim().isEmpty
                            ? null
                            : int.tryParse(limitController.text.trim()),
                        priority: priority,
                      )
                    : _apiKeys[editIndex].copyWith(
                        key: key,
                        name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
                        maxRequestsPerMinute: limitController.text.trim().isEmpty
                            ? null
                            : int.tryParse(limitController.text.trim()),
                        priority: priority,
                      );

                setState(() {
                  if (editIndex == null) {
                    _apiKeys.add(config);
                  } else {
                    _apiKeys[editIndex] = config;
                  }
                });
                _save();
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  String _strategyName(LoadBalanceStrategy s) {
    switch (s) {
      case LoadBalanceStrategy.roundRobin: return '轮询';
      case LoadBalanceStrategy.random: return '随机';
      case LoadBalanceStrategy.leastUsed: return '最少使用';
      case LoadBalanceStrategy.priority: return '优先级';
    }
  }
}

// Android/Mobile Sheet for multi-key management - 支持所有多Key搜索服务
class KeyManagementSheet extends StatefulWidget {
  final SearchServiceOptions service;
  final String serviceName;
  final ValueChanged<SearchServiceOptions> onSave;

  const KeyManagementSheet({
    super.key,
    required this.service,
    required this.serviceName,
    required this.onSave,
  });

  @override
  State<KeyManagementSheet> createState() => _KeyManagementSheetState();
}

class _KeyManagementSheetState extends State<KeyManagementSheet> {
  ApiKeyStatus? _filterStatus;
  final Set<String> _hiddenKeyIds = <String>{};
  
  late List<ApiKeyConfig> _apiKeys;
  late LoadBalanceStrategy _strategy;

  @override
  void initState() {
    super.initState();
    _apiKeys = List.from(SearchServiceFactory.getApiKeys(widget.service));
    _strategy = SearchServiceFactory.getStrategy(widget.service);
  }

  void _save() {
    final updated = SearchServiceFactory.updateMultiKey(widget.service, _apiKeys, _strategy);
    widget.onSave(updated);
  }

  String _revealToken(ApiKeyConfig k, int index) => '${k.id}_$index';

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final total = _apiKeys.length;
    final normal = _apiKeys.where((k) {
      final state = ApiKeyManager().getKeyState(k.id);
      return state?.status == 'active' || state?.status == null;
    }).length;
    final errors = _apiKeys.where((k) {
      final state = ApiKeyManager().getKeyState(k.id);
      return state?.status == 'error';
    }).length;

    final filteredKeys = _filterStatus == null
        ? _apiKeys
        : _apiKeys.where((k) => _getKeyStatus(k.id) == _filterStatus).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle + Title bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '多Key管理 - ${widget.serviceName}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ),
                      // 复制所有 Key
                      IconButton(
                        icon: Icon(Lucide.Copy, color: cs.onSurface, size: 20),
                        onPressed: _copyAllKeys,
                      ),
                      // 批量操作菜单
                      PopupMenuButton<String>(
                        icon: Icon(Lucide.MoreVertical, color: cs.onSurface),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 8,
                        color: cs.surface,
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
                              Text('删除错误Key', style: TextStyle(color: cs.error)),
                            ]),
                          ),
                        ],
                      ),
                      // 添加 Key 按钮
                      IconButton(
                        icon: Icon(Lucide.Plus, color: cs.onSurface, size: 20),
                        onPressed: () => _addKey(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Filter bar
            _buildFilterBar(context, total, normal, errors),

            // Strategy selection
            _buildStrategyRow(context),

            const Divider(height: 1),

            // Key list - 支持拖拽排序
            Expanded(
              child: _filterStatus == null
                ? ReorderableListView.builder(
                    scrollController: controller,
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                    buildDefaultDragHandles: false,
                    itemCount: filteredKeys.length,
                    onReorder: _onReorder,
                    itemBuilder: (ctx, index) => _keyRow(context, filteredKeys[index], index, canReorder: true),
                  )
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                    itemCount: filteredKeys.length,
                    itemBuilder: (ctx, index) => _keyRow(context, filteredKeys[index], index, canReorder: false),
                  ),
            ),
          ],
        ),
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
        backgroundColor: cs.surfaceContainerHighest,
        selectedColor: color.withOpacity(0.2),
        labelStyle: TextStyle(color: isSelected ? color : cs.onSurface, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
        side: BorderSide(color: isSelected ? color : Colors.transparent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          chip('全部', total, null, cs.primary),
          const SizedBox(width: 8),
          chip('正常', normal, ApiKeyStatus.active, Colors.green),
          const SizedBox(width: 8),
          chip('错误', errors, ApiKeyStatus.error, cs.error),
        ],
      ),
    );
  }

  Widget _buildStrategyRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('负载均衡策略', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: LoadBalanceStrategy.values.map((s) {
              final isSelected = _strategy == s;
              return ChoiceChip(
                label: Text(_strategyName(s)),
                selected: isSelected,
                onSelected: (_) => _updateStrategy(s),
                backgroundColor: cs.surfaceContainerHighest,
                selectedColor: cs.primaryContainer,
                labelStyle: TextStyle(color: isSelected ? cs.onPrimaryContainer : cs.onSurface),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: BorderSide(color: isSelected ? cs.primary : Colors.transparent),
              );
            }).toList(),
          ),
          if (_strategy == LoadBalanceStrategy.priority) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Lucide.Lightbulb, size: 14, color: Colors.amber.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '优先级规则：数字越小优先级越高（1最高，10最低）',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _updateStrategy(LoadBalanceStrategy s) {
    setState(() => _strategy = s);
    _save();
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _apiKeys.removeAt(oldIndex);
      _apiKeys.insert(newIndex, item);
    });
    _save();
  }

  Widget _keyRow(BuildContext context, ApiKeyConfig k, int index, {required bool canReorder}) {
    final cs = Theme.of(context).colorScheme;
    final status = _getKeyStatus(k.id);
    final token = _revealToken(k, index);
    final isHidden = !_hiddenKeyIds.contains(token);
    
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case ApiKeyStatus.active:
        statusColor = Colors.green;
        statusIcon = Lucide.CircleCheck;
        break;
      case ApiKeyStatus.error:
        statusColor = cs.error;
        statusIcon = Lucide.CircleX;
        break;
      case ApiKeyStatus.rateLimited:
        statusColor = Colors.orange;
        statusIcon = Lucide.Clock;
        break;
      case ApiKeyStatus.disabled:
        statusColor = cs.onSurface.withOpacity(0.4);
        statusIcon = Lucide.CircleMinus;
        break;
    }

    final realIndex = _apiKeys.indexWhere((key) => key.id == k.id);

    return Dismissible(
      key: ValueKey(k.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: cs.error,
        child: const Icon(Lucide.Trash2, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        if (_apiKeys.length <= 1) {
          showAppSnackBar(context, message: '至少需要保留一个Key', type: NotificationType.info);
          return false;
        }
        return true;
      },
      onDismissed: (_) {
        setState(() => _apiKeys.removeAt(realIndex));
        _save();
      },
      child: InkWell(
        onTap: () => _editKey(context, realIndex),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2))),
          ),
          child: Row(
            children: [
              Icon(statusIcon, size: 20, color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_strategy == LoadBalanceStrategy.priority && k.priority <= 10)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('P${k.priority}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer)),
                          ),
                        Expanded(
                          child: Text(
                            k.name?.isNotEmpty == true ? k.name! : 'API Key ${index + 1}',
                            style: TextStyle(fontWeight: FontWeight.w600, color: k.isEnabled ? null : cs.onSurface.withOpacity(0.5)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isHidden ? '••••••••••••••••' : k.key,
                      style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.6)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(isHidden ? Lucide.Eye : Lucide.EyeOff, size: 18, color: cs.onSurface.withOpacity(0.5)),
                onPressed: () {
                  setState(() {
                    if (isHidden) {
                      _hiddenKeyIds.add(token);
                    } else {
                      _hiddenKeyIds.remove(token);
                    }
                  });
                },
              ),
              IosSwitch(
                value: k.isEnabled,
                onChanged: (v) {
                  if (realIndex >= 0) _toggleKey(realIndex, v);
                },
                width: 40,
                height: 24,
              ),
              if (canReorder) ...[
                const SizedBox(width: 8),
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(Lucide.GripVertical, color: cs.onSurface.withOpacity(0.2), size: 20),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _toggleKey(int index, bool enabled) {
    setState(() {
      _apiKeys[index] = _apiKeys[index].copyWith(isEnabled: enabled);
    });
    _save();
  }

  void _copyAllKeys() {
    final keys = _apiKeys.map((k) => k.key).join('\n');
    Clipboard.setData(ClipboardData(text: keys));
    showAppSnackBar(context, message: '已复制 ${_apiKeys.length} 个Key', type: NotificationType.info);
  }

  void _onEnableAll() {
    setState(() {
      _apiKeys = _apiKeys.map((k) => k.copyWith(isEnabled: true)).toList();
    });
    _save();
    showAppSnackBar(context, message: '已启用所有Key', type: NotificationType.info);
  }

  void _onDisableAll() {
    setState(() {
      _apiKeys = _apiKeys.map((k) => k.copyWith(isEnabled: false)).toList();
    });
    _save();
    showAppSnackBar(context, message: '已禁用所有Key', type: NotificationType.info);
  }

  void _onDeleteAllErrorKeys() {
    final toRemove = _apiKeys.where((k) => _getKeyStatus(k.id) == ApiKeyStatus.error).toList();
    if (toRemove.isEmpty) {
      showAppSnackBar(context, message: '没有错误状态的Key', type: NotificationType.info);
      return;
    }
    setState(() {
      _apiKeys.removeWhere((k) => toRemove.any((r) => r.id == k.id));
    });
    _save();
    showAppSnackBar(context, message: '已删除 ${toRemove.length} 个错误Key', type: NotificationType.info);
  }

  Future<void> _addKey(BuildContext context) async {
    await _showKeyDialog(context: context, editIndex: null);
  }

  Future<void> _editKey(BuildContext context, int index) async {
    if (index < 0) return;
    await _showKeyDialog(context: context, editIndex: index);
  }

  Future<void> _showKeyDialog({required BuildContext context, int? editIndex}) async {
    final keyController = TextEditingController();
    final nameController = TextEditingController();
    final limitController = TextEditingController();
    int priority = 5;

    if (editIndex != null) {
      final config = _apiKeys[editIndex];
      keyController.text = config.key;
      nameController.text = config.name ?? '';
      limitController.text = config.maxRequestsPerMinute?.toString() ?? '';
      priority = config.priority;
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    InputDecoration buildInputDecoration(String label) {
      return InputDecoration(
        labelText: label,
        filled: true,
        fillColor: isDark ? Colors.white10 : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(editIndex == null ? '添加 API Key' : '编辑 API Key'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: keyController,
                  decoration: buildInputDecoration('API Key'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: buildInputDecoration('名称（可选）'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: limitController,
                  decoration: buildInputDecoration('每分钟限流（可选）'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('优先级：'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: priority,
                      items: List.generate(10, (i) => i + 1).map((p) =>
                        DropdownMenuItem(value: p, child: Text('P$p'))
                      ).toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => priority = v);
                      },
                    ),
                    const SizedBox(width: 8),
                    Text('(1最高)', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5))),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final key = keyController.text.trim();
                if (key.isEmpty) return;

                final config = editIndex == null
                    ? ApiKeyConfig.create(
                        key,
                        name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
                      ).copyWith(
                        maxRequestsPerMinute: limitController.text.trim().isEmpty
                            ? null
                            : int.tryParse(limitController.text.trim()),
                        priority: priority,
                      )
                    : _apiKeys[editIndex].copyWith(
                        key: key,
                        name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
                        maxRequestsPerMinute: limitController.text.trim().isEmpty
                            ? null
                            : int.tryParse(limitController.text.trim()),
                        priority: priority,
                      );

                setState(() {
                  if (editIndex == null) {
                    _apiKeys.add(config);
                  } else {
                    _apiKeys[editIndex] = config;
                  }
                });
                _save();
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  String _strategyName(LoadBalanceStrategy s) {
    switch (s) {
      case LoadBalanceStrategy.roundRobin: return '轮询';
      case LoadBalanceStrategy.random: return '随机';
      case LoadBalanceStrategy.leastUsed: return '最少使用';
      case LoadBalanceStrategy.priority: return '优先级';
    }
  }
}
