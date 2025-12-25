import 'dart:convert';

/// HTTP request/response logger stub for Web.
class RequestLogger {
  RequestLogger._();

  static bool _enabled = false;
  static bool get enabled => _enabled;
  
  // ignore: unused_field
  static int _nextRequestId = 0;
  static int nextRequestId() => ++_nextRequestId;

  static Future<void> setEnabled(bool v) async {
    _enabled = v;
  }

  static void logRequest(int reqId, String method, Uri uri, Map<String, String> headers, List<int> bodyBytes) {}

  static void logResponseHeaders(int reqId, int statusCode, Map<String, String> headers) {}

  static void logResponseBody(int reqId, String body) {}

  static void logResponseChunk(int reqId, List<int> chunk) {}

  static void logResponseDone(int reqId) {}

  static void logError(int reqId, String error) {}

  static String safeDecodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }
}
