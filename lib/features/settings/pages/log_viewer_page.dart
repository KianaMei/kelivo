import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/app_dirs.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../shared/widgets/markdown_with_highlight.dart';

/// 日志解析状态枚举
enum _ParseState { initial, requestHeaders, requestBody, responseHeaders, responseBody, chunks, error }

/// 将字符串中的转义字符渲染为真实字符
String _renderEscapes(String input) {
  return input
      .replaceAll(r'\n', '\n')   // 字面量 \n -> 真实换行
      .replaceAll(r'\r', '')      // 移除 \r
      .replaceAll(r'\t', '    '); // \t -> 4空格
}

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
        // 直接清空列表，不重新加载文件系统
        if (mounted) {
          setState(() {
            _logFiles = [];
          });
        }
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
  final DateTime? timestamp;
  // 结构化数据
  final Map<String, String> requestHeaders;
  final String requestBody;
  final int? statusCode;
  final Map<String, String> responseHeaders;
  final String responseBody;
  final List<String> responseChunks;
  final bool hasError;
  final String? errorMessage;
  final bool isDone;

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
    this.responseChunks = const [],
    this.hasError = false,
    this.errorMessage,
    this.isDone = false,
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
    if (responseChunks.isNotEmpty) {
      sb.writeln('Response Chunks:');
      for (final chunk in responseChunks) {
        sb.writeln(chunk);
      }
    }
    if (hasError && errorMessage != null) {
      sb.writeln('Error: $errorMessage');
    }
    return sb.toString().trim();
  }

  String get requestText {
    final sb = StringBuffer();
    sb.writeln('$method $url');
    if (requestHeaders.isNotEmpty) {
      sb.writeln('\nHeaders:');
      requestHeaders.forEach((k, v) => sb.writeln('  $k: $v'));
    }
    if (requestBody.isNotEmpty) {
      sb.writeln('\nBody:');
      sb.writeln(requestBody);
    }
    return sb.toString().trim();
  }

  String get responseText {
    final sb = StringBuffer();
    if (statusCode != null) {
      sb.writeln('Status: $statusCode');
    }
    if (responseHeaders.isNotEmpty) {
      sb.writeln('\nHeaders:');
      responseHeaders.forEach((k, v) => sb.writeln('  $k: $v'));
    }
    if (responseBody.isNotEmpty) {
      sb.writeln('\nBody:');
      sb.writeln(responseBody);
    }
    if (responseChunks.isNotEmpty) {
      sb.writeln('\nChunks:');
      for (final chunk in responseChunks) {
        sb.writeln(chunk);
      }
    }
    return sb.toString().trim();
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
  /// 支持新格式日志（带分隔符和结构化内容）
  List<_LogEntry> _parseLogContent(String content) {
    final entries = <_LogEntry>[];
    final lines = content.split('\n');
    
    // 新格式分隔符
    final mainSeparator = RegExp(r'^═{50,}$');
    final subSeparator = RegExp(r'^─{50,}$');
    // 请求头: [id] METHOD  timestamp
    final requestHeaderRegex = RegExp(r'^\[(\d+)\]\s+(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)$');
    // 响应头: ◀ RESPONSE [status]  timestamp
    final responseHeaderRegex = RegExp(r'^◀\s*RESPONSE\s*\[(\d+)\]\s+(\d{2}:\d{2}:\d{2})$');
    // Headers 分隔符
    final headersSectionRegex = RegExp(r'^\s*──\s*Headers\s*─+$');
    // Body 分隔符
    final bodySectionRegex = RegExp(r'^\s*──\s*Body\s*─+$');
    // Chunk 行: │ content
    final chunkLineRegex = RegExp(r'^\s*│\s*(.*)$');
    // Done 标记
    final doneRegex = RegExp(r'^\s*✓\s*Done\s*$');
    // Error 标记
    final errorRegex = RegExp(r'^\s*✗\s*ERROR\s*$');
    // 旧格式行: [timestamp] [REQ/RES id] ...
    final oldFormatRegex = RegExp(r'^\[([^\]]+)\]\s+\[(REQ|RES)\s+(\d+)\]\s+(.*)$');
    
    int i = 0;
    
    while (i < lines.length) {
      final line = lines[i];
      
      // 检查新格式主分隔符
      if (mainSeparator.hasMatch(line) && i + 1 < lines.length) {
        // 下一行应该是请求头
        final headerLine = lines[i + 1];
        final headerMatch = requestHeaderRegex.firstMatch(headerLine);
        
        if (headerMatch != null) {
          final reqId = int.parse(headerMatch.group(1)!);
          final method = headerMatch.group(2)!;
          final timestampStr = headerMatch.group(3)!;
          
          DateTime? timestamp;
          try {
            final parts = timestampStr.split(' ');
            if (parts.length >= 2) {
              final dateParts = parts[0].split('-');
              final timeParts = parts[1].split(':');
              if (dateParts.length == 3 && timeParts.length >= 2) {
                final secParts = timeParts.length > 2 ? timeParts[2].split('.') : ['0', '0'];
                timestamp = DateTime(
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
          
          i += 2; // 跳过分隔符和请求头行
          
          // 跳过下一个分隔符（如果有）
          if (i < lines.length && mainSeparator.hasMatch(lines[i])) {
            i++;
          }
          
          String url = '';
          Map<String, String> requestHeaders = {};
          String requestBody = '';
          int? statusCode;
          Map<String, String> responseHeaders = {};
          String responseBody = '';
          List<String> responseChunks = [];
          bool hasError = false;
          String? errorMessage;
          bool isDone = false;
          
          // 解析请求部分
          var state = _ParseState.initial;
          final bodyLines = <String>[];
          final respBodyLines = <String>[];
          
          while (i < lines.length) {
            final currentLine = lines[i];
            
            // 检查是否到达下一个请求
            if (mainSeparator.hasMatch(currentLine) && i + 1 < lines.length) {
              final nextLine = lines[i + 1];
              if (requestHeaderRegex.hasMatch(nextLine)) {
                break; // 开始下一个请求
              }
            }
            
            // ▶ REQUEST
            if (currentLine.trim().startsWith('▶ REQUEST')) {
              i++;
              // 下一行是 URL
              if (i < lines.length) {
                url = lines[i].trim();
                i++;
              }
              continue;
            }
            
            // Headers 部分
            if (headersSectionRegex.hasMatch(currentLine)) {
              if (state == _ParseState.initial || state == _ParseState.requestHeaders) {
                state = _ParseState.requestHeaders;
              } else {
                state = _ParseState.responseHeaders;
              }
              i++;
              continue;
            }
            
            // Body 部分
            if (bodySectionRegex.hasMatch(currentLine)) {
              if (state == _ParseState.initial || state == _ParseState.requestHeaders || state == _ParseState.requestBody) {
                state = _ParseState.requestBody;
                bodyLines.clear();
              } else {
                state = _ParseState.responseBody;
                respBodyLines.clear();
              }
              i++;
              continue;
            }
            
            // Response 子分隔符
            if (subSeparator.hasMatch(currentLine)) {
              i++;
              continue;
            }
            
            // Response header
            final respMatch = responseHeaderRegex.firstMatch(currentLine);
            if (respMatch != null) {
              statusCode = int.tryParse(respMatch.group(1)!);
              state = _ParseState.responseHeaders;
              i++;
              continue;
            }
            
            // Chunk 行
            final chunkMatch = chunkLineRegex.firstMatch(currentLine);
            if (chunkMatch != null) {
              state = _ParseState.chunks;
              responseChunks.add(chunkMatch.group(1) ?? '');
              i++;
              continue;
            }
            
            // Done
            if (doneRegex.hasMatch(currentLine)) {
              isDone = true;
              i++;
              continue;
            }
            
            // Error
            if (errorRegex.hasMatch(currentLine)) {
              hasError = true;
              state = _ParseState.error;
              i++;
              // 下一行是错误信息
              if (i < lines.length) {
                errorMessage = lines[i].trim();
                i++;
              }
              continue;
            }
            
            // 空行
            if (currentLine.trim().isEmpty) {
              i++;
              continue;
            }
            
            // 根据状态处理内容行
            switch (state) {
              case _ParseState.requestHeaders:
                final trimmed = currentLine.trim();
                final colonIndex = trimmed.indexOf(':');
                if (colonIndex > 0) {
                  final key = trimmed.substring(0, colonIndex).trim();
                  final value = trimmed.substring(colonIndex + 1).trim();
                  requestHeaders[key] = value;
                }
                break;
              case _ParseState.requestBody:
                bodyLines.add(currentLine.replaceFirst(RegExp(r'^\s{0,2}'), ''));
                break;
              case _ParseState.responseHeaders:
                final trimmed = currentLine.trim();
                final colonIndex = trimmed.indexOf(':');
                if (colonIndex > 0) {
                  final key = trimmed.substring(0, colonIndex).trim();
                  final value = trimmed.substring(colonIndex + 1).trim();
                  responseHeaders[key] = value;
                }
                break;
              case _ParseState.responseBody:
                respBodyLines.add(currentLine.replaceFirst(RegExp(r'^\s{0,2}'), ''));
                break;
              default:
                break;
            }
            
            i++;
          }
          
          // 合并并渲染转义字符
          requestBody = _renderEscapes(bodyLines.join('\n').trim());
          responseBody = _renderEscapes(respBodyLines.join('\n').trim());
          
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
            responseChunks: responseChunks,
            hasError: hasError,
            errorMessage: errorMessage,
            isDone: isDone,
          ));
          
          continue;
        }
      }
      
      // 尝试旧格式解析
      final oldMatch = oldFormatRegex.firstMatch(line);
      if (oldMatch != null) {
        final timestamp = oldMatch.group(1) ?? '';
        final type = oldMatch.group(2); // REQ or RES
        final idStr = oldMatch.group(3);
        final rest = oldMatch.group(4) ?? '';

        final id = int.tryParse(idStr ?? '') ?? 0;
        if (id > 0) {
          // 查找或创建 entry
          var entryIndex = entries.indexWhere((e) => e.requestId == id);
          if (entryIndex == -1) {
            String method = '';
            String url = '';
            DateTime? ts;

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

            if (type == 'REQ') {
              final reqStartRegex = RegExp(r'^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+(.+)$');
              final reqMatch = reqStartRegex.firstMatch(rest);
              if (reqMatch != null) {
                method = reqMatch.group(1) ?? '';
                url = reqMatch.group(2) ?? '';
              }
            }

            entries.add(_LogEntry(
              requestId: id,
              method: method,
              url: url,
              timestamp: ts,
              requestBody: type == 'REQ' ? rest : '',
              responseBody: type == 'RES' ? rest : '',
            ));
          }
        }
      }
      
      i++;
    }

    // Sort by request ID descending (newest first)
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
      cacheExtent: 500, // 增加缓存范围以提高滚动性能
      addAutomaticKeepAlives: false, // 减少内存使用
      addRepaintBoundaries: true, // 确保重绘边界
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return _LogEntryCard(
          key: ValueKey(entry.requestId), // 添加 key 提高性能
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
    super.key,
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
            _RequestSection(
              entry: entry,
              isDark: widget.isDark,
            ),
            // Response section
            _ResponseSection(
              entry: entry,
              isDark: widget.isDark,
            ),
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

/// Request section - 显示请求的结构化内容
class _RequestSection extends StatelessWidget {
  final _LogEntry entry;
  final bool isDark;

  const _RequestSection({
    required this.entry,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasHeaders = entry.requestHeaders.isNotEmpty;
    final hasBody = entry.requestBody.isNotEmpty;
    
    if (!hasHeaders && !hasBody && entry.url.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Icon(Lucide.Upload, size: 14, color: Colors.blue),
              const SizedBox(width: 6),
              Text(
                'Request',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
        
        // URL
        if (entry.url.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.blue.withValues(alpha: 0.1) : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: SelectableText(
              entry.url,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ),
        
        // Headers
        if (hasHeaders) ...[
          _SubSectionHeader(title: 'Headers', count: entry.requestHeaders.length),
          _HeadersTable(headers: entry.requestHeaders, isDark: isDark),
        ],
        
        // Body
        if (hasBody) ...[
          _SubSectionHeader(title: 'Body', count: null),
          _JsonBody(content: entry.requestBody, isDark: isDark),
        ],
      ],
    );
  }
}

/// Response section - 显示响应的结构化内容
class _ResponseSection extends StatelessWidget {
  final _LogEntry entry;
  final bool isDark;

  const _ResponseSection({
    required this.entry,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasHeaders = entry.responseHeaders.isNotEmpty;
    final hasBody = entry.responseBody.isNotEmpty;
    final hasChunks = entry.responseChunks.isNotEmpty;
    
    if (entry.statusCode == null && !hasHeaders && !hasBody && !hasChunks && !entry.hasError) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header with status
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Icon(Lucide.Download, size: 14, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                'Response',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
              if (entry.statusCode != null) ...[
                const SizedBox(width: 8),
                _StatusBadge(statusCode: entry.statusCode!),
              ],
              if (entry.isDone) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '✓ Done',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
              if (entry.hasError) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '✗ Error',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // Error message
        if (entry.hasError && entry.errorMessage != null)
          Container(
            margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.red.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: SelectableText(
              entry.errorMessage!,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.red.shade700,
                height: 1.4,
              ),
            ),
          ),
        
        // Headers
        if (hasHeaders) ...[
          _SubSectionHeader(title: 'Headers', count: entry.responseHeaders.length),
          _HeadersTable(headers: entry.responseHeaders, isDark: isDark),
        ],
        
        // Body
        if (hasBody) ...[
          _SubSectionHeader(title: 'Body', count: null),
          _JsonBody(content: entry.responseBody, isDark: isDark),
        ],
        
        // Chunks (for streaming responses)
        if (hasChunks) ...[
          _SubSectionHeader(title: 'Streaming Chunks', count: entry.responseChunks.length),
          _ChunksView(chunks: entry.responseChunks, isDark: isDark),
        ],
        
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 状态码徽章
class _StatusBadge extends StatelessWidget {
  final int statusCode;

  const _StatusBadge({required this.statusCode});

  Color _getStatusColor() {
    if (statusCode >= 200 && statusCode < 300) {
      return Colors.green;
    } else if (statusCode >= 300 && statusCode < 400) {
      return Colors.orange;
    } else if (statusCode >= 400 && statusCode < 500) {
      return Colors.red;
    } else if (statusCode >= 500) {
      return Colors.purple;
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        statusCode.toString(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// 子节标题
class _SubSectionHeader extends StatelessWidget {
  final String title;
  final int? count;

  const _SubSectionHeader({required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '($count)',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Headers 表格显示
class _HeadersTable extends StatelessWidget {
  final Map<String, String> headers;
  final bool isDark;

  const _HeadersTable({required this.headers, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: headers.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: SelectableText(
                    entry.key,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    entry.value,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: cs.onSurface.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// JSON Body 格式化显示 - 支持 Markdown 渲染
class _JsonBody extends StatefulWidget {
  final String content;
  final bool isDark;

  const _JsonBody({required this.content, required this.isDark});

  @override
  State<_JsonBody> createState() => _JsonBodyState();
}

class _JsonBodyState extends State<_JsonBody> {
  bool _showRendered = true; // 默认显示渲染后的内容

  /// 检测内容是否是 JSON
  bool _isJson() {
    final trimmed = widget.content.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
           (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  /// 尝试格式化 JSON
  String _formatContent() {
    try {
      final decoded = jsonDecode(widget.content);
      final formatted = const JsonEncoder.withIndent('  ').convert(decoded);
      return _renderEscapes(formatted);
    } catch (_) {
      return _renderEscapes(widget.content);
    }
  }

  /// 提取所有可渲染的文本内容（messages 中的 content 字段等）
  List<_RenderableContent> _extractRenderableContent() {
    final result = <_RenderableContent>[];
    try {
      final decoded = jsonDecode(widget.content);
      _extractFromJson(decoded, result, '');
    } catch (_) {
      // 不是 JSON，直接作为文本
      result.add(_RenderableContent(
        label: 'Content',
        content: _renderEscapes(widget.content),
        isMarkdown: true,
      ));
    }
    return result;
  }

  /// 递归提取 JSON 中的可渲染内容
  void _extractFromJson(dynamic json, List<_RenderableContent> result, String path) {
    if (json is Map) {
      // 检查是否有 messages 数组
      if (json.containsKey('messages') && json['messages'] is List) {
        final messages = json['messages'] as List;
        for (int i = 0; i < messages.length; i++) {
          final msg = messages[i];
          if (msg is Map && msg.containsKey('content')) {
            final role = msg['role']?.toString() ?? 'unknown';
            final content = msg['content'];
            if (content is String && content.isNotEmpty) {
              result.add(_RenderableContent(
                label: 'Message ${i + 1} ($role)',
                content: _renderEscapes(content),
                isMarkdown: true,
              ));
            }
          }
        }
      }
      // 检查单独的 content 字段
      else if (json.containsKey('content')) {
        final content = json['content'];
        if (content is String && content.isNotEmpty) {
          final role = json['role']?.toString();
          result.add(_RenderableContent(
            label: role != null ? 'Content ($role)' : 'Content',
            content: _renderEscapes(content),
            isMarkdown: true,
          ));
        }
      }
      // 检查 choices 数组（用于响应）
      if (json.containsKey('choices') && json['choices'] is List) {
        final choices = json['choices'] as List;
        for (int i = 0; i < choices.length; i++) {
          final choice = choices[i];
          if (choice is Map) {
            // message.content
            if (choice.containsKey('message') && choice['message'] is Map) {
              final message = choice['message'] as Map;
              if (message.containsKey('content')) {
                final content = message['content'];
                if (content is String && content.isNotEmpty) {
                  result.add(_RenderableContent(
                    label: 'Response ${i + 1}',
                    content: _renderEscapes(content),
                    isMarkdown: true,
                  ));
                }
              }
            }
            // delta.content (streaming)
            if (choice.containsKey('delta') && choice['delta'] is Map) {
              final delta = choice['delta'] as Map;
              if (delta.containsKey('content')) {
                final content = delta['content'];
                if (content is String && content.isNotEmpty) {
                  result.add(_RenderableContent(
                    label: 'Delta ${i + 1}',
                    content: _renderEscapes(content),
                    isMarkdown: true,
                  ));
                }
              }
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isJson = _isJson();
    final renderableContent = _extractRenderableContent();
    final hasRenderableContent = renderableContent.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 切换按钮（如果有可渲染内容）
        if (hasRenderableContent)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                _ViewModeButton(
                  label: '渲染视图',
                  icon: Lucide.FileText,
                  isSelected: _showRendered,
                  onTap: () => setState(() => _showRendered = true),
                ),
                const SizedBox(width: 8),
                _ViewModeButton(
                  label: '原始JSON',
                  icon: Lucide.Code,
                  isSelected: !_showRendered,
                  onTap: () => setState(() => _showRendered = false),
                ),
              ],
            ),
          ),
        
        // 内容显示
        if (_showRendered && hasRenderableContent)
          ...renderableContent.map((item) => _RenderedContentCard(
            label: item.label,
            content: item.content,
            isDark: widget.isDark,
          ))
        else
          // 原始 JSON 显示
          Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.black26 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: isJson ? Border.all(
                color: cs.primary.withValues(alpha: 0.2),
                width: 1,
              ) : null,
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: SelectableText(
                    _formatContent(),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.9),
                      height: 1.5,
                    ),
                  ),
                ),
                if (isJson)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'JSON',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 可渲染内容数据类
class _RenderableContent {
  final String label;
  final String content;
  final bool isMarkdown;

  _RenderableContent({
    required this.label,
    required this.content,
    this.isMarkdown = false,
  });
}

/// 视图模式切换按钮
class _ViewModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewModeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
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
          color: isSelected ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? cs.primary.withValues(alpha: 0.3) : cs.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 渲染后的内容卡片（使用 Markdown 渲染）
class _RenderedContentCard extends StatelessWidget {
  final String label;
  final String content;
  final bool isDark;

  const _RenderedContentCard({
    required this.label,
    required this.content,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.black12 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标签头
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Icon(Lucide.MessageSquare, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          // Markdown 内容
          Padding(
            padding: const EdgeInsets.all(12),
            child: MarkdownWithCodeHighlight(
              text: content,
              baseStyle: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Streaming chunks 显示
class _ChunksView extends StatelessWidget {
  final List<String> chunks;
  final bool isDark;

  const _ChunksView({required this.chunks, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    // 合并所有 chunks 并尝试解析 SSE 格式
    final combinedContent = _parseSSEChunks();
    
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: SelectableText(
          combinedContent,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.85),
            height: 1.4,
          ),
        ),
      ),
    );
  }

  /// 解析 SSE 格式的 chunks，提取有效内容
  String _parseSSEChunks() {
    final sb = StringBuffer();
    for (final chunk in chunks) {
      // 处理转义字符
      var processed = chunk
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '')
          .replaceAll(r'\t', '\t');
      
      // 尝试解析 SSE data 行
      final lines = processed.split('\n');
      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') {
            sb.writeln('[DONE]');
          } else {
            // 尝试解析 JSON
            try {
              final json = jsonDecode(data);
              // 提取 delta content
              if (json is Map) {
                final choices = json['choices'] as List?;
                if (choices != null && choices.isNotEmpty) {
                  final delta = choices[0]['delta'] as Map?;
                  if (delta != null && delta.containsKey('content')) {
                    sb.write(delta['content']);
                    continue;
                  }
                }
              }
              // 如果没有提取到 content，显示完整 JSON
              sb.writeln(const JsonEncoder.withIndent('  ').convert(json));
            } catch (_) {
              sb.writeln(data);
            }
          }
        } else if (line.isNotEmpty && !line.startsWith(':')) {
          sb.writeln(line);
        }
      }
    }
    return sb.toString().trim();
  }
}
