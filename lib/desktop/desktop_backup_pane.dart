import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  const _SmallIconBtn({required this.icon, required this.onTap});
  final IconData icon; final VoidCallback onTap;
  @override State<_SmallIconBtn> createState() => _SmallIconBtnState();
}

class _SmallIconBtnState extends State<_SmallIconBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05)) : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Icon(widget.icon, size: 18, color: cs.onSurface),
        ),
      ),
    );
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

class _DesktopLogViewerDialogState extends State<_DesktopLogViewerDialog> {
  final ScrollController _scrollController = ScrollController();
  late List<TalkerData> _logs;
  final Set<int> _expandedIndices = {};
  final Set<int> _selectedIndices = {};
  bool _multiSelectMode = false;

  @override
  void initState() {
    super.initState();
    _logs = talker.history.reversed.toList();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _deleteLog(int index) {
    setState(() {
      _logs.removeAt(index);
      _expandedIndices.remove(index);
      // Adjust indices after removal
      final newExpanded = <int>{};
      for (final i in _expandedIndices) {
        if (i > index) {
          newExpanded.add(i - 1);
        } else {
          newExpanded.add(i);
        }
      }
      _expandedIndices.clear();
      _expandedIndices.addAll(newExpanded);
    });
  }

  void _deleteSelected() {
    setState(() {
      final toDelete = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
      for (final index in toDelete) {
        _logs.removeAt(index);
      }
      _selectedIndices.clear();
      _expandedIndices.clear();
      _multiSelectMode = false;
    });
  }

  void _clearAll() {
    talker.cleanHistory();
    setState(() {
      _logs.clear();
      _expandedIndices.clear();
      _selectedIndices.clear();
      _multiSelectMode = false;
    });
  }

  void _toggleSelect(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  String _getFirstLine(String? message) {
    if (message == null || message.isEmpty) return '';
    final lines = message.split('\n');
    return lines.first;
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
        child: Column(
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
                  Text(
                    '${_logs.length} items',
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
                  ),
                  const SizedBox(width: 12),
                  // Multi-select toggle
                  if (_logs.isNotEmpty)
                    _SmallIconBtn(
                      icon: _multiSelectMode ? lucide.Lucide.CheckSquare : lucide.Lucide.Square,
                      onTap: () {
                        setState(() {
                          _multiSelectMode = !_multiSelectMode;
                          if (!_multiSelectMode) _selectedIndices.clear();
                        });
                      },
                    ),
                  if (_multiSelectMode && _selectedIndices.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _DeskIosButton(
                      label: '删除选中 (${_selectedIndices.length})',
                      filled: true,
                      dense: true,
                      onTap: _deleteSelected,
                    ),
                  ],
                  const SizedBox(width: 6),
                  _SmallIconBtn(icon: lucide.Lucide.Trash2, onTap: _logs.isEmpty ? () {} : _clearAll),
                  const SizedBox(width: 6),
                  _SmallIconBtn(icon: lucide.Lucide.X, onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withOpacity(0.15)),
            // Log list
            Expanded(
              child: _logs.isEmpty
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
                      child: ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _logs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (ctx, i) {
                          final log = _logs[i];
                          final isExpanded = _expandedIndices.contains(i);
                          final isSelected = _selectedIndices.contains(i);
                          final isError = log.title?.contains('ERR') == true || log.logLevel == LogLevel.error;
                          final isRequest = log.title?.contains('REQ') == true;
                          final bgColor = isSelected
                              ? cs.primary.withOpacity(0.15)
                              : isError
                                  ? cs.errorContainer.withOpacity(0.15)
                                  : isRequest
                                      ? cs.primaryContainer.withOpacity(0.1)
                                      : (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02));
                          final iconColor = isError ? cs.error : (isRequest ? cs.primary : cs.onSurface.withOpacity(0.7));
                          final icon = isError ? lucide.Lucide.CircleX : (isRequest ? lucide.Lucide.ArrowUpRight : lucide.Lucide.ArrowDownLeft);

                          return GestureDetector(
                            onTap: () {
                              if (_multiSelectMode) {
                                _toggleSelect(i);
                              } else {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedIndices.remove(i);
                                  } else {
                                    _expandedIndices.add(i);
                                  }
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? cs.primary.withOpacity(0.5) : cs.outlineVariant.withOpacity(0.08),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (_multiSelectMode) ...[
                                        Icon(
                                          isSelected ? lucide.Lucide.CheckSquare : lucide.Lucide.Square,
                                          size: 16,
                                          color: isSelected ? cs.primary : cs.onSurface.withOpacity(0.5),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Icon(icon, size: 16, color: iconColor),
                                      const SizedBox(width: 8),
                                      Text(
                                        log.title ?? 'LOG',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: iconColor),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        _formatTime(log.time),
                                        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        isExpanded ? lucide.Lucide.ChevronUp : lucide.Lucide.ChevronDown,
                                        size: 16,
                                        color: cs.onSurface.withOpacity(0.5),
                                      ),
                                      if (!_multiSelectMode) ...[
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () {
                                            Clipboard.setData(ClipboardData(text: log.message ?? ''));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(l10n.chatMessageWidgetCopiedToClipboard),
                                                duration: const Duration(seconds: 1),
                                              ),
                                            );
                                          },
                                          child: Icon(lucide.Lucide.Copy, size: 14, color: cs.primary.withOpacity(0.7)),
                                        ),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () => _deleteLog(i),
                                          child: Icon(lucide.Lucide.Trash2, size: 14, color: cs.error.withOpacity(0.7)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  // First line (always shown)
                                  Text(
                                    _getFirstLine(log.message),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: cs.onSurface.withOpacity(0.75),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  // Full content (when expanded)
                                  if (isExpanded) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.black.withOpacity(0.2) : Colors.white.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: SelectableText(
                                        log.message ?? '',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color: cs.onSurface.withOpacity(0.85),
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
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
