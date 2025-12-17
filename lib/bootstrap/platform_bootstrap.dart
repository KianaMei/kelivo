import 'platform_bootstrap_io.dart' if (dart.library.html) 'platform_bootstrap_web.dart' as impl;

Future<void> platformBootstrap() => impl.platformBootstrap();

