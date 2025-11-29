/// Prompt-based Tool Use Adapter
/// Handles tool calling via system prompt injection and XML tag parsing.
/// Used for models that don't support native function calling.

import '../../../providers/settings_provider.dart';
import '../../../models/tool_call_mode.dart';
import '../../prompt_tool_use/prompt_tool_use_service.dart';
import '../../prompt_tool_use/xml_tag_extractor.dart';
import '../models/chat_stream_chunk.dart';
import '../chat_api_service.dart';

/// Adapter for prompt-based tool use (XML tag parsing).
class PromptToolAdapter {
  PromptToolAdapter._();

  /// Send streaming request with prompt-based tool use.
  /// Tools are injected into system prompt and responses parsed for XML tags.
  static Stream<ChatStreamChunk> sendStream({
    required ProviderConfig config,
    required String modelId,
    required List<Map<String, dynamic>> messages,
    List<String>? userImagePaths,
    int? thinkingBudget,
    double? temperature,
    double? topP,
    int? maxTokens,
    required int maxToolLoopIterations,
    required List<Map<String, dynamic>> tools,
    required Future<String> Function(String name, Map<String, dynamic> args) onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
  }) async* {
    // Extract user system prompt and build enhanced messages
    String userSystemPrompt = '';
    final enhancedMessages = <Map<String, dynamic>>[];
    
    for (final msg in messages) {
      final role = (msg['role'] ?? '').toString();
      final content = (msg['content'] ?? '').toString();
      
      if (role == 'system') {
        userSystemPrompt = content;
      } else {
        enhancedMessages.add(Map<String, dynamic>.from(msg));
      }
    }
    
    // Build enhanced system prompt with tool definitions
    final enhancedSystemPrompt = PromptToolUseService.buildSystemPrompt(
      userSystemPrompt: userSystemPrompt,
      tools: tools,
    );
    
    // Insert enhanced system prompt at the beginning
    final messagesWithPrompt = <Map<String, dynamic>>[
      {'role': 'system', 'content': enhancedSystemPrompt},
      ...enhancedMessages,
    ];
    
    // Track conversation for multi-turn tool calls
    var currentMessages = messagesWithPrompt;
    int iteration = 0;
    
    while (iteration < maxToolLoopIterations) {
      iteration++;
      
      // Create XML tag extractor for this iteration
      final extractor = XmlTagExtractor();
      String accumulatedContent = '';
      ParsedToolUse? detectedToolCall;
      
      // Send request WITHOUT tools parameter - they're in the prompt
      final stream = ChatApiService.sendMessageStream(
        config: config,
        modelId: modelId,
        messages: currentMessages,
        userImagePaths: iteration == 1 ? userImagePaths : null,
        thinkingBudget: thinkingBudget,
        temperature: temperature,
        topP: topP,
        maxTokens: maxTokens,
        maxToolLoopIterations: maxToolLoopIterations,
        tools: null, // Don't send tools - they're in the prompt
        onToolCall: null, // Don't use native tool handling
        extraHeaders: extraHeaders,
        extraBody: extraBody,
        toolCallMode: ToolCallMode.native, // Use native mode for underlying request
      );
      
      await for (final chunk in stream) {
        if (chunk.isDone) {
          // Stream completed - check if we have a pending tool call
          if (detectedToolCall != null) {
            // Emit tool call info
            yield ChatStreamChunk(
              content: '',
              isDone: false,
              totalTokens: chunk.totalTokens,
              usage: chunk.usage,
              toolCalls: [
                ToolCallInfo(
                  id: detectedToolCall.id,
                  name: detectedToolCall.name,
                  arguments: detectedToolCall.arguments,
                ),
              ],
            );
            
            // Execute the tool
            final result = await onToolCall(detectedToolCall.name, detectedToolCall.arguments);
            
            // Emit tool result
            yield ChatStreamChunk(
              content: '',
              isDone: false,
              totalTokens: chunk.totalTokens,
              usage: chunk.usage,
              toolResults: [
                ToolResultInfo(
                  id: detectedToolCall.id,
                  name: detectedToolCall.name,
                  arguments: detectedToolCall.arguments,
                  content: result,
                ),
              ],
            );
            
            // Build tool result message
            final toolResultMessage = PromptToolUseService.buildToolResultMessage(
              toolName: detectedToolCall.name,
              result: result,
            );
            
            // Add assistant message with tool call and user message with result
            currentMessages = [
              ...currentMessages,
              {'role': 'assistant', 'content': accumulatedContent + detectedToolCall.toXml()},
              {'role': 'user', 'content': toolResultMessage},
            ];
            
            // Reset for next iteration
            detectedToolCall = null;
            accumulatedContent = '';
            
            // Continue to next iteration
            break;
          } else {
            // No tool call detected, we're done
            yield ChatStreamChunk(
              content: '',
              isDone: true,
              totalTokens: chunk.totalTokens,
              usage: chunk.usage,
            );
            return;
          }
        }
        
        // Process content through XML extractor
        if (chunk.content.isNotEmpty) {
          final results = extractor.processChunk(chunk.content);
          
          for (final result in results) {
            if (result.isTagContent) {
              // This is tool_use tag content - parse it
              final parsed = XmlTagExtractor.parseToolUse(result.content);
              if (parsed != null) {
                detectedToolCall = parsed;
              }
            } else {
              // Regular content - emit it
              if (result.content.isNotEmpty) {
                accumulatedContent += result.content;
                yield ChatStreamChunk(
                  content: result.content,
                  reasoning: chunk.reasoning,
                  isDone: false,
                  totalTokens: chunk.totalTokens,
                  usage: chunk.usage,
                );
              }
            }
          }
        } else if (chunk.reasoning != null && chunk.reasoning!.isNotEmpty) {
          // Pass through reasoning content
          yield ChatStreamChunk(
            content: '',
            reasoning: chunk.reasoning,
            isDone: false,
            totalTokens: chunk.totalTokens,
            usage: chunk.usage,
          );
        }
      }
      
      // If no tool call was detected in this iteration, we're done
      if (detectedToolCall == null && iteration > 1) {
        return;
      }
    }
    
    // Reached max iterations - emit final done chunk
    yield ChatStreamChunk(
      content: '',
      isDone: true,
      totalTokens: 0,
    );
  }
}
