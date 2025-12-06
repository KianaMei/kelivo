/// Code runtime template generator for frontend code preview
/// Supports React/JSX, Vue, TypeScript with CDN + local fallback
library;

import '../../core/services/runtime_cache_service.dart';

/// Supported runtime types
enum CodeRuntimeType {
  react,      // React JSX
  reactTsx,   // React TSX (with TypeScript)
  vue,        // Vue 3
  typescript, // Plain TypeScript
  javascript, // Plain JavaScript (no compilation)
  html,       // Plain HTML (no runtime needed)
}

/// Library URLs container (CDN or local)
class RuntimeLibraryUrls {
  final String react;
  final String reactDom;
  final String babel;
  final String vue;
  final String tailwind;
  final String lucide;

  const RuntimeLibraryUrls({
    required this.react,
    required this.reactDom,
    required this.babel,
    required this.vue,
    required this.tailwind,
    required this.lucide,
  });

  /// Default CDN URLs
  static const cdn = RuntimeLibraryUrls(
    react: 'https://unpkg.com/react@18/umd/react.development.js',
    reactDom: 'https://unpkg.com/react-dom@18/umd/react-dom.development.js',
    babel: 'https://unpkg.com/@babel/standalone/babel.min.js',
    vue: 'https://unpkg.com/vue@3/dist/vue.global.js',
    tailwind: 'https://cdn.tailwindcss.com',
    lucide: 'https://unpkg.com/lucide@latest/dist/umd/lucide.min.js',
  );
}

/// Generate runtime HTML template for given code and type
class CodeRuntimeTemplates {
  /// CDN URLs for various libraries
  static const _cdnReact = 'https://unpkg.com/react@18/umd/react.development.js';
  static const _cdnReactDom = 'https://unpkg.com/react-dom@18/umd/react-dom.development.js';
  static const _cdnBabel = 'https://unpkg.com/@babel/standalone/babel.min.js';
  static const _cdnVue = 'https://unpkg.com/vue@3/dist/vue.global.js';
  static const _cdnTailwind = 'https://cdn.tailwindcss.com';
  static const _cdnLucide = 'https://unpkg.com/lucide@latest/dist/umd/lucide.min.js';

  /// Get library URLs (prefers local cache if available)
  static Future<RuntimeLibraryUrls> getLibraryUrls({bool preferLocal = true}) async {
    final cache = RuntimeCacheService.instance;
    
    return RuntimeLibraryUrls(
      react: await cache.getLibraryUrl('react.development.js', preferLocal: preferLocal),
      reactDom: await cache.getLibraryUrl('react-dom.development.js', preferLocal: preferLocal),
      babel: await cache.getLibraryUrl('babel.min.js', preferLocal: preferLocal),
      vue: await cache.getLibraryUrl('vue.global.js', preferLocal: preferLocal),
      tailwind: _cdnTailwind, // Tailwind always from CDN (dynamic)
      lucide: _cdnLucide, // Lucide always from CDN
    );
  }

  /// Detect runtime type from language tag
  static CodeRuntimeType? detectType(String language) {
    final lang = language.toLowerCase().trim();
    switch (lang) {
      case 'jsx':
      case 'react':
        return CodeRuntimeType.react;
      case 'tsx':
      case 'react-tsx':
      case 'reacttsx':
        return CodeRuntimeType.reactTsx;
      case 'vue':
        return CodeRuntimeType.vue;
      case 'typescript':
      case 'ts':
        return CodeRuntimeType.typescript;
      case 'javascript':
      case 'js':
        return CodeRuntimeType.javascript;
      case 'html':
        return CodeRuntimeType.html;
      default:
        return null;
    }
  }

  /// Check if a language is previewable
  static bool isPreviewable(String language) {
    return detectType(language) != null;
  }

  /// Generate complete HTML for preview (sync, uses CDN)
  static String generateHtml({
    required String code,
    required CodeRuntimeType type,
    bool useTailwind = true,
    bool useLucide = false,
  }) {
    return generateHtmlWithUrls(
      code: code,
      type: type,
      urls: RuntimeLibraryUrls.cdn,
      useTailwind: useTailwind,
      useLucide: useLucide,
    );
  }

  /// Generate complete HTML for preview with local cache support (async)
  static Future<String> generateHtmlAsync({
    required String code,
    required CodeRuntimeType type,
    bool useTailwind = true,
    bool useLucide = false,
    bool preferLocalCache = true,
  }) async {
    final urls = await getLibraryUrls(preferLocal: preferLocalCache);
    return generateHtmlWithUrls(
      code: code,
      type: type,
      urls: urls,
      useTailwind: useTailwind,
      useLucide: useLucide,
    );
  }

  /// Generate complete HTML for preview with custom library URLs
  static String generateHtmlWithUrls({
    required String code,
    required CodeRuntimeType type,
    required RuntimeLibraryUrls urls,
    bool useTailwind = true,
    bool useLucide = false,
  }) {
    switch (type) {
      case CodeRuntimeType.react:
        return _generateReactHtmlWithUrls(code, urls: urls, useTailwind: useTailwind, useLucide: useLucide, useTypeScript: false);
      case CodeRuntimeType.reactTsx:
        return _generateReactHtmlWithUrls(code, urls: urls, useTailwind: useTailwind, useLucide: useLucide, useTypeScript: true);
      case CodeRuntimeType.vue:
        return _generateVueHtmlWithUrls(code, urls: urls, useTailwind: useTailwind);
      case CodeRuntimeType.typescript:
        return _generateTypeScriptHtmlWithUrls(code, urls: urls);
      case CodeRuntimeType.javascript:
        return _generateJavaScriptHtml(code);
      case CodeRuntimeType.html:
        return code; // Plain HTML, no wrapper needed
    }
  }

  /// Generate React HTML template
  static String _generateReactHtml(
    String code, {
    required bool useTailwind,
    required bool useLucide,
    required bool useTypeScript,
  }) {
    final tailwindScript = useTailwind 
        ? '<script src="$_cdnTailwind"></script>' 
        : '';
    final lucideScript = useLucide 
        ? '<script src="$_cdnLucide"></script>' 
        : '';
    final babelPresets = useTypeScript ? 'react,typescript' : 'react';
    
    // Detect component name from code
    final componentMount = _generateReactMount(code);

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>React Preview</title>
  <!-- React & ReactDOM -->
  <script src="$_cdnReact"></script>
  <script src="$_cdnReactDom"></script>
  <!-- Babel for JSX compilation -->
  <script src="$_cdnBabel"></script>
  <!-- Optional: Tailwind CSS -->
  $tailwindScript
  <!-- Optional: Lucide Icons -->
  $lucideScript
  <style>
    * { box-sizing: border-box; }
    body { 
      margin: 0; 
      padding: 16px; 
      font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      min-height: 100vh;
    }
    #root { min-height: 100%; }
    /* Error display */
    .runtime-error {
      background: #fef2f2;
      border: 1px solid #fecaca;
      border-radius: 8px;
      padding: 16px;
      color: #dc2626;
      font-family: monospace;
      white-space: pre-wrap;
      margin: 16px 0;
    }
  </style>
</head>
<body>
  <div id="root"></div>
  <script type="text/babel" data-presets="$babelPresets">
    // Error boundary for runtime errors
    class ErrorBoundary extends React.Component {
      constructor(props) {
        super(props);
        this.state = { hasError: false, error: null };
      }
      static getDerivedStateFromError(error) {
        return { hasError: true, error };
      }
      render() {
        if (this.state.hasError) {
          return React.createElement('div', { className: 'runtime-error' }, 
            'Runtime Error:\\n' + this.state.error?.message);
        }
        return this.props.children;
      }
    }

    try {
      // ===== User Code Start =====
$code
      // ===== User Code End =====

      // Auto-mount component
$componentMount
    } catch (e) {
      document.getElementById('root').innerHTML = 
        '<div class="runtime-error">Compilation Error:\\n' + e.message + '</div>';
      console.error(e);
    }
  </script>
  <script>
    // Catch Babel compilation errors
    window.addEventListener('error', function(e) {
      if (e.message && !document.querySelector('.runtime-error')) {
        document.getElementById('root').innerHTML = 
          '<div class="runtime-error">Error: ' + e.message + '</div>';
      }
    });
  </script>
</body>
</html>
''';
  }

  /// Generate React component mount code
  static String _generateReactMount(String code) {
    // Check for common component names
    final hasApp = RegExp(r'\bfunction\s+App\b|\bconst\s+App\s*=').hasMatch(code);
    final hasComponent = RegExp(r'\bfunction\s+Component\b|\bconst\s+Component\s*=').hasMatch(code);
    final hasDefault = RegExp(r'\bexport\s+default\b').hasMatch(code);
    
    if (hasApp) {
      return '''
      const root = ReactDOM.createRoot(document.getElementById('root'));
      root.render(
        React.createElement(ErrorBoundary, null,
          React.createElement(App)
        )
      );''';
    } else if (hasComponent) {
      return '''
      const root = ReactDOM.createRoot(document.getElementById('root'));
      root.render(
        React.createElement(ErrorBoundary, null,
          React.createElement(Component)
        )
      );''';
    } else if (hasDefault) {
      // Try to extract default export name
      return '''
      // Looking for default export...
      const root = ReactDOM.createRoot(document.getElementById('root'));
      if (typeof App !== 'undefined') {
        root.render(React.createElement(ErrorBoundary, null, React.createElement(App)));
      } else if (typeof Component !== 'undefined') {
        root.render(React.createElement(ErrorBoundary, null, React.createElement(Component)));
      } else {
        console.warn('No App or Component found to render');
      }''';
    } else {
      // Check for direct JSX expression (e.g., <div>Hello</div>)
      return '''
      // No explicit component found, try rendering as-is
      const root = ReactDOM.createRoot(document.getElementById('root'));
      if (typeof App !== 'undefined') {
        root.render(React.createElement(ErrorBoundary, null, React.createElement(App)));
      } else if (typeof Component !== 'undefined') {
        root.render(React.createElement(ErrorBoundary, null, React.createElement(Component)));
      }''';
    }
  }

  /// Generate Vue 3 HTML template
  static String _generateVueHtml(String code, {required bool useTailwind}) {
    final tailwindScript = useTailwind 
        ? '<script src="$_cdnTailwind"></script>' 
        : '';
    
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Vue Preview</title>
  <!-- Vue 3 -->
  <script src="$_cdnVue"></script>
  <!-- Optional: Tailwind CSS -->
  $tailwindScript
  <style>
    * { box-sizing: border-box; }
    body { 
      margin: 0; 
      padding: 16px; 
      font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      min-height: 100vh;
    }
    #app { min-height: 100%; }
    .runtime-error {
      background: #fef2f2;
      border: 1px solid #fecaca;
      border-radius: 8px;
      padding: 16px;
      color: #dc2626;
      font-family: monospace;
      white-space: pre-wrap;
      margin: 16px 0;
    }
  </style>
</head>
<body>
  <div id="app"></div>
  <script>
    const { createApp, ref, reactive, computed, onMounted, watch } = Vue;
    
    try {
      // ===== User Code Start =====
$code
      // ===== User Code End =====

      // Auto-mount if App is defined
      if (typeof App !== 'undefined') {
        createApp(App).mount('#app');
      } else {
        console.warn('No App component found to mount');
      }
    } catch (e) {
      document.getElementById('app').innerHTML = 
        '<div class="runtime-error">Error: ' + e.message + '</div>';
      console.error(e);
    }
  </script>
</body>
</html>
''';
  }

  /// Generate TypeScript HTML template (uses Babel for TS compilation)
  static String _generateTypeScriptHtml(String code) {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TypeScript Preview</title>
  <!-- Babel for TypeScript compilation -->
  <script src="$_cdnBabel"></script>
  <style>
    * { box-sizing: border-box; }
    body { 
      margin: 0; 
      padding: 16px; 
      font-family: monospace;
      min-height: 100vh;
      background: #1e1e1e;
      color: #d4d4d4;
    }
    pre { margin: 0; white-space: pre-wrap; }
    .runtime-error {
      background: #3c1618;
      border: 1px solid #6b2c2f;
      border-radius: 8px;
      padding: 16px;
      color: #f87171;
      font-family: monospace;
      white-space: pre-wrap;
      margin: 16px 0;
    }
  </style>
</head>
<body>
  <pre id="output"></pre>
  <script type="text/babel" data-presets="typescript">
    // Redirect console.log to output
    const output = document.getElementById('output');
    const originalLog = console.log;
    console.log = (...args) => {
      originalLog.apply(console, args);
      output.textContent += args.map(a => 
        typeof a === 'object' ? JSON.stringify(a, null, 2) : String(a)
      ).join(' ') + '\\n';
    };

    try {
      // ===== User Code Start =====
$code
      // ===== User Code End =====
    } catch (e) {
      output.innerHTML = '<div class="runtime-error">Error: ' + e.message + '</div>';
      console.error(e);
    }
  </script>
</body>
</html>
''';
  }

  // ====== Methods with custom URLs (for local cache support) ======

  /// Generate React HTML template with custom URLs
  static String _generateReactHtmlWithUrls(
    String code, {
    required RuntimeLibraryUrls urls,
    required bool useTailwind,
    required bool useLucide,
    required bool useTypeScript,
  }) {
    final tailwindScript = useTailwind 
        ? '<script src="${urls.tailwind}"></script>' 
        : '';
    final lucideScript = useLucide 
        ? '<script src="${urls.lucide}"></script>' 
        : '';
    final babelPresets = useTypeScript ? 'react,typescript' : 'react';
    final componentMount = _generateReactMount(code);

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>React Preview</title>
  <script src="${urls.react}"></script>
  <script src="${urls.reactDom}"></script>
  <script src="${urls.babel}"></script>
  $tailwindScript
  $lucideScript
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; padding: 16px; font-family: system-ui, -apple-system, sans-serif; min-height: 100vh; }
    #root { min-height: 100%; }
    .runtime-error { background: #fef2f2; border: 1px solid #fecaca; border-radius: 8px; padding: 16px; color: #dc2626; font-family: monospace; white-space: pre-wrap; margin: 16px 0; }
  </style>
</head>
<body>
  <div id="root"></div>
  <script type="text/babel" data-presets="$babelPresets">
    class ErrorBoundary extends React.Component {
      constructor(props) { super(props); this.state = { hasError: false, error: null }; }
      static getDerivedStateFromError(error) { return { hasError: true, error }; }
      render() {
        if (this.state.hasError) {
          return React.createElement('div', { className: 'runtime-error' }, 'Runtime Error:\\n' + this.state.error?.message);
        }
        return this.props.children;
      }
    }
    try {
$code
$componentMount
    } catch (e) {
      document.getElementById('root').innerHTML = '<div class="runtime-error">Compilation Error:\\n' + e.message + '</div>';
    }
  </script>
  <script>
    window.addEventListener('error', function(e) {
      if (e.message && !document.querySelector('.runtime-error')) {
        document.getElementById('root').innerHTML = '<div class="runtime-error">Error: ' + e.message + '</div>';
      }
    });
  </script>
</body>
</html>
''';
  }

  /// Generate Vue 3 HTML template with custom URLs
  static String _generateVueHtmlWithUrls(String code, {required RuntimeLibraryUrls urls, required bool useTailwind}) {
    final tailwindScript = useTailwind ? '<script src="${urls.tailwind}"></script>' : '';
    
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Vue Preview</title>
  <script src="${urls.vue}"></script>
  $tailwindScript
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; padding: 16px; font-family: system-ui, -apple-system, sans-serif; min-height: 100vh; }
    #app { min-height: 100%; }
    .runtime-error { background: #fef2f2; border: 1px solid #fecaca; border-radius: 8px; padding: 16px; color: #dc2626; font-family: monospace; white-space: pre-wrap; margin: 16px 0; }
  </style>
</head>
<body>
  <div id="app"></div>
  <script>
    const { createApp, ref, reactive, computed, onMounted, watch } = Vue;
    try {
$code
      if (typeof App !== 'undefined') { createApp(App).mount('#app'); }
    } catch (e) {
      document.getElementById('app').innerHTML = '<div class="runtime-error">Error: ' + e.message + '</div>';
    }
  </script>
</body>
</html>
''';
  }

  /// Generate TypeScript HTML template with custom URLs
  static String _generateTypeScriptHtmlWithUrls(String code, {required RuntimeLibraryUrls urls}) {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TypeScript Preview</title>
  <script src="${urls.babel}"></script>
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; padding: 16px; font-family: monospace; min-height: 100vh; background: #1e1e1e; color: #d4d4d4; }
    pre { margin: 0; white-space: pre-wrap; }
    .runtime-error { background: #3c1618; border: 1px solid #6b2c2f; border-radius: 8px; padding: 16px; color: #f87171; font-family: monospace; white-space: pre-wrap; margin: 16px 0; }
  </style>
</head>
<body>
  <pre id="output"></pre>
  <script type="text/babel" data-presets="typescript">
    const output = document.getElementById('output');
    const originalLog = console.log;
    console.log = (...args) => {
      originalLog.apply(console, args);
      output.textContent += args.map(a => typeof a === 'object' ? JSON.stringify(a, null, 2) : String(a)).join(' ') + '\\n';
    };
    try {
$code
    } catch (e) {
      output.innerHTML = '<div class="runtime-error">Error: ' + e.message + '</div>';
    }
  </script>
</body>
</html>
''';
  }

  /// Generate plain JavaScript HTML template (no Babel needed)
  static String _generateJavaScriptHtml(String code) {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>JavaScript Preview</title>
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; padding: 16px; font-family: monospace; min-height: 100vh; background: #1e1e1e; color: #d4d4d4; }
    pre { margin: 0; white-space: pre-wrap; }
    .runtime-error { background: #3c1618; border: 1px solid #6b2c2f; border-radius: 8px; padding: 16px; color: #f87171; font-family: monospace; white-space: pre-wrap; margin: 16px 0; }
  </style>
</head>
<body>
  <pre id="output"></pre>
  <script>
    const output = document.getElementById('output');
    const originalLog = console.log;
    console.log = (...args) => {
      originalLog.apply(console, args);
      output.textContent += args.map(a => typeof a === 'object' ? JSON.stringify(a, null, 2) : String(a)).join(' ') + '\\n';
    };
    try {
$code
    } catch (e) {
      output.innerHTML = '<div class="runtime-error">Error: ' + e.message + '</div>';
    }
  </script>
</body>
</html>
''';
  }
}
