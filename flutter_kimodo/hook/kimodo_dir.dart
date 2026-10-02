import 'dart:io';

/// The prebuilt kimodo folder of [os] (`windows-x64`, `linux-x64`, ...)
/// inside an unpacked archive: `bin/` holds the Windows DLLs, `lib/` the
/// shared objects elsewhere.
String kimodoPlatform(String os, String arch) => '$os-$arch';

/// The runtime library the hook must find in a prebuilt folder.
String kimodoLibrary(String os) => switch (os) {
  'windows' => 'bin/kimodo.dll',
  'macos' => 'lib/libkimodo.dylib',
  _ => 'lib/libkimodo.so',
};

/// Where the hook finds the prebuilt kimodo folder, as an absolute
/// `/`-separated path without a trailing slash.
///
/// 1. [environment] (`LUMINA_KIMODO_DIR`, direct hook runs only): as is;
/// 2. [userDefine] (`kimodo_dir`, resolved against the workspace root
///    pubspec), when it holds the runtime library, or when the package
///    default does not either (so the error names the folder asked for);
/// 3. [packageDefault]: `<package>/third_party/kimodo/prebuilt/<VERSION>/<platform>`,
///    what `tool/build_kimodo.*` and `tool/fetch_prebuilt.dart` write.
String resolveKimodoDir({
  String? environment,
  Uri? userDefine,
  required Uri packageDefault,
  required String library,
  bool Function(String path)? exists,
}) {
  if (environment != null && environment.isNotEmpty) {
    return kimodoDirPath(Uri.directory(environment));
  }
  final found = exists ?? (path) => File(path).existsSync();
  final defaultDir = kimodoDirPath(packageDefault);
  if (userDefine != null) {
    final defined = kimodoDirPath(userDefine);
    if (found('$defined/$library') || !found('$defaultDir/$library')) {
      return defined;
    }
  }
  return defaultDir;
}

/// [uri] as a `/`-separated path without a trailing slash.
String kimodoDirPath(Uri uri) {
  final path = _filePath(uri).replaceAll(r'\', '/');
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

/// A user-define such as `D:/kimodo` resolves to a URI whose scheme is the
/// drive letter; read it back as that Windows path.
String _filePath(Uri uri) => uri.scheme.length == 1
    ? '${uri.scheme.toUpperCase()}:${uri.path}'
    : uri.toFilePath();
