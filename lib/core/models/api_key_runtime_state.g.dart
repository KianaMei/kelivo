// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_key_runtime_state.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ApiKeyRuntimeStateAdapter extends TypeAdapter<ApiKeyRuntimeState> {
  @override
  final int typeId = 2;

  @override
  ApiKeyRuntimeState read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ApiKeyRuntimeState(
      keyId: fields[0] as String,
      totalRequests: fields[1] as int,
      successfulRequests: fields[2] as int,
      failedRequests: fields[3] as int,
      consecutiveFailures: fields[4] as int,
      lastUsed: fields[5] as int?,
      status: fields[6] as String,
      lastError: fields[7] as String?,
      updatedAt: fields[8] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ApiKeyRuntimeState obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.keyId)
      ..writeByte(1)
      ..write(obj.totalRequests)
      ..writeByte(2)
      ..write(obj.successfulRequests)
      ..writeByte(3)
      ..write(obj.failedRequests)
      ..writeByte(4)
      ..write(obj.consecutiveFailures)
      ..writeByte(5)
      ..write(obj.lastUsed)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.lastError)
      ..writeByte(8)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiKeyRuntimeStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
