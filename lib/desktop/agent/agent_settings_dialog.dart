import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/models/agent.dart';
import '../../core/providers/agent_provider_io.dart';
import '../../core/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../icons/lucide_adapter.dart';
import '../../shared/widgets/snackbar.dart';

enum ApiSource {
  provider, // Use existing provider from SettingsProvider
  custom,   // Use custom BaseURL + Key
}

class AgentSettingsDialog extends StatefulWidget {
  final Agent? agent; // If null, creating new agent

  const AgentSettingsDialog({super.key, this.agent});

  @override
  State<AgentSettingsDialog> createState() => _AgentSettingsDialogState();
}

class _AgentSettingsDialogState extends State<AgentSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  
  // General State
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _instructionsController;
  AgentPermissionMode _permissionMode = AgentPermissionMode.requireApproval;
  
  // API & Model State
  late TextEditingController _modelIdController;
  late TextEditingController _customBaseUrlController;
  late TextEditingController _customApiKeyController;

  ApiSource _apiSource = ApiSource.provider;
  String? _selectedProviderKey;
  
  // Navigation State
  int _selectedIndex = 0; // 0: General, 1: API & Model

  @override
  void initState() {
    super.initState();
    final a = widget.agent;
    _nameController = TextEditingController(text: a?.name ?? '');
    _descController = TextEditingController(text: a?.description ?? '');
    _instructionsController = TextEditingController(text: a?.instructions ?? '');
    _modelIdController = TextEditingController(text: a?.model ?? '');
    _permissionMode = a?.permissionMode ?? AgentPermissionMode.requireApproval;

    // Initialize API Config Logic
    if (a != null) {
      if (a.customBaseUrl != null && a.customBaseUrl!.isNotEmpty) {
        _apiSource = ApiSource.custom;
        _customBaseUrlController = TextEditingController(text: a.customBaseUrl);
        _customApiKeyController = TextEditingController(text: a.customApiKey ?? '');
      } else {
        _apiSource = ApiSource.provider;
        _selectedProviderKey = a.apiProvider;
        _customBaseUrlController = TextEditingController();
        _customApiKeyController = TextEditingController();
      }
    } else {
      // Default for new agent
      _apiSource = ApiSource.provider;
      _selectedProviderKey = null; // Will default to first available
      _customBaseUrlController = TextEditingController();
      _customApiKeyController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _instructionsController.dispose();
    _modelIdController.dispose();
    _customBaseUrlController.dispose();
    _customApiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    // Initialize selected provider if null
    if (_apiSource == ApiSource.provider && _selectedProviderKey == null) {
      final settings = context.read<SettingsProvider>();
      if (settings.providerConfigs.isNotEmpty) {
        // Try to find OpenAI or just first
        _selectedProviderKey = settings.providerConfigs.keys.firstWhere(
            (k) => k.toLowerCase().contains('openai'),
            orElse: () => settings.providerConfigs.keys.first);
      }
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 800,
        height: 600,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left Sidebar
            Container(
              width: 200,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.03) : const Color(0xFFF5F7FA),
                border: Border(
                  right: BorderSide(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Text(
                      widget.agent == null ? '新建 Agent' : 'Agent设置', // "New Agent" or "Agent Settings"
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  _buildNavItem(0, '常规设置', Lucide.Settings),
                  _buildNavItem(1, 'API 与模型', Lucide.Server), // Replaced Cpu with Server
                  const Spacer(),
                ],
              ),
            ),
            // Right Content
            Expanded(
              child: Column(
                children: [
                   // Content Area
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: KeyedSubtree(
                        key: ValueKey<int>(_selectedIndex),
                        child: _selectedIndex == 0 
                            ? _buildGeneralTab(context) 
                            : _buildApiAndModelTab(context),
                      ),
                    ),
                  ),
                  // Bottom Actions
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.backupPageCancel), // Corrected to backupPageCancel
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _save,
                          child: Text(l10n.backupPageSave), // Corrected to backupPageSave
                        ),
                      ],
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

  Widget _buildNavItem(int index, String title, IconData icon) {
    final selected = _selectedIndex == index;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), // Increased spacing
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedIndex = index),
          borderRadius: BorderRadius.circular(10), // Slightly more rounded
          hoverColor: cs.onSurface.withOpacity(0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 48, // Taller touch target
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: selected ? cs.primaryContainer.withOpacity(0.4) : Colors.transparent, // Uses primaryContainer
              borderRadius: BorderRadius.circular(10),
              border: selected ? Border.all(color: cs.primary.withOpacity(0.1)) : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20, // Slightly larger icon
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? cs.primary : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('基本信息', Lucide.info), // Replaced Info with info
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: _inputDecoration(context, 'Agent 名称', '例如：代码助手'),
              validator: (v) => v?.trim().isEmpty == true ? '名称不能为空' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descController,
              decoration: _inputDecoration(context, '描述', '简短描述该 Agent 的用途'),
              maxLines: 2,
            ),
            const SizedBox(height: 32),
            _buildSectionTitle('系统指令', Lucide.ScrollText),
            const SizedBox(height: 16),
            TextFormField(
              controller: _instructionsController,
              decoration: _inputDecoration(context, '输入系统提示词 (System Prompt)', '你是一个专业的助手...'),
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 32),
            _buildSectionTitle('权限设置', Lucide.Shield),
            const SizedBox(height: 16),
            _buildPermissionModeSelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildApiAndModelTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('API 配置 (API Configuration)', Lucide.Server),
          const SizedBox(height: 16),
          _buildApiSourceToggle(cs),
          const SizedBox(height: 24),
          if (_apiSource == ApiSource.provider) _buildProviderSelector(cs),
          if (_apiSource == ApiSource.custom) _buildCustomFields(cs),
          
          const SizedBox(height: 32),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(0.2)),
          const SizedBox(height: 32),
          
          _buildSectionTitle('模型选择 (Model Selection)', Lucide.Bot),
          const SizedBox(height: 16),
          if (_apiSource == ApiSource.custom)
             // Custom fetch button here
             Padding(
               padding: const EdgeInsets.only(bottom: 16),
               child: FilledButton.tonalIcon( // Using tonalIcon
                 onPressed: _fetchCustomModels,
                 icon: const Icon(Lucide.RefreshCw, size: 16),
                 label: const Text('获取模型列表 (Fetch Models)'),
               ),
             ),

          if (_apiSource == ApiSource.provider)
            _buildProviderModelDropdown(cs)
          else
            TextFormField(
              controller: _modelIdController,
              decoration: _inputDecoration(context, '模型 ID (Model ID)', '例如：gpt-4o'),
            ),
        ],
      ),
    );
  }
  
  // --- Enhanced Model Fetching & Selection ---

  bool _isFetchingModels = false;
  
  Future<void> _fetchCustomModels() async {
    final baseUrl = _customBaseUrlController.text.trim();
    final apiKey = _customApiKeyController.text.trim();
    
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入 Base URL 和 API Key')),
      );
      return;
    }

    setState(() => _isFetchingModels = true);
    
    try {
      // Logic adapted from desktop_api_test_page.dart
      var uriStr = baseUrl;
      if (!uriStr.endsWith('/')) uriStr += '/';
      uriStr += 'models'; // Assuming /models endpoint
      
      final uri = Uri.parse(uriStr);
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer \$apiKey',
      };
      
      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 10),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<String> models = [];
        if (data['data'] is List) {
           models = (data['data'] as List).map((m) => m['id'].toString()).toList();
        } else if (data['models'] is List) {
           // Some specialized APIs
           models = (data['models'] as List).map((m) => m['id'].toString()).toList();
        }
        
        models.sort();
        
        if (models.isEmpty) throw Exception('No models found in response');
        
        if (mounted) {
          _showModelSelectionDialog(models);
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取失败: \$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingModels = false);
    }
  }
  
  void _showModelSelectionDialog(List<String> models) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择模型'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView.separated(
            itemCount: models.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final m = models[i];
              return ListTile(
                title: Text(m),
                onTap: () {
                  _modelIdController.text = m;
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
  }

  Widget _buildProviderModelDropdown(ColorScheme cs) {
    if (_selectedProviderKey == null) return const SizedBox.shrink();

    final settings = context.watch<SettingsProvider>();
    final config = settings.getProviderConfig(_selectedProviderKey!);
    final models = config.models.toList(); // List of strings
    
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MenuAnchor(
              builder: (context, controller, child) {
                return InkWell(
                  onTap: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: constraints.maxWidth,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withOpacity(0.05) 
                          : const Color(0xFFF2F3F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: controller.isOpen ? cs.primary : Colors.transparent,
                        width: controller.isOpen ? 2.0 : 1.5
                      ),
                      boxShadow: controller.isOpen ? [
                        BoxShadow(
                          color: cs.primary.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ] : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _modelIdController.text.isEmpty ? '选择或输入模型...' : _modelIdController.text,
                            style: TextStyle(
                              color: _modelIdController.text.isEmpty ? cs.onSurface.withOpacity(0.5) : cs.onSurface,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Icon(Lucide.ChevronDown, size: 16, color: cs.onSurface.withOpacity(0.5)),
                      ],
                    ),
                  ),
                );
              },
              menuChildren: [
                 // Manual Input Trigger
                 MenuItemButton(
                   onPressed: null, // Makes it non-clickable, but we want a custom widget
                   child: SizedBox(
                     width: constraints.maxWidth - 24, // Account for padding
                     child: TextFormField(
                       controller: _modelIdController,
                       decoration: InputDecoration(
                         hintText: '手动输入模型 ID...',
                         border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                         contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                         isDense: true,
                       ),
                       onChanged: (v) => setState(() {}), // Refresh trigger text
                     ),
                   ),
                 ),
                 const Divider(height: 1),
                 if (models.isEmpty)
                   const MenuItemButton(child: Text('暂无预设模型')),
                 for (final m in models)
                   MenuItemButton(
                     onPressed: () => setState(() => _modelIdController.text = m),
                     style: ButtonStyle(
                        padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                        backgroundColor: MaterialStateProperty.resolveWith((states) {
                          if (states.contains(MaterialState.hovered)) return cs.surfaceContainerHighest.withOpacity(0.5);
                          if (_modelIdController.text == m) return cs.primary.withOpacity(0.08);
                          return null;
                        }),
                        shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                     ),
                     child: Row(
                       children: [
                         Expanded(
                           child: Text(
                             m,
                             style: TextStyle(
                               fontWeight: _modelIdController.text == m ? FontWeight.w600 : FontWeight.w400,
                               color: _modelIdController.text == m ? cs.primary : cs.onSurface,
                             ),
                           ),
                         ),
                         if (_modelIdController.text == m)
                           Icon(Lucide.Check, size: 16, color: cs.primary),
                       ],
                     ),
                   ),
              ],
              style: MenuStyle(
                backgroundColor: MaterialStateProperty.all(cs.surface),
                elevation: MaterialStateProperty.all(10), // Increased elevation
                shadowColor: MaterialStateProperty.all(Colors.black.withOpacity(0.3)), // Stronger shadow
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: cs.outline.withOpacity(0.15), width: 1.0), // More visible border
                  ),
                ),
                padding: MaterialStateProperty.all(const EdgeInsets.all(8)),
                minimumSize: MaterialStateProperty.all(Size(constraints.maxWidth, 0)),
                maximumSize: MaterialStateProperty.all(Size(constraints.maxWidth, 400)), // Reduced height
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _buildApiSourceToggle(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _ApiSourceTab(
              title: '使用已有供应商',
              selected: _apiSource == ApiSource.provider,
              onTap: () => setState(() => _apiSource = ApiSource.provider),
            ),
          ),
          Expanded(
            child: _ApiSourceTab(
              title: '自定义 API',
              selected: _apiSource == ApiSource.custom,
              onTap: () => setState(() => _apiSource = ApiSource.custom),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector(ColorScheme cs) {
    final settings = context.watch<SettingsProvider>();
    final providerPairs = settings.providerConfigs.entries
        .where((e) => e.value.enabled)
        .toList();

    final selectedName = _selectedProviderKey != null 
        ? (settings.getProviderConfig(_selectedProviderKey!).name.isNotEmpty 
            ? settings.getProviderConfig(_selectedProviderKey!).name 
            : _selectedProviderKey!)
        : '选择供应商';

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child: Text('供应商', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
            ),
            MenuAnchor(
              builder: (context, controller, child) {
                return InkWell(
                  onTap: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: constraints.maxWidth,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withOpacity(0.05) 
                          : const Color(0xFFF2F3F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: controller.isOpen ? cs.primary : cs.outline.withOpacity(0.05),
                        width: controller.isOpen ? 2.0 : 1.5 // Thicker border when open
                      ),
                      boxShadow: controller.isOpen ? [ // Glow effect when open
                        BoxShadow(
                          color: cs.primary.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ] : null,
                    ),
                    child: Row(
                      children: [
                        // Avatar/Icon for provider could be added here
                        Expanded(
                          child: Text(
                            selectedName,
                            style: TextStyle(
                               fontSize: 14,
                               fontWeight: FontWeight.w500,
                               color: cs.onSurface,
                            ),
                          ),
                        ),
                        Icon(Lucide.ChevronDown, size: 16, color: cs.onSurface.withOpacity(0.5)),
                      ],
                    ),
                  ),
                );
              },
              menuChildren: providerPairs.map((e) {
                final isSelected = _selectedProviderKey == e.key;
                return MenuItemButton(
                  onPressed: () {
                    setState(() {
                       _selectedProviderKey = e.key;
                       // Auto-select first model
                       final cfg = settings.getProviderConfig(e.key);
                       if (cfg.models.isNotEmpty) {
                         _modelIdController.text = cfg.models.first;
                       } else {
                         _modelIdController.text = '';
                       }
                    });
                  },
                  style: ButtonStyle(
                    padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 12)), // Increased vertical padding
                    backgroundColor: MaterialStateProperty.resolveWith((states) {
                      if (states.contains(MaterialState.hovered)) {
                        return cs.surfaceContainerHighest.withOpacity(0.5);
                      }
                      if (isSelected) {
                        return cs.primaryContainer.withOpacity(0.5); // consistent with sidebar
                      }
                      return null;
                    }),
                    shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    overlayColor: MaterialStateProperty.all(Colors.transparent),
                  ),
                  child: Container(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth - 24), // Full width item
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.value.name.isNotEmpty ? e.value.name : e.key,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? cs.primary : cs.onSurface,
                            ),
                          ),
                        ),
                        if (isSelected)
                           Icon(Lucide.Check, size: 16, color: cs.primary),
                      ],
                    ),
                  ),
                );
              }).toList(),
              style: MenuStyle(
                backgroundColor: MaterialStateProperty.all(cs.surface),
                elevation: MaterialStateProperty.all(10), // Increased elevation
                shadowColor: MaterialStateProperty.all(Colors.black.withOpacity(0.3)), // Stronger shadow
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: cs.outline.withOpacity(0.15), width: 1.0), // More visible border
                  ),
                ),
                padding: MaterialStateProperty.all(const EdgeInsets.all(8)),
                minimumSize: MaterialStateProperty.all(Size(constraints.maxWidth, 0)),
                maximumSize: MaterialStateProperty.all(Size(constraints.maxWidth, 400)), // Reduced height
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _buildCustomFields(ColorScheme cs) {
    return Column(
      children: [
        TextFormField(
          controller: _customBaseUrlController,
          decoration: _inputDecoration(context, 'Base URL', 'https://api.example.com/v1'),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _customApiKeyController,
          decoration: _inputDecoration(context, 'API Key', 'sk-...'),
          obscureText: true,
        ),
      ],
    );
  }

  Widget _buildPermissionModeSelector() {
    final modes = [
      (AgentPermissionMode.requireApproval, '需要批准', '任何工具调用都需要手动确认', Lucide.Shield, Colors.blue), // Replaced with Shield
      (AgentPermissionMode.acceptEdits, '自动接受编辑', '自动应用文件修改，其他操作需批准', Lucide.FileCode, Colors.orange),
      (AgentPermissionMode.bypassPermissions, '自动模式 (危险)', '无需确认即可执行所有操作', Lucide.Zap, Colors.red),
    ];

    return Column(
      children: modes.map((m) {
        final selected = _permissionMode == m.$1;
        final color = m.$5;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => setState(() => _permissionMode = m.$1),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: selected ? color.withOpacity(0.08) : Colors.transparent,
                border: Border.all(
                  color: selected ? color : Theme.of(context).dividerColor,
                  width: selected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: selected ? color.withOpacity(0.1) : Theme.of(context).colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(m.$4, size: 20, color: selected ? color : Theme.of(context).iconTheme.color),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.$2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(m.$3, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
                      ],
                    ),
                  ),
                  if (selected) Icon(Lucide.CircleCheck, color: color, size: 20),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
  
  InputDecoration _inputDecoration(BuildContext context, String label, String hint) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF2F3F5),
      // Subtle border for un-focused state
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), // Rounded 10
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10), 
        borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.03)) 
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10), 
        borderSide: BorderSide(color: cs.primary, width: 1.5)
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), // More breathing room
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: TextStyle(color: cs.onSurfaceVariant),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    
    // Validate model selection
    if (_modelIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择或输入模型 ID')),
      );
      return;
    }

    final newAgent = Agent(
      id: widget.agent?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      instructions: _instructionsController.text.trim(),
      model: _modelIdController.text.trim(),
      apiProvider: _apiSource == ApiSource.provider ? _selectedProviderKey : null,
      customBaseUrl: _apiSource == ApiSource.custom ? _customBaseUrlController.text.trim() : null,
      customApiKey: _apiSource == ApiSource.custom ? _customApiKeyController.text.trim() : null,
      permissionMode: _permissionMode,
      createdAt: widget.agent?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      // Keep existing properties if editing
      type: widget.agent?.type ?? 'claude-code',
      avatar: widget.agent?.avatar,
      accessiblePaths: widget.agent?.accessiblePaths ?? [],
    );

    context.read<AgentProvider>().saveAgent(newAgent);
    Navigator.of(context).pop();
  }
}

class _ApiSourceTab extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _ApiSourceTab({required this.title, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)] : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? cs.primary : cs.onSurface.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}
