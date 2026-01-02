import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/app_dirs.dart';

/// HTTP request/response logger.
///
/// Writes JSONL (one JSON object per line) into `logs/logs.txt`, rotated daily.
class RequestLogger {
  RequestLogger._();

  static bool _enabled = false;
  static bool get enabled => _enabled;
  static bool _writeErrorReported = false;

  static int _nextRequestId = 0;
  static bool _idInitialized = false;
  static int nextRequestId() => ++_nextRequestId;

  static Future<void> setEnabled(bool v) async {
    if (_enabled == v) return;
    _enabled = v;
    if (!v) {
      try {
        await _sink?.flush();
      } catch (_) {}
      try {
        await _sink?.close();
      } catch (_) {}
      _sink = null;
      _sinkDate = null;
    } else {
      _writeErrorReported = false;
      // 启用时从日志文件读取最大 ID，避免 ID 冲突
      if (!_idInitialized) {
        await _initNextRequestId();
        _idInitialized = true;
      }
    }
  }

  /// 从日志文件读取最大请求 ID，确保新请求 ID 不会与旧记录冲突
  static Future<void> _initNextRequestId() async {
    try {
      final dir = await AppDirs.dataRoot();
      final logFile = File('${dir.path}/logs/logs.txt');
      if (!await logFile.exists()) return;

      int maxId = 0;
      final lines = await logFile.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty || !line.trim().startsWith('{')) continue;
        try {
          final map = jsonDecode(line.trim()) as Map<String, dynamic>;
          final id = map['id'];
          if (id is int && id > maxId) {
            maxId = id;
          } else if (id is num && id.toInt() > maxId) {
            maxId = id.toInt();
          }
        } catch (_) {
          continue;
        }
      }
      _nextRequestId = maxId;
    } catch (_) {
      // Ignore errors - will start from 0
    }
  }

  static IOSink? _sink;
  static DateTime? _sinkDate;
  static Future<void> _writeQueue = Future<void>.value();

  static String _two(int v) => v.toString().padLeft(2, '0');
  static DateTime _dayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  static String _formatDate(DateTime dt) => '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';

  static Future<IOSink> _ensureSink() async {
    final now = DateTime.now();
    final today = _dayOf(now);
    if (_sink != null && _sinkDate == today) return _sink!;

    try {
      await _sink?.flush();
    } catch (_) {}
    try {
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    _sinkDate = today;

    final dir = await AppDirs.dataRoot();
    final logsDir = Directory('${dir.path}/logs');
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }

    final active = File('${logsDir.path}/logs.txt');
    if (await active.exists()) {
      try {
        final stat = await active.stat();
        final fileDay = _dayOf(stat.modified.toLocal());
        if (fileDay != today) {
          final suffix = _formatDate(fileDay);
          var rotated = File('${logsDir.path}/logs_$suffix.txt');
          if (await rotated.exists()) {
            int i = 1;
            while (await File('${logsDir.path}/logs_${suffix}_$i.txt').exists()) {
              i++;
            }
            rotated = File('${logsDir.path}/logs_${suffix}_$i.txt');
          }
          await active.rename(rotated.path);
        }
      } catch (_) {}
    }

    _sink = active.openWrite(mode: FileMode.append);
    return _sink!;
  }

  static void _enqueueWrite(String content) {
    if (!_enabled) return;
    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      if (!_enabled) return;
      try {
        final sink = await _ensureSink();
        sink.write(content);
        await sink.flush();
      } catch (_) {
        try {
          await _sink?.flush();
        } catch (_) {}
        try {
          await _sink?.close();
        } catch (_) {}
        _sink = null;
        _sinkDate = null;
        if (!_writeErrorReported) {
          _writeErrorReported = true;
          try {
            stderr.writeln('[RequestLogger] write failed; further write errors will be suppressed.');
          } catch (_) {}
        }
      }
    });
  }

  static void _writeJsonLine(Map<String, Object?> obj) {
    if (!_enabled) return;
    try {
      final json = jsonEncode(obj);
      _enqueueWrite('$json\n');
    } catch (_) {
      // Logging must never crash the app.
    }
  }

  static void logRequest(int reqId, String method, Uri uri, Map<String, String> headers, List<int> bodyBytes) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final body = bodyBytes.isNotEmpty ? safeDecodeUtf8(bodyBytes) : '';
    final safeHeaders = headers.map((k, v) => MapEntry(k, _maskSensitive(k, v)));

    _writeJsonLine({
      'v': 1,
      'type': 'request',
      'id': reqId,
      'ts': ts,
      'method': method,
      'url': uri.toString(),
      if (safeHeaders.isNotEmpty) 'headers': safeHeaders,
      if (body.isNotEmpty) 'body': body,
      if (bodyBytes.isNotEmpty) 'body_bytes': bodyBytes.length,
    });
  }

  static void logResponseHeaders(int reqId, int statusCode, Map<String, String> headers) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    _writeJsonLine({
      'v': 1,
      'type': 'response_headers',
      'id': reqId,
      'ts': ts,
      'status': statusCode,
      if (headers.isNotEmpty) 'headers': headers,
    });
  }

  static void logResponseBody(int reqId, String body) {
    if (body.isEmpty) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    _writeJsonLine({
      'v': 1,
      'type': 'response_body',
      'id': reqId,
      'ts': ts,
      'body': body,
    });
  }

  static void logResponseChunk(int reqId, List<int> chunk) {
    final s = safeDecodeUtf8(chunk);
    if (s.isEmpty) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    _writeJsonLine({
      'v': 1,
      'type': 'chunk',
      'id': reqId,
      'ts': ts,
      'chunk': s,
      'chunk_bytes': chunk.length,
    });
  }

  static void logResponseDone(int reqId) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    _writeJsonLine({
      'v': 1,
      'type': 'done',
      'id': reqId,
      'ts': ts,
    });
  }

  static void logError(int reqId, String error) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    _writeJsonLine({
      'v': 1,
      'type': 'error',
      'id': reqId,
      'ts': ts,
      'message': error,
    });
  }

  static String _maskSensitive(String key, String value) => value;

  static String safeDecodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }
}
