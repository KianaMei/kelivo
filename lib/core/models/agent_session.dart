import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'agent_session.g.dart';

/// Agent session status
@HiveType(typeId: 11)
enum AgentSessionStatus {
  @HiveField(0)
  idle,
  @HiveField(1)
  running,
  @HiveField(2)
  waitingPermission,
  @HiveField(3)
  completed,
  @HiveField(4)
  error,
  @HiveField(5)
  aborted,
}

/// Runtime agent session with message history
@HiveType(typeId: 10)
class AgentSession extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String agentId;

  @HiveField(2)
  String name;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  DateTime updatedAt;

  /// SDK session ID for resuming conversations
  @HiveField(5)
  String? sdkSessionId;

  /// Current working directory for this session
  @HiveField(6)
  String? workingDirectory;

  /// Message IDs in this session
  @HiveField(7)
  final List<String> messageIds;

  /// Current session status
  @HiveField(8)
  AgentSessionStatus status;

  /// Last error message if status is error
  @HiveField(9)
  String? lastError;

  /// Total tokens used in this session
  @HiveField(10)
  int totalTokens;

  AgentSession({
    String? id,
    required this.agentId,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.sdkSessionId,
    this.workingDirectory,
    List<String>? messageIds,
    this.status = AgentSessionStatus.idle,
    this.lastError,
    this.totalTokens = 0,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messageIds = messageIds ?? [];

  AgentSession copyWith({
    String? id,
    String? agentId,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? sdkSessionId,
    String? workingDirectory,
    List<String>? messageIds,
    AgentSessionStatus? status,
    String? lastError,
    int? totalTokens,
    bool clearSdkSessionId = false,
    bool clearWorkingDirectory = false,
    bool clearLastError = false,
  }) {
    return AgentSession(
      id: id ?? this.id,
      agentId: agentId ?? this.agentId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sdkSessionId: clearSdkSessionId ? null : (sdkSessionId ?? this.sdkSessionId),
      workingDirectory:
          clearWorkingDirectory ? null : (workingDirectory ?? this.workingDirectory),
      messageIds: messageIds ?? this.messageIds,
      status: status ?? this.status,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      totalTokens: totalTokens ?? this.totalTokens,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'agentId': agentId,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'sdkSessionId': sdkSessionId,
      'workingDirectory': workingDirectory,
      'messageIds': messageIds,
      'status': status.name,
      'lastError': lastError,
      'totalTokens': totalTokens,
    };
  }

  factory AgentSession.fromJson(Map<String, dynamic> json) {
    return AgentSession(
      id: json['id'] as String,
      agentId: json['agentId'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      sdkSessionId: json['sdkSessionId'] as String?,
      workingDirectory: json['workingDirectory'] as String?,
      messageIds: (json['messageIds'] as List<dynamic>).cast<String>(),
      status: AgentSessionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AgentSessionStatus.idle,
      ),
      lastError: json['lastError'] as String?,
      totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
    );
  }
}
