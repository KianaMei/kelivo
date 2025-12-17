/// Web version: paths are not rewritten; there is no local sandboxed filesystem.
class SandboxPathResolver {
  SandboxPathResolver._();

  static String? get dataRoot => null;
  static Future<void> init() async {}
  static String fix(String path) => path;
}

