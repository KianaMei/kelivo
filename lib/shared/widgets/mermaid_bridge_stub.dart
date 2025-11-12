import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle, PlatformException, MissingPluginException;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as winweb;
import 'mermaid_cache.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';

class MermaidViewHandle {
  final Widget widget;
  final Future<bool> Function() exportPng;
  final Future<Uint8List?> Function()? exportPngBytes;
  MermaidViewHandle({required this.widget, required this.exportPng, this.exportPngBytes});
}

/// Mobile/desktop (non-web) Mermaid renderer using webview_flutter.
/// Returns a handle with the widget and an export-to-PNG action.
MermaidViewHandle? createMermaidView(String code, bool dark, {Map<String, String>? themeVars, GlobalKey? viewKey}) {
  if (Platform.isWindows) {
    final usedKey = viewKey ?? GlobalKey<_MermaidInlineWindowsViewState>();
    final widget = _MermaidInlineWindowsView(key: usedKey, code: code, dark: dark, themeVars: themeVars);
    Future<bool> doExport() async {
      try {
        final state = usedKey.currentState;
        if (state is _MermaidInlineWindowsViewState) {
          final bytes = await state.exportPngBytes();
          if (bytes == null || bytes.isEmpty) return false;
          final suggested = 'mermaid_${DateTime.now().millisecondsSinceEpoch}.png';
          final savePath = await FilePicker.platform.saveFile(
            dialogTitle: 'Save Mermaid PNG',
            fileName: suggested,
            type: FileType.custom,
            allowedExtensions: const ['png'],
          );
          if (savePath == null || savePath.isEmpty) return false;
          final file = File(savePath);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
          return true;
        }
      } catch (_) {}
      return false;
    }

    Future<Uint8List?> doExportBytes() async {
      try {
        final state = usedKey.currentState;
        if (state is _MermaidInlineWindowsViewState) {
          return await state.exportPngBytes();
        }
      } catch (_) {}
      return null;
    }

    return MermaidViewHandle(widget: widget, exportPng: doExport, exportPngBytes: doExportBytes);
  }

  // Use stable key from caller if provided to avoid frequent WebView recreation.
  final usedKey = viewKey ?? GlobalKey<_MermaidInlineWebViewState>();
  final widget = _MermaidInlineWebView(key: usedKey, code: code, dark: dark, themeVars: themeVars);
  Future<bool> doExport() async {
    try {
      final state = usedKey.currentState;
      if (state is _MermaidInlineWebViewState) {
        return await state.exportPng();
      }
    } catch (_) {}
    return false;
  }
  Future<Uint8List?> doExportBytes() async {
    try {
      final state = usedKey.currentState;
      if (state is _MermaidInlineWebViewState) {
        return await state.exportPngBytes();
      }
    } catch (_) {}
    return null;
  }
  return MermaidViewHandle(widget: widget, exportPng: doExport, exportPngBytes: doExportBytes);
}

class _MermaidInlineWindowsView extends StatefulWidget {
  final String code;
  final bool dark;
  final Map<String, String>? themeVars;
  const _MermaidInlineWindowsView({super.key, required this.code, required this.dark, this.themeVars});

  @override
  State<_MermaidInlineWindowsView> createState() => _MermaidInlineWindowsViewState();
}

class _MermaidInlineWindowsViewState extends State<_MermaidInlineWindowsView> {
  final winweb.WebviewController _controller = winweb.WebviewController();
  StreamSubscription? _messageSub;
  double _height = 200;
  String? _lastThemeVarsSig;
  String? _tempFilePath;
  Completer<String?>? _exportCompleter;
  Timer? _heightDebounce;

  @override
  void initState() {
    super.initState();
    final cached = MermaidHeightCache.get(widget.code);
    if (cached != null) _height = cached;
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      try {
        await _controller.setBackgroundColor(const Color(0x00000000));
      } catch (_) {}
      _messageSub = _controller.webMessage.listen((event) {
        String message;
        try {
          final dynamic raw = event;
          if (raw is String) {
            message = raw;
          } else {
            message = raw.content?.toString() ?? raw.toString();
          }
        } catch (_) {
          message = event.toString();
        }
        _handleWebMessage(message);
      });
      await _loadHtml();
    } catch (_) {}
  }

  void _handleWebMessage(String raw) {
    if (raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = map['type'] as String?;
      if (type == 'height') {
        final value = (map['value'] as num?)?.toDouble();
        if (value == null) return;
        _heightDebounce?.cancel();
        _heightDebounce = Timer(const Duration(milliseconds: 60), () {
          if (!mounted) return;
          setState(() {
            _height = max(120, value + 16);
          });
          try {
            MermaidHeightCache.put(widget.code, _height);
          } catch (_) {}
        });
      } else if (type == 'export') {
        final data = map['data'] as String? ?? '';
        if (_exportCompleter != null && !(_exportCompleter!.isCompleted)) {
          _exportCompleter!.complete(data.isEmpty ? null : data);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      width: double.infinity,
      height: _height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: winweb.Webview(_controller),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _MermaidInlineWindowsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final themeSig = _themeVarsSignature(widget.themeVars);
    final changed = oldWidget.code != widget.code || oldWidget.dark != widget.dark || _lastThemeVarsSig != themeSig;
    if (changed) {
      _loadHtml();
    } else {
      _postHeight();
    }
  }

  Future<void> _loadHtml() async {
    try {
      final mermaidJs = await rootBundle.loadString('assets/mermaid.min.js');
      final html = _buildHtml(widget.code, widget.dark, mermaidJs, widget.themeVars);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mermaid_${DateTime.now().millisecondsSinceEpoch}.html');
      await file.writeAsString(html, flush: true);
      _tempFilePath = file.path;
      await _controller.loadUrl(Uri.file(file.path).toString());
      _lastThemeVarsSig = _themeVarsSignature(widget.themeVars);
    } catch (_) {}
  }

  void _postHeight() {
    try {
      _controller.executeScript('postHeight();');
    } catch (_) {}
  }

  String _themeVarsSignature(Map<String, String>? vars) {
    if (vars == null || vars.isEmpty) return '';
    final entries = vars.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  String _buildHtml(String code, bool dark, String mermaidJs, Map<String, String>? themeVars) {
    final bg = dark ? '#111111' : '#ffffff';
    final fg = dark ? '#eaeaea' : '#222222';
    final escaped = code.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    String themeVarsJson = '{}';
    if (themeVars != null && themeVars.isNotEmpty) {
      final entries = themeVars.entries.map((e) => '"${e.key}": "${e.value}"').join(',');
      themeVarsJson = '{' + entries + '}';
    }
    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes, maximum-scale=5.0">
    <title>Mermaid</title>
    <script>${mermaidJs}</script>
    <style>
      html,body{margin:0;padding:0;background:${bg};color:${fg};}
      .wrap{padding:8px;}
      .mermaid{width:100%;text-align:center;}
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="mermaid">${escaped}</div>
    </div>
    <script>
      function postHeight(){
        try{
          const el = document.querySelector('.mermaid');
          if(!el){return;}
          const rect = el.getBoundingClientRect();
          const scale = window.visualViewport ? window.visualViewport.scale : 1;
          const h = Math.ceil((rect.height + 8) * scale);
          window.chrome.webview.postMessage(JSON.stringify({type:'height', value:h}));
        }catch(e){}
      }
      function sendExportPayload(data){
        window.chrome.webview.postMessage(JSON.stringify({type:'export', data:data || ''}));
      }
      window.exportSvgToPng = function(){
        try{
          const svg = document.querySelector('.mermaid svg');
          if(!svg){ sendExportPayload(''); return; }
          let w = 0, h = 0;
          try{
            if(svg.viewBox && svg.viewBox.baseVal){
              w = Math.ceil(svg.viewBox.baseVal.width);
              h = Math.ceil(svg.viewBox.baseVal.height);
            }else if(svg.width && svg.height && svg.width.baseVal && svg.height.baseVal){
              w = Math.ceil(svg.width.baseVal.value);
              h = Math.ceil(svg.height.baseVal.value);
            }else if(svg.getBBox){
              const bb = svg.getBBox();
              w = Math.ceil(bb.width);
              h = Math.ceil(bb.height);
            }
          }catch(e){}
          if(!w || !h){
            const rect = svg.getBoundingClientRect();
            w = Math.ceil(rect.width);
            h = Math.ceil(rect.height);
          }
          const scale = (window.devicePixelRatio || 1) * 2;
          const canvas = document.createElement('canvas');
          canvas.width = Math.max(1, Math.floor(w * scale));
          canvas.height = Math.max(1, Math.floor(h * scale));
          const ctx = canvas.getContext('2d');
          const xml = new XMLSerializer().serializeToString(svg);
          const img = new Image();
          img.onload = function(){
            ctx.fillStyle = '${bg}';
            ctx.fillRect(0,0,canvas.width,canvas.height);
            ctx.drawImage(img,0,0,canvas.width,canvas.height);
            const data = canvas.toDataURL('image/png');
            const payload = data.split(',')[1] || '';
            sendExportPayload(payload);
          };
          img.onerror = function(){ sendExportPayload(''); };
          img.src = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(xml)));
        }catch(e){
          sendExportPayload('');
        }
      };
      mermaid.initialize({ startOnLoad:false, theme:'${dark ? 'dark' : 'default'}', securityLevel:'loose', fontFamily:'inherit', themeVariables:${themeVarsJson} });
      mermaid.run({ querySelector: '.mermaid' }).then(postHeight).catch(postHeight);
      window.addEventListener('resize', postHeight);
      document.addEventListener('DOMContentLoaded', postHeight);
      setTimeout(postHeight, 200);
    </script>
  </body>
</html>
''';
  }

  Future<Uint8List?> exportPngBytes() async {
    try {
      _exportCompleter = Completer<String?>();
      await _controller.executeScript('exportSvgToPng();');
      final b64 = await _exportCompleter!.future.timeout(const Duration(seconds: 8));
      if (b64 == null || b64.isEmpty) return null;
      return base64Decode(b64);
    } catch (_) {
      return null;
    } finally {
      _exportCompleter = null;
    }
  }

  @override
  void dispose() {
    try {
      _heightDebounce?.cancel();
    } catch (_) {}
    _heightDebounce = null;
    try {
      _messageSub?.cancel();
    } catch (_) {}
    _messageSub = null;
    try {
      _controller.dispose();
    } catch (_) {}
    if (_tempFilePath != null) {
      try {
        File(_tempFilePath!).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }
}

class _MermaidInlineWebView extends StatefulWidget {
  final String code;
  final bool dark;
  final Map<String, String>? themeVars;
  const _MermaidInlineWebView({Key? key, required this.code, required this.dark, this.themeVars}) : super(key: key);

  @override
  State<_MermaidInlineWebView> createState() => _MermaidInlineWebViewState();
}

class _MermaidInlineWebViewState extends State<_MermaidInlineWebView> {
  late final WebViewController _controller;
  double _height = 160;
  Completer<String?>? _exportCompleter;
  String? _lastThemeVarsSig;
  Timer? _heightDebounce;

  @override
  void initState() {
    super.initState();
    // Seed initial height from cache to reduce layout jumps
    try {
      final cached = MermaidHeightCache.get(widget.code);
      if (cached != null) _height = cached;
    } catch (_) {}
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('HeightChannel', onMessageReceived: (JavaScriptMessage msg) {
        final v = double.tryParse(msg.message);
        if (v != null && mounted) {
          // Debounce rapid height updates to avoid jank
          _heightDebounce?.cancel();
          _heightDebounce = Timer(const Duration(milliseconds: 60), () {
            if (!mounted) return;
            setState(() {
              _height = max(120, v + 16);
            });
            try { MermaidHeightCache.put(widget.code, _height); } catch (_) {}
          });
        }
      })
      ..addJavaScriptChannel('ExportChannel', onMessageReceived: (JavaScriptMessage msg) {
        if (_exportCompleter != null && !(_exportCompleter!.isCompleted)) {
          final b64 = msg.message;
          _exportCompleter!.complete(b64.isEmpty ? null : b64);
        }
      });
    _loadHtml();
  }

  @override
  void didUpdateWidget(covariant _MermaidInlineWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final themeSig = _themeVarsSignature(widget.themeVars);
    final themeChanged = _lastThemeVarsSig != themeSig;
    final codeChanged = oldWidget.code != widget.code;
    final darkChanged = oldWidget.dark != widget.dark;
    if (codeChanged || darkChanged || themeChanged) {
      _loadHtml();
    } else {
      // No content change; still re-measure to keep height in sync after rebuilds
      _safePostHeight();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      width: double.infinity,
      height: _height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: WebViewWidget(controller: _controller),
      ),
    );
  }

  Future<void> _loadHtml() async {
    // Load mermaid script from assets and inline it to avoid external requests.
    final mermaidJs = await rootBundle.loadString('assets/mermaid.min.js');
    final html = _buildHtml(widget.code, widget.dark, mermaidJs, widget.themeVars);
    await _controller.loadHtmlString(html);
    // Store latest theme signature for change detection
    _lastThemeVarsSig = _themeVarsSignature(widget.themeVars);
  }

  String _buildHtml(String code, bool dark, String mermaidJs, Map<String, String>? themeVars) {
    final bg = dark ? '#111111' : '#ffffff';
    final fg = dark ? '#eaeaea' : '#222222';
    final escaped = code
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    // Build themeVariables JSON
    String themeVarsJson = '{}';
    if (themeVars != null && themeVars.isNotEmpty) {
      final entries = themeVars.entries.map((e) => '"${e.key}": "${e.value}"').join(',');
      themeVarsJson = '{' + entries + '}';
    }
    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes, maximum-scale=5.0">
    <title>Mermaid</title>
    <script>${mermaidJs}</script>
    <style>
      html,body{margin:0;padding:0;background:${bg};color:${fg};}
      .wrap{padding:8px;}
      .mermaid{width:100%; text-align:center;}
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="mermaid">${escaped}</div>
    </div>
    <script>
      function postHeight(){
        try{
          const el = document.querySelector('.mermaid');
          const r = el.getBoundingClientRect();
          const scale = window.visualViewport ? window.visualViewport.scale : 1;
          const h = Math.ceil((r.height + 8) * scale);
          HeightChannel.postMessage(String(h));
        }catch(e){/*ignore*/}
      }
      window.exportSvgToPng = function(){
        try{
          const svg = document.querySelector('.mermaid svg');
          if(!svg){ ExportChannel.postMessage(''); return; }
          let w = 0, h = 0;
          try {
            if (svg.viewBox && svg.viewBox.baseVal && svg.viewBox.baseVal.width && svg.viewBox.baseVal.height) {
              w = Math.ceil(svg.viewBox.baseVal.width);
              h = Math.ceil(svg.viewBox.baseVal.height);
            } else if (svg.width && svg.height && svg.width.baseVal && svg.height.baseVal) {
              w = Math.ceil(svg.width.baseVal.value);
              h = Math.ceil(svg.height.baseVal.value);
            } else if (svg.getBBox) {
              const bb = svg.getBBox();
              w = Math.ceil(bb.width);
              h = Math.ceil(bb.height);
            }
          } catch(_) {}
          if (!w || !h) {
            const rect = svg.getBoundingClientRect();
            w = Math.ceil(rect.width);
            h = Math.ceil(rect.height);
          }
          const scale = (window.devicePixelRatio || 1) * 2;
          const canvas = document.createElement('canvas');
          canvas.width = Math.max(1, Math.floor(w * scale));
          canvas.height = Math.max(1, Math.floor(h * scale));
          const ctx = canvas.getContext('2d');
          const xml = new XMLSerializer().serializeToString(svg);
          const img = new Image();
          img.onload = function(){
            ctx.fillStyle = '${bg}';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
            const data = canvas.toDataURL('image/png');
            const b64 = data.split(',')[1] || '';
            ExportChannel.postMessage(b64);
          };
          img.onerror = function(){ ExportChannel.postMessage(''); };
          img.src = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(xml)));
        }catch(e){
          ExportChannel.postMessage('');
        }
      };
      mermaid.initialize({ startOnLoad:false, theme: '${dark ? 'dark' : 'default'}', securityLevel:'loose', fontFamily: 'inherit', themeVariables: ${themeVarsJson} });
      mermaid.run({ querySelector: '.mermaid' }).then(postHeight).catch(postHeight);
      window.addEventListener('resize', postHeight);
      document.addEventListener('DOMContentLoaded', postHeight);
      setTimeout(postHeight, 200);
    </script>
  </body>
</html>
  ''';
  }

  void _safePostHeight() {
    try {
      _controller.runJavaScript('postHeight();');
    } catch (_) {}
  }

  String _themeVarsSignature(Map<String, String>? vars) {
    if (vars == null || vars.isEmpty) return '';
    final entries = vars.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  Future<bool> exportPng() async {
    try {
      _exportCompleter = Completer<String?>();
      await _controller.runJavaScript('exportSvgToPng();');
      final b64 = await _exportCompleter!.future.timeout(const Duration(seconds: 8));
      if (b64 == null || b64.isEmpty) return false;
      final bytes = base64Decode(b64);
      final dir = await getTemporaryDirectory();
      final filename = 'mermaid_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      // iPad requires a non-zero popover source rect. Use the Overlay's
      // coordinate space to avoid issues with platform views (WebView).
      Rect rect;
      final overlay = Overlay.of(context);
      final ro = overlay?.context.findRenderObject();
      if (ro is RenderBox && ro.hasSize) {
        final size = ro.size;
        final centerGlobal = ro.localToGlobal(Offset(size.width / 2, size.height / 2));
        rect = Rect.fromCenter(center: centerGlobal, width: 1, height: 1);
      } else {
        final size = MediaQuery.of(context).size;
        rect = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
      }
      try {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/png', name: filename)],
          text: 'Mermaid diagram',
          sharePositionOrigin: rect,
        );
        return true;
      } on MissingPluginException catch (_) {
        final res = await OpenFilex.open(file.path);
        return res.type == ResultType.done;
      } on PlatformException catch (_) {
        final res = await OpenFilex.open(file.path);
        return res.type == ResultType.done;
      }
    } catch (_) {
      return false;
    } finally {
      _exportCompleter = null;
    }
  }

  @override
  void dispose() {
    try { _heightDebounce?.cancel(); } catch (_) {}
    _heightDebounce = null;
    super.dispose();
  }

  Future<Uint8List?> exportPngBytes() async {
    try {
      _exportCompleter = Completer<String?>();
      await _controller.runJavaScript('exportSvgToPng();');
      final b64 = await _exportCompleter!.future.timeout(const Duration(seconds: 8));
      if (b64 == null || b64.isEmpty) return null;
      final bytes = base64Decode(b64);
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _exportCompleter = null;
    }
  }
}
