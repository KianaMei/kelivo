/**
 * Kelivo Agent Bridge
 *
 * Bridges Kelivo Flutter app and Claude Agent SDK via JSON-RPC over stdin/stdout.
 *
 * Protocol:
 * - Flutter → Bridge: JSON-RPC requests/notifications via stdin
 * - Bridge → Flutter: JSON-RPC responses/notifications via stdout
 */

import { query } from '@anthropic-ai/claude-agent-sdk';
import { createInterface } from 'readline';

// Current abort controller for cancelling agent execution
let currentAbortController = null;
let currentSessionId = null;

/**
 * Send a JSON-RPC notification to Flutter
 */
function sendNotification(method, params) {
  const notification = {
    jsonrpc: '2.0',
    method,
    params,
  };
  console.log(JSON.stringify(notification));
}

/**
 * Send a JSON-RPC response to Flutter
 */
function sendResponse(id, result) {
  const response = {
    jsonrpc: '2.0',
    id,
    result,
  };
  console.log(JSON.stringify(response));
}

/**
 * Send a JSON-RPC error to Flutter
 */
function sendError(id, code, message) {
  const response = {
    jsonrpc: '2.0',
    id,
    error: { code, message },
  };
  console.log(JSON.stringify(response));
}

/**
 * Create permission handler that forwards requests to Flutter
 */
function createPermissionHandler() {
  const pendingPermissions = new Map();

  return {
    /**
     * Handle permission request from SDK - called by canUseTool callback
     */
    async requestPermission(toolName, input, options) {
      const requestId = `perm-${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const expiresAt = Date.now() + 300000; // 5 minute timeout

      // Send permission request to Flutter
      const request = {
        jsonrpc: '2.0',
        id: requestId,
        method: 'requestPermission',
        params: {
          toolName,
          input,
          inputPreview: JSON.stringify(input).slice(0, 500),
          expiresAt,
          toolUseID: options?.toolUseID,
        },
      };
      console.log(JSON.stringify(request));

      // Wait for Flutter response
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          pendingPermissions.delete(requestId);
          reject(new Error('Permission request timed out'));
        }, 300000);

        pendingPermissions.set(requestId, { resolve, reject, timeout });
      });
    },

    /**
     * Handle permission response from Flutter
     */
    handleResponse(id, result) {
      const pending = pendingPermissions.get(id);
      if (pending) {
        clearTimeout(pending.timeout);
        pendingPermissions.delete(id);
        pending.resolve(result);
      }
    },
  };
}

const permissionHandler = createPermissionHandler();

/**
 * Convert SDK messages to JSON-RPC notifications
 */
function handleAgentMessage(message) {
  switch (message.type) {
    case 'assistant':
      // Full assistant message with content
      if (message.message?.content) {
        const textBlocks = message.message.content.filter(b => b.type === 'text');
        const toolUseBlocks = message.message.content.filter(b => b.type === 'tool_use');

        for (const block of textBlocks) {
          sendNotification('stream', {
            type: 'text-done',
            id: message.uuid,
            text: block.text,
          });
        }

        for (const block of toolUseBlocks) {
          sendNotification('stream', {
            type: 'tool-start',
            id: block.id,
            toolName: block.name,
            input: block.input,
            inputPreview: JSON.stringify(block.input).slice(0, 200),
          });
        }
      }
      break;

    case 'stream_event':
      // Streaming delta events
      const event = message.event;
      if (event.type === 'content_block_delta') {
        if (event.delta?.type === 'text_delta') {
          sendNotification('stream', {
            type: 'text-delta',
            id: message.uuid,
            text: event.delta.text,
          });
        } else if (event.delta?.type === 'thinking_delta') {
          sendNotification('stream', {
            type: 'thinking',
            id: message.uuid,
            text: event.delta.thinking,
          });
        }
      }
      break;

    case 'user':
      // User message (tool result)
      if (message.tool_use_result !== undefined) {
        sendNotification('stream', {
          type: 'tool-done',
          id: message.parent_tool_use_id,
          result: typeof message.tool_use_result === 'string'
            ? message.tool_use_result
            : JSON.stringify(message.tool_use_result),
        });
      }
      break;

    case 'system':
      if (message.subtype === 'init') {
        // Session initialized
        currentSessionId = message.session_id;
        sendNotification('stream', {
          type: 'session-id',
          sessionId: message.session_id,
        });
      }
      break;

    case 'result':
      // Final result
      if (message.subtype === 'success') {
        sendNotification('stream', {
          type: 'result',
          result: message.result,
          usage: message.usage,
          costUSD: message.total_cost_usd,
        });
      } else {
        sendNotification('stream', {
          type: 'error',
          message: message.errors?.join(', ') || `Execution failed: ${message.subtype}`,
        });
      }
      break;

    case 'tool_progress':
      sendNotification('stream', {
        type: 'tool-progress',
        id: message.tool_use_id,
        toolName: message.tool_name,
        elapsedSeconds: message.elapsed_time_seconds,
      });
      break;
  }
}

/**
 * Handle invoke request from Flutter
 */
async function handleInvoke(id, params) {
  const {
    prompt,
    cwd,
    model,
    apiKey,
    apiHost,
    systemPrompt,
    permissionMode,
    allowedTools,
    maxTurns,
    resume,
  } = params;

  // Create abort controller
  currentAbortController = new AbortController();

  // Set up environment
  if (apiKey) {
    process.env.ANTHROPIC_API_KEY = apiKey;
  }
  if (apiHost) {
    process.env.ANTHROPIC_BASE_URL = apiHost;
  }

  // Build SDK options
  const options = {
    model: model || 'claude-sonnet-4-20250514',
    cwd: cwd || process.cwd(),
    maxTurns: maxTurns || 100,
    abortController: currentAbortController,
    includePartialMessages: true,
    ...(systemPrompt && { systemPrompt }),
    ...(allowedTools?.length && { allowedTools }),
    ...(permissionMode && { permissionMode }),
    ...(resume && { resume }),
    // Custom permission handler to forward to Flutter
    canUseTool: async (toolName, input, toolOptions) => {
      // Check if aborted
      if (toolOptions.signal.aborted) {
        return { behavior: 'deny', message: 'Aborted' };
      }

      try {
        const result = await permissionHandler.requestPermission(toolName, input, toolOptions);
        return result;
      } catch (error) {
        return { behavior: 'deny', message: error.message, interrupt: true };
      }
    },
  };

  try {
    // Start the query
    const queryResult = query({
      prompt,
      options,
    });

    // Stream events
    for await (const message of queryResult) {
      handleAgentMessage(message);
    }

    sendNotification('stream', { type: 'done' });
    sendResponse(id, { success: true, sessionId: currentSessionId });
  } catch (error) {
    if (error.name === 'AbortError') {
      sendNotification('stream', { type: 'aborted' });
      sendResponse(id, { success: false, aborted: true });
    } else {
      sendNotification('stream', {
        type: 'error',
        message: error.message || 'Unknown error',
      });
      sendError(id, -32000, error.message || 'Invoke failed');
    }
  } finally {
    currentAbortController = null;
  }
}

/**
 * Handle abort notification from Flutter
 */
function handleAbort() {
  if (currentAbortController) {
    currentAbortController.abort();
  }
}

/**
 * Parse and handle incoming JSON-RPC message
 */
function handleMessage(line) {
  if (!line.trim()) return;

  try {
    const message = JSON.parse(line);

    if (message.jsonrpc !== '2.0') return;

    const { id, method, result, params } = message;

    // Handle responses (permission responses from Flutter)
    if (id && result !== undefined) {
      permissionHandler.handleResponse(id, result);
      return;
    }

    // Handle requests and notifications
    switch (method) {
      case 'invoke':
        handleInvoke(id, params || {});
        break;
      case 'abort':
        handleAbort();
        break;
      default:
        if (id) {
          sendError(id, -32601, `Method not found: ${method}`);
        }
    }
  } catch (error) {
    console.error(`[Bridge] Failed to parse message: ${error.message}`);
  }
}

// Set up readline for stdin
const rl = createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false,
});

rl.on('line', handleMessage);

// Handle process signals
process.on('SIGINT', () => {
  handleAbort();
  process.exit(0);
});

process.on('SIGTERM', () => {
  handleAbort();
  process.exit(0);
});

// Log startup
console.error('[Bridge] Kelivo Agent Bridge started');
