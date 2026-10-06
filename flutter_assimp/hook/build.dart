// ignore_for_file: avoid_print

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final packageName = input.packageName;
    final targetOS = input.config.code.targetOS;
    final filament = _filamentDir(input);
    final libcxx = _libcxxDir(input);
    // cl.exe runs in the hook's output directory, so Windows link inputs are
    // absolute; they come from Filament's MSVC build.
    String windowsLib(String path) => '$filament/out/cmake-release-windows/$path';
    // Filament builds Assimp with only its OBJ and FBX importers; the
    // Collada, 3DS, PLY, DirectX and STL importers are compiled here from the
    // same checkout and registered by the bridge. A Filament folder without
    // those sources (an older prebuilt archive) builds the bridge without them.
    final extraImporterSources = [
      '$filament/third_party/libassimp/code/Collada/ColladaLoader.cpp',
      '$filament/third_party/libassimp/code/Collada/ColladaParser.cpp',
      '$filament/third_party/libassimp/code/Common/ZipArchiveIOSystem.cpp',
      '$filament/third_party/libassimp/code/3DS/3DSLoader.cpp',
      '$filament/third_party/libassimp/code/3DS/3DSConverter.cpp',
      '$filament/third_party/libassimp/code/Ply/PlyLoader.cpp',
      '$filament/third_party/libassimp/code/Ply/PlyParser.cpp',
      '$filament/third_party/libassimp/code/X/XFileImporter.cpp',
      '$filament/third_party/libassimp/code/X/XFileParser.cpp',
      '$filament/third_party/libassimp/code/STL/STLLoader.cpp',
    ];
    final extraImporters = extraImporterSources.every((s) => File(s).existsSync());
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: 'src/third_party/assimp_c.g.dart',
      sources: [
        'src/assimp_bridge.cpp',
        'src/assimp_exporters_stub.cpp',
        '$filament/third_party/libassimp/code/glTF/glTFCommon.cpp',
        '$filament/third_party/libassimp/code/glTF2/glTF2Exporter.cpp',
        if (extraImporters) ...extraImporterSources,
      ],
      includes: [
        'src',
        '$filament/third_party/libassimp/include',
        '$filament/third_party/libassimp/code',
        '$filament/third_party/libassimp/contrib/rapidjson/include',
        if (extraImporters) ...[
          '$filament/third_party/libassimp/contrib/irrXML',
          '$filament/third_party/libassimp/contrib/unzip',
          '$filament/third_party/libz',
        ],
      ],
      defines: {
        if (extraImporters) ...{
          'FLUTTER_ASSIMP_EXTRA_IMPORTERS': null,
          // zlib (compressed .x, zipped .zae) is Filament's libz.
          'ASSIMP_BUILD_NO_OWN_ZLIB': null,
        },
      },
      flags: [
        if (targetOS == OS.windows)
          ...['/std:c++20', '/EHsc', '/utf-8', '/bigobj', '/W0', '/MT', '/DNOMINMAX', '/D_CRT_SECURE_NO_WARNINGS']
        else
          '-std=c++20',
        if (targetOS == OS.linux) ...[
          '-nostdinc++',
          '-isystem', '$libcxx/usr/lib/llvm-21/include/c++/v1',
          '-isystem', '$libcxx/usr/lib/llvm-21/include',
          '-Wl,--whole-archive',
          '$filament/out/cmake-release/third_party/libassimp/tnt/libassimp.a',
          '$filament/out/cmake-release/third_party/zstd/tnt/libzstd.a',
          '-Wl,--no-whole-archive',
          '$libcxx/usr/lib/${_linuxTriplet(input)}/libc++.a',
          '$libcxx/usr/lib/${_linuxTriplet(input)}/libc++abi.a',
          '-lz',
          '-ldl',
          '-lpthread',
        ] else if (targetOS == OS.macOS) ...[
          '$filament/out/cmake-release/third_party/libassimp/tnt/libassimp.a',
          '$filament/out/cmake-release/third_party/zstd/tnt/libzstd.a',
          '-lz',
          '-lc++',
          '-lc++abi',
        ] else if (targetOS == OS.windows) ...[
          windowsLib('third_party/libassimp/tnt/assimp.lib'),
          windowsLib('third_party/zstd/tnt/zstd.lib'),
          windowsLib('third_party/libz/tnt/z.lib'),
        ],
      ],
      cppLinkStdLib: targetOS == OS.macOS ? 'c++' : null,
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

/// Filament's checkout (patched v1.77.0 with its prebuilt `out/` folders),
/// as an absolute `/`-separated path. In order:
/// 1. `LUMINA_FILAMENT_DIR` (reaches the hook only when it is run directly:
///    the hooks runner forwards an allow-list of variables, never `LUMINA_*`);
/// 2. the `filament_dir` user-define in the workspace root pubspec, relative to
///    that pubspec (`hooks: user_defines: flutter_assimp: filament_dir: filament`),
///    which is how a git dependency in the pub cache finds the app's Filament;
/// 3. `<package root>/../filament`: the repo's own gitignored `filament/` link.
String _filamentDir(BuildInput input) {
  final env = Platform.environment['LUMINA_FILAMENT_DIR'];
  final uri = env != null && env.isNotEmpty
      ? Uri.directory(env)
      : input.userDefines.path('filament_dir') ?? input.packageRoot.resolve('../filament/');
  return _dir(uri);
}

/// The bundled libc++ Linux links against (flutter_filament's
/// `third_party/libcxx`): `LUMINA_LIBCXX_DIR`, else the `libcxx_dir`
/// user-define, else the lumina repo checked out beside this one.
String _libcxxDir(BuildInput input) {
  final env = Platform.environment['LUMINA_LIBCXX_DIR'];
  final uri = env != null && env.isNotEmpty
      ? Uri.directory(env)
      : input.userDefines.path('libcxx_dir') ??
          input.packageRoot.resolve('../../lumina/flutter_filament/third_party/libcxx/');
  return _dir(uri);
}

String _dir(Uri uri) {
  final path = _filePath(uri).replaceAll(r'\', '/');
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

/// A user-define such as `D:/filament` resolves to a URI whose scheme is the
/// drive letter; read it back as that Windows path.
String _filePath(Uri uri) =>
    uri.scheme.length == 1 ? '${uri.scheme.toUpperCase()}:${uri.path}' : uri.toFilePath();

/// The folder of the bundled libc++'s static libraries for the Linux target
/// architecture: `x86_64-linux-gnu` or `aarch64-linux-gnu`.
String _linuxTriplet(BuildInput input) => switch (input.config.code.targetArchitecture) {
      Architecture.x64 => 'x86_64-linux-gnu',
      Architecture.arm64 => 'aarch64-linux-gnu',
      final other => throw UnsupportedError('Unsupported Linux architecture: $other'),
    };
