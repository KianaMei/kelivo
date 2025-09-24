import 'dart:io';

import 'package:open_filex/open_filex.dart';

import 'platform_capabilities.dart';

class FileOpenResult {
  final bool success;
  final String? message;

  const FileOpenResult({required this.success, this.message});
}

Future<FileOpenResult> openFileWithFallback(String path, {String? mimeType}) async {
  if (PlatformCapabilities.supportsOpenFilePlugin) {
    try {
      final result = await OpenFilex.open(path, type: mimeType);
      return FileOpenResult(
        success: result.type == ResultType.done,
        message: result.message ?? result.type.name,
      );
    } catch (e) {
      return FileOpenResult(success: false, message: e.toString());
    }
  }

  if (PlatformCapabilities.isWindows) {
    try {
      final escaped = path.replaceAll('"', '`"');
      final command = 'Start-Process -FilePath "' + escaped + '"';
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', command],
      );
      if (result.exitCode == 0) {
        return const FileOpenResult(success: true);
      }
      final stderr = result.stderr;
      final stdout = result.stdout;
      final message =
          (stderr is String && stderr.trim().isNotEmpty)
              ? stderr.trim()
              : (stdout is String && stdout.trim().isNotEmpty)
                  ? stdout.trim()
                  : null;
      return FileOpenResult(success: false, message: message);
    } catch (e) {
      return FileOpenResult(success: false, message: e.toString());
    }
  }

  return const FileOpenResult(
    success: false,
    message: 'File opening is not supported on this platform.',
  );
}
