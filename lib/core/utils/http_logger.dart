import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:talker/talker.dart';

/// 全局 Talker 实例，用于记录所有日志
final talker = Talker(
  settings: TalkerSettings(
    enabled: true,  // 始终启用，通过 maxHistoryItems 控制内存
    useConsoleLogs: kDebugMode,  // 只在 debug 模式打印到控制台
    maxHistoryItems: 200,
  ),
);

/// Talker 日志开关（用于控制是否记录到 Talker）
class TalkerLogger {
  TalkerLogger._();

  static bool _enabled = false;
  static bool get enabled => _enabled;

  static void setEnabled(bool v) {
    _enabled = v;
  }
}

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
    this.enabled = true,  // 默认启用
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

      // 检查是否是 SSE 流式响应
      final contentType = response.headers['content-type'] ?? '';
      final isSSE = contentType.contains('text/event-stream');

      if (isSSE && printResponseBody) {
        // SSE 流式响应：边转发边记录，流结束后输出完整日志
        final bodyBuffer = StringBuffer();
        final controller = StreamController<List<int>>();

        response.stream.listen(
          (chunk) {
            controller.add(chunk);
            try {
              bodyBuffer.write(String.fromCharCodes(chunk));
            } catch (_) {}
          },
          onError: (e, st) {
            controller.addError(e, st);
          },
          onDone: () {
            // 流结束，记录完整响应
            _logResponse(
              request,
              response,
              stopwatch.elapsedMilliseconds,
              bodyBuffer.toString(),
            );
            controller.close();
          },
          cancelOnError: false,
        );

        return http.StreamedResponse(
          controller.stream,
          response.statusCode,
          contentLength: response.contentLength,
          request: response.request,
          headers: response.headers,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase,
        );
      } else {
        // 非流式响应：读取完整 body 后记录
        final responseBody = await response.stream.toBytes();
        String bodyText = '';
        try {
          bodyText = String.fromCharCodes(responseBody);
        } catch (_) {
          bodyText = '[Binary data, ${responseBody.length} bytes]';
        }
        _logResponse(request, response, stopwatch.elapsedMilliseconds, bodyText);

        return http.StreamedResponse(
          Stream.value(responseBody),
          response.statusCode,
          contentLength: responseBody.length,
          request: response.request,
          headers: response.headers,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase,
        );
      }
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
        // 直接显示所有 header，包括 API key
        sb.writeln('  $key: $value');
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
    String responseBody,
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

    // 记录响应 body
    if (printResponseBody && responseBody.isNotEmpty) {
      final truncatedBody = _truncate(responseBody, 2000);
      sb.writeln('Body: $truncatedBody');
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

