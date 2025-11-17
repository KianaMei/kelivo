import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show exit;

import 'window_size_manager.dart';
import 'system_tray_manager.dart';
import '../utils/platform_utils.dart';

/// Handles desktop window initialization and persistence (size/position/maximized).
class DesktopWindowController with WindowListener {
  DesktopWindowController._();
  static final DesktopWindowController instance = DesktopWindowController._();

  final WindowSizeManager _sizeMgr = const WindowSizeManager();
  bool _attached = false;

  // Cache the close-to-tray setting to avoid async read on every close
  bool _closeToTray = false;

  /// Update the close-to-tray setting cache
  void updateCloseToTraySetting(bool value) {
    _closeToTray = value;
  }

  Future<void> initializeAndShow({String? title}) async {
    if (kIsWeb || !PlatformUtils.isDesktop) return;

    try {
      await windowManager.ensureInitialized();
    } catch (e) {
      debugPrint('Window manager initialization failed: $e');
      return;
    }

    // Windows custom title bar is handled in main (TitleBarStyle.hidden)
    // Prevent default close behavior to handle it ourselves
    await windowManager.setPreventClose(true);

    // Initialize system tray if needed and cache the setting for instant close response
    final prefs = await SharedPreferences.getInstance();
    final closeToTray = prefs.getBool('desktop_close_to_tray_v1') ?? false;
    _closeToTray = closeToTray; // Cache the value to avoid async read on close
    if (closeToTray) {
      await SystemTrayManager.instance.init();
    }

    final initialSize = await _sizeMgr.getInitialSize();
    const minSize = Size(WindowSizeManager.minWindowWidth, WindowSizeManager.minWindowHeight);
    const maxSize = Size(WindowSizeManager.maxWindowWidth, WindowSizeManager.maxWindowHeight);

    final options = WindowOptions(
      size: initialSize,
      minimumSize: minSize,
      maximumSize: maxSize,
      title: title,
    );

    final savedPos = await _sizeMgr.getPosition();
    final wasMax = await _sizeMgr.getWindowMaximized();

    await windowManager.waitUntilReadyToShow(options, () async {
      if (savedPos != null) {
        try { await windowManager.setPosition(savedPos); } catch (_) {}
      }
      await windowManager.show();
      await windowManager.focus();
      if (wasMax) {
        try { await windowManager.maximize(); } catch (_) {}
      }
    });

    _attachListeners();
  }

  void _attachListeners() {
    if (_attached) return;
    windowManager.addListener(this);
    _attached = true;
  }

  @override
  void onWindowResize() async {
    try {
      final isMax = await windowManager.isMaximized();
      // Avoid saving full-screen/maximized size; keep last restored size.
      if (!isMax) {
        final s = await windowManager.getSize();
        await _sizeMgr.setSize(s);
      }
    } catch (_) {}
  }

  @override
  void onWindowMove() async {
    try {
      final offset = await windowManager.getPosition();
      await _sizeMgr.setPosition(offset);
    } catch (_) {}
  }

  @override
  void onWindowMaximize() async {
    try { await _sizeMgr.setWindowMaximized(true); } catch (_) {}
  }

  @override
  void onWindowUnmaximize() async {
    try { await _sizeMgr.setWindowMaximized(false); } catch (_) {}
  }

  @override
  void onWindowClose() async {
    debugPrint('[WindowController] onWindowClose triggered, closeToTray=$_closeToTray');
    final startTime = DateTime.now();

    // Use cached setting for instant response (no async read)
    if (_closeToTray) {
      try {
        debugPrint('[WindowController] Hiding to tray...');
        // Initialize system tray if not already initialized
        if (!SystemTrayManager.instance.initialized) {
          debugPrint('[WindowController] Tray not initialized, initializing now...');
          await SystemTrayManager.instance.init();
        }
        // Hide the window to tray immediately
        await SystemTrayManager.instance.hideWindow();
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        debugPrint('[WindowController] Successfully hid to tray in ${elapsed}ms');
      } catch (e) {
        debugPrint('[WindowController] Error hiding to tray: $e - exiting process');
        exit(0);
      }
    } else {
      debugPrint('[WindowController] Exiting process (not using tray)');
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[WindowController] Preparing to exit, elapsed=${elapsed}ms');
      exit(0);
    }
  }
}

