import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool _shouldDisableMaterialTooltip() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows;
}

String? safeTooltipMessage(String? message) {
  if (message == null || message.isEmpty) return null;
  return _shouldDisableMaterialTooltip() ? null : message;
}

Widget wrapWithSafeTooltip({
  required Widget child,
  required String message,
  Duration? waitDuration,
  TooltipTriggerMode? triggerMode,
}) {
  if (message.isEmpty) return child;
  if (_shouldDisableMaterialTooltip()) {
    return Semantics(tooltip: message, child: child);
  }
  return Tooltip(
    message: message,
    waitDuration: waitDuration,
    triggerMode: triggerMode,
    child: child,
  );
}
