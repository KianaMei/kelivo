/// Global Dio HTTP Client (IO platforms)
///
/// 统一的 HTTP 客户端，支持：
/// - 日志记录（Talker + RequestLogger 文件日志）
/// - 代理配置
/// - SSL 验证跳过
/// - 超时配置

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../../providers/settings_provider.dart';
import '../../utils/http_logger.dart';
import '../network/request_logger.dart';

/// Extra key to mark requests that should only log results (not full request/response)
const String kLogNetworkResultOnlyExtraKey = 'kelivo_log_network_result_only';

/// 全局 Dio 实例
late final Dio dio;

/// 初始化全局 Dio 实例（应在 app 启动时调用）
void initDio() {
  dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 30),
  ));

  // 添加条件 Talker 日志拦截器（受开关控制）
  dio.interceptors.add(ConditionalTalkerInterceptor());
}

/// 为特定 Provider 创建配置好的 Dio 实例
///
/// 支持：
/// - 代理配置
/// - SSL 验证跳过
/// - 自定义 baseUrl
Dio createDioForProvider(ProviderConfig cfg, {String? baseUrl}) {
  final instance = Dio(BaseOptions(
    baseUrl: baseUrl ?? cfg.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 120), // 流式响应需要更长时间
    sendTimeout: const Duration(seconds: 30),
  ));

  // 配置代理和 SSL
  _configureAdapter(instance, cfg);

  // 添加请求日志拦截器（文件日志，用户可控）
  instance.interceptors.add(RequestLoggerInterceptor());

  // 添加条件 Talker 日志拦截器（受开关控制）
  instance.interceptors.add(ConditionalTalkerInterceptor());

  return instance;
}

/// 配置 Dio 的 HttpClientAdapter（代理和 SSL）
void _configureAdapter(Dio instance, ProviderConfig cfg) {
  final proxyEnabled = cfg.proxyEnabled == true;
  final host = (cfg.proxyHost ?? '').trim();
  final portStr = (cfg.proxyPort ?? '').trim();
  final user = (cfg.proxyUsername ?? '').trim();
  final pass = (cfg.proxyPassword ?? '').trim();
  final allowInsecure = cfg.allowInsecureConnection == true;

  if (!proxyEnabled && !allowInsecure) return;

  instance.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();

      // 配置代理
      if (proxyEnabled && host.isNotEmpty && portStr.isNotEmpty) {
        final port = int.tryParse(portStr) ?? 8080;
        client.findProxy = (uri) => 'PROXY $host:$port';
        if (user.isNotEmpty && pass.isNotEmpty) {
          client.addProxyCredentials(
            host,
            port,
            'Basic',
            HttpClientBasicCredentials(user, pass),
          );
        }
      }

      // 跳过 SSL 验证
      if (allowInsecure) {
        client.badCertificateCallback = (cert, host, port) => true;
      }

      return client;
    },
  );
}

/// 简单请求（不需要 Provider 配置）
/// 用于头像下载、更新检查等简单场景
Dio get simpleDio => dio;

/// Request Logger Interceptor - 记录请求/响应到文件
class RequestLoggerInterceptor extends Interceptor {
  final Map<RequestOptions, int> _requestIds = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (RequestLogger.enabled) {
      final reqId = RequestLogger.nextRequestId();
      _requestIds[options] = reqId;

      // 记录请求
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

      // 记录响应体（非流式）
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

/// 流式响应拦截器 - 记录流式数据的每个 chunk
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
      // 流式数据的 chunk 记录在 chat_api_service 中处理
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

  /// 获取请求 ID（用于流式响应的 chunk 记录）
  int? getRequestId(RequestOptions options) => _requestIds[options];

  /// 完成请求记录
  void finishRequest(RequestOptions options) {
    final reqId = _requestIds.remove(options);
    if (reqId != null && RequestLogger.enabled) {
      RequestLogger.logResponseDone(reqId);
    }
  }
}

/// 条件 Talker 日志拦截器 - 仅在开关开启时记录完整请求/响应
class ConditionalTalkerInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (TalkerLogger.enabled) {
      final sb = StringBuffer();
      sb.writeln('→ ${options.method} ${options.uri}');

      // Headers
      if (options.headers.isNotEmpty) {
        sb.writeln('Headers:');
        options.headers.forEach((key, value) {
          sb.writeln('  $key: $value');
        });
      }

      // Request Body
      if (options.data != null) {
        sb.writeln('Body:');
        String bodyStr = '';
        if (options.data is String) {
          bodyStr = options.data as String;
        } else if (options.data is Map || options.data is List) {
          try {
            final encoder = JsonEncoder.withIndent('  ');
            bodyStr = encoder.convert(options.data);
          } catch (_) {
            bodyStr = options.data.toString();
          }
        } else {
          bodyStr = options.data.toString();
        }
        sb.writeln(bodyStr);
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

      // Response Headers
      if (response.headers.map.isNotEmpty) {
        sb.writeln('Headers:');
        response.headers.forEach((name, values) {
          sb.writeln('  $name: ${values.join(", ")}');
        });
      }

      // Response Body (非流式)
      if (response.data != null && response.data is! ResponseBody) {
        sb.writeln('Body:');
        String bodyStr = '';
        if (response.data is String) {
          bodyStr = response.data as String;
        } else if (response.data is Map || response.data is List) {
          try {
            final encoder = JsonEncoder.withIndent('  ');
            bodyStr = encoder.convert(response.data);
          } catch (_) {
            bodyStr = response.data.toString();
          }
        } else {
          bodyStr = response.data.toString();
        }
        sb.writeln(bodyStr);
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
      if (err.response != null) {
        sb.writeln('Status: ${err.response?.statusCode}');
        if (err.response?.data != null) {
          sb.writeln('Response: ${err.response?.data}');
        }
      }
      talker.logTyped(HttpErrorLog(sb.toString()));
    }
    handler.next(err);
  }
}
