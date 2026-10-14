// ignore_for_file: avoid_print

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import 'package:flutter_jolt/src/hook/jolt_dir.dart';

/// Builds `flutter_jolt` (the C wrapper in `src/jolt_c.cpp`) as a dynamic
/// library linked against a Jolt Physics static library.
///
/// The Jolt build folder ([resolveJoltDir]: `LUMINA_JOLT_DIR`, the `jolt_dir`
/// user-define, else `third_party/jolt` as `tool/build_jolt.*` writes it)
/// provides the headers, the library and the `JPH_*` defines Jolt was built
/// with; the wrapper is compiled with exactly those defines.
///
/// When the target has no Jolt build (a platform the build scripts do not
/// cover yet, or a checkout that never ran them) the hook emits no code
/// asset: `JoltPhysics.isAvailable` is then false and callers fall back.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final targetOS = input.config.code.targetOS;
    final staticLib = targetOS == OS.windows ? 'Jolt.lib' : 'libJolt.a';
    final joltDir = resolveJoltDir(
      environment: Platform.environment['LUMINA_JOLT_DIR'],
      userDefine: input.userDefines.path('jolt_dir'),
      packageDefault: input.packageRoot.resolve('third_party/jolt/'),
      staticLib: staticLib,
    );
    final library = '$joltDir/lib/$staticLib';
    final definesFile = File('$joltDir/jolt_defines.txt');
    if (!File(library).existsSync() || !definesFile.existsSync()) {
      print(
        'flutter_jolt: no Jolt build at $joltDir (run tool/build_jolt.* or set '
        'the jolt_dir user-define); building without the native library.',
      );
      return;
    }
    output.dependencies
      ..add(File(library).absolute.uri)
      ..add(definesFile.absolute.uri);
    final joltDefines = parseJoltDefines(definesFile.readAsStringSync());

    // Linux only: the bundled libc++ of a Lumina checkout (Jolt is built
    // against it, like the other native packages).
    final libcxx = targetOS == OS.linux ? _bundledLibcxx(input) : null;
    if (targetOS == OS.linux && libcxx == null) {
      throw StateError(
        'The Jolt library at $library was built against the bundled libc++, '
        'which is missing. Set the libcxx_dir user-define.',
      );
    }

    final cbuilder = CBuilder.library(
      name: input.packageName,
      // Language.cpp would pass `-x c++`, reading the static library in
      // [flags] as a source; the .cpp extension selects C++ anyway.
      language: Language.c,
      assetName: 'src/jolt_native.dart',
      sources: const ['src/jolt_c.cpp'],
      includes: ['src', '$joltDir/include'],
      defines: {...joltDefines, 'NDEBUG': null},
      flags: [
        if (targetOS == OS.windows) ...[
          '/std:c++17',
          '/EHsc',
          '/utf-8',
          '/W0',
          '/MT',
          '/O2',
          '/DNOMINMAX',
          // Absolute, because cl.exe runs in the hook's output directory.
          library,
        ] else ...[
          '-std=c++17',
          '-O2',
          '-fPIC',
          '-w',
          // The instruction sets Jolt was built with (SSE4.1/4.2 on x64).
          if (input.config.code.targetArchitecture == Architecture.x64) ...joltIsaFlags(joltDefines),
          if (libcxx != null) ...[
            '-nostdinc++',
            '-isystem',
            '$libcxx/usr/lib/llvm-21/include/c++/v1',
            '-isystem',
            '$libcxx/usr/lib/llvm-21/include',
          ],
          // A library with an unresolved symbol fails to link here instead
          // of failing to load at run time.
          // ld64 resolves archives wherever they are named.
          if (targetOS == OS.macOS || targetOS == OS.iOS) library,
          if (targetOS == OS.linux || targetOS == OS.android) '-Wl,-z,defs',
        ],
      ],
      // The archives after the wrapper's object: GNU ld takes from an
      // archive only what the objects before it need, so Jolt and libc++
      // named among the flags (ahead of the source) were linked in empty
      // and the library failed to load on Linux.
      libraryDirectories: [
        if (targetOS == OS.linux || targetOS == OS.android) '$joltDir/lib',
        if (libcxx != null) '$libcxx/usr/lib/${_linuxTriplet(input)}',
      ],
      libraries: [
        if (targetOS == OS.linux || targetOS == OS.android) ':$staticLib',
        if (libcxx != null) ...[':libc++.a', ':libc++abi.a'],
        if (targetOS == OS.macOS || targetOS == OS.iOS) ...['c++', 'c++abi'],
        if (targetOS == OS.android) 'c++_shared',
        if (targetOS == OS.linux) ...['dl', 'pthread', 'm'],
      ],
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

/// The bundled libc++ Linux links against (flutter_filament's
/// `third_party/libcxx`): `LUMINA_LIBCXX_DIR`, else the `libcxx_dir`
/// user-define, else the lumina repo checked out beside this one. Null when
/// that folder has no libc++ headers.
String? _bundledLibcxx(BuildInput input) {
  final env = Platform.environment['LUMINA_LIBCXX_DIR'];
  final uri = env != null && env.isNotEmpty
      ? Uri.directory(env)
      : input.userDefines.path('libcxx_dir') ??
            input.packageRoot.resolve(
              '../../lumina/flutter_filament/third_party/libcxx/',
            );
  final dir = joltDirPath(uri);
  return Directory('$dir/usr/lib/llvm-21/include/c++/v1').existsSync()
      ? dir
      : null;
}

/// The folder of the bundled libc++'s static libraries for the Linux target
/// architecture.
String _linuxTriplet(BuildInput input) =>
    switch (input.config.code.targetArchitecture) {
      Architecture.x64 => 'x86_64-linux-gnu',
      Architecture.arm64 => 'aarch64-linux-gnu',
      final other => throw UnsupportedError(
        'Unsupported Linux architecture: $other',
      ),
    };
