import 'dart:convert';

/// API测试页面的配置模型
/// 支持保存多个配置，类似WebDavConfig的模式
class ApiTestConfig {
  final String id;           // 唯一标识符
  final String name;         // 用户可读的名称（如 "OpenAI正式"、"本地Ollama"）
  final String provider;     // 供应商类型: openai, anthropic, google, custom
  final String apiKey;
  final String baseUrl;
  final List<String> models; // 已获取的模型列表
  final String? selectedModel;

  const ApiTestConfig({
    this.id = '',
    this.name = '',
    this.provider = 'openai',
    this.apiKey = '',
    this.baseUrl = '',
    this.models = const [],
    this.selectedModel,
  });

  /// 生成新的配置（带随机ID）
  factory ApiTestConfig.create({
    String? name,
    String? provider,
    String? apiKey,
    String? baseUrl,
    List<String>? models,
    String? selectedModel,
  }) {
    return ApiTestConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name ?? '',
      provider: provider ?? 'openai',
      apiKey: apiKey ?? '',
      baseUrl: baseUrl ?? '',
      models: models ?? [],
      selectedModel: selectedModel,
    );
  }

  ApiTestConfig copyWith({
    String? id,
    String? name,
    String? provider,
    String? apiKey,
    String? baseUrl,
    List<String>? models,
    String? selectedModel,
    bool clearSelectedModel = false,
  }) {
    return ApiTestConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      models: models ?? this.models,
      selectedModel: clearSelectedModel ? null : (selectedModel ?? this.selectedModel),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'models': models,
        'selectedModel': selectedModel,
      };

  static ApiTestConfig fromJson(Map<String, dynamic> json) {
    return ApiTestConfig(
      id: (json['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: (json['name'] as String?) ?? '',
      provider: (json['provider'] as String?) ?? 'openai',
      apiKey: (json['apiKey'] as String?) ?? '',
      baseUrl: (json['baseUrl'] as String?) ?? '',
      models: (json['models'] as List?)?.cast<String>() ?? [],
      selectedModel: json['selectedModel'] as String?,
    );
  }

  static ApiTestConfig fromJsonString(String s) {
    try {
      final map = jsonDecode(s) as Map<String, dynamic>;
      return ApiTestConfig.fromJson(map);
    } catch (_) {
      return const ApiTestConfig();
    }
  }

  String toJsonString() => jsonEncode(toJson());

  /// 显示名称：优先使用 name，否则使用 provider + baseUrl host
  String get displayName {
    if (name.isNotEmpty) return name;
    if (baseUrl.isEmpty) return provider.toUpperCase();
    try {
      final uri = Uri.parse(baseUrl);
      return uri.host.isNotEmpty ? uri.host : provider.toUpperCase();
    } catch (_) {
      return provider.toUpperCase();
    }
  }

  /// 是否为空配置
  bool get isEmpty => apiKey.isEmpty && baseUrl.isEmpty;
  bool get isNotEmpty => !isEmpty;
}
