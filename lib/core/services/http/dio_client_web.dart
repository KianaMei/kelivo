/// Global Dio HTTP Client (Web)
///
/// 统一的 HTTP 客户端，支持：
/// - 日志记录（Talker + RequestLogger Stub）
/// - 自定义 baseUrl
///
/// 注意：Web 端不支持 dart:io 的 HttpClientAdapter，因此不支持原生的代理配置和 SSL 验证跳过。
/// 浏览器环境由浏览器自身的网络栈管理。

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../providers/settings_provider.dart';
import '../../utils/http_logger.dart';
import '../network/request_logger.dart';

/// One-time log key
const String kLogNetworkResultOnlyExtraKey = 'kelivo_log_network_result_only';

bool _logNetworkResultOnly(RequestOptions options) =>
    options.extra[kLogNetworkResultOnlyExtraKey] == true;

/// 全局 Dio 实例
late final Dio dio;

/// 初始化全局 Dio 实例
void initDio() {
  dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 30),
  ));

  // Logger interceptors (stubbed on web or using console/Talker)
  dio.interceptors.add(RequestLoggerInterceptor());
  dio.interceptors.add(ConditionalTalkerInterceptor());
}

/// 为 Provider 创建 Dio 实例 (Web)
Dio createDioForProvider(ProviderConfig cfg, {String? baseUrl}) {
  // Web does not support IOHttpClientAdapter, so we ignore proxy/SSL configs intended for IO.
  // We just use the standard BrowserHttpClientAdapter (default for Dio on Web).
  
  final instance = Dio(BaseOptions(
    baseUrl: baseUrl ?? cfg.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 120),
    sendTimeout: const Duration(seconds: 30),
  ));

  instance.interceptors.add(RequestLoggerInterceptor());
  instance.interceptors.add(ConditionalTalkerInterceptor());

  return instance;
}

Dio get simpleDio => dio;

/// Request Logger Interceptor (Web compatible)
class RequestLoggerInterceptor extends Interceptor {
  final Map<RequestOptions, int> _requestIds = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (RequestLogger.enabled) {
      final reqId = RequestLogger.nextRequestId();
      _requestIds[options] = reqId;

      final headers = Map<String, String>.from(
        options.headers.map((k, v) => MapEntry(k, v.toString())),
      );
      List<int> bodyBytes = const [];
      if (options.data != null) {
        if (options.data is List<int>) {
          bodyBytes = options.data as List<int>;
        } else if (options.data is String) {
          bodyBytes = utf8.encode(options.data as String);
        } else if (options.data is Map || options.data is List) {
          try {
            bodyBytes = utf8.encode(jsonEncode(options.data));
          } catch (_) {}
        }
      }
      RequestLogger.logRequest(reqId, options.method, options.uri, headers, bodyBytes);
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (RequestLogger.enabled) {
      final reqId = _requestIds.remove(response.requestOptions) ?? 0;
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        if (values.isNotEmpty) headers[name] = values.join(',');
      });
      RequestLogger.logResponseHeaders(reqId, response.statusCode ?? 0, headers);

      if (response.data != null && response.data is! ResponseBody) {
        String bodyStr = '';
        if (response.data is String) {
          bodyStr = response.data as String;
        } else if (response.data is Map || response.data is List) {
          try {
            bodyStr = jsonEncode(response.data);
          } catch (_) {}
        } else if (response.data is Uint8List) {
          bodyStr = RequestLogger.safeDecodeUtf8(response.data as Uint8List);
        } else if (response.data is List<int>) {
           bodyStr = RequestLogger.safeDecodeUtf8(response.data as List<int>);
        }
        if (bodyStr.isNotEmpty) {
          RequestLogger.logResponseBody(reqId, bodyStr);
        }
      }
      RequestLogger.logResponseDone(reqId);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (RequestLogger.enabled) {
      final reqId = _requestIds.remove(err.requestOptions) ?? 0;
      RequestLogger.logError(reqId, err.toString());
    }
    handler.next(err);
  }
}

class StreamResponseLoggerInterceptor extends Interceptor {
  final Map<RequestOptions, int> _requestIds = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (RequestLogger.enabled && options.responseType == ResponseType.stream) {
      final reqId = RequestLogger.nextRequestId();
      _requestIds[options] = reqId;

      final headers = Map<String, String>.from(
        options.headers.map((k, v) => MapEntry(k, v.toString())),
      );
      List<int> bodyBytes = const [];
      if (options.data != null) {
         if (options.data is List<int>) {
          bodyBytes = options.data as List<int>;
        } else if (options.data is String) {
          bodyBytes = utf8.encode(options.data as String);
        } else if (options.data is Map || options.data is List) {
          try {
            bodyBytes = utf8.encode(jsonEncode(options.data));
          } catch (_) {}
        }
      }
      RequestLogger.logRequest(reqId, options.method, options.uri, headers, bodyBytes);
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (RequestLogger.enabled && response.requestOptions.responseType == ResponseType.stream) {
      final reqId = _requestIds[response.requestOptions] ?? 0;
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
         if (values.isNotEmpty) headers[name] = values.join(',');
      });
      RequestLogger.logResponseHeaders(reqId, response.statusCode ?? 0, headers);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (RequestLogger.enabled) {
      final reqId = _requestIds.remove(err.requestOptions) ?? 0;
      RequestLogger.logError(reqId, err.toString());
    }
    handler.next(err);
  }

  int? getRequestId(RequestOptions options) => _requestIds[options];

  void finishRequest(RequestOptions options) {
    final reqId = _requestIds.remove(options);
    if (reqId != null && RequestLogger.enabled) {
      RequestLogger.logResponseDone(reqId);
    }
  }
}

class ConditionalTalkerInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (TalkerLogger.enabled) {
      final sb = StringBuffer();
      sb.writeln('→ ${options.method} ${options.uri}');

      if (options.headers.isNotEmpty) {
        sb.writeln('Headers:');
        options.headers.forEach((key, value) {
          sb.writeln('  $key: $value');
        });
      }

      if (options.data != null) {
        sb.writeln('Body:');
        sb.writeln(options.data.toString());
      }

      talker.logTyped(HttpRequestLog(sb.toString()));
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (TalkerLogger.enabled) {
      final sb = StringBuffer();
      sb.writeln('← ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.uri}');

      if (response.headers.map.isNotEmpty) {
        sb.writeln('Headers:');
         response.headers.forEach((name, values) {
          sb.writeln('  $name: ${values.join(", ")}');
        });
      }

      if (response.data != null && response.data is! ResponseBody) {
        sb.writeln('Body:');
        sb.writeln(response.data.toString());
      }
      
      if (response.statusCode != null && response.statusCode! >= 400) {
        talker.logTyped(HttpErrorLog(sb.toString()));
      } else {
        talker.logTyped(HttpResponseLog(sb.toString()));
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (TalkerLogger.enabled) {
       final sb = StringBuffer();
      sb.writeln('✕ ERROR ${err.requestOptions.method} ${err.requestOptions.uri}');
      sb.writeln('Type: ${err.type}');
      sb.writeln('Message: ${err.message}');
      talker.logTyped(HttpErrorLog(sb.toString()));
    }
    handler.next(err);
  }
}
