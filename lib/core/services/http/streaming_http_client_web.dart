import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'dart:typed_data';

class StreamingHttpResponse {
  final int statusCode;
  final Stream<List<int>> stream;

  const StreamingHttpResponse({required this.statusCode, required this.stream});
}

Future<StreamingHttpResponse> postJsonStream({
  required Object dio, // ignored on web
  required Uri url,
  required Map<String, String> headers,
  required Map<String, dynamic> body,
}) async {
  final controller = StreamController<List<int>>(sync: true);
  final req = html.HttpRequest();
  int lastLen = 0;
  final statusCompleter = Completer<int>();

  void emitDelta() {
    final text = req.responseText ?? '';
    if (text.length <= lastLen) return;
    final delta = text.substring(lastLen);
    lastLen = text.length;
    controller.add(Uint8List.fromList(utf8.encode(delta)));
  }

  req.onReadyStateChange.listen((_) {
    if (req.readyState == html.HttpRequest.HEADERS_RECEIVED && !statusCompleter.isCompleted) {
      statusCompleter.complete(req.status);
    }
  });

  req.onProgress.listen((_) => emitDelta());

  req.onLoadEnd.listen((_) {
    if (!statusCompleter.isCompleted) statusCompleter.complete(req.status);
    try {
      emitDelta();
    } catch (_) {}
    controller.close();
  });

  req.onError.listen((_) {
    if (!statusCompleter.isCompleted) statusCompleter.complete(req.status);
    controller.addError(Exception('Network error'));
    controller.close();
  });

  controller.onCancel = () {
    try {
      req.abort();
    } catch (_) {}
  };

  req.open('POST', url.toString());
  headers.forEach((k, v) {
    try {
      req.setRequestHeader(k, v);
    } catch (_) {}
  });
  // Ensure content-type
  if (!headers.keys.map((e) => e.toLowerCase()).contains('content-type')) {
    req.setRequestHeader('Content-Type', 'application/json');
  }
  req.send(jsonEncode(body));

  final status = await statusCompleter.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () => req.status ?? 0,
  );
  return StreamingHttpResponse(statusCode: status, stream: controller.stream);
}

