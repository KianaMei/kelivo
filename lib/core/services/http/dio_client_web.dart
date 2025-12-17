/// Global Dio HTTP Client (Web)
///
/// Web 环境下：
/// - 不支持自定义系统代理 / 跳过 SSL
/// - Dio 走浏览器的 Fetch/XHR 适配器

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';
import '../../providers/settings_provider.dart';
import '../../utils/http_logger.dart';

late final Dio dio;

void initDio() {
  dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 30),
  ));

  if (kDebugMode) {
    dio.interceptors.add(TalkerDioLogger(
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
}

Dio createDioForProvider(ProviderConfig cfg, {String? baseUrl}) {
  final instance = Dio(BaseOptions(
    baseUrl: baseUrl ?? cfg.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 120),
    sendTimeout: const Duration(seconds: 30),
  ));

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

Dio get simpleDio => dio;

