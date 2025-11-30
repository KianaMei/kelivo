import '../api/chat_api_service.dart';
import '../../providers/settings_provider.dart';

/// OCR 服务 - 提供图片 OCR 功能和缓存管理
class OcrService {
  /// LRU 缓存：imagePath -> extracted text
  final Map<String, String> _cache = <String, String>{};
  final List<String> _cacheKeys = <String>[];
  final int maxCacheSize;

  OcrService({this.maxCacheSize = 50});

  /// 获取缓存的 OCR 文本 (LRU 访问更新)
  String? getCached(String imagePath) {
    final key = imagePath.trim();
    if (_cache.containsKey(key)) {
      // Move to end (most recently used)
      _cacheKeys.remove(key);
      _cacheKeys.add(key);
      return _cache[key];
    }
    return null;
  }

  /// 缓存 OCR 文本 (LRU 淘汰)
  void cache(String imagePath, String text) {
    final key = imagePath.trim();
    if (_cache.containsKey(key)) {
      _cacheKeys.remove(key);
    } else if (_cacheKeys.length >= maxCacheSize) {
      // Evict least recently used
      final oldest = _cacheKeys.removeAt(0);
      _cache.remove(oldest);
    }
    _cache[key] = text;
    _cacheKeys.add(key);
  }

  /// 清空缓存
  void clearCache() {
    _cache.clear();
    _cacheKeys.clear();
  }

  /// 包装 OCR 文本为结构化块
  static String wrapOcrBlock(String ocrText) {
    final buf = StringBuffer();
    buf.writeln("The image_file_ocr tag contains a description of an image that the user uploaded to you, not the user's prompt.");
    buf.writeln('<image_file_ocr>');
    buf.writeln(ocrText.trim());
    buf.writeln('</image_file_ocr>');
    buf.writeln();
    return buf.toString();
  }

  /// 执行 OCR - 使用配置的 OCR 模型
  ///
  /// [imagePaths] - 图片路径列表
  /// [settings] - 设置提供者 (获取 OCR 模型配置)
  ///
  /// 返回提取的文本，如果失败返回 null
  static Future<String?> runOcr({
    required List<String> imagePaths,
    required SettingsProvider settings,
  }) async {
    if (imagePaths.isEmpty) return null;
    final prov = settings.ocrModelProvider;
    final model = settings.ocrModelId;
    if (prov == null || model == null) return null;
    final cfg = settings.getProviderConfig(prov);

    final messages = <Map<String, dynamic>>[
      {
        'role': 'user',
        'content': settings.ocrPrompt,
      },
    ];

    final stream = ChatApiService.sendMessageStream(
      config: cfg,
      modelId: model,
      messages: messages,
      userImagePaths: imagePaths,
      thinkingBudget: null,
      temperature: 0.0,
      topP: null,
      maxTokens: null,
      tools: null,
      onToolCall: null,
      extraHeaders: null,
      extraBody: null,
    );

    String out = '';
    await for (final chunk in stream) {
      if (chunk.content.isNotEmpty) {
        out += chunk.content;
      }
    }
    out = out.trim();
    return out.isEmpty ? null : out;
  }

  /// 检查 OCR 是否已配置并启用
  static bool isConfigured(SettingsProvider settings) {
    return settings.ocrEnabled &&
        settings.ocrModelProvider != null &&
        settings.ocrModelId != null;
  }
}
