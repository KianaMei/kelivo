import 'package:flutter/services.dart';

Future<void> platformBootstrap() async {
  // Web 只需要系统 UI 模式设置（不会涉及文件系统/桌面窗口）。
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

