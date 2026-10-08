import 'dart:io';

/// Where the hook finds the built OpenRigLogic static library, as an
/// absolute `/`-separated folder path without a trailing slash.
///
/// 1. [environment] (`LUMINA_RIGLOGIC_LIB_DIR`): taken as is;
/// 2. [userDefine] (`riglogic_lib_dir`, already resolved against the
///    workspace root pubspec), when it holds [staticLib];
/// 3. [packageDefault] (`<package>/third_party/openriglogic/lib`), when it
///    holds [staticLib].
///
/// A user-define that does not hold the library yet yields to the package's
/// own build: an app's root pubspec can name the folder a prebuilt library is
/// linked into while a development checkout, whose path dependency on this
/// package carries a library built in place, keeps using that one. When
/// neither holds it the user-define wins, so the error names the folder the
/// app asked for.
String resolveRiglogicLibDir({
  String? environment,
  Uri? userDefine,
  required Uri packageDefault,
  required String staticLib,
  String? androidAbi,
  bool Function(String path)? exists,
}) {
  if (environment != null && environment.isNotEmpty) {
    return riglogicDirPath(Uri.directory(environment));
  }
  final found = exists ?? (path) => File(path).existsSync();
  final defaultDir = riglogicDirPath(packageDefault);
  final libSubpath = androidAbi != null
      ? 'android/$androidAbi/$staticLib'
      : staticLib;
  if (userDefine != null) {
    final defined = riglogicDirPath(userDefine);
    if (found('$defined/$libSubpath') ||
        found('$defined/$staticLib') ||
        !found('$defaultDir/$libSubpath')) {
      return defined;
    }
  }
  return defaultDir;
}

/// [uri] as a `/`-separated path without a trailing slash.
String riglogicDirPath(Uri uri) {
  final path = _filePath(uri).replaceAll(r'\', '/');
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

/// A user-define such as `D:/openriglogic/lib` resolves to a URI whose scheme
/// is the drive letter; read it back as that Windows path.
String _filePath(Uri uri) => uri.scheme.length == 1
    ? '${uri.scheme.toUpperCase()}:${uri.path}'
    : uri.toFilePath();
