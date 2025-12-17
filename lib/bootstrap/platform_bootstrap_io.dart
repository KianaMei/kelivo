import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:window_manager/window_manager.dart';

import '../desktop/desktop_window_controller.dart';
import '../utils/app_dirs.dart';
import '../utils/platform_utils.dart';
import '../utils/sandbox_path_resolver.dart';

Future<void> platformBootstrap() async {
  // Web won't compile this file, but keep the guard anyway.
  if (kIsWeb) return;

  // Initialize app data directories (IO only).
  await AppDirs.init();

  // Desktop window setup (Windows only).
  if (PlatformUtils.isWindows) {
    await PlatformUtils.callPlatformMethod(() async {
      await windowManager.ensureInitialized();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    });
  }

  // Initialize and show desktop window with persisted size/position
  await DesktopWindowController.instance.initializeAndShow(title: 'Kelivo');

  // Cache current Documents directory to fix sandboxed absolute paths on iOS
  await SandboxPathResolver.init();

  // Preload system fonts on desktop
  final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  if (isDesktop) {
    try {
      final sf = SystemFonts();
      await sf.loadAllFonts();
    } catch (_) {}
  }

  // Enable edge-to-edge to allow content under system bars (Android)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

