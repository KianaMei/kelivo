import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform, File, Directory, exit;
import 'package:path/path.dart' as path;
import '../utils/platform_utils.dart';

/// Manages system tray functionality for desktop platforms
class SystemTrayManager with TrayListener {
  SystemTrayManager._();
  static final SystemTrayManager instance = SystemTrayManager._();

  bool _initialized = false;
  bool get initialized => _initialized;

  /// Initialize system tray with icon and context menu
  Future<void> init() async {
    if (!PlatformUtils.isDesktop) return;
    if (_initialized) return;

    try {
      debugPrint('[SystemTray] Starting initialization...');

      // Construct absolute path to ICO file in Flutter assets
      // tray_manager requires absolute path, relative paths don't work reliably
      String iconPath;

      if (PlatformUtils.isWindows) {
        // Get executable path and construct path to Flutter assets
        final exePath = Platform.resolvedExecutable;
        final exeDir = path.dirname(exePath);
        // Flutter assets are in data/flutter_assets/ relative to exe
        iconPath = path.join(exeDir, 'data', 'flutter_assets', 'assets', 'icons', 'app_icon.ico');

        debugPrint('[SystemTray] Exe path: $exePath');
        debugPrint('[SystemTray] Exe dir: $exeDir');
        debugPrint('[SystemTray] Constructed icon path: $iconPath');
        debugPrint('[SystemTray] Icon file exists: ${File(iconPath).existsSync()}');

        // If ICO doesn't exist, try PNG fallback
        if (!File(iconPath).existsSync()) {
          iconPath = path.join(exeDir, 'data', 'flutter_assets', 'assets', 'icons', 'kelivo.png');
          debugPrint('[SystemTray] ICO not found, trying PNG fallback: $iconPath');
          debugPrint('[SystemTray] PNG file exists: ${File(iconPath).existsSync()}');
        }
      } else {
        // macOS/Linux: use relative asset path
        iconPath = 'assets/icons/kelivo.png';
      }

      debugPrint('[SystemTray] Final icon path: $iconPath');
      await trayManager.setIcon(iconPath);

      // Set tooltip
      await trayManager.setToolTip('Kelivo');

      // Set up context menu
      await _updateContextMenu(isWindowVisible: true);

      // Add listener
      trayManager.addListener(this);

      _initialized = true;
      debugPrint('System tray initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize system tray: $e');
    }
  }

  /// Update tray context menu
  Future<void> _updateContextMenu({required bool isWindowVisible}) async {
    // Get current locale setting
    String showLabel = 'Show Window';
    String hideLabel = 'Hide Window';
    String quitLabel = 'Quit';

    try {
      final prefs = await SharedPreferences.getInstance();
      final locale = prefs.getString('app_locale_v1') ?? 'system';
      final isZh = locale == 'zh' || (locale == 'system' && PlatformUtils.isWindows);

      if (isZh) {
        showLabel = '显示窗口';
        hideLabel = '隐藏窗口';
        quitLabel = '退出';
      }
    } catch (_) {
      // Use default English labels if there's an error
    }

    final Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_hide',
          label: isWindowVisible ? hideLabel : showLabel,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: quitLabel,
        ),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  /// Handle window visibility change
  Future<void> onWindowVisibilityChanged(bool isVisible) async {
    await _updateContextMenu(isWindowVisible: isVisible);
  }

  /// Show the application window
  Future<void> showWindow() async {
    debugPrint('[SystemTray] Showing window...');
    await windowManager.show();
    await windowManager.focus();
    await onWindowVisibilityChanged(true);
    debugPrint('[SystemTray] Window shown');
  }

  /// Hide the application window
  Future<void> hideWindow() async {
    debugPrint('[SystemTray] Hiding window...');
    final startTime = DateTime.now();
    await windowManager.hide();
    final hideTime = DateTime.now().difference(startTime).inMilliseconds;
    debugPrint('[SystemTray] Window hide took ${hideTime}ms');

    await onWindowVisibilityChanged(false);
    final totalTime = DateTime.now().difference(startTime).inMilliseconds;
    debugPrint('[SystemTray] Total hide operation: ${totalTime}ms');
  }

  /// Quit the application
  Future<void> quitApp() async {
    debugPrint('[SystemTray] ========================================');
    debugPrint('[SystemTray] QUIT REQUESTED FROM TRAY MENU');
    debugPrint('[SystemTray] ========================================');

    try {
      debugPrint('[SystemTray] Exiting process from tray menu...');
    } catch (e) {
      debugPrint('[SystemTray] Unexpected error before exit: $e');
    }
    exit(0);
  }

  // TrayListener methods
  @override
  void onTrayIconMouseDown() async {
    debugPrint('[SystemTray] Tray icon clicked');
    // Show window on tray icon click
    final isVisible = await windowManager.isVisible();
    if (isVisible) {
      await hideWindow();
    } else {
      await showWindow();
    }
  }

  @override
  void onTrayIconRightMouseDown() async {
    debugPrint('[SystemTray] Tray icon right-clicked');
    // Show context menu on right click
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    debugPrint('[SystemTray] Tray menu item clicked: ${menuItem.key}');
    switch (menuItem.key) {
      case 'show_hide':
        final isVisible = await windowManager.isVisible();
        if (isVisible) {
          await hideWindow();
        } else {
          await showWindow();
        }
        break;
      case 'quit':
        await quitApp();
        break;
    }
  }

  /// Dispose resources
  void dispose() {
    if (_initialized) {
      trayManager.removeListener(this);
      trayManager.destroy();
      _initialized = false;
    }
  }
}