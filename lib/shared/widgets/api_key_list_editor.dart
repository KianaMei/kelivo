import 'package:flutter/material.dart';
import '../../core/models/api_keys.dart';
import '../../core/services/api_key_manager.dart';
import '../../icons/lucide_adapter.dart';
import '../../utils/safe_tooltip.dart';
import 'ios_switch.dart';

/// Shared widget for editing a list of API keys with load balancing strategy.
/// Used by both Provider multi-key management and Search service multi-key management.
class ApiKeyListEditor extends StatefulWidget {
  const ApiKeyListEditor({
    super.key,
    required this.keys,
    required this.strategy,
    required this.onKeysChanged,
    required this.onStrategyChanged,
    this.onTestKey,
    this.allowReorder = false,
    this.showStrategySelector = true,
    this.showFilter = false,
    this.showBatchActions = false,
  });

  final List<ApiKeyConfig> keys;
  final LoadBalanceStrategy strategy;
  final ValueChanged<List<ApiKeyConfig>> onKeysChanged;
  final ValueChanged<LoadBalanceStrategy> onStrategyChanged;
  /// Optional callback to test a single key. Returns true if test passed.
  final Future<bool> Function(ApiKeyConfig key)? onTestKey;
  /// Allow drag-to-reorder keys
  final bool allowReorder;
  /// Show strategy selector at top
  final bool showStrategySelector;
  /// Show filter bar (all/normal/error)
  final bool showFilter;
  /// Show batch actions (enable all/disable all)
  final bool showBatchActions;

  @override
  State<ApiKeyListEditor> createState() => ApiKeyListEditorState();
}

enum _FilterStatus { all, normal, error }

class ApiKeyListEditorState extends State<ApiKeyListEditor> {
  int? _editingIndex;
  bool _adding = false;
  final _editKeyController = TextEditingController();
  final _editNameController = TextEditingController();
  final _editLimitController = TextEditingController();
  int _editPriority = 5;
  bool _editUnlimited = true;
  final Set<int> _testingKeys = {};
  _FilterStatus _filterStatus = _FilterStatus.all;
  ApiKeyConfig? _lastDeleted;
  int? _lastDeletedIndex;

  @override
  void dispose() {
    _editKeyController.dispose();
    _editNameController.dispose();
    _editLimitController.dispose();
    super.dispose();
  }

  void _beginEdit(int index) {
    final k = widget.keys[index];
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

    final newKeys = List<ApiKeyConfig>.from(widget.keys);
    if (_adding) {
      final cfg = ApiKeyConfig.create(key).copyWith(
        name: _editNameController.text.trim().isEmpty ? null : _editNameController.text.trim(),
        maxRequestsPerMinute: (rpm == null || rpm <= 0) ? null : rpm,
        priority: clampedPri,
      );
      newKeys.add(cfg);
    } else if (_editingIndex != null && _editingIndex! >= 0 && _editingIndex! < newKeys.length) {
      final old = newKeys[_editingIndex!];
      newKeys[_editingIndex!] = old.copyWith(
        key: key,
        name: _editNameController.text.trim().isEmpty ? null : _editNameController.text.trim(),
        maxRequestsPerMinute: (rpm == null || rpm <= 0) ? null : rpm,
        priority: clampedPri,
      );
    }
    widget.onKeysChanged(newKeys);
    _cancelEdit();
  }

  void _deleteKey(int index, BuildContext context) {
    if (widget.keys.length <= 1) return;
    final deleted = widget.keys[index];
    _lastDeleted = deleted;
    _lastDeletedIndex = index;
    final newKeys = List<ApiKeyConfig>.from(widget.keys)..removeAt(index);
    widget.onKeysChanged(newKeys);
    // Show undo snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除 "${deleted.name ?? 'API Key'}"'),
        action: SnackBarAction(label: '撤销', onPressed: _undoDelete),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _undoDelete() {
    if (_lastDeleted == null) return;
    final newKeys = List<ApiKeyConfig>.from(widget.keys);
    final idx = (_lastDeletedIndex ?? newKeys.length).clamp(0, newKeys.length);
    newKeys.insert(idx, _lastDeleted!);
    widget.onKeysChanged(newKeys);
    _lastDeleted = null;
    _lastDeletedIndex = null;
  }

  void _enableAll() {
    final newKeys = widget.keys.map((k) => k.copyWith(isEnabled: true)).toList();
    widget.onKeysChanged(newKeys);
  }

  void _disableAll() {
    final newKeys = widget.keys.map((k) => k.copyWith(isEnabled: false)).toList();
    widget.onKeysChanged(newKeys);
  }

  _FilterStatus _getKeyStatus(ApiKeyConfig k) {
    final state = ApiKeyManager().getKeyState(k.id);
    if (state?.status == 'error') return _FilterStatus.error;
    return _FilterStatus.normal;
  }

  List<ApiKeyConfig> get _filteredKeys {
    if (_filterStatus == _FilterStatus.all) return widget.keys;
    return widget.keys.where((k) => _getKeyStatus(k) == _filterStatus).toList();
  }

  void _toggleEnabled(int index, bool enabled) {
    final newKeys = List<ApiKeyConfig>.from(widget.keys);
    newKeys[index] = newKeys[index].copyWith(isEnabled: enabled);
    widget.onKeysChanged(newKeys);
  }

  Future<void> _testKey(int index) async {
    if (widget.onTestKey == null || _testingKeys.contains(index)) return;
    setState(() => _testingKeys.add(index));
    try {
      await widget.onTestKey!(widget.keys[index]);
    } finally {
      if (mounted) setState(() => _testingKeys.remove(index));
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final newKeys = List<ApiKeyConfig>.from(widget.keys);
    final item = newKeys.removeAt(oldIndex);
    newKeys.insert(newIndex, item);
    widget.onKeysChanged(newKeys);
  }

  Widget _buildFilterBar(ColorScheme cs) {
    final total = widget.keys.length;
    final normal = widget.keys.where((k) => _getKeyStatus(k) == _FilterStatus.normal).length;
    final errors = widget.keys.where((k) => _getKeyStatus(k) == _FilterStatus.error).length;

    Widget chip(String label, int count, _FilterStatus status, Color color) {
      final isSelected = _filterStatus == status;
      return FilterChip(
        label: Text('$label ($count)'),
        selected: isSelected,
        onSelected: (_) => setState(() => _filterStatus = isSelected ? _FilterStatus.all : status),
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
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('全部', total, _FilterStatus.all, cs.primary),
          const SizedBox(width: 8),
          chip('正常', normal, _FilterStatus.normal, Colors.green),
          const SizedBox(width: 8),
          chip('错误', errors, _FilterStatus.error, cs.error),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayKeys = _filteredKeys;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter bar
        if (widget.showFilter) ...[
          _buildFilterBar(cs),
          const SizedBox(height: 12),
        ],
        // Strategy selector - Provider style
        if (widget.showStrategySelector) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('多Key访问策略', style: TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(width: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final s in LoadBalanceStrategy.values)
                          ChoiceChip(
                            label: Text(
                              _strategyLabel(s),
                              style: TextStyle(
                                fontSize: 12,
                                color: widget.strategy == s ? cs.onPrimary : cs.onSurface,
                              ),
                            ),
                            selected: widget.strategy == s,
                            selectedColor: cs.primary,
                            backgroundColor: cs.surfaceVariant,
                            shape: StadiumBorder(
                              side: BorderSide(color: cs.outline.withOpacity(0.4)),
                            ),
                            onSelected: (selected) {
                              if (selected && s != widget.strategy) {
                                widget.onStrategyChanged(s);
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
                if (widget.strategy == LoadBalanceStrategy.priority)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 6),
                    child: Text(
                      '💡 优先级规则：数字越小优先级越高（1最高，10最低）',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                    ),
                  ),
              ],
            ),
          ),
        ],
        // Keys list
        Expanded(
          child: widget.allowReorder
              ? ReorderableListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: displayKeys.length + (_adding ? 1 : 0),
                  onReorder: _onReorder,
                  itemBuilder: (ctx, i) {
                    if (_adding && i == displayKeys.length) {
                      return _buildKeyCard(context, null, cs, isDark, isNew: true, key: const ValueKey('new'));
                    }
                    final realIndex = widget.keys.indexOf(displayKeys[i]);
                    return _buildKeyCard(context, realIndex, cs, isDark, key: ValueKey(displayKeys[i].id));
                  },
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: displayKeys.length + (_adding ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (_adding && i == displayKeys.length) {
                      return _buildKeyCard(context, null, cs, isDark, isNew: true);
                    }
                    final realIndex = widget.keys.indexOf(displayKeys[i]);
                    return _buildKeyCard(context, realIndex, cs, isDark);
                  },
                ),
        ),
        const SizedBox(height: 8),
        // Bottom bar
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _beginAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加 Key'),
            ),
            if (widget.showBatchActions) ...[
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Lucide.MoreVertical, size: 18),
                tooltip: '批量操作',
                onSelected: (v) {
                  if (v == 'enable_all') _enableAll();
                  if (v == 'disable_all') _disableAll();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'enable_all', child: Row(children: [
                    Icon(Lucide.circleDot, size: 18, color: cs.primary),
                    const SizedBox(width: 12),
                    const Text('启用所有'),
                  ])),
                  PopupMenuItem(value: 'disable_all', child: Row(children: [
                    Icon(Lucide.CircleX, size: 18, color: cs.onSurface.withOpacity(0.7)),
                    const SizedBox(width: 12),
                    const Text('禁用所有'),
                  ])),
                ],
              ),
            ],
            const Spacer(),
            Text('${widget.keys.length} 个 Key', style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
          ],
        ),
      ],
    );
  }

  final Set<String> _hiddenKeyIds = {};

  String _strategyLabel(LoadBalanceStrategy s) {
    switch (s) {
      case LoadBalanceStrategy.priority: return '优先级';
      case LoadBalanceStrategy.leastUsed: return '最少使用';
      case LoadBalanceStrategy.random: return '随机';
      case LoadBalanceStrategy.roundRobin: default: return '轮询';
    }
  }

  String _maskKey(String key) {
    if (key.length <= 8) return key;
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  Color _statusColor(ApiKeyConfig k, ColorScheme cs) {
    final state = ApiKeyManager().getKeyState(k.id);
    if (state?.status == 'error') return cs.error;
    if (!k.isEnabled) return cs.outline;
    return Colors.green;
  }

  String _statusText(ApiKeyConfig k) {
    final state = ApiKeyManager().getKeyState(k.id);
    if (state?.status == 'error') return '错误';
    if (!k.isEnabled) return '已禁用';
    return '正常';
  }

  Widget _buildKeyCard(BuildContext context, int? index, ColorScheme cs, bool isDark, {bool isNew = false, Key? key}) {
    final bg = Color.alphaBlend(cs.primary.withOpacity(isDark ? 0.05 : 0.03), cs.surface);
    final border = cs.outlineVariant.withOpacity(isDark ? 0.16 : 0.18);
    final isEditing = isNew ? _adding : (_editingIndex == index);
    final k = isNew ? null : widget.keys[index!];

    if (isNew || isEditing) {
      return Container(
        key: key,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isNew ? '添加新的 API Key' : '编辑 API Key', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(controller: _editNameController, decoration: const InputDecoration(labelText: '名称（可选）', hintText: '例如：google / 备用Key', isDense: true)),
            const SizedBox(height: 10),
            TextField(controller: _editKeyController, decoration: const InputDecoration(labelText: 'API Key', isDense: true)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('优先级', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(min: 1, max: 10, divisions: 9, label: '$_editPriority', value: _editPriority.toDouble(),
                    onChanged: (v) => setState(() => _editPriority = v.round().clamp(1, 10))),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: cs.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text('P$_editPriority', style: TextStyle(color: cs.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _cancelEdit, child: const Text('取消')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _commitEdit, child: Text(isNew ? '添加' : '保存')),
              ],
            ),
          ],
        ),
      );
    }

    // Display mode - Provider style
    final token = '${k!.id}_$index';
    final isHidden = !_hiddenKeyIds.contains(token);
    final alias = (k.name ?? '').trim();
    final keyLabel = isHidden ? _maskKey(k.key) : k.key;
    final hasAlias = alias.isNotEmpty;
    final display = hasAlias ? alias : keyLabel;
    final statusClr = _statusColor(k, cs);

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Status bar
            Container(
              width: 3, height: 36,
              decoration: BoxDecoration(color: statusClr, borderRadius: BorderRadius.circular(1.5)),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(display, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: cs.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text('P${k.priority}', style: TextStyle(color: cs.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  if (hasAlias) ...[
                    const SizedBox(height: 2),
                    Text(keyLabel, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5), fontFamily: 'monospace'),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(_statusText(k), style: TextStyle(color: statusClr, fontSize: 11)),
                      const SizedBox(width: 8),
                      Text('已调用 ${ApiKeyManager().getKeyState(k.id)?.totalRequests ?? 0} 次',
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
                    ],
                  ),
                ],
              ),
            ),
            // Actions
            IconButton(
              icon: Icon(isHidden ? Lucide.Eye : Lucide.EyeOff, size: 16),
              color: cs.onSurface.withOpacity(0.4),
              onPressed: () => setState(() {
                if (isHidden) _hiddenKeyIds.add(token); else _hiddenKeyIds.remove(token);
              }),
              tooltip: safeTooltipMessage(isHidden ? '显示' : '隐藏'),
              visualDensity: VisualDensity.compact,
            ),
            IosSwitch(
              value: k.isEnabled,
              onChanged: (v) => _toggleEnabled(index!, v),
              width: 40,
              height: 24,
            ),
            const SizedBox(width: 4),
            if (widget.onTestKey != null)
              IconButton(
                onPressed: _testingKeys.contains(index) ? null : () => _testKey(index!),
                icon: _testingKeys.contains(index)
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(cs.primary)))
                    : Icon(Lucide.HeartPulse, size: 16, color: cs.primary),
                tooltip: safeTooltipMessage('测试'),
                visualDensity: VisualDensity.compact,
              ),
            IconButton(
              onPressed: () => _beginEdit(index!),
              icon: Icon(Lucide.Pencil, size: 16, color: cs.primary),
              tooltip: safeTooltipMessage('编辑'),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: widget.keys.length > 1 ? () => _deleteKey(index!, context) : null,
              icon: Icon(Lucide.Trash2, size: 16, color: widget.keys.length > 1 ? cs.error : cs.outline),
              tooltip: safeTooltipMessage('删除'),
              visualDensity: VisualDensity.compact,
            ),
            // 拖拽手柄 - 和 Provider 一致
            if (widget.allowReorder) ...[
              const SizedBox(width: 4),
              ReorderableDragStartListener(
                index: index!,
                child: Icon(Lucide.GripVertical, color: cs.onSurface.withOpacity(0.2), size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
