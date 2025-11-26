import 'package:shared_preferences/shared_preferences.dart';
import '../models/tool_call_mode.dart';

/// Store for managing tool call mode preference
/// 
/// Stores the user's preferred tool call mode (native or prompt) in SharedPreferences.
/// This allows the preference to persist across app sessions.
class ToolCallModeStore {
  static const String _modeKey = 'tool_call_mode_v1';

  static ToolCallMode? _modeCache;

  /// Get the current tool call mode
  /// 
  /// Returns the cached value if available, otherwise reads from SharedPreferences.
  /// Defaults to [ToolCallMode.native] if no preference is stored.
  static Future<ToolCallMode> getMode() async {
    if (_modeCache != null) return _modeCache!;
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_modeKey);
    _modeCache = ToolCallMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => ToolCallMode.native,
    );
    return _modeCache!;
  }

  /// Set the tool call mode
  /// 
  /// Saves the mode to SharedPreferences and updates the cache.
  static Future<void> setMode(ToolCallMode mode) async {
    _modeCache = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  /// Toggle between native and prompt modes
  /// 
  /// Returns the new mode after toggling.
  static Future<ToolCallMode> toggleMode() async {
    final current = await getMode();
    final next = current == ToolCallMode.native 
        ? ToolCallMode.prompt 
        : ToolCallMode.native;
    await setMode(next);
    return next;
  }

  /// Clear the cache (useful for testing)
  static void clearCache() {
    _modeCache = null;
  }
}
