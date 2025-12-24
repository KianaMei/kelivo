import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../../core/services/search/search_service.dart';
import '../../../core/models/api_keys.dart';
import '../../../core/services/api_key_manager.dart';
import '../../../core/services/haptics.dart';
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
  late TextEditingController _baseUrlController;

  @override
  void initState() {
    super.initState();
    _apiKeys = List.from(SearchServiceFactory.getApiKeys(widget.service));
    _strategy = SearchServiceFactory.getStrategy(widget.service);
    _baseUrlController = TextEditingController(
      text: SearchServiceFactory.getBaseUrl(widget.service) ?? '',
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  void _save() {
    final baseUrl = _baseUrlController.text.trim();
    final updated = SearchServiceFactory.updateMultiKey(
      widget.service,
      _apiKeys,
      _strategy,
      baseUrl: baseUrl.isEmpty ? null : baseUrl,
    );
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

              // Base URL configuration (only for services that support it)
              if (SearchServiceFactory.supportsBaseUrl(widget.service))
                _buildBaseUrlRow(context),

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

  Widget _buildBaseUrlRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Lucide.Link, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              const Text('自定义 API 地址', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('(可选)', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5))),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _baseUrlController,
            decoration: InputDecoration(
              hintText: ExaOptions.defaultBaseUrl,
              hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.3)),
              filled: true,
              fillColor: isDark ? Colors.white10 : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 4),
          Text(
            '留空使用官方地址，填写中转地址可使用第三方服务',
            style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
          ),
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

  String _mask(String key) {
    if (key.length <= 8) return key;
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  String _statusText(ApiKeyStatus st) {
    switch (st) {
      case ApiKeyStatus.active: return '正常';
      case ApiKeyStatus.disabled: return '已禁用';
      case ApiKeyStatus.error: return '错误';
      case ApiKeyStatus.rateLimited: return '限流中';
    }
  }

  void _showContextMenu(BuildContext context, ApiKeyConfig k, int realIndex, Offset position) {
    final cs = Theme.of(context).colorScheme;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.surface,
      elevation: 8,
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Lucide.Pencil, size: 16, color: cs.primary),
            const SizedBox(width: 12),
            const Text('编辑'),
          ]),
        ),
        PopupMenuItem(
          value: 'test',
          child: Row(children: [
            Icon(Lucide.Play, size: 16, color: Colors.green),
            const SizedBox(width: 12),
            const Text('测试'),
          ]),
        ),
        PopupMenuItem(
          value: 'copy',
          child: Row(children: [
            Icon(Lucide.Copy, size: 16, color: cs.onSurface.withOpacity(0.7)),
            const SizedBox(width: 12),
            const Text('复制'),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Lucide.Trash2, size: 16, color: cs.error),
            const SizedBox(width: 12),
            Text('删除', style: TextStyle(color: cs.error)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == 'edit') _editKey(context, realIndex);
      if (value == 'test') _testKey(k);
      if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: k.key));
        showAppSnackBar(context, message: '已复制', type: NotificationType.success);
      }
      if (value == 'delete') _deleteKey(realIndex);
    });
  }

  void _deleteKey(int index) {
    if (_apiKeys.length <= 1) {
      showAppSnackBar(context, message: '至少需要保留一个Key', type: NotificationType.info);
      return;
    }
    setState(() => _apiKeys.removeAt(index));
    _save();
  }

  Future<void> _testKey(ApiKeyConfig k) async {
    showAppSnackBar(context, message: '正在测试...', type: NotificationType.info);
    try {
      final testService = SearchServiceFactory.updateMultiKey(
        widget.service,
        [k.copyWith(isEnabled: true)],
        LoadBalanceStrategy.roundRobin,
      );
      final searchService = SearchService.getService(testService);
      await searchService.search(
        query: 'test',
        commonOptions: const SearchCommonOptions(resultSize: 1),
        serviceOptions: testService,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      showAppSnackBar(context, message: '测试成功 ✓', type: NotificationType.success);
    } on TimeoutException {
      if (!mounted) return;
      showAppSnackBar(context, message: '测试超时', type: NotificationType.error);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('401')) {
        showAppSnackBar(context, message: 'Key 无效', type: NotificationType.error);
      } else if (msg.contains('429')) {
        showAppSnackBar(context, message: '请求频率限制', type: NotificationType.warning);
      } else {
        showAppSnackBar(context, message: '测试失败: ${msg.length > 50 ? '${msg.substring(0, 50)}...' : msg}', type: NotificationType.error);
      }
    }
  }

  Widget _keyRow(BuildContext context, ApiKeyConfig k, int index, {required bool canReorder}) {
    final cs = Theme.of(context).colorScheme;
    final status = _getKeyStatus(k.id);
    final token = _revealToken(k, index);
    // 默认展示key（不在集合中=展示）
    final isHidden = _hiddenKeyIds.contains(token);
    
    Color statusColor;
    switch (status) {
      case ApiKeyStatus.active:
        statusColor = Colors.green;
        break;
      case ApiKeyStatus.error:
        statusColor = cs.error;
        break;
      case ApiKeyStatus.rateLimited:
        statusColor = Colors.orange;
        break;
      case ApiKeyStatus.disabled:
        statusColor = cs.onSurface.withOpacity(0.4);
        break;
    }

    final realIndex = _apiKeys.indexWhere((key) => key.id == k.id);
    final alias = (k.name ?? '').trim();
    final hasAlias = alias.isNotEmpty;
    final keyLabel = isHidden ? _mask(k.key) : k.key;
    final display = hasAlias ? alias : keyLabel;
    final usageCount = ApiKeyManager().getKeyState(k.id)?.totalRequests ?? 0;
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
                      defaultTargetPlatform == TargetPlatform.linux ||
                      defaultTargetPlatform == TargetPlatform.macOS;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          // 状态条
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 14),
          // Key 信息 - 三行布局
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行：名字（或 key）
                if (hasAlias)
                  Text(
                    alias,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: k.isEnabled ? null : cs.onSurface.withOpacity(0.5)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                // 第二行：key 本身
                const SizedBox(height: 2),
                isHidden
                    ? Text(
                        keyLabel,
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.6)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : SelectableText(
                        k.key,
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.6)),
                        maxLines: 1,
                      ),
                // 第三行：优先级 + 使用次数
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (_strategy == LoadBalanceStrategy.priority && k.priority <= 10) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('P${k.priority}', style: TextStyle(color: cs.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _statusText(status),
                      style: TextStyle(color: statusColor, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '已调用 $usageCount 次',
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 右侧按钮：眼睛、复制、拖动手柄
          IconButton(
            icon: Icon(isHidden ? Lucide.Eye : Lucide.EyeOff, size: 16, color: cs.onSurface.withOpacity(0.4)),
            visualDensity: VisualDensity.compact,
            tooltip: isHidden ? '显示' : '隐藏',
            onPressed: () {
              setState(() {
                if (isHidden) {
                  _hiddenKeyIds.remove(token);
                } else {
                  _hiddenKeyIds.add(token);
                }
              });
            },
          ),
          IconButton(
            icon: Icon(Lucide.Copy, size: 16, color: cs.onSurface.withOpacity(0.4)),
            visualDensity: VisualDensity.compact,
            tooltip: '复制',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: k.key));
              showAppSnackBar(context, message: '已复制', type: NotificationType.success);
            },
          ),
          // 拖拽手柄
          if (canReorder) ...[
            const SizedBox(width: 4),
            ReorderableDragStartListener(
              index: index,
              child: Icon(Lucide.GripVertical, color: cs.onSurface.withOpacity(0.2), size: 20),
            ),
          ],
        ],
      ),
    );

    // 使用触感列表行组件
    return _TactileKeyRow(
      key: ValueKey(k.id),
      onTap: () => _editKey(context, realIndex),
      onSecondaryTap: isDesktop ? (pos) => _showContextMenu(context, k, realIndex, pos) : null,
      onLongPress: !isDesktop ? (pos) => _showContextMenu(context, k, realIndex, pos) : null,
      child: content,
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

  Widget _buildKeyRowContent(BuildContext context, ApiKeyConfig k, int index, bool isHidden, String keyLabel, String alias, bool hasAlias, int usageCount, Color statusColor, ApiKeyStatus status, bool canReorder) {
    final cs = Theme.of(context).colorScheme;
    final token = _revealToken(k, index);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          // 状态条
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 14),
          // Key 信息 - 三行布局
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasAlias)
                  Text(
                    alias,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: k.isEnabled ? null : cs.onSurface.withOpacity(0.5)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 2),
                isHidden
                    ? Text(
                        keyLabel,
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.6)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : SelectableText(
                        k.key,
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.6)),
                        maxLines: 1,
                      ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (_strategy == LoadBalanceStrategy.priority && k.priority <= 10) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('P${k.priority}', style: TextStyle(color: cs.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _statusText(status),
                      style: TextStyle(color: statusColor, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '已调用 $usageCount 次',
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 右侧按钮
          _TactileIconButton(
            icon: isHidden ? Lucide.Eye : Lucide.EyeOff,
            color: cs.onSurface.withOpacity(0.4),
            tooltip: isHidden ? '显示' : '隐藏',
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
          _TactileIconButton(
            icon: Lucide.Copy,
            color: cs.onSurface.withOpacity(0.4),
            tooltip: '复制',
            onTap: () {
              Clipboard.setData(ClipboardData(text: k.key));
              showAppSnackBar(context, message: '已复制', type: NotificationType.success);
            },
          ),
          if (canReorder) ...[
            const SizedBox(width: 4),
            ReorderableDragStartListener(
              index: index,
              child: Icon(Lucide.GripVertical, color: cs.onSurface.withOpacity(0.2), size: 20),
            ),
          ],
        ],
      ),
    );
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
  late TextEditingController _baseUrlController;

  @override
  void initState() {
    super.initState();
    _apiKeys = List.from(SearchServiceFactory.getApiKeys(widget.service));
    _strategy = SearchServiceFactory.getStrategy(widget.service);
    _baseUrlController = TextEditingController(
      text: SearchServiceFactory.getBaseUrl(widget.service) ?? '',
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  void _save() {
    final baseUrl = _baseUrlController.text.trim();
    final updated = SearchServiceFactory.updateMultiKey(
      widget.service,
      _apiKeys,
      _strategy,
      baseUrl: baseUrl.isEmpty ? null : baseUrl,
    );
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

            // Base URL configuration (only for services that support it)
            if (SearchServiceFactory.supportsBaseUrl(widget.service))
              _buildBaseUrlRow(context),

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

  Widget _buildBaseUrlRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Lucide.Link, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              const Text('自定义 API 地址', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('(可选)', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5))),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _baseUrlController,
            decoration: InputDecoration(
              hintText: ExaOptions.defaultBaseUrl,
              hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.3)),
              filled: true,
              fillColor: isDark ? Colors.white10 : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 4),
          Text(
            '留空使用官方地址，填写中转地址可使用第三方服务',
            style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
          ),
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

  String _mask(String key) {
    if (key.length <= 8) return key;
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  String _statusText(ApiKeyStatus st) {
    switch (st) {
      case ApiKeyStatus.active: return '正常';
      case ApiKeyStatus.disabled: return '已禁用';
      case ApiKeyStatus.error: return '错误';
      case ApiKeyStatus.rateLimited: return '限流中';
    }
  }

  void _showContextMenu(BuildContext context, ApiKeyConfig k, int realIndex, Offset position) {
    final cs = Theme.of(context).colorScheme;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.surface,
      elevation: 8,
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Lucide.Pencil, size: 16, color: cs.primary),
            const SizedBox(width: 12),
            const Text('编辑'),
          ]),
        ),
        PopupMenuItem(
          value: 'test',
          child: Row(children: [
            Icon(Lucide.Play, size: 16, color: Colors.green),
            const SizedBox(width: 12),
            const Text('测试'),
          ]),
        ),
        PopupMenuItem(
          value: 'copy',
          child: Row(children: [
            Icon(Lucide.Copy, size: 16, color: cs.onSurface.withOpacity(0.7)),
            const SizedBox(width: 12),
            const Text('复制'),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Lucide.Trash2, size: 16, color: cs.error),
            const SizedBox(width: 12),
            Text('删除', style: TextStyle(color: cs.error)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == 'edit') _editKey(context, realIndex);
      if (value == 'test') _testKey(k);
      if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: k.key));
        showAppSnackBar(context, message: '已复制', type: NotificationType.success);
      }
      if (value == 'delete') _deleteKey(realIndex);
    });
  }

  void _deleteKey(int index) {
    if (_apiKeys.length <= 1) {
      showAppSnackBar(context, message: '至少需要保留一个Key', type: NotificationType.info);
      return;
    }
    setState(() => _apiKeys.removeAt(index));
    _save();
  }

  Future<void> _testKey(ApiKeyConfig k) async {
    showAppSnackBar(context, message: '正在测试...', type: NotificationType.info);
    try {
      final testService = SearchServiceFactory.updateMultiKey(
        widget.service,
        [k.copyWith(isEnabled: true)],
        LoadBalanceStrategy.roundRobin,
      );
      final searchService = SearchService.getService(testService);
      await searchService.search(
        query: 'test',
        commonOptions: const SearchCommonOptions(resultSize: 1),
        serviceOptions: testService,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      showAppSnackBar(context, message: '测试成功 ✓', type: NotificationType.success);
    } on TimeoutException {
      if (!mounted) return;
      showAppSnackBar(context, message: '测试超时', type: NotificationType.error);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('401')) {
        showAppSnackBar(context, message: 'Key 无效', type: NotificationType.error);
      } else if (msg.contains('429')) {
        showAppSnackBar(context, message: '请求频率限制', type: NotificationType.warning);
      } else {
        showAppSnackBar(context, message: '测试失败: ${msg.length > 50 ? '${msg.substring(0, 50)}...' : msg}', type: NotificationType.error);
      }
    }
  }

  Widget _keyRow(BuildContext context, ApiKeyConfig k, int index, {required bool canReorder}) {
    final cs = Theme.of(context).colorScheme;
    final status = _getKeyStatus(k.id);
    final token = _revealToken(k, index);
    // 默认展示key（不在集合中=展示）
    final isHidden = _hiddenKeyIds.contains(token);
    
    Color statusColor;
    switch (status) {
      case ApiKeyStatus.active:
        statusColor = Colors.green;
        break;
      case ApiKeyStatus.error:
        statusColor = cs.error;
        break;
      case ApiKeyStatus.rateLimited:
        statusColor = Colors.orange;
        break;
      case ApiKeyStatus.disabled:
        statusColor = cs.onSurface.withOpacity(0.4);
        break;
    }

    final realIndex = _apiKeys.indexWhere((key) => key.id == k.id);
    final alias = (k.name ?? '').trim();
    final hasAlias = alias.isNotEmpty;
    final keyLabel = isHidden ? _mask(k.key) : k.key;
    final usageCount = ApiKeyManager().getKeyState(k.id)?.totalRequests ?? 0;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          // 状态条
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 14),
          // Key 信息 - 三行布局
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行：名字（或 key）
                if (hasAlias)
                  Text(
                    alias,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: k.isEnabled ? null : cs.onSurface.withOpacity(0.5)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                // 第二行：key 本身
                const SizedBox(height: 2),
                isHidden
                    ? Text(
                        keyLabel,
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.6)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : SelectableText(
                        k.key,
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.6)),
                        maxLines: 1,
                      ),
                // 第三行：优先级 + 使用次数
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (_strategy == LoadBalanceStrategy.priority && k.priority <= 10) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('P${k.priority}', style: TextStyle(color: cs.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _statusText(status),
                      style: TextStyle(color: statusColor, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '已调用 $usageCount 次',
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 右侧按钮：眼睛、复制、拖动手柄
          IconButton(
            icon: Icon(isHidden ? Lucide.Eye : Lucide.EyeOff, size: 16, color: cs.onSurface.withOpacity(0.4)),
            visualDensity: VisualDensity.compact,
            tooltip: isHidden ? '显示' : '隐藏',
            onPressed: () {
              setState(() {
                if (isHidden) {
                  _hiddenKeyIds.remove(token);
                } else {
                  _hiddenKeyIds.add(token);
                }
              });
            },
          ),
          IconButton(
            icon: Icon(Lucide.Copy, size: 16, color: cs.onSurface.withOpacity(0.4)),
            visualDensity: VisualDensity.compact,
            tooltip: '复制',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: k.key));
              showAppSnackBar(context, message: '已复制', type: NotificationType.success);
            },
          ),
          // 拖拽手柄
          if (canReorder) ...[
            const SizedBox(width: 4),
            ReorderableDragStartListener(
              index: index,
              child: Icon(Lucide.GripVertical, color: cs.onSurface.withOpacity(0.2), size: 20),
            ),
          ],
        ],
      ),
    );

    // 使用触感列表行组件
    return _TactileKeyRow(
      key: ValueKey(k.id),
      onTap: () => _editKey(context, realIndex),
      onLongPress: (pos) => _showContextMenu(context, k, realIndex, pos),
      child: content,
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

// ============================================================================
// Tactile Widgets - 触感反馈组件
// ============================================================================

/// iOS 风格触感图标按钮 - 带缩放动画
class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.tooltip,
    this.size = 16,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;

  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      widget.icon,
      size: widget.size,
      color: _pressed ? widget.color.withOpacity(0.5) : widget.color,
    );

    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.85 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: icon,
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// 触感列表行 - 带缩放和颜色变化动画
class _TactileKeyRow extends StatefulWidget {
  const _TactileKeyRow({
    super.key,
    required this.child,
    required this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback onTap;
  final void Function(Offset position)? onSecondaryTap;
  final void Function(Offset position)? onLongPress;

  @override
  State<_TactileKeyRow> createState() => _TactileKeyRowState();
}

class _TactileKeyRowState extends State<_TactileKeyRow> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
                      defaultTargetPlatform == TargetPlatform.linux ||
                      defaultTargetPlatform == TargetPlatform.macOS;

    return MouseRegion(
      onEnter: isDesktop ? (_) => setState(() => _hovered = true) : null,
      onExit: isDesktop ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.soft();
          widget.onTap();
        },
        onSecondaryTapUp: widget.onSecondaryTap != null
            ? (details) => widget.onSecondaryTap!(details.globalPosition)
            : null,
        onLongPressStart: widget.onLongPress != null
            ? (details) {
                Haptics.medium();
                widget.onLongPress!(details.globalPosition);
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          color: _pressed
              ? cs.primary.withOpacity(0.08)
              : _hovered
                  ? cs.primary.withOpacity(0.04)
                  : Colors.transparent,
          child: AnimatedScale(
            scale: _pressed ? 0.98 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
