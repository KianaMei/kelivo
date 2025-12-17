import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

Future<String> saveTextToDocuments({
  required String fileName,
  required String content,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(content);
  return file.path;
}

Future<void> openHtmlExternally({required String htmlContent}) async {
  final dir = await getTemporaryDirectory();
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final file = File('${dir.path}/preview_$timestamp.html');
  await file.writeAsString(htmlContent);
  await launchUrl(Uri.file(file.path));
}

