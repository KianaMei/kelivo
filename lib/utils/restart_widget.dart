import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:restart_app/restart_app.dart';
import 'restart_process.dart';

/// A widget that can restart the entire app.
///
/// Usage:
/// 1. Wrap your root widget (e.g., MyApp) with RestartWidget:
///    ```dart
///    runApp(RestartWidget(child: const MyApp()));
///    ```
///
/// 2. Call RestartWidget.restartApp(context) to restart the app:
///    ```dart
///    RestartWidget.restartApp(context);
///    ```
///
/// Platform behavior:
/// - Desktop (Windows/macOS/Linux): Restarts the app process
/// - Mobile (Android/iOS): Uses restart_app package to restart
/// - Web: Rebuilds the widget tree (requires manual restart for full effect)
class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});

  final Widget child;

  static Future<void> restartApp(BuildContext context) async {
    final state = context.findAncestorStateOfType<_RestartWidgetState>();
    if (state != null) {
      await state.restartApp();
    }
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  Future<void> restartApp() async {
    if (kIsWeb) {
      // Web: just rebuild the widget tree
      setState(() {
        _key = UniqueKey();
      });
    } else if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
      // Mobile: use restart_app package
      await Restart.restartApp();
    } else {
      // Desktop: restart the process
      await _restartProcess();
    }
  }

  Future<void> _restartProcess() async {
    try {
      final ok = await restartProcess();
      if (!ok) {
        setState(() {
          _key = UniqueKey();
        });
      }
    } catch (e) {
      debugPrint('Failed to restart app process: $e');
      // Fallback to widget rebuild if process restart fails
      setState(() {
        _key = UniqueKey();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: widget.child,
    );
  }
}
