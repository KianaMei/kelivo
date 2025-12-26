import 'dart:html' as html;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/models/backup.dart';
import '../../../core/providers/backup_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../utils/backup_filename.dart';
import '../../../utils/restart_widget.dart';
import '../../../core/services/sync/webdav_incremental_sync_web.dart';
import '../../../core/providers/assistant_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// File size formatter (B, KB, MB, GB)
String _fmtBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(2)} KB';
  return '$bytes B';
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, this.embedded = false});

  /// Whether this page is embedded in a desktop settings layout (no Scaffold/AppBar)
  final bool embedded;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  RestoreMode _mode = RestoreMode.overwrite;
  List<BackupFileItem> _remote = const <BackupFileItem>[];
  bool _loadingRemote = false;

  // Incremental sync state
  bool _syncing = false;
  int _syncCurrent = 0;
  int _syncTotal = 0;
  String _syncStage = '';

  void _downloadBytes(String fileName, Uint8List bytes) {
    final blob = html.Blob(<dynamic>[bytes], 'application/zip');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final a = html.AnchorElement(href: url)
      ..download = fileName
      ..style.display = 'none';
    html.document.body?.children.add(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _export(BackupProvider vm) async {
    try {
      final bytes = await vm.exportToBytes();
      final name = kelivoBackupFileNameEpoch();
      _downloadBytes(name, bytes);
      if (!mounted) return;
      showAppSnackBar(context, message: 'Backup downloaded', type: NotificationType.success);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'Export failed: $e', type: NotificationType.error);
    }
  }

  Future<void> _import(BackupProvider vm) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null) {
        showAppSnackBar(context, message: 'Failed to read backup file', type: NotificationType.error);
        return;
      }
      await vm.restoreFromLocalBytes(Uint8List.fromList(bytes), mode: _mode);
      if (!mounted) return;
      showAppSnackBar(context, message: 'Restored', type: NotificationType.success);
      await _showRestartRequiredDialog(context);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'Restore failed: $e', type: NotificationType.error);
    }
  }

  Future<void> _showRestartRequiredDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: Text(l10n.backupPageRestartRequired),
        content: Text(l10n.backupPageRestartContent),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(dctx).pop();
              await RestartWidget.restartApp(context);
            },
            child: Text(l10n.backupPageOK),
          ),
        ],
      ),
    );
  }

  Future<RestoreMode?> _chooseImportModeDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white10 : const Color(0xFFF7F7F9);

    return showDialog<RestoreMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.backupPageSelectImportMode),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionCard(
              color: cardColor,
              icon: Lucide.RotateCw,
              title: l10n.backupPageOverwriteMode,
              subtitle: l10n.backupPageOverwriteModeDescription,
              onTap: () => Navigator.of(ctx).pop(RestoreMode.overwrite),
            ),
            const SizedBox(height: 10),
            _ActionCard(
              color: cardColor,
              icon: Lucide.GitFork,
              title: l10n.backupPageMergeMode,
              subtitle: l10n.backupPageMergeModeDescription,
              onTap: () => Navigator.of(ctx).pop(RestoreMode.merge),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.backupPageCancel),
          ),
        ],
      ),
    );
  }

  Future<T> _runWithImportingOverlay<T>(BuildContext context, Future<T> Function() task) async {
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: CupertinoActivityIndicator(radius: 14),
            ),
          ),
        ),
      ),
    );
    try {
      final res = await task();
      return res;
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _showWebDavSettingsSheet(
    BuildContext context,
    SettingsProvider settings,
    BackupProvider vm,
    WebDavConfig cfg,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    final urlCtrl = TextEditingController(text: cfg.url);
    final usernameCtrl = TextEditingController(text: cfg.username);
    final passwordCtrl = TextEditingController(text: cfg.password);
    final pathCtrl = TextEditingController(text: cfg.path);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    l10n.backupPageWebDavServerSettings,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsTextField(
                  label: l10n.backupPageWebDavServerUrl,
                  controller: urlCtrl,
                  hintText: 'https://dav.example.com/webdav/',
                ),
                const SizedBox(height: 12),
                _SettingsTextField(
                  label: l10n.backupPageWebDavUsername,
                  controller: usernameCtrl,
                ),
                const SizedBox(height: 12),
                _SettingsTextField(
                  label: l10n.backupPageWebDavPassword,
                  controller: passwordCtrl,
                  obscure: true,
                ),
                const SizedBox(height: 12),
                _SettingsTextField(
                  label: l10n.backupPageWebDavPath,
                  controller: pathCtrl,
                  hintText: '/kelivo/',
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(l10n.backupPageCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final newCfg = cfg.copyWith(
                            url: urlCtrl.text.trim(),
                            username: usernameCtrl.text.trim(),
                            password: passwordCtrl.text,
                            path: pathCtrl.text.trim(),
                          );
                          await settings.setWebDavConfig(newCfg);
                          vm.updateConfig(newCfg);
                          Navigator.of(ctx).pop();
                        },
                        child: Text(l10n.backupPageSave),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    return ChangeNotifierProvider(
      create: (_) => BackupProvider(
        chatService: context.read<ChatService>(),
        initialConfig: settings.webDavConfig,
      ),
      child: Builder(builder: (context) {
        final vm = context.watch<BackupProvider>();
        final cfg = vm.config;

        // iOS-style section header
        Widget header(String text, {bool first = false}) => Padding(
          padding: EdgeInsets.fromLTRB(12, first ? 2 : 18, 12, 6),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withOpacity(0.8),
            ),
          ),
        );

        final bodyContent = ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(Lucide.Info, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Web backup uses a gateway proxy for WebDAV operations.',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.85), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            // Section 1: 备份管理
            header(l10n.backupPageBackupManagement, first: false),
            _iosSectionCard(children: [
              _iosSwitchRow(
                context,
                icon: Lucide.MessageSquare,
                label: l10n.backupPageChatsLabel,
                value: cfg.includeChats,
                onChanged: (v) async {
                  final newCfg = cfg.copyWith(includeChats: v);
                  await settings.setWebDavConfig(newCfg);
                  vm.updateConfig(newCfg);
                },
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.FileText,
                label: l10n.backupPageFilesLabel,
                value: cfg.includeFiles,
                onChanged: (v) async {
                  final newCfg = cfg.copyWith(includeFiles: v);
                  await settings.setWebDavConfig(newCfg);
                  vm.updateConfig(newCfg);
                },
              ),
            ]),

            // Section 2: WebDAV备份
            header(l10n.backupPageWebDavBackup),
            _iosSectionCard(children: [
              _iosNavRow(
                context,
                icon: Lucide.Settings,
                label: l10n.backupPageWebDavServerSettings,
                onTap: () => _showWebDavSettingsSheet(context, settings, vm, cfg),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Cable,
                label: l10n.backupPageTestConnection,
                onTap: vm.busy ? null : () async {
                  await vm.test();
                  if (!mounted) return;
                  final rawMessage = vm.message;
                  final message = rawMessage ?? l10n.backupPageTestDone;
                  showAppSnackBar(
                    context,
                    message: message,
                    type: rawMessage != null && rawMessage != 'OK'
                        ? NotificationType.error
                        : NotificationType.success,
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Import,
                label: l10n.backupPageRestore,
                onTap: vm.busy ? null : () async {
                  setState(() => _loadingRemote = true);
                  try {
                    final list = await vm.listRemote();
                    list.sort((a, b) {
                      if (a.lastModified != null && b.lastModified != null) {
                        return b.lastModified!.compareTo(a.lastModified!);
                      }
                      if (a.lastModified == null && b.lastModified == null) {
                        return b.displayName.compareTo(a.displayName);
                      }
                      if (a.lastModified == null) return 1;
                      return -1;
                    });
                    setState(() => _remote = list);
                  } finally {
                    setState(() => _loadingRemote = false);
                  }
                  
                  if (!mounted) return;
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: cs.surface,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (ctx) => _RemoteListSheet(
                      items: _remote,
                      loading: _loadingRemote,
                      onDelete: (item) async {
                        final list = await vm.deleteAndReload(item);
                        list.sort((a, b) {
                          if (a.lastModified != null && b.lastModified != null) {
                            return b.lastModified!.compareTo(a.lastModified!);
                          }
                          if (a.lastModified == null && b.lastModified == null) {
                            return b.displayName.compareTo(a.displayName);
                          }
                          if (a.lastModified == null) return 1;
                          return -1;
                        });
                        setState(() => _remote = list);
                      },
                      onRestore: (item) async {
                        Navigator.of(ctx).pop();
                        
                        if (!mounted) return;
                        final mode = await _chooseImportModeDialog(context);
                        
                        if (mode == null) return;
                        
                        await _runWithImportingOverlay(context, () => vm.restoreFromItem(item, mode: mode));
                        if (!mounted) return;
                        await _showRestartRequiredDialog(context);
                      },
                    ),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Upload,
                label: l10n.backupPageBackupNow,
                onTap: vm.busy ? null : () async {
                  await _runWithImportingOverlay(context, () => vm.backup());
                  if (!mounted) return;
                  final rawMessage = vm.message;
                  final message = rawMessage ?? l10n.backupPageBackupUploaded;
                  showAppSnackBar(
                    context,
                    message: message,
                    type: NotificationType.info,
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Zap,
                label: _syncing ? '$_syncCurrent/$_syncTotal' : l10n.backupPageIncrementalSyncTitle,
                detailText: _syncing ? _syncStage : '',
                onTap: (vm.busy || _syncing) ? null : () => _performIncrementalSync(context, vm, settings),
              ),
              // Sync progress bar
              if (_syncing) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _syncTotal > 0 ? _syncCurrent / _syncTotal : null,
                      minHeight: 6,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    _syncStage.isNotEmpty ? _syncStage : l10n.backupPageSyncing,
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                  ),
                ),
              ],
            ]),

            // Section 3: 本地备份
            header(l10n.backupPageLocalBackup),
            _iosSectionCard(children: [
              _iosNavRow(
                context,
                icon: Lucide.Export,
                label: l10n.backupPageExportToFile,
                onTap: vm.busy ? null : () => _export(vm),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Import2,
                label: l10n.backupPageImportBackupFile,
                onTap: vm.busy ? null : () => _import(vm),
              ),
            ]),

            // Restore mode selector
            header('Restore Mode'),
            _iosSectionCard(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: SegmentedButton<RestoreMode>(
                  segments: [
                    ButtonSegment(value: RestoreMode.overwrite, label: Text(l10n.backupPageOverwriteMode)),
                    ButtonSegment(value: RestoreMode.merge, label: Text(l10n.backupPageMergeMode)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() => _mode = v.first),
                ),
              ),
            ]),
          ],
        );

        // If embedded, return body content directly without Scaffold
        if (widget.embedded) {
          return bodyContent;
        }

        // Otherwise, return full page with Scaffold and AppBar
        return Scaffold(
          appBar: AppBar(title: Text(l10n.backupPageTitle)),
          body: bodyContent,
        );
      }),
    );
  }

  Future<void> _performIncrementalSync(
    BuildContext context,
    BackupProvider vm,
    SettingsProvider settings,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final cfg = vm.config;

    if (cfg.url.isEmpty) {
      showAppSnackBar(context, message: l10n.backupPageWebDavServerUrl + '?', type: NotificationType.error);
      return;
    }

    setState(() {
      _syncing = true;
      _syncCurrent = 0;
      _syncTotal = 0;
      _syncStage = '';
    });

    try {
      final chatService = context.read<ChatService>();
      final settingsProvider = context.read<SettingsProvider>();
      final assistantProvider = context.read<AssistantProvider>();

      final manager = IncrementalSyncManagerWeb(
        cfg,
        logger: (msg) => print('[Sync/Web] $msg'),
      );

      // Get local conversations (full JSON for complete sync)
      final convs = chatService.getAllConversations();
      final localConvsMapped = convs.map((c) => c.toJson()).toList();

      // Export data - use full SharedPreferences snapshot for complete sync
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final settingsMap = <String, dynamic>{
        'exportedAt': DateTime.now().toIso8601String(),
      };
      for (final k in allKeys) {
        settingsMap[k] = prefs.get(k);
      }
      final assistantsList = assistantProvider.exportAssistants();

      await manager.performSync(
        localConversations: localConvsMapped,
        localSettings: settingsMap,
        localAssistants: assistantsList,
        localMessagesFetcher: (convId) async {
          // Fetch real messages with tool events
          final messages = chatService.getMessages(convId);
          final toolEvents = <String, List<Map<String, dynamic>>>{};
          for (final m in messages) {
            if (m.role == 'assistant') {
              final ev = chatService.getToolEvents(m.id);
              if (ev.isNotEmpty) toolEvents[m.id] = ev;
            }
          }
          return {
            'messages': messages.map((m) => m.toJson()).toList(),
            'toolEvents': toolEvents,
          };
        },
        onRemoteConversationFound: (c) async {
          print('[Sync/Web] Remote conv found: ${c['id']}');
          await chatService.importConversationFromJson(c);
        },
        onRemoteMessagesFound: (id, data) async {
          // Handle both old format (List) and new format (Map with toolEvents)
          List<Map<String, dynamic>> msgs;
          Map<String, List<Map<String, dynamic>>> toolEvents = {};
          if (data is Map) {
            msgs = ((data['messages'] as List?) ?? []).cast<Map<String, dynamic>>();
            toolEvents = ((data['toolEvents'] as Map?) ?? {}).map(
              (k, v) => MapEntry(k.toString(), (v as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList()),
            );
          } else if (data is List) {
            msgs = data.cast<Map<String, dynamic>>();
          } else {
            return;
          }
          print('[Sync/Web] Remote msgs found for $id: ${msgs.length} items, ${toolEvents.length} tool events');
          await chatService.importMessagesFromJson(id, msgs);
          // Import tool events
          for (final entry in toolEvents.entries) {
            try { await chatService.setToolEvents(entry.key, entry.value); } catch (_) {}
          }
        },
        onRemoteSettingsFound: (data) async {
          // Use full SharedPreferences restore for complete sync
          final prefs = await SharedPreferences.getInstance();
          for (final entry in data.entries) {
            final k = entry.key;
            final v = entry.value;
            if (v is bool) await prefs.setBool(k, v);
            else if (v is int) await prefs.setInt(k, v);
            else if (v is double) await prefs.setDouble(k, v);
            else if (v is String) await prefs.setString(k, v);
            else if (v is List) {
              await prefs.setStringList(k, v.whereType<String>().toList());
            }
          }
          // Reload settings provider to pick up changes
          await settingsProvider.reload();
        },
        onRemoteAssistantsFound: (list) async {
          await assistantProvider.importAssistants(list);
        },
        onProgress: (current, total, stage) {
          if (mounted) {
            setState(() {
              _syncCurrent = current;
              _syncTotal = total;
              _syncStage = stage;
            });
          }
        },
      );

      if (!mounted) return;
      showAppSnackBar(context, message: l10n.backupPageSyncDone, type: NotificationType.success);
    } catch (e) {
      print(e);
      if (!mounted) return;
      showAppSnackBar(context, message: l10n.backupPageSyncError(e.toString()), type: NotificationType.error);
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  // === iOS-style widgets ===

  Widget _iosSectionCard({required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.15)),
      ),
      child: Column(children: children),
    );
  }

  Widget _iosDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 50),
      color: cs.outlineVariant.withOpacity(0.2),
    );
  }

  Widget _iosSwitchRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          IOSSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _iosNavRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? detailText,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            if (detailText != null && detailText.isNotEmpty) ...[
              Text(detailText, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.5))),
              const SizedBox(width: 4),
            ],
            Icon(Lucide.ChevronRight, size: 18, color: cs.onSurface.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }
}

// === Helper Widgets ===

class _SettingsTextField extends StatelessWidget {
  const _SettingsTextField({
    required this.label,
    required this.controller,
    this.hintText,
    this.obscure = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7))),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hintText,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: cs.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteListSheet extends StatelessWidget {
  const _RemoteListSheet({
    required this.items,
    required this.loading,
    required this.onDelete,
    required this.onRestore,
  });

  final List<BackupFileItem> items;
  final bool loading;
  final void Function(BackupFileItem) onDelete;
  final void Function(BackupFileItem) onRestore;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                l10n.backupPageRemoteBackups,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            if (loading)
              const Center(child: CupertinoActivityIndicator())
            else if (items.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.backupPageNoRemoteBackups,
                    style: TextStyle(color: cs.onSurface.withOpacity(0.5)),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    return ListTile(
                      title: Text(item.displayName, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        '${_fmtBytes(item.size)} • ${item.lastModified?.toLocal().toString().split('.').first ?? ''}',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Lucide.Trash2, size: 18, color: cs.error),
                            onPressed: () => onDelete(item),
                          ),
                          IconButton(
                            icon: Icon(Lucide.Download, size: 18, color: cs.primary),
                            onPressed: () => onRestore(item),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
