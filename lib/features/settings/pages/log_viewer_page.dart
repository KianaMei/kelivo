import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/app_dirs.dart';
import '../../../shared/widgets/snackbar.dart';

/// 日志查看页面 - 显示日志文件列表，支持查看和导出
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  List<FileSystemEntity> _logFiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogFiles();
  }

  Future<void> _loadLogFiles() async {
    setState(() => _loading = true);
    try {
      final dir = await AppDirs.dataRoot();
      final logsDir = Directory('${dir.path}/logs');
      if (await logsDir.exists()) {
        final files = await logsDir
            .list()
            .where((e) => e is File && e.path.endsWith('.txt'))
            .toList();
        // 按修改时间降序排列（最新的在前）
        files.sort((a, b) {
          final aStat = (a as File).statSync();
          final bStat = (b as File).statSync();
          return bStat.modified.compareTo(aStat.modified);
        });
        setState(() {
          _logFiles = files;
          _loading = false;
        });
      } else {
        setState(() {
          _logFiles = [];
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _logFiles = [];
        _loading = false;
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _clearAllLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有日志'),
        content: const Text('确定要删除所有日志文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final dir = await AppDirs.dataRoot();
        final logsDir = Directory('${dir.path}/logs');
        if (await logsDir.exists()) {
          await logsDir.delete(recursive: true);
        }
        await _loadLogFiles();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, color: cs.onSurface, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.logViewerTitle),
        actions: [
          IconButton(
            icon: Icon(Lucide.Trash2, color: cs.onSurface, size: 20),
            tooltip: '清除所有日志',
            onPressed: _logFiles.isEmpty ? null : _clearAllLogs,
          ),
          IconButton(
            icon: Icon(Lucide.RefreshCw, color: cs.onSurface, size: 20),
            onPressed: _loadLogFiles,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logFiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Lucide.FileText, size: 48, color: cs.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        l10n.logViewerEmpty,
                        style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _logFiles.length,
                  itemBuilder: (context, index) {
                    final file = _logFiles[index] as File;
                    final stat = file.statSync();
                    final fileName = file.path.split(Platform.pathSeparator).last;
                    final isCurrentLog = fileName == 'logs.txt';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          isCurrentLog ? Lucide.FileText : Lucide.FileClock,
                          color: isCurrentLog ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
                        ),
                        title: Text(
                          isCurrentLog ? l10n.logViewerCurrentLog : fileName,
                          style: TextStyle(
                            fontWeight: isCurrentLog ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${_formatFileSize(stat.size)} · ${_formatDate(stat.modified)}',
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                        ),
                        trailing: Icon(Lucide.ChevronRight, color: cs.onSurface.withValues(alpha: 0.4)),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _LogContentPage(file: file),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

/// 日志内容查看页面
class _LogContentPage extends StatefulWidget {
  const _LogContentPage({required this.file});
  final File file;

  @override
  State<_LogContentPage> createState() => _LogContentPageState();
}

/// 解析后的请求/响应条目
class _LogEntry {
  final int requestId;
  final String method;
  final String url;
  final List<String> requestLines;
  final List<String> responseLines;
  final DateTime? timestamp;

  _LogEntry({
    required this.requestId,
    required this.method,
    required this.url,
    required this.requestLines,
    required this.responseLines,
    this.timestamp,
  });

  String get fullText {
    final sb = StringBuffer();
    for (final line in requestLines) {
      sb.writeln(line);
    }
    for (final line in responseLines) {
      sb.writeln(line);
    }
    return sb.toString().trim();
  }

  String get requestText {
    return requestLines.join('\n');
  }

  String get responseText {
    return responseLines.join('\n');
  }
}

class _LogContentPageState extends State<_LogContentPage> {
  List<_LogEntry> _entries = [];
  String _rawContent = '';
  bool _loading = true;
  bool _showParsed = true; // Toggle between parsed view and raw view

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() => _loading = true);
    try {
      final content = await widget.file.readAsString();
      final entries = _parseLogContent(content);
      setState(() {
        _rawContent = content;
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _rawContent = 'Error loading file: $e';
        _entries = [];
        _loading = false;
      });
    }
  }

  /// Parse log content into request/response entries
  List<_LogEntry> _parseLogContent(String content) {
    final lines = content.split('\n');
    final entriesMap = <int, _LogEntry>{};

    // Regex to match log lines: [timestamp] [REQ/RES id] ...
    final lineRegex = RegExp(r'^\[([^\]]+)\]\s+\[(REQ|RES)\s+(\d+)\]\s+(.*)$');
    // Regex to match request start: METHOD URL
    final reqStartRegex = RegExp(r'^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+(.+)$');

    for (final line in lines) {
      final match = lineRegex.firstMatch(line);
      if (match == null) continue;

      final timestamp = match.group(1) ?? '';
      final type = match.group(2); // REQ or RES
      final idStr = match.group(3);
      final rest = match.group(4) ?? '';

      final id = int.tryParse(idStr ?? '') ?? 0;
      if (id <= 0) continue;

      // Get or create entry
      var entry = entriesMap[id];
      if (entry == null) {
        String method = '';
        String url = '';
        DateTime? ts;

        // Try to parse timestamp
        try {
          final parts = timestamp.split(' ');
          if (parts.length >= 2) {
            final dateParts = parts[0].split('-');
            final timeParts = parts[1].split(':');
            if (dateParts.length == 3 && timeParts.length >= 2) {
              final secParts = timeParts.length > 2 ? timeParts[2].split('.') : ['0', '0'];
              ts = DateTime(
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

        // Check if this is a request start line
        if (type == 'REQ') {
          final reqMatch = reqStartRegex.firstMatch(rest);
          if (reqMatch != null) {
            method = reqMatch.group(1) ?? '';
            url = reqMatch.group(2) ?? '';
          }
        }

        entry = _LogEntry(
          requestId: id,
          method: method,
          url: url,
          requestLines: [],
          responseLines: [],
          timestamp: ts,
        );
        entriesMap[id] = entry;
      }

      // Add line to appropriate list
      if (type == 'REQ') {
        entry.requestLines.add(line);
        // Update method/url if this is the start line and we haven't captured it yet
        if (entry.method.isEmpty) {
          final reqMatch = reqStartRegex.firstMatch(rest);
          if (reqMatch != null) {
            entriesMap[id] = _LogEntry(
              requestId: entry.requestId,
              method: reqMatch.group(1) ?? '',
              url: reqMatch.group(2) ?? '',
              requestLines: entry.requestLines,
              responseLines: entry.responseLines,
              timestamp: entry.timestamp,
            );
          }
        }
      } else {
        entry.responseLines.add(line);
      }
    }

    // Sort by request ID descending (newest first)
    final entries = entriesMap.values.toList();
    entries.sort((a, b) => b.requestId.compareTo(a.requestId));
    return entries;
  }

  Future<void> _exportFile() async {
    try {
      await Share.shareXFiles(
        [XFile(widget.file.path)],
        subject: widget.file.path.split(Platform.pathSeparator).last,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    showAppSnackBar(
      context,
      message: '$label 已复制',
      type: NotificationType.success,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final fileName = widget.file.path.split(Platform.pathSeparator).last;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, color: cs.onSurface, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(fileName == 'logs.txt' ? l10n.logViewerCurrentLog : fileName),
        actions: [
          // Toggle view mode
          IconButton(
            icon: Icon(
              _showParsed ? Lucide.List : Lucide.FileText,
              color: cs.onSurface,
              size: 20,
            ),
            tooltip: _showParsed ? '显示原始日志' : '显示分组视图',
            onPressed: () => setState(() => _showParsed = !_showParsed),
          ),
          IconButton(
            icon: Icon(Lucide.Share2, color: cs.onSurface, size: 20),
            tooltip: l10n.logViewerExport,
            onPressed: _exportFile,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rawContent.isEmpty
              ? Center(
                  child: Text(
                    l10n.logViewerEmpty,
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                )
              : _showParsed && _entries.isNotEmpty
                  ? _buildParsedView(cs, isDark)
                  : _buildRawView(cs),
    );
  }

  Widget _buildRawView(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _rawContent,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: cs.onSurface.withValues(alpha: 0.85),
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildParsedView(ColorScheme cs, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return _LogEntryCard(
          entry: entry,
          isDark: isDark,
          onCopyAll: () => _copyToClipboard(entry.fullText, '完整日志'),
          onCopyRequest: () => _copyToClipboard(entry.requestText, '请求'),
          onCopyResponse: () => _copyToClipboard(entry.responseText, '响应'),
        );
      },
    );
  }
}

/// 单个日志条目卡片
class _LogEntryCard extends StatefulWidget {
  final _LogEntry entry;
  final bool isDark;
  final VoidCallback onCopyAll;
  final VoidCallback onCopyRequest;
  final VoidCallback onCopyResponse;

  const _LogEntryCard({
    required this.entry,
    required this.isDark,
    required this.onCopyAll,
    required this.onCopyRequest,
    required this.onCopyResponse,
  });

  @override
  State<_LogEntryCard> createState() => _LogEntryCardState();
}

class _LogEntryCardState extends State<_LogEntryCard> {
  bool _expanded = false;

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _shortenUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      final path = uri.path;
      if (path.length > 30) {
        return '$host${path.substring(0, 30)}...';
      }
      return '$host$path';
    } catch (_) {
      if (url.length > 50) {
        return '${url.substring(0, 50)}...';
      }
      return url;
    }
  }

  Color _getMethodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return Colors.green;
      case 'POST':
        return Colors.blue;
      case 'PUT':
        return Colors.orange;
      case 'DELETE':
        return Colors.red;
      case 'PATCH':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entry = widget.entry;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header - always visible
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  // Request ID badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#${entry.requestId}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Method badge
                  if (entry.method.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getMethodColor(entry.method).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.method,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _getMethodColor(entry.method),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  // URL
                  Expanded(
                    child: Text(
                      entry.url.isNotEmpty ? _shortenUrl(entry.url) : '(unknown)',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Timestamp
                  if (entry.timestamp != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        _formatTimestamp(entry.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  // Expand icon
                  Icon(
                    _expanded ? Lucide.ChevronUp : Lucide.ChevronDown,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (_expanded) ...[
            const Divider(height: 1),
            // Copy buttons row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  _CopyButton(
                    icon: Lucide.Copy,
                    label: '复制全部',
                    onTap: widget.onCopyAll,
                  ),
                  const SizedBox(width: 8),
                  _CopyButton(
                    icon: Lucide.Upload,
                    label: '复制请求',
                    onTap: widget.onCopyRequest,
                  ),
                  const SizedBox(width: 8),
                  _CopyButton(
                    icon: Lucide.Download,
                    label: '复制响应',
                    onTap: widget.onCopyResponse,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Request section
            if (entry.requestLines.isNotEmpty) ...[
              _LogSection(
                title: 'Request',
                icon: Lucide.Upload,
                color: Colors.blue,
                lines: entry.requestLines,
                isDark: widget.isDark,
              ),
            ],
            // Response section
            if (entry.responseLines.isNotEmpty) ...[
              _LogSection(
                title: 'Response',
                icon: Lucide.Download,
                color: Colors.green,
                lines: entry.responseLines,
                isDark: widget.isDark,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Copy button widget
class _CopyButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CopyButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Log section (request or response)
class _LogSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> lines;
  final bool isDark;

  const _LogSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.lines,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${lines.length} lines)',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        // Content
        Container(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? Colors.black26 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            lines.join('\n'),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
