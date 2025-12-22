import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons/lucide_adapter.dart' as lucide;
import '../l10n/app_localizations.dart';
import '../core/models/backup.dart';
import '../core/providers/backup_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/services/chat/chat_service.dart';
import '../core/services/backup/cherry_importer.dart' if (dart.library.html) '../core/services/backup/cherry_importer_stub.dart';
import '../shared/widgets/ios_switch.dart';
import '../shared/widgets/snackbar.dart';
import '../utils/backup_filename.dart';
import '../utils/restart_widget.dart';
import 'package:talker_flutter/talker_flutter.dart';
import '../core/utils/http_logger.dart';
import '../utils/web_download_helper.dart' if (dart.library.io) '../utils/web_download_helper_stub.dart';
import '../utils/file_io_helper.dart' if (dart.library.html) '../utils/file_io_helper_stub.dart';
import '../core/services/runtime_cache_service.dart';
import '../features/settings/pages/log_viewer_page.dart';
import '../utils/app_dirs.dart';

class DesktopBackupPane extends StatefulWidget {
  const DesktopBackupPane({super.key});
  @override
  State<DesktopBackupPane> createState() => _DesktopBackupPaneState();
}

class _DesktopBackupPaneState extends State<DesktopBackupPane> {
  // Local form controllers
  late TextEditingController _url;
  late TextEditingController _username;
  late TextEditingController _password;
  late TextEditingController _path;
  bool _includeChats = true;
  bool _includeFiles = true;

  // Password visibility toggle (FIX: remote doesn't have this!)
  bool _obscurePassword = true;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final cfg = Provider.of<SettingsProvider>(context, listen: false).webDavConfig;
      _url = TextEditingController(text: cfg.url);
      _username = TextEditingController(text: cfg.username);
      _password = TextEditingController(text: cfg.password);
      _path = TextEditingController(text: cfg.path);
      _includeChats = cfg.includeChats;
      _includeFiles = cfg.includeFiles;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _path.dispose();
    super.dispose();
  }

  WebDavConfig _buildConfigFromForm() {
    return WebDavConfig(
      url: _url.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
      path: _path.text.trim().isEmpty ? 'kelivo_backups' : _path.text.trim(),
      includeChats: _includeChats,
      includeFiles: _includeFiles,
    );
  }

  Future<void> _saveConfig() async {
    final cfg = _buildConfigFromForm();
    await Provider.of<SettingsProvider>(context, listen: false).setWebDavConfig(cfg);
    Provider.of<BackupProvider>(context, listen: false).updateConfig(cfg);
  }

  Future<void> _applyPartial({String? url, String? username, String? password, String? path, bool? includeChats, bool? includeFiles}) async {
    final cfg = WebDavConfig(
      url: url ?? _url.text.trim(),
      username: username ?? _username.text.trim(),
      password: password ?? _password.text,
      path: path ?? (_path.text.trim().isEmpty ? 'kelivo_backups' : _path.text.trim()),
      includeChats: includeChats ?? _includeChats,
      includeFiles: includeFiles ?? _includeFiles,
    );
    await Provider.of<SettingsProvider>(context, listen: false).setWebDavConfig(cfg);
    Provider.of<BackupProvider>(context, listen: false).updateConfig(cfg);
  }

  Future<void> _chooseRestoreModeAndRun(Future<void> Function(RestoreMode) action) async {
    final l10n = AppLocalizations.of(context)!;
    final mode = await showDialog<RestoreMode>(
      context: context,
      builder: (ctx) => _RestoreModeDialog(),
    );
    if (mode == null) return;
    await action(mode);
    // Inform restart requirement
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.backupPageRestartRequired),
        content: Text(l10n.backupPageRestartContent),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await RestartWidget.restartApp(context);
            },
            child: Text(l10n.backupPageOK),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final busy = context.watch<BackupProvider>().busy;

    return Container(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: CustomScrollView(
            slivers: [
              // Title row
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.backupPageTitle,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.12)),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 6)),

              // WebDAV settings card with left label right input/switch, realtime save
              SliverToBoxAdapter(
                child: _sectionCard(children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.backupPageWebDavServerSettings,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.95)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ItemRow(
                    label: l10n.backupPageWebDavServerUrl,
                    trailing: SizedBox(
                      width: 420,
                      child: TextField(
                        controller: _url,
                        enabled: !busy,
                        style: const TextStyle(fontSize: 14),
                        decoration: _deskInputDecoration(context).copyWith(hintText: 'https://dav.example.com/remote.php/webdav/'),
                        onChanged: (v) => _applyPartial(url: v),
                      ),
                    ),
                  ),
                  _rowDivider(context),
                  _ItemRow(
                    label: l10n.backupPageUsername,
                    trailing: SizedBox(
                      width: 420,
                      child: TextField(
                        controller: _username,
                        enabled: !busy,
                        style: const TextStyle(fontSize: 14),
                        decoration: _deskInputDecoration(context).copyWith(hintText: l10n.backupPageUsername),
                        onChanged: (v) => _applyPartial(username: v),
                      ),
                    ),
                  ),
                  _rowDivider(context),
                  // ✅ FIX: Password field with visibility toggle
                  _ItemRow(
                    label: l10n.backupPagePassword,
                    trailing: SizedBox(
                      width: 420,
                      child: TextField(
                        controller: _password,
                        enabled: !busy,
                        obscureText: _obscurePassword,
                        style: const TextStyle(fontSize: 14),
                        decoration: _deskInputDecoration(context).copyWith(
                          hintText: '••••••••',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? lucide.Lucide.Eye : lucide.Lucide.EyeOff,
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            color: cs.onSurface.withOpacity(0.7),
                            splashRadius: 18,
                          ),
                        ),
                        onChanged: (v) => _applyPartial(password: v),
                      ),
                    ),
                  ),
                  _rowDivider(context),
                  _ItemRow(
                    label: l10n.backupPagePath,
                    trailing: SizedBox(
                      width: 420,
                      child: TextField(
                        controller: _path,
                        enabled: !busy,
                        style: const TextStyle(fontSize: 14),
                        decoration: _deskInputDecoration(context).copyWith(hintText: 'kelivo_backups'),
                        onChanged: (v) => _applyPartial(path: v),
                      ),
                    ),
                  ),
                  _rowDivider(context),
                  _ItemRow(
                    label: l10n.backupPageChatsLabel,
                    vpad: 2,
                    trailing: IosSwitch(
                      value: _includeChats,
                      onChanged: busy ? null : (v) async {
                        setState(() => _includeChats = v);
                        await _applyPartial(includeChats: v);
                      },
                    ),
                  ),
                  _rowDivider(context),
                  _ItemRow(
                    label: l10n.backupPageFilesLabel,
                    vpad: 2,
                    trailing: IosSwitch(
                      value: _includeFiles,
                      onChanged: busy ? null : (v) async {
                        setState(() => _includeFiles = v);
                        await _applyPartial(includeFiles: v);
                      },
                    ),
                  ),
                  _rowDivider(context),
                  _ItemRow(
                    label: l10n.backupPageBackupManagement,
                    trailing: Wrap(spacing: 8, children: [
                      _DeskIosButton(
                        label: l10n.backupPageTestConnection,
                        filled: false,
                        dense: true,
                        onTap: busy ? (){} : () async {
                          await _saveConfig();
                          await context.read<BackupProvider>().test();
                          if (!mounted) return;
                          final rawMessage = context.read<BackupProvider>().message;
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
                      _DeskIosButton(
                        label: l10n.backupPageRestore,
                        filled: false,
                        dense: true,
                        onTap: busy ? (){} : () => _showRemoteBackupsDialog(context),
                      ),
                      _DeskIosButton(
                        label: l10n.backupPageBackupNow,
                        filled: true,
                        dense: true,
                        onTap: busy ? (){} : () async {
                          await _saveConfig();
                          
                          // 显示备份进度对话框
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => _BackupProgressDialog(),
                          );
                          
                          await context.read<BackupProvider>().backup();
                          
                          // 关闭进度对话框
                          if (!mounted) return;
                          Navigator.of(context, rootNavigator: true).pop();
                          
                          final rawMessage = context.read<BackupProvider>().message;
                          final message = rawMessage ?? l10n.backupPageBackupUploaded;
                          showAppSnackBar(
                            context,
                            message: message,
                            type: NotificationType.info,
                          );
                        },
                      ),
                    ]),
                  ),
                ]),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // Local import/export
              SliverToBoxAdapter(
                child: _sectionCard(children: [
                  Row(children: [
                    Expanded(child: Text(l10n.backupPageLocalBackup, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _DeskIosButton(label: l10n.backupPageExportToFile, filled: false, dense: true, onTap: () async {
                      await _saveConfig();
                      final bytes = await context.read<BackupProvider>().exportToBytes();
                      final filename = kelivoBackupFileNameEpoch();
                      if (kIsWeb) {
                        // Web: trigger browser download
                        downloadBytes(bytes, filename);
                      } else {
                        // Desktop: use file picker save dialog
                        String? savePath = await FilePicker.platform.saveFile(
                          dialogTitle: l10n.backupPageExportToFile,
                          fileName: filename,
                          type: FileType.custom,
                          allowedExtensions: ['zip'],
                        );
                        if (savePath != null) {
                          try {
                            await writeFile(savePath, bytes);
                          } catch (_) {}
                        }
                      }
                    }),
                    _DeskIosButton(label: l10n.backupPageImportBackupFile, filled: false, dense: true, onTap: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.any,
                        allowMultiple: false,
                        withData: true, // Required to get bytes on all platforms
                      );
                      final bytes = result?.files.single.bytes;
                      if (bytes == null) return;
                      await _chooseRestoreModeAndRun((mode) async {
                        await context.read<BackupProvider>().restoreFromLocalBytes(bytes, mode: mode);
                      });
                    }),
                    // Cherry Studio import only available on desktop (requires File)
                    if (!kIsWeb)
                      _DeskIosButton(label: l10n.backupPageImportFromCherryStudio, filled: false, dense: true, onTap: () async {
                        final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
                        final path = result?.files.single.path;
                        if (path == null) return;
                        final mode = await showDialog<RestoreMode>(context: context, builder: (_) => _RestoreModeDialog());
                        if (mode == null) return;
                        final settings = context.read<SettingsProvider>();
                        final chat = context.read<ChatService>();
                        try {
                          await CherryImporter.importFromCherryStudio(file: createFile(path), mode: mode, settings: settings, chatService: chat);
                        await showDialog(context: context, builder: (_) => AlertDialog(
                          backgroundColor: cs.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: Text(l10n.backupPageRestartRequired),
                          content: Text(l10n.backupPageRestartContent),
                          actions: [
                            TextButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                await RestartWidget.restartApp(context);
                              },
                              child: Text(l10n.backupPageOK),
                            ),
                          ],
                        ));
                      } catch (e) {
                        await showDialog(context: context, builder: (_) => AlertDialog(
                          backgroundColor: cs.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: Text('Error'),
                          content: Text(e.toString()),
                          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.backupPageOK))],
                        ));
                      }
                    }),
                  ]),
                ]),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // Request logging section
              SliverToBoxAdapter(
                child: _sectionCard(children: [
                  Row(children: [
                    Expanded(child: Text(l10n.requestLoggingTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 6),
                  _ItemRow(
                    label: l10n.requestLoggingSubtitle,
                    vpad: 2,
                    trailing: IosSwitch(
                      value: context.watch<SettingsProvider>().requestLoggingEnabled,
                      onChanged: (v) => context.read<SettingsProvider>().setRequestLoggingEnabled(v),
                    ),
                  ),
                  _rowDivider(context),
                  _ItemRow(
                    label: l10n.requestLoggingViewLogs,
                    trailing: _DeskIosButton(
                      label: l10n.requestLoggingViewLogs,
                      filled: false,
                      dense: true,
                      onTap: () => _showDesktopLogViewer(context),
                    ),
                  ),
                ]),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // Runtime cache section
              SliverToBoxAdapter(
                child: _sectionCard(children: [
                  Row(children: [
                    Expanded(child: Text(l10n.runtimeCacheTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 6),
                  _RuntimeCacheRow(),
                ]),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // Chat storage section
              SliverToBoxAdapter(
                child: _sectionCard(children: [
                  Row(children: [
                    Expanded(child: Text(l10n.settingsPageChatStorage, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 6),
                  _ChatStorageRow(),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteItemCard extends StatefulWidget {
  const _RemoteItemCard({required this.item, required this.onRestore, required this.onDelete});
  final BackupFileItem item;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  @override
  State<_RemoteItemCard> createState() => _RemoteItemCardState();
}

class _RemoteItemCardState extends State<_RemoteItemCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    final borderColor = _hover
        ? cs.primary.withOpacity(isDark ? 0.35 : 0.45)
        : cs.outlineVariant.withOpacity(isDark ? 0.12 : 0.08);
    final l10n = AppLocalizations.of(context)!;
    final dateStr = widget.item.lastModified?.toLocal().toString().split('.').first ?? '';

    String prettySize(int size) {
      const units = ['B', 'KB', 'MB', 'GB'];
      double s = size.toDouble();
      int u = 0;
      while (s >= 1024 && u < units.length - 1) { s /= 1024; u++; }
      return '${s.toStringAsFixed(s >= 10 || u == 0 ? 0 : 1)} ${units[u]}';
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        decoration: BoxDecoration(
          color: baseBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(lucide.Lucide.HardDrive, size: 20, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.item.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${prettySize(widget.item.size)}${dateStr.isNotEmpty ? ' · $dateStr' : ''}', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(0.7))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(message: l10n.backupPageRestoreTooltip, child: _SmallIconBtn(icon: lucide.Lucide.RotateCw, onTap: widget.onRestore)),
            const SizedBox(width: 6),
            Tooltip(message: l10n.backupPageDeleteTooltip, child: _SmallIconBtn(icon: lucide.Lucide.Trash2, onTap: widget.onDelete)),
          ],
        ),
      ),
    );
  }
}

class _RemoteBackupsDialog extends StatefulWidget {
  const _RemoteBackupsDialog();
  @override
  State<_RemoteBackupsDialog> createState() => _RemoteBackupsDialogState();
}

class _RemoteBackupsDialogState extends State<_RemoteBackupsDialog> {
  List<BackupFileItem> _items = const [];
  bool _loading = true;
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<BackupProvider>().listRemote();
      // Sort by newest first (desc by lastModified), mimic mobile behavior
      list.sort((a, b) {
        final aTime = a.lastModified;
        final bTime = b.lastModified;
        if (aTime != null && bTime != null) return bTime.compareTo(aTime);
        if (aTime == null && bTime == null) return b.displayName.compareTo(a.displayName);
        if (aTime == null) return 1; // items with time go first
        return -1;
      });
      if (mounted) setState(() { _items = list; });
    } catch (_) {
      if (mounted) setState(() { _items = const []; });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseRestoreModeAndRun(Future<void> Function(RestoreMode) action) async {
    final mode = await showDialog<RestoreMode>(context: context, builder: (_) => _RestoreModeDialog());
    if (mode == null) return;
    await action(mode);
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    await showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(l10n.backupPageRestartRequired),
      content: Text(l10n.backupPageRestartContent),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await RestartWidget.restartApp(context);
          },
          child: Text(l10n.backupPageOK),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 540),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(l10n.backupPageRemoteBackups, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                  _SmallIconBtn(icon: lucide.Lucide.RefreshCw, onTap: _loading ? (){} : _load),
                  const SizedBox(width: 6),
                  _SmallIconBtn(icon: lucide.Lucide.X, onTap: () => Navigator.of(context).maybePop()),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                    : _items.isEmpty
                        ? Center(child: Text(l10n.backupPageNoBackups, style: TextStyle(color: cs.onSurface.withOpacity(0.7))))
                        : Scrollbar(
                            controller: _controller,
                            child: ListView.separated(
                              controller: _controller,
                              primary: false,
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final it = _items[i];
                                return _RemoteItemCard(
                                  item: it,
                                  onRestore: () => _chooseRestoreModeAndRun((mode) async {
                                    await context.read<BackupProvider>().restoreFromItem(it, mode: mode);
                                  }),
                                  onDelete: () async {
                                    // 1. 显示确认对话框
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => _DeleteConfirmDialog(fileName: it.displayName),
                                    );
                                    if (confirmed != true) return;
                                    
                                    // 2. 显示删除进度对话框
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (ctx) => _DeleteProgressDialog(),
                                    );
                                    
                                    // 3. 执行删除
                                    final next = await context.read<BackupProvider>().deleteAndReload(it);
                                    
                                    // 4. 关闭进度对话框
                                    if (!mounted) return;
                                    Navigator.of(context, rootNavigator: true).pop();
                                    
                                    // 5. 刷新列表
                                    next.sort((a, b) {
                                      final aTime = a.lastModified;
                                      final bTime = b.lastModified;
                                      if (aTime != null && bTime != null) return bTime.compareTo(aTime);
                                      if (aTime == null && bTime == null) return b.displayName.compareTo(a.displayName);
                                      if (aTime == null) return 1;
                                      return -1;
                                    });
                                    if (mounted) setState(() => _items = next);
                                  },
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showRemoteBackupsDialog(BuildContext context) {
  showDialog(context: context, builder: (_) => const _RemoteBackupsDialog());
}

Widget _rowDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(height: 1, color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06));
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.label, required this.trailing, this.vpad = 8});
  final String label; final Widget trailing; final double vpad;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: vpad),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.88)))),
          const SizedBox(width: 12),
          Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ),
    );
  }
}

class _RestoreModeDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.backupPageSelectImportMode, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(l10n.backupPageSelectImportModeDescription, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8))),
            const SizedBox(height: 12),
            _RestoreModeTile(
              title: l10n.backupPageOverwriteMode,
              subtitle: l10n.backupPageOverwriteModeDescription,
              onTap: () => Navigator.of(context).pop(RestoreMode.overwrite),
            ),
            const SizedBox(height: 8),
            _RestoreModeTile(
              title: l10n.backupPageMergeMode,
              subtitle: l10n.backupPageMergeModeDescription,
              onTap: () => Navigator.of(context).pop(RestoreMode.merge),
            ),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.backupPageCancel))),
          ],
          ),
        ),
      ),
    );
  }
}

class _RestoreModeTile extends StatefulWidget {
  const _RestoreModeTile({required this.title, required this.subtitle, required this.onTap});
  final String title; final String subtitle; final VoidCallback onTap;
  @override State<_RestoreModeTile> createState() => _RestoreModeTileState();
}

class _RestoreModeTileState extends State<_RestoreModeTile> {
  bool _hover = false; bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)) : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant.withOpacity(0.12), width: 0.6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(widget.subtitle, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SmallIconBtn extends StatefulWidget {
  const _SmallIconBtn({required this.icon, required this.onTap, this.tooltip});
  final IconData icon; final VoidCallback onTap; final String? tooltip;
  @override State<_SmallIconBtn> createState() => _SmallIconBtnState();
}

class _SmallIconBtnState extends State<_SmallIconBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06)) : Colors.transparent;

    Widget btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (hovering) => setState(() => _hover = hovering),
        borderRadius: BorderRadius.circular(8),
        hoverColor: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Icon(widget.icon, size: 18, color: cs.onSurface),
        ),
      ),
    );

    if (widget.tooltip != null) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

class _DeskIosButton extends StatefulWidget {
  const _DeskIosButton({required this.label, required this.filled, required this.dense, required this.onTap});
  final String label; final bool filled; final bool dense; final VoidCallback onTap;
  @override State<_DeskIosButton> createState() => _DeskIosButtonState();
}

class _DeskIosButtonState extends State<_DeskIosButton> {
  bool _hover = false; bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = widget.filled ? Colors.white : cs.onSurface.withOpacity(0.9);
    final bg = widget.filled
        ? (_hover ? cs.primary.withOpacity(0.92) : cs.primary)
        : (_hover ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05)) : Colors.transparent);
    final borderColor = widget.filled ? Colors.transparent : cs.outlineVariant.withOpacity(isDark ? 0.22 : 0.18);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: widget.dense ? 8 : 12, horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
            child: Text(widget.label, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: widget.dense ? 13 : 14)),
          ),
        ),
      ),
    );
  }
}

Widget _sectionCard({required List<Widget> children}) {
  return Builder(builder: (context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    return Container(
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.12 : 0.08), width: 0.8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  });
}

InputDecoration _deskInputDecoration(BuildContext context) {
  // Match provider dialog style (compact), but slightly shorter height and 14px font hint
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
    hintStyle: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.5)),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.12), width: 0.6),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.12), width: 0.6),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.primary.withOpacity(0.35), width: 0.8),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );
}

class _BackupProgressDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '正在备份到 WebDAV',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    backgroundColor: isDark 
                        ? Colors.white.withOpacity(0.1) 
                        : Colors.black.withOpacity(0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '压缩数据并上传中...',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({required this.fileName});
  final String fileName;
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(lucide.Lucide.MessageCircleWarning, size: 22, color: cs.error),
                  const SizedBox(width: 10),
                  Text(
                    '确认删除',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '确定要删除备份文件吗？',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  fileName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withOpacity(0.8),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '此操作无法撤销',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.error.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('删除'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteProgressDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '正在删除备份',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    backgroundColor: isDark 
                        ? Colors.white.withOpacity(0.1) 
                        : Colors.black.withOpacity(0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(cs.error),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '正在从服务器删除文件...',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showDesktopLogViewer(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _DesktopLogViewerDialog(),
  );
}

class _DesktopLogViewerDialog extends StatefulWidget {
  const _DesktopLogViewerDialog();
  @override
  State<_DesktopLogViewerDialog> createState() => _DesktopLogViewerDialogState();
}

/// 将字符串中的转义字符渲染为真实字符
String _renderEscapesDesktop(String input) {
  return input
      .replaceAll(r'\n', '\n')   // 字面量 \n -> 真实换行
      .replaceAll(r'\r', '')      // 移除 \r
      .replaceAll(r'\t', '    '); // \t -> 4空格
}

/// 解析后的日志条目
class _LogEntry {
  final int requestId;
  final String method;
  final String url;
  final DateTime? timestamp;
  // 结构化数据
  final Map<String, String> requestHeaders;
  final String requestBody;
  final int? statusCode;
  final Map<String, String> responseHeaders;
  final String responseBody;
  // 原始行（用于兼容）
  final List<String> requestLines;
  final List<String> responseLines;

  _LogEntry({
    required this.requestId,
    required this.method,
    required this.url,
    this.timestamp,
    this.requestHeaders = const {},
    this.requestBody = '',
    this.statusCode,
    this.responseHeaders = const {},
    this.responseBody = '',
    this.requestLines = const [],
    this.responseLines = const [],
  });

  String get fullText {
    final sb = StringBuffer();
    sb.writeln('[$requestId] $method $url');
    if (requestHeaders.isNotEmpty) {
      sb.writeln('Request Headers:');
      requestHeaders.forEach((k, v) => sb.writeln('  $k: $v'));
    }
    if (requestBody.isNotEmpty) {
      sb.writeln('Request Body:');
      sb.writeln(requestBody);
    }
    if (statusCode != null) {
      sb.writeln('Response Status: $statusCode');
    }
    if (responseHeaders.isNotEmpty) {
      sb.writeln('Response Headers:');
      responseHeaders.forEach((k, v) => sb.writeln('  $k: $v'));
    }
    if (responseBody.isNotEmpty) {
      sb.writeln('Response Body:');
      sb.writeln(responseBody);
    }
    return sb.toString().trim();
  }
}

class _DesktopLogViewerDialogState extends State<_DesktopLogViewerDialog> {
  final ScrollController _scrollController = ScrollController();
  final LayerLink _logPickerLink = LayerLink();
  final Object _logPickerTapGroup = Object();
  List<_LogEntry> _entries = [];
  final Set<int> _deleteConfirmIndices = {}; // 正在确认删除的条目
  bool _loading = true;
  List<File> _logFiles = [];
  String? _selectedLogFileName; // e.g. logs.txt, logs_YYYY-MM-DD.txt
  bool _logPickerOpen = false;
  bool _logPickerBtnHover = false;
  bool _logPickerBtnPressed = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _fileName(String path) => path.split(Platform.pathSeparator).last;

  String _logTitle(String fileName, AppLocalizations l10n) {
    if (fileName == 'logs.txt') return l10n.logViewerCurrentLog;
    final m = RegExp(r'^logs_(\d{4}-\d{2}-\d{2})(?:_(\d+))?\.txt$').firstMatch(fileName);
    if (m != null) {
      final date = m.group(1)!;
      final n = int.tryParse(m.group(2) ?? '');
      if (n != null && n > 0) return '$date ($n)';
      return date;
    }
    return fileName;
  }

  void _toggleLogPicker() {
    if (_loading || _logFiles.length <= 1) return;
    setState(() => _logPickerOpen = !_logPickerOpen);
  }

  void _selectLogFile(String fileName) {
    if (fileName == _selectedLogFileName) {
      setState(() => _logPickerOpen = false);
      return;
    }
    setState(() => _logPickerOpen = false);
    _loadLogs(selectFileName: fileName);
  }

  Widget _buildLogPickerButton(ColorScheme cs, bool isDark, AppLocalizations l10n) {
    final selected = _selectedLogFileName;
    final label = selected == null ? '' : _logTitle(selected, l10n);
    final baseBg = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04);
    final hoverBg = isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.06);
    final openBg = isDark ? cs.primary.withOpacity(0.22) : cs.primary.withOpacity(0.14);
    final bg = _logPickerOpen ? openBg : (_logPickerBtnHover ? hoverBg : baseBg);
    final border = _logPickerOpen ? cs.primary.withOpacity(isDark ? 0.42 : 0.32) : cs.outlineVariant.withOpacity(0.12);
    final iconColor = _logPickerOpen ? cs.primary : cs.onSurface.withOpacity(0.72);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _logPickerBtnHover = true),
      onExit: (_) => setState(() => _logPickerBtnHover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _logPickerBtnPressed = true),
        onTapUp: (_) => setState(() => _logPickerBtnPressed = false),
        onTapCancel: () => setState(() => _logPickerBtnPressed = false),
        onTap: _toggleLogPicker,
        child: AnimatedScale(
          scale: _logPickerBtnPressed ? 0.985 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
              boxShadow: _logPickerOpen
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.28 : 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_note_outlined, size: 16, color: iconColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withOpacity(0.92),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _logPickerOpen ? lucide.Lucide.ChevronUp : lucide.Lucide.ChevronDown,
                  size: 16,
                  color: cs.onSurface.withOpacity(0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogPickerPanel(ColorScheme cs, bool isDark, AppLocalizations l10n) {
    const maxVisibleItems = 4;
    const rowHeight = 64.0;
    const rowGap = 6.0;
    const listPadding = 8.0;
    const maxHeight = (listPadding * 2) + (rowHeight * maxVisibleItems) + (rowGap * (maxVisibleItems - 1));
    final shouldScroll = _logFiles.length > maxVisibleItems;

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: maxHeight),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView.builder(
              shrinkWrap: true,
              primary: false,
              physics: shouldScroll ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(listPadding),
              itemCount: _logFiles.length,
              itemBuilder: (ctx, i) {
                final file = _logFiles[i];
                final name = _fileName(file.path);
                final title = _logTitle(name, l10n);
                final isSelected = name == _selectedLogFileName;

                return Padding(
                  padding: EdgeInsets.only(bottom: i == _logFiles.length - 1 ? 0 : rowGap),
                  child: SizedBox(
                    height: rowHeight,
                    child: _LogPickerItem(
                      title: title,
                      subtitle: name,
                      selected: isSelected,
                      onTap: () => _selectLogFile(name),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadLogs({String? selectFileName}) async {
    setState(() => _loading = true);
    try {
      final dir = await AppDirs.dataRoot();
      final logsDir = Directory('${dir.path}/logs');

      final files = <File>[];
      if (await logsDir.exists()) {
        final found = await logsDir
            .list()
            .where((e) => e is File && e.path.endsWith('.txt'))
            .cast<File>()
            .toList();
        found.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        files.addAll(found);
      }

      final candidate = selectFileName ?? _selectedLogFileName;
      String? selectedName;
      if (files.isNotEmpty) {
        final names = files.map((f) => _fileName(f.path)).toSet();
        if (candidate != null && names.contains(candidate)) {
          selectedName = candidate;
        } else if (names.contains('logs.txt')) {
          selectedName = 'logs.txt';
        } else {
          selectedName = _fileName(files.first.path);
        }
      }

      final selectedFile = selectedName == null ? null : files.firstWhere((f) => _fileName(f.path) == selectedName);

      List<_LogEntry> entries = [];
      if (selectedFile != null && await selectedFile.exists()) {
        // 在后台线程读取并解析日志，避免阻塞UI（减少主线程大字符串复制）
        entries = await compute(_parseLogFileIsolate, selectedFile.path);
      }

      if (mounted) {
        setState(() {
          _logFiles = files;
          _selectedLogFileName = selectedName;
          _entries = entries;
          _loading = false;
          _deleteConfirmIndices.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _logFiles = [];
          _selectedLogFileName = null;
          _entries = [];
          _loading = false;
          _deleteConfirmIndices.clear();
        });
      }
    }
  }

  /// 手动刷新日志（带反馈提示）
  Future<void> _refreshLogs() async {
    await _loadLogs();
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.logViewerRefresh,
        type: NotificationType.info,
        duration: const Duration(seconds: 1),
      );
    }
  }

  /// 解析状态枚举
  static const int _stateInitial = 0;
  static const int _stateRequestHeaders = 1;
  static const int _stateRequestBody = 2;
  static const int _stateResponseHeaders = 3;
  static const int _stateResponseBody = 4;

  List<_LogEntry> _parseLogContent(String content) {
    final entries = <_LogEntry>[];
    final lines = content.split('\n');

    // 正则表达式 - 支持带毫秒或不带毫秒的时间戳
    final mainSeparator = RegExp(r'^═{20,}');
    final headerRegex = RegExp(r'^\[(\d+)\]\s+(\w+)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)');
    final responseHeaderRegex = RegExp(r'^◀\s*RESPONSE\s*\[(\d+)\]\s+(\d{2}:\d{2}:\d{2})');
    final headersSectionRegex = RegExp(r'──\s*Headers\s*─');
    final bodySectionRegex = RegExp(r'──\s*Body\s*─');

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // 检查主分隔符
      if (mainSeparator.hasMatch(line) && i + 1 < lines.length) {
        final headerLine = lines[i + 1];
        final headerMatch = headerRegex.firstMatch(headerLine);

        if (headerMatch != null) {
          final reqId = int.parse(headerMatch.group(1)!);
          final method = headerMatch.group(2)!;
          final timestampStr = headerMatch.group(3)!;
          final timestamp = _parseTimestamp(timestampStr);

          i += 2; // 跳过分隔符和请求头
          if (i < lines.length && mainSeparator.hasMatch(lines[i])) i++;

          String url = '';
          final requestHeaders = <String, String>{};
          final requestBodyLines = <String>[];
          int? statusCode;
          final responseHeaders = <String, String>{};
          final responseBodyLines = <String>[];
          int state = _stateInitial;

          while (i < lines.length) {
            final currentLine = lines[i];

            // 检查是否到达下一个请求
            if (mainSeparator.hasMatch(currentLine) && i + 1 < lines.length) {
              if (headerRegex.hasMatch(lines[i + 1])) break;
            }

            // ▶ REQUEST
            if (currentLine.trim().startsWith('▶ REQUEST')) {
              i++;
              if (i < lines.length) {
                url = lines[i].trim();
                i++;
              }
              continue;
            }

            // Headers 部分
            if (headersSectionRegex.hasMatch(currentLine)) {
              state = (state < _stateResponseHeaders) ? _stateRequestHeaders : _stateResponseHeaders;
              i++;
              continue;
            }

            // Body 部分
            if (bodySectionRegex.hasMatch(currentLine)) {
              state = (state < _stateResponseHeaders) ? _stateRequestBody : _stateResponseBody;
              i++;
              continue;
            }

            // Response header
            final respMatch = responseHeaderRegex.firstMatch(currentLine);
            if (respMatch != null) {
              statusCode = int.tryParse(respMatch.group(1)!);
              state = _stateResponseHeaders;
              i++;
              continue;
            }

            // ✓ Done 标记
            if (currentLine.trim().startsWith('✓ Done')) {
              i++;
              continue;
            }

            // 子分隔符
            if (currentLine.startsWith('───')) {
              i++;
              continue;
            }

            // 空行
            if (currentLine.trim().isEmpty) {
              i++;
              continue;
            }

            // 根据状态收集内容
            switch (state) {
              case _stateRequestHeaders:
                final trimmed = currentLine.trim();
                final colonIndex = trimmed.indexOf(':');
                if (colonIndex > 0) {
                  final key = trimmed.substring(0, colonIndex).trim();
                  final value = trimmed.substring(colonIndex + 1).trim();
                  requestHeaders[key] = value;
                }
                break;
              case _stateRequestBody:
                requestBodyLines.add(currentLine.replaceFirst(RegExp(r'^\s{0,2}'), ''));
                break;
              case _stateResponseHeaders:
                final trimmed = currentLine.trim();
                final colonIndex = trimmed.indexOf(':');
                if (colonIndex > 0) {
                  final key = trimmed.substring(0, colonIndex).trim();
                  final value = trimmed.substring(colonIndex + 1).trim();
                  responseHeaders[key] = value;
                }
                break;
              case _stateResponseBody:
                responseBodyLines.add(currentLine.replaceFirst(RegExp(r'^\s{0,2}'), ''));
                break;
            }
            i++;
          }

          // 渲染转义字符
          final requestBody = _renderEscapesDesktop(requestBodyLines.join('\n').trim());
          final responseBody = _renderEscapesDesktop(responseBodyLines.join('\n').trim());

          entries.add(_LogEntry(
            requestId: reqId,
            method: method,
            url: url,
            timestamp: timestamp,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            statusCode: statusCode,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
          ));
          continue;
        }
      }
      i++;
    }

    // 按时间戳倒序排列（最新的在前面）
    entries.sort((a, b) {
      final aTime = a.timestamp ?? DateTime(1970);
      final bTime = b.timestamp ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    return entries;
  }

  DateTime? _parseTimestamp(String timestamp) {
    try {
      final parts = timestamp.split(' ');
      if (parts.length >= 2) {
        final dateParts = parts[0].split('-');
        final timeParts = parts[1].split(':');
        if (dateParts.length == 3 && timeParts.length >= 2) {
          final secParts = timeParts.length > 2 ? timeParts[2].split('.') : ['0', '0'];
          return DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
            int.parse(secParts[0]),
            secParts.length > 1 ? int.parse(secParts[1]) : 0,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// 删除单条日志
  Future<void> _deleteEntry(_LogEntry entry) async {
    try {
      if (_selectedLogFileName != 'logs.txt') return;
      final dir = await AppDirs.dataRoot();
      final logFile = File('${dir.path}/logs/logs.txt');
      if (!await logFile.exists()) return;

      final raw = await logFile.readAsString();
      final lines = raw.split('\n');
      final newLines = <String>[];
      final headerRegex = RegExp(r'^\[(\d+)\]\s+\w+\s+\d{4}-\d{2}-\d{2}');

      bool inTargetEntry = false;

      for (final line in lines) {
        // 检测请求头开始
        final headerMatch = headerRegex.firstMatch(line);
        if (headerMatch != null) {
          final id = int.tryParse(headerMatch.group(1) ?? '');
          inTargetEntry = id == entry.requestId;
        }

        // 如果不是要删除的条目，保留该行
        if (!inTargetEntry) {
          newLines.add(line);
        }
      }

      // 写回文件
      await logFile.writeAsString(newLines.join('\n'));

      // 重新加载
      await _loadLogs();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, message: '删除失败: $e', type: NotificationType.error);
      }
    }
  }

  Future<void> _confirmClearLogs() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.logViewerClearAll),
        content: Text(l10n.logViewerClearConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.sideDrawerCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.homePageDelete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _clearLogs();
    }
  }

  Future<void> _clearLogs() async {
    try {
      final dir = await AppDirs.dataRoot();
      final logsDir = Directory('${dir.path}/logs');
      if (await logsDir.exists()) {
        await logsDir.delete(recursive: true);
      }
      await _loadLogs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  String _shortenUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      if (path.length > 40) {
        return '${uri.host}${path.substring(0, 40)}...';
      }
      return '${uri.host}$path';
    } catch (_) {
      if (url.length > 60) return '${url.substring(0, 60)}...';
      return url;
    }
  }

  Color _getMethodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET': return Colors.green;
      case 'POST': return Colors.blue;
      case 'PUT': return Colors.orange;
      case 'DELETE': return Colors.red;
      case 'PATCH': return Colors.purple;
      default: return Colors.grey;
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 750),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      Icon(lucide.Lucide.ScrollText, size: 20, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.requestLoggingTitle,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
                        ),
                      ),
                      if (!_loading && _logFiles.length > 1)
                        CompositedTransformTarget(
                          link: _logPickerLink,
                          child: TapRegion(
                            groupId: _logPickerTapGroup,
                            child: _buildLogPickerButton(cs, isDark, l10n),
                          ),
                        ),
                      if (!_loading) ...[
                        const SizedBox(width: 10),
                        Text(
                          '${_entries.length} requests',
                          style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
                        ),
                      ],
                      const SizedBox(width: 12),
                      _SmallIconBtn(icon: lucide.Lucide.RefreshCw, onTap: _refreshLogs, tooltip: l10n.logViewerRefresh),
                      const SizedBox(width: 6),
                      _SmallIconBtn(icon: lucide.Lucide.Trash2, onTap: _entries.isEmpty ? () {} : _confirmClearLogs, tooltip: l10n.logViewerClearAll),
                      const SizedBox(width: 6),
                      _SmallIconBtn(icon: lucide.Lucide.X, onTap: () => Navigator.of(context).pop(), tooltip: l10n.sideDrawerCancel),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.15)),
                // Log list
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _entries.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(lucide.Lucide.FileText, size: 48, color: cs.onSurface.withOpacity(0.3)),
                                  const SizedBox(height: 16),
                                  Text(
                                    l10n.logViewerEmpty,
                                    style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                                  ),
                                ],
                              ),
                            )
                          : Scrollbar(
                              controller: _scrollController,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(12),
                                itemCount: _entries.length,
                                // 使用 cacheExtent 预渲染更多条目
                                cacheExtent: 200,
                                itemBuilder: (ctx, i) {
                                  final entry = _entries[i];
                                  return Padding(
                                    padding: EdgeInsets.only(bottom: i < _entries.length - 1 ? 6 : 0),
                                    child: _LogEntryTile(
                                      key: ValueKey('log_entry_${entry.requestId}_${entry.timestamp?.millisecondsSinceEpoch ?? 0}'),
                                      entry: entry,
                                      index: i,
                                      canDelete: _selectedLogFileName == 'logs.txt',
                                      onDelete: () => _deleteEntry(entry),
                                    ),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
            if (!_loading && _logFiles.length > 1 && _logPickerOpen)
              CompositedTransformFollower(
                link: _logPickerLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomRight,
                followerAnchor: Alignment.topRight,
                offset: const Offset(0, 10),
                child: TapRegion(
                  groupId: _logPickerTapGroup,
                  onTapOutside: (_) => setState(() => _logPickerOpen = false),
                  child: Material(
                    color: Colors.transparent,
                    child: _buildLogPickerPanel(cs, isDark, l10n),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LogPickerItem extends StatefulWidget {
  const _LogPickerItem({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_LogPickerItem> createState() => _LogPickerItemState();
}

class _LogPickerItemState extends State<_LogPickerItem> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hoverBg = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04);
    final selectedBg = isDark ? cs.primary.withOpacity(0.18) : cs.primary.withOpacity(0.10);
    final bg = widget.selected ? selectedBg : (_hover ? hoverBg : Colors.transparent);

    final titleColor = cs.onSurface.withOpacity(0.92);
    final subtitleColor = cs.onSurface.withOpacity(widget.selected ? 0.55 : 0.45);
    final iconColor = cs.onSurface.withOpacity(widget.selected ? 0.75 : 0.55);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 30,
                  decoration: BoxDecoration(
                    color: widget.selected ? cs.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.description_outlined, size: 18, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: widget.selected ? FontWeight.w800 : FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: subtitleColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.selected) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.check_rounded, size: 18, color: cs.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个日志条目组件 - 独立管理状态，懒加载内容
class _LogEntryTile extends StatefulWidget {
  final _LogEntry entry;
  final int index;
  final bool canDelete;
  final VoidCallback onDelete;

  const _LogEntryTile({
    super.key,
    required this.entry,
    required this.index,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  State<_LogEntryTile> createState() => _LogEntryTileState();
}

class _LogEntryTileState extends State<_LogEntryTile> with AutomaticKeepAliveClientMixin {
  bool _isExpanded = false;
  bool _isDeleteConfirm = false;
  // 缓存格式化后的 JSON
  String? _formattedRequestBody;
  String? _formattedResponseBody;

  @override
  bool get wantKeepAlive => _isExpanded; // 展开时保持状态

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      _isDeleteConfirm = false;
      // 懒加载：只在展开时格式化 JSON
      if (_isExpanded && _formattedRequestBody == null) {
        _formatBodies();
      }
    });
  }

  void _formatBodies() {
    // Request body
    if (widget.entry.requestBody.isNotEmpty) {
      try {
        final decoded = json.decode(widget.entry.requestBody);
        _formattedRequestBody = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        _formattedRequestBody = _renderEscapesDesktop(widget.entry.requestBody);
      }
    } else {
      _formattedRequestBody = '';
    }
    // Response body
    if (widget.entry.responseBody.isNotEmpty) {
      try {
        final decoded = json.decode(widget.entry.responseBody);
        _formattedResponseBody = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        _formattedResponseBody = _renderEscapesDesktop(widget.entry.responseBody);
      }
    } else {
      _formattedResponseBody = '';
    }
  }

  Color _getMethodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET': return Colors.green;
      case 'POST': return Colors.blue;
      case 'PUT': return Colors.orange;
      case 'DELETE': return Colors.red;
      case 'PATCH': return Colors.purple;
      case 'PROPFIND': return Colors.teal;
      default: return Colors.grey;
    }
  }

  String _shortenUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.host}${uri.path}';
    } catch (_) {
      return url;
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--:--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entry = widget.entry;
    
    final bgColor = isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02);

    return GestureDetector(
      onTap: _toggleExpand,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Request ID badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#${entry.requestId}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary),
                  ),
                ),
                const SizedBox(width: 8),
                // Method badge
                if (entry.method.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getMethodColor(entry.method).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      entry.method,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _getMethodColor(entry.method)),
                    ),
                  ),
                const SizedBox(width: 8),
                // URL
                Expanded(
                  child: Text(
                    entry.url.isNotEmpty ? _shortenUrl(entry.url) : '(unknown)',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.8)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Timestamp
                Text(
                  _formatTime(entry.timestamp),
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5), fontFamily: 'monospace'),
                ),
                const SizedBox(width: 8),
                Icon(
                  _isExpanded ? lucide.Lucide.ChevronUp : lucide.Lucide.ChevronDown,
                  size: 16,
                  color: cs.onSurface.withOpacity(0.5),
                ),
                const SizedBox(width: 8),
                // Copy button
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: entry.fullText));
                    showAppSnackBar(context, message: l10n.logViewerCopied, type: NotificationType.success, duration: const Duration(seconds: 2));
                  },
                  child: Icon(lucide.Lucide.Copy, size: 14, color: cs.primary.withOpacity(0.7)),
                ),
                const SizedBox(width: 8),
                // Delete button - 确认按钮在前，保持删除操作位置一致
                if (widget.canDelete)
                  if (_isDeleteConfirm) ...[
                    GestureDetector(
                      onTap: () => setState(() => _isDeleteConfirm = false),
                      child: Icon(lucide.Lucide.X, size: 14, color: cs.onSurface.withOpacity(0.6)),
                    ),
                    const SizedBox(width: 6),
                    Text(l10n.logViewerDeleteConfirmInline, style: TextStyle(fontSize: 11, color: cs.error)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        setState(() => _isDeleteConfirm = false);
                        widget.onDelete();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(4)),
                        child: Text(l10n.homePageDelete, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ] else ...[
                    GestureDetector(
                      onTap: () => setState(() => _isDeleteConfirm = true),
                      child: Icon(lucide.Lucide.Trash2, size: 14, color: cs.error.withOpacity(0.6)),
                    ),
                  ],
              ],
            ),
            // Expanded content - 懒加载
            if (_isExpanded) ...[
              const SizedBox(height: 10),
              _LogRequestSectionOptimized(
                entry: entry,
                formattedBody: _formattedRequestBody ?? '',
                isDark: isDark,
              ),
              _LogResponseSectionOptimized(
                entry: entry,
                formattedBody: _formattedResponseBody ?? '',
                isDark: isDark,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Runtime cache row for desktop backup pane
class _RuntimeCacheRow extends StatefulWidget {
  @override
  State<_RuntimeCacheRow> createState() => _RuntimeCacheRowState();
}

class _RuntimeCacheRowState extends State<_RuntimeCacheRow> {
  Map<String, bool> _cacheStatus = {};
  bool _isLoading = true;
  bool _isDownloading = false;
  String _downloadingFile = '';
  int _downloadProgress = 0;
  int _cacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    try {
      final cache = RuntimeCacheService.instance;
      await cache.init();
      final status = await cache.getCacheStatus();
      final size = await cache.getCacheSize();
      if (mounted) {
        setState(() {
          _cacheStatus = status;
          _cacheSize = size;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadAll() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final cache = RuntimeCacheService.instance;
      await cache.downloadAll(
        onProgress: (fileName, progress) {
          if (mounted) {
            setState(() {
              _downloadingFile = RuntimeCacheService.getLibraryName(fileName);
              _downloadProgress = progress;
            });
          }
        },
      );
      await _loadStatus();
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingFile = '';
          _downloadProgress = 0;
        });
      }
    }
  }

  Future<void> _clearCache() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.runtimeCacheClearTitle),
        content: Text(l10n.runtimeCacheClearMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.backupPageCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.runtimeCacheClearButton, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final cache = RuntimeCacheService.instance;
      await cache.clearCache();
      await _loadStatus();
    }
  }

  String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
        ),
      );
    }

    final cachedCount = _cacheStatus.values.where((v) => v).length;
    final totalCount = _cacheStatus.length;
    final allCached = cachedCount == totalCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ItemRow(
          label: l10n.runtimeCacheStatus,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                allCached ? lucide.Lucide.CheckCircle : lucide.Lucide.Circle,
                size: 16,
                color: allCached ? Colors.green : cs.onSurface.withOpacity(0.5),
              ),
              const SizedBox(width: 8),
              Text(
                '$cachedCount/$totalCount · ${_formatBytes(_cacheSize)}',
                style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7)),
              ),
            ],
          ),
        ),
        if (_isDownloading) ...[
          _rowDivider(context),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${l10n.runtimeCacheDownloading} $_downloadingFile...',
                        style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8)),
                      ),
                    ),
                    Text(
                      '$_downloadProgress%',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _downloadProgress / 100,
                    backgroundColor: cs.primary.withOpacity(0.15),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          _rowDivider(context),
          _ItemRow(
            label: l10n.runtimeCacheActions,
            trailing: Wrap(spacing: 8, children: [
              _DeskIosButton(
                label: allCached ? l10n.runtimeCacheAllDownloaded : l10n.runtimeCacheDownloadAll,
                filled: !allCached,
                dense: true,
                onTap: allCached ? () {} : _downloadAll,
              ),
              if (_cacheSize > 0)
                _DeskIosButton(
                  label: l10n.runtimeCacheClearButton,
                  filled: false,
                  dense: true,
                  onTap: _clearCache,
                ),
            ]),
          ),
        ],
      ],
    );
  }
}

/// Chat storage row for desktop backup pane
class _ChatStorageRow extends StatefulWidget {
  @override
  State<_ChatStorageRow> createState() => _ChatStorageRowState();
}

class _ChatStorageRowState extends State<_ChatStorageRow> {
  UploadStats? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final svc = context.read<ChatService>();
      final stats = await svc.getUploadStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
        ),
      );
    }

    final count = _stats?.fileCount ?? 0;
    final size = _formatBytes(_stats?.totalBytes ?? 0);

    return _ItemRow(
      label: l10n.settingsPageFilesCount(count, size),
      trailing: Icon(lucide.Lucide.HardDrive, size: 18, color: cs.onSurface.withOpacity(0.5)),
    );
  }
}

/// Request section widget for log viewer
class _LogRequestSection extends StatelessWidget {
  final _LogEntry entry;
  final bool isDark;

  const _LogRequestSection({required this.entry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasHeaders = entry.requestHeaders.isNotEmpty;
    final hasBody = entry.requestBody.isNotEmpty;

    if (!hasHeaders && !hasBody) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Request title with icon
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(lucide.Lucide.Upload, size: 12, color: Colors.blue),
              const SizedBox(width: 4),
              Text('REQUEST', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.blue, letterSpacing: 0.5)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Headers section
        if (hasHeaders) ...[
          _buildSectionHeader(context, 'Headers', lucide.Lucide.FileText, entry.requestHeaders.length),
          const SizedBox(height: 4),
          _buildHeadersTable(context, entry.requestHeaders, isDark),
          const SizedBox(height: 10),
        ],
        // Body section
        if (hasBody) ...[
          _buildSectionHeader(context, 'Body', lucide.Lucide.Code, null),
          const SizedBox(height: 4),
          _buildBodyContent(context, entry.requestBody, isDark),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String label, IconData icon, int? count) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 12, color: cs.onSurface.withOpacity(0.5)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.7))),
        if (count != null) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(4)),
            child: Text('$count', style: TextStyle(fontSize: 9, color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  Widget _buildHeadersTable(BuildContext context, Map<String, String> headers, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.25) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withOpacity(0.1)),
      ),
      child: Column(
        children: headers.entries.toList().asMap().entries.map((mapEntry) {
          final i = mapEntry.key;
          final e = mapEntry.value;
          final isLast = i == headers.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: isLast ? null : Border(bottom: BorderSide(color: cs.outline.withOpacity(0.08))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    e.key,
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.primary, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    e.value,
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.85)),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBodyContent(BuildContext context, String body, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    // Try to format as JSON
    String displayBody = body;
    bool isJson = false;
    try {
      final decoded = json.decode(body);
      displayBody = const JsonEncoder.withIndent('  ').convert(decoded);
      isJson = true;
    } catch (_) {
      displayBody = _renderEscapesDesktop(body);
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.25) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withOpacity(0.1)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: double.infinity,
                    child: SelectableText(
                      displayBody,
                      style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.85), height: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // JSON badge
          if (isJson)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(3)),
                child: Text('JSON', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.orange.shade700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Response section widget for log viewer
class _LogResponseSection extends StatelessWidget {
  final _LogEntry entry;
  final bool isDark;

  const _LogResponseSection({required this.entry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasHeaders = entry.responseHeaders.isNotEmpty;
    final hasBody = entry.responseBody.isNotEmpty;

    if (!hasHeaders && !hasBody) return const SizedBox.shrink();

    // Determine status color
    final statusCode = entry.statusCode ?? 0;
    Color statusColor = Colors.green;
    String statusText = 'OK';
    if (statusCode >= 500) {
      statusColor = Colors.red.shade700;
      statusText = 'Server Error';
    } else if (statusCode >= 400) {
      statusColor = Colors.red;
      statusText = 'Client Error';
    } else if (statusCode >= 300) {
      statusColor = Colors.orange;
      statusText = 'Redirect';
    } else if (statusCode >= 200) {
      statusColor = Colors.green;
      statusText = 'Success';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // Response title with status badge
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(lucide.Lucide.Download, size: 12, color: statusColor),
                  const SizedBox(width: 4),
                  Text('RESPONSE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor, letterSpacing: 0.5)),
                ],
              ),
            ),
            if (statusCode > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$statusCode', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                    const SizedBox(width: 4),
                    Text(statusText, style: TextStyle(fontSize: 9, color: statusColor.withOpacity(0.8))),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Headers section
        if (hasHeaders) ...[
          _buildSectionHeader(context, 'Headers', lucide.Lucide.FileText, entry.responseHeaders.length),
          const SizedBox(height: 4),
          _buildHeadersTable(context, entry.responseHeaders, isDark),
          const SizedBox(height: 10),
        ],
        // Body section
        if (hasBody) ...[
          _buildSectionHeader(context, 'Body', lucide.Lucide.Code, null),
          const SizedBox(height: 4),
          _buildBodyContent(context, entry.responseBody, isDark),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String label, IconData icon, int? count) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 12, color: cs.onSurface.withOpacity(0.5)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.7))),
        if (count != null) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(4)),
            child: Text('$count', style: TextStyle(fontSize: 9, color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  Widget _buildHeadersTable(BuildContext context, Map<String, String> headers, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.25) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withOpacity(0.1)),
      ),
      child: Column(
        children: headers.entries.toList().asMap().entries.map((mapEntry) {
          final i = mapEntry.key;
          final e = mapEntry.value;
          final isLast = i == headers.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: isLast ? null : Border(bottom: BorderSide(color: cs.outline.withOpacity(0.08))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    e.key,
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.primary, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    e.value,
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.85)),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBodyContent(BuildContext context, String body, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    // Try to format as JSON
    String displayBody = body;
    bool isJson = false;
    try {
      final decoded = json.decode(body);
      displayBody = const JsonEncoder.withIndent('  ').convert(decoded);
      isJson = true;
    } catch (_) {
      displayBody = _renderEscapesDesktop(body);
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 350),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.25) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withOpacity(0.1)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: double.infinity,
                    child: SelectableText(
                      displayBody,
                      style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.85), height: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // JSON badge
          if (isJson)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(3)),
                child: Text('JSON', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.orange.shade700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// JSON syntax highlighting widget - simplified for performance
class _JsonSyntaxHighlight extends StatelessWidget {
  final String json;
  final bool isDark;

  const _JsonSyntaxHighlight({required this.json, required this.isDark});

  @override
  Widget build(BuildContext context) {
    // For performance, just use colored SelectableText without complex regex parsing
    final textColor = isDark ? Colors.white70 : Colors.black87;
    return SelectableText(
      json,
      style: TextStyle(
        fontSize: 10,
        fontFamily: 'monospace',
        height: 1.5,
        color: textColor,
      ),
    );
  }
}

/// Section label widget (kept for compatibility)
class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 12, color: cs.onSurface.withOpacity(0.5)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: cs.onSurface.withOpacity(0.6)),
        ),
      ],
    );
  }
}

/// 优化版 Request Section - 使用预格式化的 body
class _LogRequestSectionOptimized extends StatelessWidget {
  final _LogEntry entry;
  final String formattedBody;
  final bool isDark;

  const _LogRequestSectionOptimized({
    required this.entry,
    required this.formattedBody,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasHeaders = entry.requestHeaders.isNotEmpty;
    final hasBody = formattedBody.isNotEmpty;

    if (!hasHeaders && !hasBody) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Request label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(lucide.Lucide.Upload, size: 12, color: Colors.blue),
              const SizedBox(width: 4),
              Text('REQUEST', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.blue, letterSpacing: 0.5)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Headers
        if (hasHeaders) ...[
          _buildSimpleHeaders(context, entry.requestHeaders, isDark),
          const SizedBox(height: 8),
        ],
        // Body
        if (hasBody) ...[
          _buildSimpleBody(context, formattedBody, isDark),
        ],
      ],
    );
  }

  Widget _buildSimpleHeaders(BuildContext context, Map<String, String> headers, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: headers.entries.map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${e.key}: ', style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.w600)),
              TextSpan(text: e.value, style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.8))),
            ]),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildSimpleBody(BuildContext context, String body, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final isJson = body.trimLeft().startsWith('{') || body.trimLeft().startsWith('[');
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 200),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        children: [
          Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: SelectableText(
                  body,
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.85), height: 1.4),
                ),
              ),
            ),
          ),
          if (isJson)
            Positioned(
              top: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(3)),
                child: Text('JSON', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.orange.shade700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 优化版 Response Section - 使用预格式化的 body
class _LogResponseSectionOptimized extends StatelessWidget {
  final _LogEntry entry;
  final String formattedBody;
  final bool isDark;

  const _LogResponseSectionOptimized({
    required this.entry,
    required this.formattedBody,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasHeaders = entry.responseHeaders.isNotEmpty;
    final hasBody = formattedBody.isNotEmpty;

    if (!hasHeaders && !hasBody) return const SizedBox.shrink();

    final statusCode = entry.statusCode ?? 0;
    Color statusColor = Colors.green;
    if (statusCode >= 400) statusColor = Colors.red;
    else if (statusCode >= 300) statusColor = Colors.orange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        // Response label with status
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(lucide.Lucide.Download, size: 12, color: statusColor),
                  const SizedBox(width: 4),
                  Text('RESPONSE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor, letterSpacing: 0.5)),
                ],
              ),
            ),
            if (statusCode > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                child: Text('$statusCode', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Headers
        if (hasHeaders) ...[
          _buildSimpleHeaders(context, entry.responseHeaders, isDark),
          const SizedBox(height: 8),
        ],
        // Body
        if (hasBody) ...[
          _buildSimpleBody(context, formattedBody, isDark),
        ],
      ],
    );
  }

  Widget _buildSimpleHeaders(BuildContext context, Map<String, String> headers, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: headers.entries.map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${e.key}: ', style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.w600)),
              TextSpan(text: e.value, style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.8))),
            ]),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildSimpleBody(BuildContext context, String body, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final isJson = body.trimLeft().startsWith('{') || body.trimLeft().startsWith('[');
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 300),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        children: [
          Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: SelectableText(
                  body,
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.85), height: 1.4),
                ),
              ),
            ),
          ),
          if (isJson)
            Positioned(
              top: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(3)),
                child: Text('JSON', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.orange.shade700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Isolate function for parsing log content (runs in background thread)
List<_LogEntry> _parseLogFileIsolate(String filePath) {
  String content = '';
  try {
    content = File(filePath).readAsStringSync();
  } catch (_) {
    return <_LogEntry>[];
  }
  final entries = <_LogEntry>[];
  final lines = content.split('\n');

  // 正则表达式 - 支持带毫秒或不带毫秒的时间戳
  final mainSeparator = RegExp(r'^═{20,}');
  final headerRegex = RegExp(r'^\[(\d+)\]\s+(\w+)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)');
  final responseHeaderRegex = RegExp(r'^◀\s*RESPONSE\s*\[(\d+)\]\s+(\d{2}:\d{2}:\d{2})');
  final headersSectionRegex = RegExp(r'──\s*Headers\s*─');
  final bodySectionRegex = RegExp(r'──\s*Body\s*─');

  const stateInitial = 0;
  const stateRequestHeaders = 1;
  const stateRequestBody = 2;
  const stateResponseHeaders = 3;
  const stateResponseBody = 4;

  int i = 0;
  while (i < lines.length) {
    final line = lines[i];

    // 检查主分隔符
    if (mainSeparator.hasMatch(line) && i + 1 < lines.length) {
      final headerLine = lines[i + 1];
      final headerMatch = headerRegex.firstMatch(headerLine);

      if (headerMatch != null) {
        final reqId = int.parse(headerMatch.group(1)!);
        final method = headerMatch.group(2)!;
        final timestampStr = headerMatch.group(3)!;
        final timestamp = _parseTimestampIsolate(timestampStr);

        i += 2;
        if (i < lines.length && mainSeparator.hasMatch(lines[i])) i++;

        String url = '';
        final requestHeaders = <String, String>{};
        final requestBodyLines = <String>[];
        int? statusCode;
        final responseHeaders = <String, String>{};
        final responseBodyLines = <String>[];
        int state = stateInitial;

        while (i < lines.length) {
          final currentLine = lines[i];

          if (mainSeparator.hasMatch(currentLine) && i + 1 < lines.length) {
            if (headerRegex.hasMatch(lines[i + 1])) break;
          }

          if (currentLine.trim().startsWith('▶ REQUEST')) {
            i++;
            if (i < lines.length) {
              url = lines[i].trim();
              i++;
            }
            continue;
          }

          if (headersSectionRegex.hasMatch(currentLine)) {
            state = (state < stateResponseHeaders) ? stateRequestHeaders : stateResponseHeaders;
            i++;
            continue;
          }

          if (bodySectionRegex.hasMatch(currentLine)) {
            state = (state < stateResponseHeaders) ? stateRequestBody : stateResponseBody;
            i++;
            continue;
          }

          final respMatch = responseHeaderRegex.firstMatch(currentLine);
          if (respMatch != null) {
            statusCode = int.tryParse(respMatch.group(1)!);
            state = stateResponseHeaders;
            i++;
            continue;
          }

          if (currentLine.trim().startsWith('✓ Done') || currentLine.trim().startsWith('✗ ERROR')) {
            i++;
            continue;
          }

          if (currentLine.startsWith('───')) {
            i++;
            continue;
          }

          if (currentLine.trim().isEmpty) {
            i++;
            continue;
          }

          switch (state) {
            case stateRequestHeaders:
              final trimmed = currentLine.trim();
              final colonIndex = trimmed.indexOf(':');
              if (colonIndex > 0) {
                final key = trimmed.substring(0, colonIndex).trim();
                final value = trimmed.substring(colonIndex + 1).trim();
                requestHeaders[key] = value;
              }
              break;
            case stateRequestBody:
              requestBodyLines.add(currentLine.replaceFirst(RegExp(r'^\s{0,2}'), ''));
              break;
            case stateResponseHeaders:
              final trimmed = currentLine.trim();
              final colonIndex = trimmed.indexOf(':');
              if (colonIndex > 0) {
                final key = trimmed.substring(0, colonIndex).trim();
                final value = trimmed.substring(colonIndex + 1).trim();
                responseHeaders[key] = value;
              }
              break;
            case stateResponseBody:
              responseBodyLines.add(currentLine.replaceFirst(RegExp(r'^\s{0,2}'), ''));
              break;
          }
          i++;
        }

        final requestBody = requestBodyLines.join('\n').trim();
        final responseBody = responseBodyLines.join('\n').trim();

        entries.add(_LogEntry(
          requestId: reqId,
          method: method,
          url: url,
          timestamp: timestamp,
          requestHeaders: requestHeaders,
          requestBody: requestBody,
          statusCode: statusCode,
          responseHeaders: responseHeaders,
          responseBody: responseBody,
        ));
        continue;
      }
    }
    i++;
  }

  // 按时间戳倒序排列
  entries.sort((a, b) {
    final aTime = a.timestamp ?? DateTime(1970);
    final bTime = b.timestamp ?? DateTime(1970);
    return bTime.compareTo(aTime);
  });
  return entries;
}

DateTime? _parseTimestampIsolate(String timestamp) {
  try {
    final parts = timestamp.split(' ');
    if (parts.length >= 2) {
      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');
      if (dateParts.length == 3 && timeParts.length >= 2) {
        final secParts = timeParts.length > 2 ? timeParts[2].split('.') : ['0', '0'];
        return DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
          int.parse(secParts[0]),
          secParts.length > 1 ? int.parse(secParts[1]) : 0,
        );
      }
    }
  } catch (_) {}
  return null;
}
