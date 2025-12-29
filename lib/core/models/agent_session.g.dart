// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AgentSessionAdapter extends TypeAdapter<AgentSession> {
  @override
  final int typeId = 10;

  @override
  AgentSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AgentSession(
      id: fields[0] as String?,
      agentId: fields[1] as String,
      name: fields[2] as String,
      createdAt: fields[3] as DateTime?,
      updatedAt: fields[4] as DateTime?,
      sdkSessionId: fields[5] as String?,
      workingDirectory: fields[6] as String?,
      messageIds: (fields[7] as List?)?.cast<String>(),
      status: fields[8] as AgentSessionStatus,
      lastError: fields[9] as String?,
      totalTokens: fields[10] as int,
    );
  }

  @override
  void write(BinaryWriter writer, AgentSession obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.agentId)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.updatedAt)
      ..writeByte(5)
      ..write(obj.sdkSessionId)
      ..writeByte(6)
      ..write(obj.workingDirectory)
      ..writeByte(7)
      ..write(obj.messageIds)
      ..writeByte(8)
      ..write(obj.status)
      ..writeByte(9)
      ..write(obj.lastError)
      ..writeByte(10)
      ..write(obj.totalTokens);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AgentSessionStatusAdapter extends TypeAdapter<AgentSessionStatus> {
  @override
  final int typeId = 11;

  @override
  AgentSessionStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AgentSessionStatus.idle;
      case 1:
        return AgentSessionStatus.running;
      case 2:
        return AgentSessionStatus.waitingPermission;
      case 3:
        return AgentSessionStatus.completed;
      case 4:
        return AgentSessionStatus.error;
      case 5:
        return AgentSessionStatus.aborted;
      default:
        return AgentSessionStatus.idle;
    }
  }

  @override
  void write(BinaryWriter writer, AgentSessionStatus obj) {
    switch (obj) {
      case AgentSessionStatus.idle:
        writer.writeByte(0);
        break;
      case AgentSessionStatus.running:
        writer.writeByte(1);
        break;
      case AgentSessionStatus.waitingPermission:
        writer.writeByte(2);
        break;
      case AgentSessionStatus.completed:
        writer.writeByte(3);
        break;
      case AgentSessionStatus.error:
        writer.writeByte(4);
        break;
      case AgentSessionStatus.aborted:
        writer.writeByte(5);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentSessionStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
