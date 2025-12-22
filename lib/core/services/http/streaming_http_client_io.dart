import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../network/request_logger.dart';

class StreamingHttpResponse {
  final int statusCode;
  final Stream<List<int>> stream;

  const StreamingHttpResponse({required this.statusCode, required this.stream});
}

Future<StreamingHttpResponse> postJsonStream({
  required Dio dio,
  required Uri url,
  required Map<String, String> headers,
  required Map<String, dynamic> body,
}) async {
  final reqId = RequestLogger.nextRequestId();

  // 记录请求到 RequestLogger（文件日志）
  if (RequestLogger.enabled) {
    RequestLogger.logRequest(reqId, 'POST', url, headers, utf8.encode(jsonEncode(body)));
  }

  final res = await dio.post<ResponseBody>(
    url.toString(),
    data: body,
    options: Options(
      headers: headers,
      responseType: ResponseType.stream,
      validateStatus: (status) => true,
    ),
  );

  // 记录响应头到 RequestLogger
  if (RequestLogger.enabled) {
    final resHeaders = <String, String>{};
    res.headers.forEach((k, v) => resHeaders[k] = v.join(','));
    RequestLogger.logResponseHeaders(reqId, res.statusCode ?? 0, resHeaders);
  }

  // 拦截流，边转发边记录
  final originalStream = res.data?.stream ?? Stream<List<int>>.empty();

  if (!RequestLogger.enabled) {
    return StreamingHttpResponse(statusCode: res.statusCode ?? 0, stream: originalStream);
  }

  final controller = StreamController<List<int>>();

  originalStream.listen(
    (chunk) {
      controller.add(chunk); // 先转发
      RequestLogger.logResponseChunk(reqId, chunk); // 再记录
    },
    onError: (e, st) {
      RequestLogger.logError(reqId, e.toString());
      controller.addError(e, st);
    },
    onDone: () {
      RequestLogger.logResponseDone(reqId);
      controller.close();
    },
    cancelOnError: false,
  );

  return StreamingHttpResponse(statusCode: res.statusCode ?? 0, stream: controller.stream);
}

