// ignore_for_file: avoid_print

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import 'riglogic_lib_dir.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final packageName = input.packageName;
    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;
    final libcxx = _libcxxDir(input);
    final staticLib = targetOS == OS.windows ? 'riglogic.lib' : 'libriglogic.a';
    final androidAbi = targetOS == OS.android ? _androidAbi(targetArch) : null;
    final riglogicLib = _riglogicLibDir(
      input,
      staticLib,
      androidAbi: androidAbi,
    );

    final String staticLibPath;
    if (targetOS == OS.android) {
      if (File('$riglogicLib/android/$androidAbi/$staticLib').existsSync()) {
        staticLibPath = '$riglogicLib/android/$androidAbi/$staticLib';
      } else if (File('$riglogicLib/$androidAbi/$staticLib').existsSync()) {
        staticLibPath = '$riglogicLib/$androidAbi/$staticLib';
      } else if (File('$riglogicLib/$staticLib').existsSync()) {
        staticLibPath = '$riglogicLib/$staticLib';
      } else {
        staticLibPath = '$riglogicLib/android/$androidAbi/$staticLib';
      }
    } else {
      staticLibPath = '$riglogicLib/$staticLib';
    }

    if (!File(staticLibPath).existsSync()) {
      final scriptName = targetOS == OS.windows
          ? 'build_openriglogic.bat'
          : (targetOS == OS.android
                ? 'build_openriglogic_android.bat'
                : 'build_openriglogic.sh');
      throw StateError(
        'OpenRigLogic is not built: $staticLibPath is missing. '
        'Run tool/$scriptName in flutter_riglogic, '
        'or point LUMINA_RIGLOGIC_LIB_DIR / the riglogic_lib_dir user-define at a built one.',
      );
    }
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: 'src/riglogic_bindings_generated.dart',
      sources: ['src/riglogic_c.cpp'],
      includes: ['src', 'third_party/openriglogic/include'],
      flags: [
        if (targetOS == OS.windows)
        // RIGLOGIC_EXPORTS: riglogic_c.h dllexports (not dllimports) the C API.
        ...[
          '/std:c++17',
          '/EHsc',
          '/utf-8',
          '/W0',
          '/MT',
          '/DNOMINMAX',
          '/DRIGLOGIC_EXPORTS',
        ] else
          '-std=c++17',
        if (targetOS == OS.linux) ...[
          '-nostdinc++',
          '-isystem',
          '$libcxx/usr/lib/llvm-21/include/c++/v1',
          '-isystem',
          '$libcxx/usr/lib/llvm-21/include',
          '-Wl,--whole-archive',
          '$riglogicLib/libriglogic.a',
          '-Wl,--no-whole-archive',
          '$libcxx/usr/lib/${_linuxTriplet(input)}/libc++.a',
          '$libcxx/usr/lib/${_linuxTriplet(input)}/libc++abi.a',
          '-ldl',
          '-lpthread',
        ] else if (targetOS == OS.macOS) ...[
          '$riglogicLib/libriglogic.a',
          '-lc++',
          '-lc++abi',
        ] else if (targetOS == OS.windows) ...[
          // Built by tool/build_openriglogic.bat. Absolute, because cl.exe
          // runs in the hook's output directory.
          '$riglogicLib/riglogic.lib',
        ] else if (targetOS == OS.android) ...[
          '-fPIC',
          '-Wl,--whole-archive',
          staticLibPath,
          '-Wl,--no-whole-archive',
          '-llog',
        ],
      ],
      cppLinkStdLib: targetOS == OS.macOS
          ? 'c++'
          : (targetOS == OS.android ? 'c++_shared' : null),
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
/// user-define, else the lumina repo checked out beside this one.
String _libcxxDir(BuildInput input) {
  final env = Platform.environment['LUMINA_LIBCXX_DIR'];
  final uri = env != null && env.isNotEmpty
      ? Uri.directory(env)
      : input.userDefines.path('libcxx_dir') ??
            input.packageRoot.resolve(
              '../../lumina/flutter_filament/third_party/libcxx/',
            );
  return _dir(uri);
}

String _dir(Uri uri) => riglogicDirPath(uri);

/// The folder of the bundled libc++'s static libraries for the Linux target
/// architecture: `x86_64-linux-gnu` or `aarch64-linux-gnu`.
String _linuxTriplet(BuildInput input) => switch (input.config.code.targetArchitecture) {
      Architecture.x64 => 'x86_64-linux-gnu',
      Architecture.arm64 => 'aarch64-linux-gnu',
      final other => throw UnsupportedError('Unsupported Linux architecture: $other'),
    };
