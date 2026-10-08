// ignore_for_file: avoid_print

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import 'package:flutter_riglogic/src/hook/riglogic_lib_dir.dart';

/// Builds `flutter_riglogic` (the C wrapper in `src/riglogic_c.cpp`) as a
/// dynamic library.
///
/// Two ways to get OpenRigLogic into it:
///
/// * **Prebuilt static library** (fast path): when the folder found by
///   [resolveRiglogicLibDir] holds `riglogic.lib` / `libriglogic.a` (built by
///   `tool/build_openriglogic.*`, or named by the `riglogic_lib_dir`
///   user-define), only the wrapper is compiled and the library is linked.
/// * **From source** (default for a package from pub.dev): otherwise the
///   vendored OpenRigLogic sources in `third_party/openriglogic/src` are
///   compiled together with the wrapper. No CMake and no setup; only the
///   platform's C++ compiler (Visual Studio on Windows, clang/gcc on Linux,
///   Xcode on macOS/iOS, the NDK on Android).
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;
    final staticLib = targetOS == OS.windows ? 'riglogic.lib' : 'libriglogic.a';
    final androidAbi = targetOS == OS.android ? _androidAbi(targetArch) : null;
    final riglogicLib = _riglogicLibDir(
      input,
      staticLib,
      androidAbi: androidAbi,
    );
    final prebuilt = _prebuiltLibrary(riglogicLib, staticLib, androidAbi);
    // Linux only: the bundled libc++ of a Lumina checkout, when there is one.
    final libcxx = targetOS == OS.linux ? _bundledLibcxx(input) : null;
    if (prebuilt != null && targetOS == OS.linux && libcxx == null) {
      throw StateError(
        'The prebuilt $prebuilt was built against the bundled libc++, which '
        'is missing. Set the libcxx_dir user-define, or remove the prebuilt '
        'library so the hook compiles OpenRigLogic from source.',
      );
    }

    // The vendored sources go to the compiler through a response file: their
    // absolute paths overflow the Windows command line (cl.exe runs through
    // cmd.exe with the Visual Studio environment script).
    String? sourcesResponseFile;
    if (prebuilt == null) {
      final root = Directory.fromUri(
        input.packageRoot.resolve('third_party/openriglogic/src/'),
      );
      final vendored =
          root
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.cpp'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (vendored.isEmpty) {
        throw StateError('OpenRigLogic sources are missing under ${root.path}.');
      }
      final rsp = File.fromUri(
        input.outputDirectory.resolve('openriglogic_sources.rsp'),
      );
      rsp.writeAsStringSync(
        vendored.map((f) => '"${_slash(f.absolute.path)}"').join('\n'),
      );
      sourcesResponseFile = _slash(rsp.path);
      output.dependencies.addAll(vendored.map((f) => f.absolute.uri));
    }

    // Language.cpp makes native_toolchain_c link the platform's C++ standard
    // library, but it also passes `-x c++`, which would read the static
    // libraries in [flags] as sources. So it is used only when nothing is
    // linked by path: a source build without the bundled libc++.
    final cppLanguage = prebuilt == null && libcxx == null;
    final cbuilder = CBuilder.library(
      name: input.packageName,
      language: cppLanguage ? Language.cpp : Language.c,
      assetName: 'src/riglogic_native.dart',
      sources: const ['src/riglogic_c.cpp'],
      includes: [
        'src',
        'third_party/openriglogic/include',
        if (prebuilt == null) 'third_party/openriglogic/src',
      ],
      defines: {
        // RIGLOGIC_EXPORTS: riglogic_c.h dllexports (not dllimports) the C API.
        'RIGLOGIC_EXPORTS': null,
        if (prebuilt == null)
          for (final order in _rotationOrders)
            'RL_BUILD_WITH_${order}_ROTATION_ORDER': null,
      },
      flags: [
        if (targetOS == OS.windows) ...[
          '/std:c++17',
          '/EHsc',
          '/utf-8',
          '/W0',
          '/MT',
          '/DNOMINMAX',
          // Compile the sources in parallel (one cl.exe invocation).
          if (prebuilt == null) '/MP',
        ] else ...[
          '-std=c++17',
          if (prebuilt == null) '-w',
        ],
        if (libcxx != null) ...[
          '-nostdinc++',
          '-isystem',
          '$libcxx/usr/lib/llvm-21/include/c++/v1',
          '-isystem',
          '$libcxx/usr/lib/llvm-21/include',
        ],
        if (sourcesResponseFile != null) '@$sourcesResponseFile',
        if (prebuilt != null) ..._prebuiltLinkFlags(targetOS, prebuilt),
        if (libcxx != null) ...[
          '$libcxx/usr/lib/${_linuxTriplet(input)}/libc++.a',
          '$libcxx/usr/lib/${_linuxTriplet(input)}/libc++abi.a',
        ],
        if (!cppLanguage && (targetOS == OS.macOS || targetOS == OS.iOS)) ...[
          '-lc++',
          '-lc++abi',
        ],
        if (!cppLanguage && targetOS == OS.android) '-lc++_shared',
        if (targetOS == OS.linux) ...['-ldl', '-lpthread'],
        if (targetOS == OS.android) '-llog',
      ],
      // A source build links libc++ statically on Android, so the app needs
      // no libc++_shared.so; elsewhere the platform default applies (MSVC's
      // CRT, libstdc++ on Linux, libc++ on Apple platforms).
      cppLinkStdLib: cppLanguage && targetOS == OS.android
          ? 'c++_static'
          : null,
    );
    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}

/// The rotation orders OpenRigLogic's CMake build enables by default.
const _rotationOrders = ['XYZ', 'XZY', 'YXZ', 'YZX', 'ZXY', 'ZYX'];

/// The prebuilt OpenRigLogic static library under [libDir], or null when there
/// is none (the hook then compiles the vendored sources).
String? _prebuiltLibrary(String libDir, String staticLib, String? androidAbi) {
  final candidates = androidAbi == null
      ? ['$libDir/$staticLib']
      : [
          '$libDir/android/$androidAbi/$staticLib',
          '$libDir/$androidAbi/$staticLib',
          '$libDir/$staticLib',
        ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

List<String> _prebuiltLinkFlags(OS targetOS, String library) =>
    switch (targetOS) {
      OS.linux ||
      OS.android => ['-Wl,--whole-archive', library, '-Wl,--no-whole-archive'],
      // Absolute, because cl.exe runs in the hook's output directory.
      _ => [library],
    };

String _androidAbi(Architecture architecture) {
  switch (architecture) {
    case Architecture.arm64:
      return 'arm64-v8a';
    case Architecture.x64:
      return 'x86_64';
    case Architecture.arm:
      return 'armeabi-v7a';
    case Architecture.ia32:
      return 'x86';
    default:
      throw UnsupportedError('Unsupported Android architecture: $architecture');
  }
}

/// The built OpenRigLogic static library's folder ([resolveRiglogicLibDir]):
/// `LUMINA_RIGLOGIC_LIB_DIR` (direct hook runs only: the hooks runner never
/// forwards `LUMINA_*`), else the `riglogic_lib_dir` user-define in the
/// workspace root pubspec (relative to it) when it holds the library, else
/// `third_party/openriglogic/lib` (what tool/build_openriglogic.* writes).
String _riglogicLibDir(
  BuildInput input,
  String staticLib, {
  String? androidAbi,
}) => resolveRiglogicLibDir(
  environment: Platform.environment['LUMINA_RIGLOGIC_LIB_DIR'],
  userDefine: input.userDefines.path('riglogic_lib_dir'),
  packageDefault: input.packageRoot.resolve('third_party/openriglogic/lib/'),
  staticLib: staticLib,
  androidAbi: androidAbi,
);

/// The bundled libc++ Linux links against (flutter_filament's
/// `third_party/libcxx`): `LUMINA_LIBCXX_DIR`, else the `libcxx_dir`
/// user-define, else the lumina repo checked out beside this one. Null when
/// that folder has no libc++ headers (a package from pub.dev): the build then
/// uses the compiler's own C++ standard library.
String? _bundledLibcxx(BuildInput input) {
  final env = Platform.environment['LUMINA_LIBCXX_DIR'];
  final uri = env != null && env.isNotEmpty
      ? Uri.directory(env)
      : input.userDefines.path('libcxx_dir') ??
            input.packageRoot.resolve(
              '../../lumina/flutter_filament/third_party/libcxx/',
            );
  final dir = riglogicDirPath(uri);
  return Directory('$dir/usr/lib/llvm-21/include/c++/v1').existsSync()
      ? dir
      : null;
}

String _slash(String path) => path.replaceAll(r'\', '/');

/// The folder of the bundled libc++'s static libraries for the Linux target
/// architecture: `x86_64-linux-gnu` or `aarch64-linux-gnu`.
String _linuxTriplet(BuildInput input) =>
    switch (input.config.code.targetArchitecture) {
      Architecture.x64 => 'x86_64-linux-gnu',
      Architecture.arm64 => 'aarch64-linux-gnu',
      final other => throw UnsupportedError(
        'Unsupported Linux architecture: $other',
      ),
    };
