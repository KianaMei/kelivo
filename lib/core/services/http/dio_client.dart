/// Global Dio HTTP Client
/// 
/// 统一的 HTTP 客户端，支持：
/// - 日志记录（Talker）
/// - 代理配置
/// - SSL 验证跳过
/// - 超时配置

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';
import '../../providers/settings_provider.dart';
import '../../utils/http_logger.dart';

/// 全局 Dio 实例
late final Dio dio;

/// 初始化全局 Dio 实例（应在 app 启动时调用）
void initDio() {
  dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 30),
  ));

  // 添加 Talker 日志拦截器（仅 Debug 模式）
  if (kDebugMode) {
    dio.interceptors.add(TalkerDioLogger(
      talker: talker,
      settings: const TalkerDioLoggerSettings(
        printRequestHeaders: false,
        printResponseHeaders: false,
        printRequestData: false,
        printResponseData: false, // 关闭所有响应数据打印，避免字节流污染控制台
        printResponseMessage: true,
      ),
    ));
  }
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

  // 添加日志拦截器
  if (kDebugMode) {
    instance.interceptors.add(TalkerDioLogger(
      talker: talker,
      settings: const TalkerDioLoggerSettings(
        printRequestHeaders: false,
        printResponseHeaders: false,
        printRequestData: false,
        printResponseData: false,
        printResponseMessage: true,
      ),
    ));
  }

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
