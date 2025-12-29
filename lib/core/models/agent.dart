import 'dart:convert';

/// Permission mode for agent tool execution
enum AgentPermissionMode {
  /// Require user approval for all tool calls
  requireApproval,
  /// Auto-approve file edits, require approval for others
  acceptEdits,
  /// Bypass all permission checks (dangerous)
  bypassPermissions,
  /// Plan mode - read-only exploration
  planOnly,
}

/// Agent configuration template (not runtime state)
class Agent {
  final String id;
  final String type; // 'claude-code'
  final String name;
  final String? description;
  final String? avatar;
  final List<String> accessiblePaths; // Allowed directories
  final String? instructions; // System prompt
  final String model; // Model ID (e.g., 'claude-sonnet-4-20250514')
  final String? apiProvider; // Provider ID, null for default
  final String? customApiKey; // Custom API key (overrides provider)
  final String? customBaseUrl; // Custom base URL (overrides provider)
  final List<String> mcpServerIds; // Bound MCP server IDs
  final List<String> allowedTools; // Allowed tool names
  final AgentPermissionMode permissionMode;
  final int maxTurns; // Maximum conversation turns
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deletable;

  const Agent({
    required this.id,
    this.type = 'claude-code',
    required this.name,
    this.description,
    this.avatar,
    this.accessiblePaths = const <String>[],
    this.instructions,
    this.model = 'claude-sonnet-4-20250514',
    this.apiProvider,
    this.customApiKey,
    this.customBaseUrl,
    this.mcpServerIds = const <String>[],
    this.allowedTools = const <String>[],
    this.permissionMode = AgentPermissionMode.requireApproval,
    this.maxTurns = 100,
    required this.createdAt,
    required this.updatedAt,
    this.deletable = true,
  });

  Agent copyWith({
    String? id,
    String? type,
    String? name,
    String? description,
    String? avatar,
    List<String>? accessiblePaths,
    String? instructions,
    String? model,
    String? apiProvider,
    String? customApiKey,
    String? customBaseUrl,
    List<String>? mcpServerIds,
    List<String>? allowedTools,
    AgentPermissionMode? permissionMode,
    int? maxTurns,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deletable,
    bool clearDescription = false,
    bool clearAvatar = false,
    bool clearInstructions = false,
    bool clearApiProvider = false,
    bool clearCustomApiKey = false,
    bool clearCustomBaseUrl = false,
  }) {
    return Agent(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      description: clearDescription ? null : (description ?? this.description),
      avatar: clearAvatar ? null : (avatar ?? this.avatar),
      accessiblePaths: accessiblePaths ?? this.accessiblePaths,
      instructions: clearInstructions ? null : (instructions ?? this.instructions),
      model: model ?? this.model,
      apiProvider: clearApiProvider ? null : (apiProvider ?? this.apiProvider),
      customApiKey: clearCustomApiKey ? null : (customApiKey ?? this.customApiKey),
      customBaseUrl: clearCustomBaseUrl ? null : (customBaseUrl ?? this.customBaseUrl),
      mcpServerIds: mcpServerIds ?? this.mcpServerIds,
      allowedTools: allowedTools ?? this.allowedTools,
      permissionMode: permissionMode ?? this.permissionMode,
      maxTurns: maxTurns ?? this.maxTurns,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletable: deletable ?? this.deletable,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'description': description,
        'avatar': avatar,
        'accessiblePaths': accessiblePaths,
        'instructions': instructions,
        'model': model,
        'apiProvider': apiProvider,
        'customApiKey': customApiKey,
        'customBaseUrl': customBaseUrl,
        'mcpServerIds': mcpServerIds,
        'allowedTools': allowedTools,
        'permissionMode': permissionMode.name,
        'maxTurns': maxTurns,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletable': deletable,
      };

  static Agent fromJson(Map<String, dynamic> json) => Agent(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'claude-code',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        avatar: json['avatar'] as String?,
        accessiblePaths:
            (json['accessiblePaths'] as List?)?.cast<String>() ?? const <String>[],
        instructions: json['instructions'] as String?,
        model: json['model'] as String? ?? 'claude-sonnet-4-20250514',
        apiProvider: json['apiProvider'] as String?,
        customApiKey: json['customApiKey'] as String?,
        customBaseUrl: json['customBaseUrl'] as String?,
        mcpServerIds:
            (json['mcpServerIds'] as List?)?.cast<String>() ?? const <String>[],
        allowedTools:
            (json['allowedTools'] as List?)?.cast<String>() ?? const <String>[],
        permissionMode: _parsePermissionMode(json['permissionMode']),
        maxTurns: (json['maxTurns'] as num?)?.toInt() ?? 100,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
        deletable: json['deletable'] as bool? ?? true,
      );

  static AgentPermissionMode _parsePermissionMode(dynamic value) {
    if (value == null) return AgentPermissionMode.requireApproval;
    if (value is String) {
      return AgentPermissionMode.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AgentPermissionMode.requireApproval,
      );
    }
    return AgentPermissionMode.requireApproval;
  }

  static String encodeList(List<Agent> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<Agent> decodeList(String raw) {
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      return [for (final e in arr) Agent.fromJson(e as Map<String, dynamic>)];
    } catch (_) {
      return const <Agent>[];
    }
  }
}
