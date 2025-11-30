import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/model_provider.dart';

/// 连接测试状态
enum ConnectionTestState { idle, loading, success, error }

/// 连接测试结果
class ConnectionTestResult {
  final ConnectionTestState state;
  final String? errorMessage;

  const ConnectionTestResult({
    required this.state,
    this.errorMessage,
  });

  factory ConnectionTestResult.idle() => const ConnectionTestResult(state: ConnectionTestState.idle);
  factory ConnectionTestResult.loading() => const ConnectionTestResult(state: ConnectionTestState.loading);
  factory ConnectionTestResult.success() => const ConnectionTestResult(state: ConnectionTestState.success);
  factory ConnectionTestResult.error(String message) => ConnectionTestResult(
    state: ConnectionTestState.error,
    errorMessage: message,
  );

  bool get isIdle => state == ConnectionTestState.idle;
  bool get isLoading => state == ConnectionTestState.loading;
  bool get isSuccess => state == ConnectionTestState.success;
  bool get isError => state == ConnectionTestState.error;
}

/// Provider 连接测试服务
/// 
/// 提供统一的连接测试逻辑，供移动端和桌面端共用。
class ProviderTestService {
  ProviderTestService._();

  /// 清理 URL
  /// 
  /// 移除控制字符（换行、回车、制表符等）防止 URL 解析错误
  static String sanitizeUrl(String input) {
    return input.trim().replaceAll(RegExp(r'[\r\n\t\f\v\x00-\x1F\x7F]'), '');
  }

  /// 执行连接测试
  /// 
  /// [context] - BuildContext，用于获取 SettingsProvider
  /// [providerKey] - Provider 的唯一标识
  /// [providerDisplayName] - Provider 的显示名称（用于创建默认配置）
  /// [modelId] - 要测试的模型 ID
  /// 
  /// 返回 [ConnectionTestResult]，包含测试状态和可能的错误信息
  static Future<ConnectionTestResult> testConnection({
    required BuildContext context,
    required String providerKey,
    required String providerDisplayName,
    required String modelId,
  }) async {
    try {
      final rawCfg = context.read<SettingsProvider>().getProviderConfig(
        providerKey,
        defaultName: providerDisplayName,
      );
      
      // 清理 URL
      final cfg = rawCfg.copyWith(
        baseUrl: sanitizeUrl(rawCfg.baseUrl),
        chatPath: rawCfg.chatPath != null ? sanitizeUrl(rawCfg.chatPath!) : null,
      );
      
      await ProviderManager.testConnection(cfg, modelId);
      return ConnectionTestResult.success();
    } catch (e) {
      return ConnectionTestResult.error(e.toString());
    }
  }

  /// 获取应用了用户覆盖的有效 ModelInfo
  /// 
  /// [modelId] - 模型 ID
  /// [cfg] - Provider 配置
  /// 
  /// 返回合并了用户自定义覆盖的 ModelInfo
  static ModelInfo getEffectiveModelInfo(String modelId, ProviderConfig cfg) {
    // Start with inferred model info
    ModelInfo base = ModelRegistry.infer(ModelInfo(id: modelId, displayName: modelId));
    
    // Apply user overrides if they exist
    final ov = cfg.modelOverrides[modelId] as Map?;
    if (ov != null) {
      final name = (ov['name'] as String?)?.trim() ?? base.displayName;
      final typeStr = (ov['type'] as String?) ?? '';
      final type = typeStr == 'embedding' ? ModelType.embedding : ModelType.chat;
      
      final inArr = (ov['input'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final outArr = (ov['output'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final abArr = (ov['abilities'] as List?)?.map((e) => e.toString()).toList() ?? [];
      
      final input = inArr.isEmpty ? base.input : inArr.map((e) => e == 'image' ? Modality.image : Modality.text).toList();
      final output = outArr.isEmpty ? base.output : outArr.map((e) => e == 'image' ? Modality.image : Modality.text).toList();
      final abilities = abArr.isEmpty ? base.abilities : abArr.map((e) => e == 'reasoning' ? ModelAbility.reasoning : ModelAbility.tool).toList();
      
      return ModelInfo(
        id: modelId,
        displayName: name,
        type: type,
        input: input,
        output: output,
        abilities: abilities,
      );
    }
    
    return base;
  }
}
