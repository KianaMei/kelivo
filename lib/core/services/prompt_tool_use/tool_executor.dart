import 'dart:convert';
import '../sticker/sticker_tool_service.dart';
import '../search/search_tool_service.dart';
import '../../providers/settings_provider.dart';

/// Result of a tool execution
class ToolExecutionResult {
  /// Name of the tool that was executed
  final String toolName;
  
  /// Result data from the tool
  final Map<String, dynamic> result;
  
  /// Whether the execution resulted in an error
  final bool isError;
  
  const ToolExecutionResult({
    required this.toolName,
    required this.result,
    this.isError = false,
  });
  
  /// Convert result to JSON string
  String toJsonString() => jsonEncode(result);
  
  @override
  String toString() => 'ToolExecutionResult(toolName: $toolName, isError: $isError, result: $result)';
}

/// Tool executor for prompt-based tool use
/// 
/// Routes tool calls to their respective implementations based on tool name.
/// Supports dynamic registration of tools and handles unknown tool errors.
/// 
/// Note: This class provides a centralized registry for tool execution.
/// In practice, the actual tool execution is handled by the onToolCall callback
/// in home_page.dart, which already supports all tools (search, sticker, memory, MCP).
/// This class is provided for future extensibility and testing purposes.
/// 
/// Requirements: 4.1, 4.5
class ToolExecutor {
  /// Registry of tool names to their execution functions
  static final Map<String, Future<ToolExecutionResult> Function(Map<String, dynamic> args, ToolExecutionContext? context)> _registry = {};
  
  /// Whether the executor has been initialized
  static bool _initialized = false;
  
  /// Initialize the executor with default tools
  static void init() {
    if (_initialized) return;
    _initialized = true;
    
    // Register built-in tools
    registerTool(StickerToolService.toolName, _executeStickerTool);
    registerTool(SearchToolService.toolName, _executeSearchTool);
  }
  
  /// Register a tool with its execution function
  static void registerTool(
    String toolName,
    Future<ToolExecutionResult> Function(Map<String, dynamic> args, ToolExecutionContext? context) executor,
  ) {
    _registry[toolName] = executor;
  }
  
  /// Unregister a tool
  static void unregisterTool(String toolName) {
    _registry.remove(toolName);
  }
  
  /// Check if a tool is registered
  static bool isToolRegistered(String toolName) {
    return _registry.containsKey(toolName);
  }
  
  /// Get list of all registered tool names
  static List<String> get registeredTools => _registry.keys.toList();
  
  /// Execute a tool by name
  /// 
  /// Returns a [ToolExecutionResult] with the tool output or error information.
  /// If the tool is not registered, returns an error result.
  static Future<ToolExecutionResult> execute({
    required String toolName,
    required Map<String, dynamic> arguments,
    ToolExecutionContext? context,
  }) async {
    // Check if tool is registered
    if (!_registry.containsKey(toolName)) {
      return ToolExecutionResult(
        toolName: toolName,
        result: {
          'error': 'Unknown tool: $toolName',
          'available_tools': _registry.keys.toList(),
        },
        isError: true,
      );
    }
    
    try {
      // Execute the tool
      final executor = _registry[toolName]!;
      return await executor(arguments, context);
    } catch (e) {
      // Handle execution errors
      return ToolExecutionResult(
        toolName: toolName,
        result: {
          'error': 'Tool execution failed: $e',
        },
        isError: true,
      );
    }
  }
  
  /// Execute sticker tool
  static Future<ToolExecutionResult> _executeStickerTool(
    Map<String, dynamic> args,
    ToolExecutionContext? context,
  ) async {
    final stickerId = args['sticker_id'];
    if (stickerId == null) {
      return ToolExecutionResult(
        toolName: StickerToolService.toolName,
        result: {'error': 'Missing required parameter: sticker_id'},
        isError: true,
      );
    }
    
    final id = stickerId is int ? stickerId : int.tryParse(stickerId.toString()) ?? 0;
    final resultJson = await StickerToolService.getSticker(id);
    final result = jsonDecode(resultJson) as Map<String, dynamic>;
    
    return ToolExecutionResult(
      toolName: StickerToolService.toolName,
      result: result,
      isError: result.containsKey('error'),
    );
  }
  
  /// Execute search tool
  static Future<ToolExecutionResult> _executeSearchTool(
    Map<String, dynamic> args,
    ToolExecutionContext? context,
  ) async {
    final query = args['query'];
    if (query == null || query.toString().trim().isEmpty) {
      return ToolExecutionResult(
        toolName: SearchToolService.toolName,
        result: {'error': 'Missing required parameter: query'},
        isError: true,
      );
    }
    
    // Search tool requires settings provider
    if (context?.settings == null) {
      return ToolExecutionResult(
        toolName: SearchToolService.toolName,
        result: {'error': 'Search tool requires settings context'},
        isError: true,
      );
    }
    
    final resultJson = await SearchToolService.executeSearch(
      query.toString(),
      context!.settings!,
    );
    final result = jsonDecode(resultJson) as Map<String, dynamic>;
    
    return ToolExecutionResult(
      toolName: SearchToolService.toolName,
      result: result,
      isError: result.containsKey('error'),
    );
  }
}

/// Context for tool execution
/// 
/// Provides access to services and state needed by tools during execution.
class ToolExecutionContext {
  /// Settings provider for accessing app configuration
  final SettingsProvider? settings;
  
  /// Conversation ID for context-aware tools
  final String? conversationId;
  
  /// Additional context data
  final Map<String, dynamic>? extra;
  
  const ToolExecutionContext({
    this.settings,
    this.conversationId,
    this.extra,
  });
}
