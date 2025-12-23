import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:html2md/html2md.dart' as html2md;
import 'package:http/http.dart' as http;
import 'package:mcp_client/mcp_client.dart' as mcp;

/// @kelivo/fetch tool request payload.
class KelivoFetchRequestPayload {
  final Uri url;
  final Map<String, String> headers;

  KelivoFetchRequestPayload({required this.url, this.headers = const {}});

  static KelivoFetchRequestPayload parse(Map<String, dynamic> json) {
    final urlRaw = json['url'];
    if (urlRaw == null) throw Exception('Missing required param: url');
    final url = Uri.tryParse(urlRaw.toString());
    if (url == null) throw Exception('Invalid URL: $urlRaw');
    Map<String, String> headers = {};
    if (json['headers'] is Map) {
      headers = (json['headers'] as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return KelivoFetchRequestPayload(url: url, headers: headers);
  }
}

/// Implements the four fetch tools.
class KelivoFetcher {
  static const _userAgent = 'Mozilla/5.0 (compatible; Kelivo/1.0)';

  static Future<http.Response> _fetch(KelivoFetchRequestPayload payload) async {
    try {
      final merged = <String, String>{
        'User-Agent': _userAgent,
        ...payload.headers,
      };
      final resp = await http.get(payload.url, headers: merged);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      return resp;
    } catch (e) {
      throw Exception('Failed to fetch ${payload.url}: ${e is Exception ? e.toString() : 'Unknown error'}');
    }
  }

  static Future<Map<String, dynamic>> html(KelivoFetchRequestPayload payload) async {
    try {
      final resp = await _fetch(payload);
      final text = resp.body;
      return _ok(text);
    } catch (e) {
      return _err(e.toString());
    }
  }

  static Future<Map<String, dynamic>> json(KelivoFetchRequestPayload payload) async {
    try {
      final resp = await _fetch(payload);
      final raw = resp.body;
      final dynamic data = jsonDecode(raw);
      return _ok(const JsonEncoder.withIndent('  ').convert(data));
    } catch (e) {
      return _err(e.toString());
    }
  }

  static Future<Map<String, dynamic>> txt(KelivoFetchRequestPayload payload) async {
    try {
      final resp = await _fetch(payload);
      final html = resp.body;
      final dom.Document document = html_parser.parse(html);
      document.querySelectorAll('script,style').forEach((el) => el.remove());
      final text = document.body?.text ?? '';
      final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      return _ok(normalized);
    } catch (e) {
      return _err(e.toString());
    }
  }

  static Future<Map<String, dynamic>> markdown(KelivoFetchRequestPayload payload) async {
    try {
      final resp = await _fetch(payload);
      final html = resp.body;
      final md = html2md.convert(html);
      return _ok(md);
    } catch (e) {
      return _err(e.toString());
    }
  }

  static Map<String, dynamic> _ok(String text) => {
        'content': [
          {'type': 'text', 'text': text}
        ],
        'isStreaming': false,
        'isError': false,
      };

  static Map<String, dynamic> _err(String message) => {
        'content': [
          {'type': 'text', 'text': message}
        ],
        'isStreaming': false,
        'isError': true,
      };
}

/// Minimal JSON-RPC server for MCP that serves @kelivo/fetch tools.
class KelivoFetchMcpServerEngine {
  bool _closed = false;

  Future<dynamic> handleMessage(dynamic message) async {
    if (_closed) return null;

    // Support batch arrays defensively (return array of responses)
    if (message is List) {
      final out = <dynamic>[];
      for (final m in message) {
        out.add(await _handleSingle(m));
      }
      return out;
    }
    return await _handleSingle(message);
  }

  Future<Map<String, dynamic>> _handleSingle(dynamic raw) async {
    try {
      if (raw is! Map) {
        return _error(null, code: -32600, message: 'Invalid Request');
      }
      final req = raw.cast<String, dynamic>();
      final id = req['id'];
      final method = (req['method'] ?? '').toString();
      final params = (req['params'] is Map)
          ? (req['params'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      switch (method) {
        case mcp.McpProtocol.methodInitialize:
          return _ok(id, result: {
            'serverInfo': {
              'name': '@kelivo/fetch',
              'version': '0.1.0',
            },
            'protocolVersion': mcp.McpProtocol.defaultVersion,
            // Only tools capability is advertised for this minimal server
            'capabilities': {
              'tools': {'listChanged': false},
            },
          });

        case mcp.McpProtocol.methodListTools:
          return _ok(id, result: {
            'tools': _toolDefinitions(),
          });

        case mcp.McpProtocol.methodCallTool:
          final name = (params['name'] ?? '').toString();
          final arguments = (params['arguments'] is Map)
              ? (params['arguments'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};

          KelivoFetchRequestPayload payload;
          try {
            payload = KelivoFetchRequestPayload.parse(arguments);
          } catch (e) {
            return _ok(id, result: KelivoFetcher._err(e.toString()));
          }

          if (name == 'fetch_html') {
            return _ok(id, result: await KelivoFetcher.html(payload));
          }
          if (name == 'fetch_markdown') {
            return _ok(id, result: await KelivoFetcher.markdown(payload));
          }
          if (name == 'fetch_txt') {
            return _ok(id, result: await KelivoFetcher.txt(payload));
          }
          if (name == 'fetch_json') {
            return _ok(id, result: await KelivoFetcher.json(payload));
          }
          return _error(id, code: -32101, message: 'Tool not found: $name');

        default:
          // Ignore common notifications; respond error for unknown requests
          if (id == null) {
            return _noop();
          }
          return _error(id, code: -32601, message: 'Method not found: $method');
      }
    } catch (e) {
      return _error(null, code: -32603, message: 'Internal error: $e');
    }
  }

  void close() {
    _closed = true;
  }

  Map<String, dynamic> _ok(dynamic id, {required Map<String, dynamic> result}) {
    return {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'result': result,
    };
  }

  Map<String, dynamic> _error(dynamic id, {required int code, required String message}) {
    return {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'error': {'code': code, 'message': message},
    };
  }

  Map<String, dynamic> _noop() => {'jsonrpc': '2.0'};

  List<Map<String, dynamic>> _toolDefinitions() {
    Map<String, dynamic> schema() => {
          'type': 'object',
          'properties': {
            'url': {'type': 'string', 'description': 'URL of the website to fetch'},
            'headers': {'type': 'object', 'description': 'Optional headers to include in the request'},
          },
          'required': ['url']
        };

    return [
      {
        'name': 'fetch_html',
        'description': 'Fetch a website and return the content as HTML',
        'inputSchema': schema(),
      },
      {
        'name': 'fetch_markdown',
        'description': 'Fetch a website and return the content as Markdown',
        'inputSchema': schema(),
      },
      {
        'name': 'fetch_txt',
        'description': 'Fetch a website, return the content as plain text (no HTML)',
        'inputSchema': schema(),
      },
      {
        'name': 'fetch_json',
        'description': 'Fetch a JSON file from a URL',
        'inputSchema': schema(),
      },
    ];
  }
}

/// In-memory ClientTransport that directly invokes the local server engine.
class KelivoInMemoryClientTransport implements mcp.ClientTransport {
  final KelivoFetchMcpServerEngine _server;
  final _messageController = StreamController<dynamic>.broadcast();
  final _closeCompleter = Completer<void>();
  bool _closed = false;

  KelivoInMemoryClientTransport(this._server);

  @override
  Stream<dynamic> get onMessage => _messageController.stream;

  @override
  Future<void> get onClose => _closeCompleter.future;

  @override
  void send(dynamic message) {
    if (_closed) return;
    // Process asynchronously to mimic real transport
    Future.microtask(() async {
      final resp = await _server.handleMessage(message);
      if (_closed) return;
      if (resp != null) {
        _messageController.add(resp);
      }
    });
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _server.close();
    } catch (_) {}
    if (!_messageController.isClosed) _messageController.close();
    if (!_closeCompleter.isCompleted) _closeCompleter.complete();
  }
}
