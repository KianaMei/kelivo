import 'package:http/http.dart' as http;
import '../../../providers/settings_provider.dart';
import '../models/chat_stream_event.dart';

/// Base interface for provider-specific chat adapters.
abstract class ChatProviderAdapter {
  /// Build HTTP request for the provider.
  Future<http.Request> buildRequest({
    required String requestId,
    required ProviderConfig config,
    required String modelId,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? toolChoice,
    int? maxTokens,
    double? temperature,
    double? topP,
    int? reasoningBudget,
    bool stream = true,
    Map<String, String>? extraHeaders,
  });

  /// Parse raw SSE/HTTP chunk into provider-specific events.
  List<dynamic> parseChunk(String rawChunk);

  /// Parse error response.
  ChatStreamEvent parseError(http.Response response);
  
  /// Provider identifier (e.g., 'openai', 'anthropic', 'google').
  String get providerId;
}
