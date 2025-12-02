import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:talker/talker.dart';

/// 全局 Talker 实例，用于记录所有日志
final talker = Talker(
  settings: TalkerSettings(
    enabled: kDebugMode,
    useConsoleLogs: true,
    maxHistoryItems: 500,
  ),
);

/// HTTP 日志客户端，使用 Talker 记录请求/响应
class TalkerHttpClient extends http.BaseClient {
  final http.Client _inner;
  final bool enabled;
  final bool printRequestHeaders;
  final bool printResponseHeaders;
  final bool printRequestBody;
  final bool printResponseBody;

  TalkerHttpClient(
    this._inner, {
    this.enabled = kDebugMode,
    this.printRequestHeaders = false,
    this.printResponseHeaders = false,
    this.printRequestBody = true,
    this.printResponseBody = true,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!enabled) {
      return _inner.send(request);
    }

    final stopwatch = Stopwatch()..start();

    // 记录请求
    _logRequest(request);

    try {
      final response = await _inner.send(request);
      stopwatch.stop();

      // 对于流式响应，不读取 body（会破坏流）
      // 只记录基本信息
      _logResponse(request, response, stopwatch.elapsedMilliseconds);

      return response;
    } catch (e, stackTrace) {
      stopwatch.stop();
      _logError(request, e, stackTrace, stopwatch.elapsedMilliseconds);
      rethrow;
    }
  }

  void _logRequest(http.BaseRequest request) {
    final sb = StringBuffer();
    sb.writeln('→ ${request.method} ${request.url}');

    if (printRequestHeaders && request.headers.isNotEmpty) {
      sb.writeln('Headers:');
      request.headers.forEach((key, value) {
        // 隐藏敏感信息
        if (_isSensitiveHeader(key)) {
          sb.writeln('  $key: ***');
        } else {
          sb.writeln('  $key: $value');
        }
      });
    }

    if (printRequestBody && request is http.Request && request.body.isNotEmpty) {
      final body = _truncate(request.body, 500);
      sb.writeln('Body: $body');
    }

    talker.logTyped(HttpRequestLog(sb.toString()));
  }

  void _logResponse(
    http.BaseRequest request,
    http.StreamedResponse response,
    int durationMs,
  ) {
    final sb = StringBuffer();
    sb.writeln('← ${response.statusCode} ${request.method} ${request.url}');
    sb.writeln('Duration: ${durationMs}ms');

    if (printResponseHeaders && response.headers.isNotEmpty) {
      sb.writeln('Headers:');
      response.headers.forEach((key, value) {
        sb.writeln('  $key: $value');
      });
    }

    if (response.statusCode >= 400) {
      talker.logTyped(HttpErrorLog(sb.toString()));
    } else {
      talker.logTyped(HttpResponseLog(sb.toString()));
    }
  }

  void _logError(
    http.BaseRequest request,
    Object error,
    StackTrace stackTrace,
    int durationMs,
  ) {
    talker.handle(
      error,
      stackTrace,
      '${request.method} ${request.url} (${durationMs}ms)',
    );
  }

  bool _isSensitiveHeader(String key) {
    final lower = key.toLowerCase();
    return lower.contains('authorization') ||
        lower.contains('api-key') ||
        lower.contains('x-api-key') ||
        lower.contains('token');
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}... (truncated)';
  }
}

/// HTTP 请求日志类型
class HttpRequestLog extends TalkerLog {
  HttpRequestLog(super.message);

  @override
  String get title => 'HTTP-REQ';

  @override
  AnsiPen get pen => AnsiPen()..cyan();
}

/// HTTP 响应日志类型
class HttpResponseLog extends TalkerLog {
  HttpResponseLog(super.message);

  @override
  String get title => 'HTTP-RES';

  @override
  AnsiPen get pen => AnsiPen()..green();
}

/// HTTP 错误日志类型
class HttpErrorLog extends TalkerLog {
  HttpErrorLog(super.message);

  @override
  String get title => 'HTTP-ERR';

  @override
  AnsiPen get pen => AnsiPen()..red();
}

