import 'dart:convert';
import 'dart:html' as html;

Future<String> saveTextToDocuments({
  required String fileName,
  required String content,
}) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob(<dynamic>[bytes], 'text/plain;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.children.add(a);
  a.click();
  a.remove();
  html.Url.revokeObjectUrl(url);
  return fileName;
}

Future<void> openHtmlExternally({required String htmlContent}) async {
  final bytes = utf8.encode(htmlContent);
  final b64 = base64Encode(bytes);
  final url = 'data:text/html;base64,$b64';
  try {
    html.window.open(url, '_blank');
  } catch (_) {
    try {
      html.window.location.href = url;
    } catch (_) {}
  }
}

