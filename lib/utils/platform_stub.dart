// Platform stub for non-desktop platforms
// This file is imported when the desktop-specific features are not available

class SystemTrayManager {
  static final instance = SystemTrayManager._();
  SystemTrayManager._();

  bool get initialized => false;

  Future<void> init() async {
    // No-op on non-desktop platforms
  }

  Future<void> showWindow() async {
    // No-op on non-desktop platforms
  }

  Future<void> hideWindow() async {
    // No-op on non-desktop platforms
  }

  void dispose() {
    // No-op on non-desktop platforms
  }
}

class DesktopWindowController {
  static final instance = DesktopWindowController._();
  DesktopWindowController._();

  void updateCloseToTraySetting(bool value) {
    // No-op on non-desktop platforms
  }

  Future<void> initializeAndShow({String? title}) async {
    // No-op on non-desktop platforms
  }
}