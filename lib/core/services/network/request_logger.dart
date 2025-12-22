import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/app_dirs.dart';

/// 请求日志记录器
///
/// 用于记录 HTTP 请求/响应到文件，支持：
/// - 按天轮转日志文件
/// - 异步串行化写入
/// - 流式数据 chunk 记录
/// - 美化格式输出，提高可读性
class RequestLogger {
  RequestLogger._();

  static bool _enabled = false;
  static bool get enabled => _enabled;

  static int _nextRequestId = 0;
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
    }
  }

  static IOSink? _sink;
  static DateTime? _sinkDate;
  static Future<void> _writeQueue = Future<void>.value();

  static String _two(int v) => v.toString().padLeft(2, '0');
  static DateTime _dayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  static String _formatDate(DateTime dt) => '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';
  static String _formatTs(DateTime dt) {
    return '${_formatDate(dt)} ${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}.${dt.millisecond.toString().padLeft(3, '0')}';
  }
  static String _formatTime(DateTime dt) {
    return '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
  }

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

  /// 写入原始内容（不添加时间戳）
  static void _writeRaw(String content) {
    if (!_enabled) return;
    _writeQueue = _writeQueue.then((_) async {
      final sink = await _ensureSink();
      sink.write(content);
      await sink.flush();
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // 分隔符常量
  // ═══════════════════════════════════════════════════════════════════
  static const _separator = '═══════════════════════════════════════════════════════════════════════════════';
  static const _subSeparator = '───────────────────────────────────────────────────────────────────────────────';

  /// 记录请求开始
  static void logRequest(int reqId, String method, Uri uri, Map<String, String> headers, List<int> bodyBytes) {
    final now = DateTime.now();
    final sb = StringBuffer();

    // 请求头部
    sb.writeln();
    sb.writeln(_separator);
    sb.writeln('[$reqId] $method  ${_formatTs(now)}');
    sb.writeln(_separator);
    sb.writeln();
    sb.writeln('▶ REQUEST');
    sb.writeln('  $uri');

    // Headers
    if (headers.isNotEmpty) {
      sb.writeln();
      sb.writeln('  ── Headers ${'─' * 60}');
      for (final entry in headers.entries) {
        // 隐藏敏感信息
        final value = _maskSensitive(entry.key, entry.value);
        sb.writeln('  ${entry.key}: $value');
      }
    }

    // Body
    if (bodyBytes.isNotEmpty) {
      final decoded = safeDecodeUtf8(bodyBytes);
      if (decoded.isNotEmpty) {
        sb.writeln();
        sb.writeln('  ── Body ${'─' * 63}');
        final formatted = tryFormatJson(decoded);
        if (formatted != null) {
          // 缩进每一行
          for (final line in formatted.split('\n')) {
            sb.writeln('  $line');
          }
        } else {
          sb.writeln('  $decoded');
        }
      }
    }

    sb.writeln();
    _writeRaw(sb.toString());
  }

  /// 记录响应头
  static void logResponseHeaders(int reqId, int statusCode, Map<String, String> headers) {
    final now = DateTime.now();
    final sb = StringBuffer();

    sb.writeln(_subSeparator);
    sb.writeln('◀ RESPONSE [$statusCode]  ${_formatTime(now)}');

    // Headers
    if (headers.isNotEmpty) {
      sb.writeln();
      sb.writeln('  ── Headers ${'─' * 60}');
      for (final entry in headers.entries) {
        sb.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    _writeRaw(sb.toString());
  }

  /// 记录响应体（非流式）
  static void logResponseBody(int reqId, String body) {
    if (body.isEmpty) return;
    final sb = StringBuffer();

    sb.writeln();
    sb.writeln('  ── Body ${'─' * 63}');
    final formatted = tryFormatJson(body);
    if (formatted != null) {
      for (final line in formatted.split('\n')) {
        sb.writeln('  $line');
      }
    } else {
      sb.writeln('  $body');
    }

    _writeRaw(sb.toString());
  }

  /// 记录响应 chunk（流式）
  static void logResponseChunk(int reqId, List<int> chunk) {
    final s = safeDecodeUtf8(chunk);
    if (s.isNotEmpty) {
      _writeRaw('  │ ${escape(s)}\n');
    }
  }

  /// 记录响应完成
  static void logResponseDone(int reqId) {
    _writeRaw('\n  ✓ Done\n\n');
  }

  /// 记录错误
  static void logError(int reqId, String error) {
    final sb = StringBuffer();
    sb.writeln();
    sb.writeln('  ✗ ERROR');
    sb.writeln('  $error');
    sb.writeln();
    _writeRaw(sb.toString());
  }

  /// 返回完整的 header 值（不隐藏任何信息）
  static String _maskSensitive(String key, String value) {
    // 不再隐藏任何信息，直接返回完整值
    return value;
  }

  /// 尝试格式化 JSON 字符串
  static String? tryFormatJson(String input) {
    try {
      final decoded = jsonDecode(input);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return null;
    }
  }

  static String safeDecodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  static String escape(String input) {
    return input
        .replaceAll('\\', r'\\')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
  }
}
