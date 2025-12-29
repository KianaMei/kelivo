// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AgentMessageAdapter extends TypeAdapter<AgentMessage> {
  @override
  final int typeId = 12;

  @override
  AgentMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AgentMessage(
      id: fields[0] as String?,
      sessionId: fields[1] as String,
      type: fields[2] as AgentMessageType,
      content: fields[3] as String,
      timestamp: fields[4] as DateTime?,
      toolName: fields[5] as String?,
      toolInputJson: fields[6] as String?,
      toolInputPreview: fields[7] as String?,
      toolResult: fields[8] as String?,
      toolStatus: fields[9] as ToolCallStatus?,
      relatedToolCallId: fields[10] as String?,
      isStreaming: fields[11] as bool,
      modelId: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AgentMessage obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.sessionId)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.content)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.toolName)
      ..writeByte(6)
      ..write(obj.toolInputJson)
      ..writeByte(7)
      ..write(obj.toolInputPreview)
      ..writeByte(8)
      ..write(obj.toolResult)
      ..writeByte(9)
      ..write(obj.toolStatus)
      ..writeByte(10)
      ..write(obj.relatedToolCallId)
      ..writeByte(11)
      ..write(obj.isStreaming)
      ..writeByte(12)
      ..write(obj.modelId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AgentMessageTypeAdapter extends TypeAdapter<AgentMessageType> {
  @override
  final int typeId = 13;

  @override
  AgentMessageType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AgentMessageType.user;
      case 1:
        return AgentMessageType.assistant;
      case 2:
        return AgentMessageType.toolCall;
      case 3:
        return AgentMessageType.toolResult;
      case 4:
        return AgentMessageType.system;
      case 5:
        return AgentMessageType.error;
      default:
        return AgentMessageType.user;
    }
  }

  @override
  void write(BinaryWriter writer, AgentMessageType obj) {
    switch (obj) {
      case AgentMessageType.user:
        writer.writeByte(0);
        break;
      case AgentMessageType.assistant:
        writer.writeByte(1);
        break;
      case AgentMessageType.toolCall:
        writer.writeByte(2);
        break;
      case AgentMessageType.toolResult:
        writer.writeByte(3);
        break;
      case AgentMessageType.system:
        writer.writeByte(4);
        break;
      case AgentMessageType.error:
        writer.writeByte(5);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentMessageTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ToolCallStatusAdapter extends TypeAdapter<ToolCallStatus> {
  @override
  final int typeId = 14;

  @override
  ToolCallStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ToolCallStatus.pending;
      case 1:
        return ToolCallStatus.running;
      case 2:
        return ToolCallStatus.completed;
      case 3:
        return ToolCallStatus.failed;
      case 4:
        return ToolCallStatus.denied;
      default:
        return ToolCallStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, ToolCallStatus obj) {
    switch (obj) {
      case ToolCallStatus.pending:
        writer.writeByte(0);
        break;
      case ToolCallStatus.running:
        writer.writeByte(1);
        break;
      case ToolCallStatus.completed:
        writer.writeByte(2);
        break;
      case ToolCallStatus.failed:
        writer.writeByte(3);
        break;
      case ToolCallStatus.denied:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCallStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
