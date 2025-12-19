import 'dart:html' as html;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/backup.dart';
import '../../../core/providers/backup_provider.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../utils/backup_filename.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  RestoreMode _mode = RestoreMode.overwrite;

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

  Future<void> _export() async {
      final vm = context.read<BackupProvider>();
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

  Future<void> _import() async {
    final vm = context.read<BackupProvider>();
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
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'Restore failed: $e', type: NotificationType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vm = context.watch<BackupProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
            ),
            child: Text(
              'Web backup supports export/import of a .zip file. WebDAV remote backup is not available in browser builds.',
              style: TextStyle(color: cs.onSurface.withOpacity(0.85)),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<RestoreMode>(
            segments: const [
              ButtonSegment(value: RestoreMode.overwrite, label: Text('Overwrite')),
              ButtonSegment(value: RestoreMode.merge, label: Text('Merge')),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: vm.busy ? null : _export,
            icon: const Icon(Icons.download),
            label: const Text('Export backup (.zip)'),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: vm.busy ? null : _import,
            icon: const Icon(Icons.upload_file),
            label: const Text('Import backup (.zip)'),
          ),
          if ((vm.message ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(vm.message!, style: TextStyle(color: cs.onSurface.withOpacity(0.75))),
          ],
        ],
      ),
    );
  }
}

