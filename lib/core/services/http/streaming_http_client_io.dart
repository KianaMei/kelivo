import 'dart:convert';

import 'package:dio/dio.dart';

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
  final res = await dio.post<ResponseBody>(
    url.toString(),
    data: body,
    options: Options(
      headers: headers,
      responseType: ResponseType.stream,
      validateStatus: (status) => true,
    ),
  );

  final stream = res.data?.stream ?? Stream<List<int>>.empty();
  return StreamingHttpResponse(statusCode: res.statusCode ?? 0, stream: stream);
}

