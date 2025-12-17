Future<List<String>> persistClipboardImages(List<String> srcPaths) async {
  // Web 平台不支持从原生剪贴板拿到本地文件路径；调用方通常会拿到空数组。
  return const <String>[];
}

