import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/search/search_service.dart';
import '../../../core/models/api_keys.dart';
import '../../../core/services/api_key_manager.dart';

// Windows/Desktop Dialog for multi-key management
class KeyManagementDialog extends StatefulWidget {
  final TavilyOptions service;
  
  const KeyManagementDialog({super.key, required this.service});
  
  @override
  State<KeyManagementDialog> createState() => _KeyManagementDialogState();
}

class _KeyManagementDialogState extends State<KeyManagementDialog> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 480, maxWidth: 640, maxHeight: 700),
        child: Material(
          color: cs.surface,
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? Colors.white.withOpacity(0.08) : cs.outlineVariant.withOpacity(0.25),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title bar
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Text('API Key 管理', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            
            // Strategy selection
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const Text('负载均衡策略：'),
                  const SizedBox(width: 12),
                  DropdownButton<LoadBalanceStrategy>(
                    value: widget.service.strategy,
                    items: LoadBalanceStrategy.values.map((s) => 
                      DropdownMenuItem(
                        value: s,
                        child: Text(_strategyName(s)),
                      )
                    ).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {});
                      }
                    },
                  ),
                ],
              ),
            ),
            
            // Key list
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: widget.service.apiKeys.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (ctx, index) => _buildDesktopKeyItem(index, cs, isDark),
              ),
            ),
            
            const Divider(height: 1),
            
            // Bottom buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('添加 Key'),
                    onPressed: () => _addKey(context),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('完成'),
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
  
  Widget _buildDesktopKeyItem(int index, ColorScheme cs, bool isDark) {
    final keyConfig = widget.service.apiKeys[index];
    
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            // Enable switch
            Switch(
              value: keyConfig.isEnabled,
              onChanged: (v) => _toggleKey(index, v),
            ),
            const SizedBox(width: 12),
            
            // Key info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    keyConfig.name ?? 'API Key ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '已使用: ${ApiKeyManager().getKeyState(keyConfig.id)?.totalRequests ?? 0}次 | '
                    '${keyConfig.maxRequestsPerMinute != null ? "限流: ${keyConfig.maxRequestsPerMinute}/分钟" : "无限制"}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            
            // Action buttons
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () => _editKey(context, index),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: () => _deleteKey(index),
            ),
          ],
        ),
      ),
    );
  }
  
  void _toggleKey(int index, bool enabled) {
    setState(() {
      final oldConfig = widget.service.apiKeys[index];
      widget.service.apiKeys[index] = oldConfig.copyWith(
        isEnabled: enabled,
      );
    });
    _saveService();
  }
  
  Future<void> _addKey(BuildContext context) async {
    await _showKeyDialog(context: context, editIndex: null);
  }
  
  Future<void> _editKey(BuildContext context, int index) async {
    await _showKeyDialog(context: context, editIndex: index);
  }
  
  void _deleteKey(int index) {
    if (widget.service.apiKeys.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要保留一个 API Key')),
      );
      return;
    }
    setState(() {
      widget.service.removeKey(index);
    });
    _saveService();
  }
  
  Future<void> _showKeyDialog({required BuildContext context, int? editIndex}) async {
    final keyController = TextEditingController();
    final nameController = TextEditingController();
    final limitController = TextEditingController();
    
    if (editIndex != null) {
      final config = widget.service.apiKeys[editIndex];
      keyController.text = config.key;
      nameController.text = config.name ?? '';
      limitController.text = config.maxRequestsPerMinute?.toString() ?? '';
    }
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editIndex == null ? '添加 API Key' : '编辑 API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: const InputDecoration(labelText: 'API Key'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '名称（可选）'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: limitController,
              decoration: const InputDecoration(labelText: '每分钟限流（可选）'),
              keyboardType: TextInputType.number,
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
                    )
                  : widget.service.apiKeys[editIndex].copyWith(
                      key: key,
                      name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
                      maxRequestsPerMinute: limitController.text.trim().isEmpty
                          ? null
                          : int.tryParse(limitController.text.trim()),
                    );
              
              setState(() {
                if (editIndex == null) {
                  widget.service.addKey(config);
                } else {
                  widget.service.updateKey(editIndex, config);
                }
              });
              _saveService();
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
  
  void _saveService() {
    final sp = Provider.of<SettingsProvider>(context, listen: false);
    sp.setSearchServices(sp.searchServices);
  }
  
  String _strategyName(LoadBalanceStrategy s) {
    switch (s) {
      case LoadBalanceStrategy.roundRobin:
        return '轮询';
      case LoadBalanceStrategy.random:
        return '随机';
      case LoadBalanceStrategy.leastUsed:
        return '最少使用';
      case LoadBalanceStrategy.priority:
        return '优先级';
    }
  }
}

// Android/Mobile Sheet for multi-key management
class KeyManagementSheet extends StatefulWidget {
  final TavilyOptions service;
  
  const KeyManagementSheet({super.key, required this.service});
  
  @override
  State<KeyManagementSheet> createState() => _KeyManagementSheetState();
}

class _KeyManagementSheetState extends State<KeyManagementSheet> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Title
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'API Key 管理',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            
            // Strategy selection
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Text('负载均衡：'),
                  const Spacer(),
                  DropdownButton<LoadBalanceStrategy>(
                    value: widget.service.strategy,
                    items: LoadBalanceStrategy.values.map((s) => 
                      DropdownMenuItem(value: s, child: Text(_strategyName(s)))
                    ).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() {});
                    },
                  ),
                ],
              ),
            ),
            
            const Divider(),
            
            // Key list
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.service.apiKeys.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, index) => _buildMobileKeyItem(index),
              ),
            ),
            
            // Add button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('添加 API Key'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _addKey(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMobileKeyItem(int index) {
    final keyConfig = widget.service.apiKeys[index];
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      leading: Icon(
        keyConfig.isEnabled ? Icons.check_circle : Icons.cancel,
        color: keyConfig.isEnabled ? Colors.green : Colors.grey,
      ),
      title: Text(keyConfig.name ?? 'API Key ${index + 1}'),
      subtitle: Text(
        '已使用: ${ApiKeyManager().getKeyState(keyConfig.id)?.totalRequests ?? 0}次 | '
        '${keyConfig.maxRequestsPerMinute != null ? "限流: ${keyConfig.maxRequestsPerMinute}/分钟" : "无限制"}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: keyConfig.isEnabled,
            onChanged: (v) => _toggleKey(index, v),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'edit') {
                _editKey(context, index);
              } else if (value == 'delete') {
                _deleteKey(index);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
  
  void _toggleKey(int index, bool enabled) {
    setState(() {
      final oldConfig = widget.service.apiKeys[index];
      widget.service.apiKeys[index] = oldConfig.copyWith(
        isEnabled: enabled,
      );
    });
    _saveService();
  }
  
  Future<void> _addKey(BuildContext context) async {
    await _showKeyDialog(context: context, editIndex: null);
  }
  
  Future<void> _editKey(BuildContext context, int index) async {
    await _showKeyDialog(context: context, editIndex: index);
  }
  
  void _deleteKey(int index) {
    if (widget.service.apiKeys.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要保留一个 API Key')),
      );
      return;
    }
    setState(() {
      widget.service.removeKey(index);
    });
    _saveService();
  }
  
  Future<void> _showKeyDialog({required BuildContext context, int? editIndex}) async {
    final keyController = TextEditingController();
    final nameController = TextEditingController();
    final limitController = TextEditingController();
    
    if (editIndex != null) {
      final config = widget.service.apiKeys[editIndex];
      keyController.text = config.key;
      nameController.text = config.name ?? '';
      limitController.text = config.maxRequestsPerMinute?.toString() ?? '';
    }
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editIndex == null ? '添加 API Key' : '编辑 API Key'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyController,
                decoration: const InputDecoration(labelText: 'API Key'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '名称（可选）'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limitController,
                decoration: const InputDecoration(labelText: '每分钟限流（可选）'),
                keyboardType: TextInputType.number,
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
                    )
                  : widget.service.apiKeys[editIndex].copyWith(
                      key: key,
                      name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
                      maxRequestsPerMinute: limitController.text.trim().isEmpty
                          ? null
                          : int.tryParse(limitController.text.trim()),
                    );
              
              setState(() {
                if (editIndex == null) {
                  widget.service.addKey(config);
                } else {
                  widget.service.updateKey(editIndex, config);
                }
              });
              _saveService();
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
  
  void _saveService() {
    final sp = Provider.of<SettingsProvider>(context, listen: false);
    sp.setSearchServices(sp.searchServices);
  }
  
  String _strategyName(LoadBalanceStrategy s) {
    switch (s) {
      case LoadBalanceStrategy.roundRobin:
        return '轮询';
      case LoadBalanceStrategy.random:
        return '随机';
      case LoadBalanceStrategy.leastUsed:
        return '最少使用';
      case LoadBalanceStrategy.priority:
        return '优先级';
    }
  }
}
