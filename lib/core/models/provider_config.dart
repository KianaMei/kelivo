import '../utils/tool_schema_sanitizer.dart' show ProviderKind;
import 'api_keys.dart';

/// Provider configuration for LLM API providers
class ProviderConfig {
  final String id;
  final bool enabled;
  final String name;
  final String apiKey;
  final String baseUrl;
  final ProviderKind? providerType; // Explicit provider type to avoid misclassification
  final String? chatPath; // openai only
  final bool? useResponseApi; // openai only
  final bool? vertexAI; // google only
  final String? location; // google vertex ai only
  final String? projectId; // google vertex ai only
  // Google Vertex AI via service account JSON (paste or import)
  final String? serviceAccountJson; // google vertex ai only
  final List<String> models; // placeholder for future model management
  // Per-model overrides (by model id)
  // {'<modelId>': {'name': String?, 'type': 'chat'|'embedding', 'input': ['text','image'], 'output': [...], 'abilities': ['tool','reasoning']}}
  final Map<String, dynamic> modelOverrides;
  // Per-provider proxy
  final bool? proxyEnabled;
  final String? proxyHost;
  final String? proxyPort;
  final String? proxyUsername;
  final String? proxyPassword;
  // Multi-key mode
  final bool? multiKeyEnabled; // default false
  final List<ApiKeyConfig>? apiKeys; // when enabled
  final KeyManagementConfig? keyManagement;
  // SSL/TLS settings
  final bool? allowInsecureConnection; // Skip SSL certificate verification (for self-signed certs)
  // Custom avatar
  final String? customAvatarPath; // Local path to custom provider avatar

  ProviderConfig({
    required this.id,
    required this.enabled,
    required this.name,
    required this.apiKey,
    required this.baseUrl,
    this.providerType,
    this.chatPath,
    this.useResponseApi,
    this.vertexAI,
    this.location,
    this.projectId,
    this.serviceAccountJson,
    this.models = const [],
    this.modelOverrides = const {},
    this.proxyEnabled,
    this.proxyHost,
    this.proxyPort,
    this.proxyUsername,
    this.proxyPassword,
    this.multiKeyEnabled,
    this.apiKeys,
    this.keyManagement,
    this.allowInsecureConnection,
    this.customAvatarPath,
  });

  ProviderConfig copyWith({
    String? id,
    bool? enabled,
    String? name,
    String? apiKey,
    String? baseUrl,
    ProviderKind? providerType,
    String? chatPath,
    bool? useResponseApi,
    bool? vertexAI,
    String? location,
    String? projectId,
    String? serviceAccountJson,
    List<String>? models,
    Map<String, dynamic>? modelOverrides,
    bool? proxyEnabled,
    String? proxyHost,
    String? proxyPort,
    String? proxyUsername,
    String? proxyPassword,
    bool? multiKeyEnabled,
    List<ApiKeyConfig>? apiKeys,
    KeyManagementConfig? keyManagement,
    bool? allowInsecureConnection,
    String? customAvatarPath,
  }) => ProviderConfig(
        id: id ?? this.id,
        enabled: enabled ?? this.enabled,
        name: name ?? this.name,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        providerType: providerType ?? this.providerType,
        chatPath: chatPath ?? this.chatPath,
        useResponseApi: useResponseApi ?? this.useResponseApi,
        vertexAI: vertexAI ?? this.vertexAI,
        location: location ?? this.location,
        projectId: projectId ?? this.projectId,
        serviceAccountJson: serviceAccountJson ?? this.serviceAccountJson,
        models: models ?? this.models,
        modelOverrides: modelOverrides ?? this.modelOverrides,
        proxyEnabled: proxyEnabled ?? this.proxyEnabled,
        proxyHost: proxyHost ?? this.proxyHost,
        proxyPort: proxyPort ?? this.proxyPort,
        proxyUsername: proxyUsername ?? this.proxyUsername,
        proxyPassword: proxyPassword ?? this.proxyPassword,
        multiKeyEnabled: multiKeyEnabled ?? this.multiKeyEnabled,
        apiKeys: apiKeys ?? this.apiKeys,
        keyManagement: keyManagement ?? this.keyManagement,
        allowInsecureConnection: allowInsecureConnection ?? this.allowInsecureConnection,
        customAvatarPath: customAvatarPath ?? this.customAvatarPath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        'name': name,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'providerType': providerType?.name,
        'chatPath': chatPath,
        'useResponseApi': useResponseApi,
        'vertexAI': vertexAI,
        'location': location,
        'projectId': projectId,
        'serviceAccountJson': serviceAccountJson,
        'models': models,
        'modelOverrides': modelOverrides,
        'proxyEnabled': proxyEnabled,
        'proxyHost': proxyHost,
        'proxyPort': proxyPort,
        'proxyUsername': proxyUsername,
        'proxyPassword': proxyPassword,
        'multiKeyEnabled': multiKeyEnabled,
        'apiKeys': apiKeys?.map((e) => e.toJson()).toList(),
        'keyManagement': keyManagement?.toJson(),
        'allowInsecureConnection': allowInsecureConnection,
        'customAvatarPath': customAvatarPath,
      };

  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
        id: json['id'] as String? ?? (json['name'] as String? ?? ''),
        enabled: json['enabled'] as bool? ?? true,
        name: json['name'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? '',
        providerType: json['providerType'] != null
            ? ProviderKind.values.firstWhere(
                (e) => e.name == json['providerType'],
                orElse: () => classify(json['id'] as String? ?? ''),
              )
            : null,
        chatPath: json['chatPath'] as String?,
        useResponseApi: json['useResponseApi'] as bool?,
        vertexAI: json['vertexAI'] as bool?,
        location: json['location'] as String?,
        projectId: json['projectId'] as String?,
        serviceAccountJson: json['serviceAccountJson'] as String?,
        models: (json['models'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        modelOverrides: (json['modelOverrides'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? const {},
        proxyEnabled: json['proxyEnabled'] as bool?,
        proxyHost: json['proxyHost'] as String?,
        proxyPort: json['proxyPort'] as String?,
        proxyUsername: json['proxyUsername'] as String?,
        proxyPassword: json['proxyPassword'] as String?,
        multiKeyEnabled: json['multiKeyEnabled'] as bool?,
        apiKeys: (json['apiKeys'] as List?)
            ?.whereType<Map>()
            .map((e) => ApiKeyConfig.fromJson(e.cast<String, dynamic>()))
            .toList(),
        keyManagement: KeyManagementConfig.fromJson(
          (json['keyManagement'] as Map?)?.cast<String, dynamic>(),
        ),
        allowInsecureConnection: json['allowInsecureConnection'] as bool?,
        customAvatarPath: json['customAvatarPath'] as String?,
      );

  /// Classify provider type from key name
  static ProviderKind classify(String key, {ProviderKind? explicitType}) {
    // If an explicit type is provided, use it
    if (explicitType != null) return explicitType;

    // Otherwise, infer from the key
    final k = key.toLowerCase();
    if (k.contains('gemini') || k.contains('google')) return ProviderKind.google;
    if (k.contains('claude') || k.contains('anthropic')) return ProviderKind.claude;
    return ProviderKind.openai;
  }

  static String _defaultBase(String key) {
    final k = key.toLowerCase();
    if (k.contains('tensdaq')) return 'https://tensdaq-api.x-aio.com/v1';
    if (k.contains('kelivoin')) return 'https://text.pollinations.ai/openai';
    if (k.contains('openrouter')) return 'https://openrouter.ai/api/v1';
    if (RegExp(r'qwen|aliyun|dashscope').hasMatch(k)) return 'https://dashscope.aliyuncs.com/compatible-mode/v1';
    if (RegExp(r'bytedance|doubao|volces|ark').hasMatch(k)) return 'https://ark.cn-beijing.volces.com/api/v3';
    if (k.contains('silicon')) return 'https://api.siliconflow.cn/v1';
    if (k.contains('grok') || k.contains('x.ai') || k.contains('xai')) return 'https://api.x.ai/v1';
    if (k.contains('deepseek')) return 'https://api.deepseek.com/v1';
    if (RegExp(r'zhipu|智谱|glm').hasMatch(k)) return 'https://open.bigmodel.cn/api/paas/v4';
    if (k.contains('gemini') || k.contains('google')) return 'https://generativelanguage.googleapis.com/v1beta';
    if (k.contains('claude') || k.contains('anthropic')) return 'https://api.anthropic.com/v1';
    return 'https://api.openai.com/v1';
  }

  static ProviderConfig defaultsFor(String key, {String? displayName}) {
    bool defaultEnabled(String k) {
      final s = k.toLowerCase();
      if (s.contains('tensdaq')) return true;
      if (s.contains('openai')) return true;
      if (s.contains('gemini') || s.contains('google')) return true;
      if (s.contains('silicon')) return true;
      if (s.contains('openrouter')) return true;
      if (s.contains('kelivoin')) return true;
      return false; // others disabled by default
    }
    final kind = classify(key);
    final lowerKey = key.toLowerCase();
    switch (kind) {
      case ProviderKind.google:
        return ProviderConfig(
          id: key,
          enabled: defaultEnabled(key),
          name: displayName ?? key,
          apiKey: '',
          baseUrl: _defaultBase(key),
          providerType: ProviderKind.google,
          vertexAI: false,
          location: '',
          projectId: '',
          serviceAccountJson: '',
          models: const [],
          modelOverrides: const {},
          proxyEnabled: false,
          proxyHost: '',
          proxyPort: '8080',
          proxyUsername: '',
          proxyPassword: '',
          multiKeyEnabled: false,
          apiKeys: const [],
          keyManagement: const KeyManagementConfig(),
        );
      case ProviderKind.claude:
        return ProviderConfig(
          id: key,
          enabled: defaultEnabled(key),
          name: displayName ?? key,
          apiKey: '',
          baseUrl: _defaultBase(key),
          providerType: ProviderKind.claude,
          models: const [],
          modelOverrides: const {},
          proxyEnabled: false,
          proxyHost: '',
          proxyPort: '8080',
          proxyUsername: '',
          proxyPassword: '',
          multiKeyEnabled: false,
          apiKeys: const [],
          keyManagement: const KeyManagementConfig(),
        );
      case ProviderKind.openai:
      default:
        // Special-case KelivoIN default models and overrides
        if (lowerKey.contains('kelivoin')) {
          return ProviderConfig(
            id: key,
            enabled: defaultEnabled(key),
            name: displayName ?? key,
            apiKey: 'kelivo',
            baseUrl: _defaultBase(key),
            providerType: ProviderKind.openai,
            chatPath: null, // keep empty in UI; code uses default '/chat/completions'
            useResponseApi: false,
            models: const [
              'mistral',
              'qwen-coder',
            ],
            modelOverrides: const {
              'mistral': {
                'type': 'chat',
                'input': ['text'],
                'output': ['text'],
                'abilities': ['tool'],
              },
              'qwen-coder': {
                'type': 'chat',
                'input': ['text'],
                'output': ['text'],
                'abilities': ['tool'],
              },
            },
            proxyEnabled: false,
            proxyHost: '',
            proxyPort: '8080',
            proxyUsername: '',
            proxyPassword: '',
            multiKeyEnabled: false,
            apiKeys: const [],
            keyManagement: const KeyManagementConfig(),
          );
        }
        // Special-case SiliconFlow: prefill two partnered models
        if (lowerKey.contains('silicon')) {
          return ProviderConfig(
            id: key,
            enabled: defaultEnabled(key),
            name: displayName ?? key,
            apiKey: '',
            baseUrl: _defaultBase(key),
            providerType: ProviderKind.openai,
            chatPath: '/chat/completions',
            useResponseApi: false,
            models: const [
              'THUDM/GLM-4-9B-0414',
              'Qwen/Qwen3-8B',
            ],
            modelOverrides: const {
              'THUDM/GLM-4-9B-0414': {
                'type': 'chat',
                'input': ['text'],
                'output': ['text'],
                'abilities': ['tool'],
              },
              'Qwen/Qwen3-8B': {
                'type': 'chat',
                'input': ['text'],
                'output': ['text'],
                'abilities': ['tool', 'reasoning'],
              },
            },
            proxyEnabled: false,
            proxyHost: '',
            proxyPort: '8080',
            proxyUsername: '',
            proxyPassword: '',
            multiKeyEnabled: false,
            apiKeys: const [],
            keyManagement: const KeyManagementConfig(),
          );
        }
        return ProviderConfig(
          id: key,
          enabled: defaultEnabled(key),
          name: displayName ?? key,
          apiKey: '',
          baseUrl: _defaultBase(key),
          providerType: ProviderKind.openai,
          chatPath: '/chat/completions',
          useResponseApi: false,
          models: const [],
          modelOverrides: const {},
          proxyEnabled: false,
          proxyHost: '',
          proxyPort: '8080',
          proxyUsername: '',
          proxyPassword: '',
          multiKeyEnabled: false,
          apiKeys: const [],
          keyManagement: const KeyManagementConfig(),
        );
    }
  }
}
