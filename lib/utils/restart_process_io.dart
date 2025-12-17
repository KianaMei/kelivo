import 'dart:io';

Future<bool> restartProcess() async {
  try {
    final executable = Platform.resolvedExecutable;
    await Process.start(
      executable,
      const <String>[],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  } catch (_) {
    return false;
  }
}

