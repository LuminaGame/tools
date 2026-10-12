import 'dart:io';

/// The Jolt build folder the native-assets hook links against, as an absolute
/// `/`-separated path without a trailing slash. A Jolt build folder holds
/// `include/Jolt/Jolt.h`, `lib/Jolt.lib` (Windows) or `lib/libJolt.a`, and
/// `jolt_defines.txt` (what `tool/build_jolt.*` writes).
///
/// 1. [environment] (`LUMINA_JOLT_DIR`): taken as is;
/// 2. [userDefine] (`jolt_dir`, already resolved against the workspace root
///    pubspec), when it holds [staticLib];
/// 3. [packageDefault] (`<package>/third_party/jolt`).
///
/// A user-define that does not hold the library yields to the package's own
/// build, so an app can name a shared folder while a development checkout
/// keeps the library built in place.
String resolveJoltDir({
  String? environment,
  Uri? userDefine,
  required Uri packageDefault,
  required String staticLib,
  bool Function(String path)? exists,
}) {
  if (environment != null && environment.isNotEmpty) {
    return joltDirPath(Uri.directory(environment));
  }
  final found = exists ?? (path) => File(path).existsSync();
  final defaultDir = joltDirPath(packageDefault);
  if (userDefine != null) {
    final defined = joltDirPath(userDefine);
    if (found('$defined/lib/$staticLib') ||
        !found('$defaultDir/lib/$staticLib')) {
      return defined;
    }
  }
  return defaultDir;
}

/// The preprocessor defines in a `jolt_defines.txt` (one `NAME` or
/// `NAME=VALUE` per line; blank lines and `#` comments are skipped).
Map<String, String?> parseJoltDefines(String text) {
  final out = <String, String?>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 0) {
      out[line] = null;
    } else {
      out[line.substring(0, eq)] = line.substring(eq + 1);
    }
  }
  return out;
}

/// [uri] as a `/`-separated path without a trailing slash.
String joltDirPath(Uri uri) {
  final path = _filePath(uri).replaceAll(r'\', '/');
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

/// A user-define such as `D:/jolt` resolves to a URI whose scheme is the
/// drive letter; read it back as that Windows path.
String _filePath(Uri uri) => uri.scheme.length == 1
    ? '${uri.scheme.toUpperCase()}:${uri.path}'
    : uri.toFilePath();
