// ignore_for_file: avoid_print

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Builds `flutter_assimp` (the C bridge in `src/`) as a dynamic library.
///
/// Two ways to get Assimp into it:
///
/// * **Filament build** (Lumina's setup): when the Filament folder found by
///   [_filamentDir] holds Filament's prebuilt Assimp library, the bridge links
///   it and compiles only the exporter and extra importers from that
///   checkout.
/// * **Vendored sources** (default for a package from pub.dev): otherwise the
///   Assimp 5.0 sources in `third_party/assimp` (Filament's patched copy, see
///   `tool/vendor_assimp.dart`) are compiled together with the bridge. No
///   CMake and no setup; only the platform's C++ compiler. zlib comes from
///   `third_party/zlib` on Windows and from the system elsewhere.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final logger = Logger('')
      ..level = Level.ALL
      ..onRecord.listen((record) => print(record.message));
    final filament = _filamentDir(input);
    if (_hasFilamentAssimp(filament, input.config.code.targetOS)) {
      await _buildAgainstFilament(input, output, logger, filament);
    } else {
      await _buildVendored(input, output, logger);
    }
  });
}

/// Whether [filament] holds Filament's prebuilt Assimp library for [targetOS].
bool _hasFilamentAssimp(String filament, OS targetOS) {
  final library = targetOS == OS.windows
      ? '$filament/out/cmake-release-windows/third_party/libassimp/tnt/assimp.lib'
      : '$filament/out/cmake-release/third_party/libassimp/tnt/libassimp.a';
  return File(library).existsSync() &&
      File(
        '$filament/third_party/libassimp/include/assimp/scene.h',
      ).existsSync();
}

Future<void> _buildAgainstFilament(
  BuildInput input,
  BuildOutputBuilder output,
  Logger logger,
  String filament,
) async {
  final targetOS = input.config.code.targetOS;
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
  final extraImporters = extraImporterSources.every(
    (s) => File(s).existsSync(),
  );
  final cbuilder = CBuilder.library(
    name: input.packageName,
    assetName: _assetName,
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
      if (targetOS == OS.windows) ..._msvcFlags else '-std=c++20',
      if (targetOS == OS.linux) ...[
        '-nostdinc++',
        '-isystem',
        '$libcxx/usr/lib/llvm-21/include/c++/v1',
        '-isystem',
        '$libcxx/usr/lib/llvm-21/include',
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
  await cbuilder.run(input: input, output: output, logger: logger);
}

/// Compiles the bridge with the vendored Assimp (and, on Windows, zlib).
Future<void> _buildVendored(
  BuildInput input,
  BuildOutputBuilder output,
  Logger logger,
) async {
  final targetOS = input.config.code.targetOS;
  final windows = targetOS == OS.windows;
  final assimp = input.packageRoot.resolve('third_party/assimp/');
  final zlib = input.packageRoot.resolve('third_party/zlib/');
  if (!File.fromUri(assimp.resolve('include/assimp/scene.h')).existsSync()) {
    throw StateError(
      'The vendored Assimp sources are missing under ${assimp.toFilePath()}.',
    );
  }
  // Linux only: the bundled libc++ of a Lumina checkout, when there is one.
  final libcxx = targetOS == OS.linux ? _bundledLibcxx(input) : null;

  final includes = [
    'src',
    'third_party/assimp',
    'third_party/assimp/code',
    'third_party/assimp/include',
    'third_party/assimp/contrib/irrXML',
    'third_party/assimp/contrib/rapidjson/include',
    'third_party/assimp/contrib/unzip',
    if (windows) 'third_party/zlib',
  ];
  // Every importer but the seven the bridge reads; Assimp's importer registry
  // then registers exactly those (FBX, OBJ, Collada, 3DS, PLY, DirectX, STL),
  // so FLUTTER_ASSIMP_EXTRA_IMPORTERS stays undefined.
  Map<String, String?> defines({required bool gltfHeaders}) => {
    for (final importer in _disabledImporters)
      if (gltfHeaders ? !importer.startsWith('GLTF') : true)
        'ASSIMP_BUILD_NO_${importer}_IMPORTER': null,
    'ASSIMP_BUILD_NO_OWN_ZLIB': null,
  };
  final cxxFlags = [
    if (windows) ..._msvcFlags else ...['-std=c++20', '-w'],
    if (libcxx != null) ...[
      '-nostdinc++',
      '-isystem',
      '$libcxx/usr/lib/llvm-21/include/c++/v1',
      '-isystem',
      '$libcxx/usr/lib/llvm-21/include',
    ],
  ];
  // The static library CBuilder writes for [name] (Windows: `<name>.lib`).
  String windowsStaticLibrary(String name) =>
      _slash(File.fromUri(input.outputDirectory.resolve('$name.lib')).path);

  // The glTF 2 exporter, compiled with the glTF headers visible.
  await CBuilder.library(
    name: _gltfLibrary,
    assetName: null,
    linkModePreference: LinkModePreference.static,
    sources: [for (final source in _gltfSources) 'third_party/assimp/$source'],
    includes: includes,
    defines: defines(gltfHeaders: true),
    flags: cxxFlags,
  ).run(input: input, output: output, logger: logger);

  // minizip (zipped Collada .zae) is C. On Windows it compiles with the rest
  // (cl.exe picks the language by extension); clang rejects -std=c++20 for C
  // files, so elsewhere it becomes a static library of its own.
  final unzipSources = [
    'third_party/assimp/contrib/unzip/ioapi.c',
    'third_party/assimp/contrib/unzip/unzip.c',
  ];
  if (!windows) {
    await CBuilder.library(
      name: _unzipLibrary,
      assetName: null,
      linkModePreference: LinkModePreference.static,
      sources: unzipSources,
      includes: const ['third_party/assimp/contrib/unzip'],
      defines: const {'ASSIMP_BUILD_NO_OWN_ZLIB': null},
      flags: const ['-w'],
    ).run(input: input, output: output, logger: logger);
  }

  // The rest of the Assimp C++ sources, as tool/vendor_assimp.dart listed
  // them (the exporter and minizip are handled above).
  final list = File.fromUri(assimp.resolve('sources.txt'));
  final sources = [
    for (final line in list.readAsLinesSync().map((l) => l.trim()))
      if (line.isNotEmpty &&
          !line.startsWith('#') &&
          !line.endsWith('.c') &&
          !_gltfSources.contains(line))
        assimp.resolve(line),
    if (windows) ...[
      for (final source in unzipSources) input.packageRoot.resolve(source),
      for (final source in _zlibSources) zlib.resolve(source),
    ],
  ];
  // The sources go to the compiler through a response file: their absolute
  // paths overflow the Windows command line (cl.exe runs through cmd.exe with
  // the Visual Studio environment script).
  final rsp = File.fromUri(input.outputDirectory.resolve('assimp_sources.rsp'));
  await rsp.writeAsString(
    sources
        .map((uri) => '"${_slash(File.fromUri(uri).absolute.path)}"')
        .join('\n'),
  );
  output.dependencies.addAll([list.uri, ...sources]);

  // Language.cpp makes native_toolchain_c link the platform's C++ standard
  // library, but it also passes `-x c++` (and /TP on Windows, which would
  // compile zlib as C++). So it is used only on clang without the bundled
  // libc++, which is linked by path.
  final cppLanguage = !windows && libcxx == null;
  final cbuilder = CBuilder.library(
    name: input.packageName,
    assetName: _assetName,
    language: cppLanguage ? Language.cpp : Language.c,
    sources: const ['src/assimp_bridge.cpp', 'src/assimp_exporters_stub.cpp'],
    includes: includes,
    defines: defines(gltfHeaders: false),
    flags: [
      ...cxxFlags,
      if (windows) '/MP',
      '@${_slash(rsp.path)}',
      // cl.exe hands .lib inputs to the linker; clang gets `-l` below.
      if (windows) windowsStaticLibrary(_gltfLibrary),
      if (libcxx != null) ...[
        '$libcxx/usr/lib/${_linuxTriplet(input)}/libc++.a',
        '$libcxx/usr/lib/${_linuxTriplet(input)}/libc++abi.a',
      ],
      if (targetOS == OS.linux) ...['-ldl', '-lpthread'],
    ],
    libraries: [
      if (!windows) ...[_gltfLibrary, _unzipLibrary, 'z'],
    ],
    libraryDirectories: [if (!windows) '.'],
    // A source build links libc++ statically on Android, so the app needs no
    // libc++_shared.so; elsewhere the platform default applies (MSVC's CRT,
    // libstdc++ on Linux, libc++ on Apple platforms).
    cppLinkStdLib: cppLanguage && targetOS == OS.android ? 'c++_static' : null,
  );
  await cbuilder.run(input: input, output: output, logger: logger);
}

const _assetName = 'src/third_party/assimp_c.g.dart';

const _unzipLibrary = 'flutter_assimp_unzip';

const _gltfLibrary = 'flutter_assimp_gltf';

/// The glTF 2 exporter's sources: unlike the rest they need the glTF headers,
/// which `ASSIMP_BUILD_NO_GLTF_IMPORTER` hides.
const _gltfSources = [
  'code/glTF/glTFCommon.cpp',
  'code/glTF2/glTF2Exporter.cpp',
];

const _msvcFlags = [
  '/std:c++20',
  '/EHsc',
  '/utf-8',
  '/bigobj',
  '/W0',
  '/MT',
  '/DNOMINMAX',
  '/D_CRT_SECURE_NO_WARNINGS',
];

/// The importers Filament's Assimp build disables
/// (`third_party/libassimp/tnt/CMakeLists.txt`), minus Collada, 3DS, PLY,
/// DirectX (X) and STL, which the bridge reads too.
const _disabledImporters = [
  '3D', '3MF', 'AC', 'AMF', 'ASSBIN', 'ASE', 'B3D', 'BLEND', 'BVH', 'C4D', //
  'COB', 'CSM', 'DXF', 'GLTF', 'GLTF2', 'HMP', 'IFC', 'IRR', 'IRRMESH', //
  'LWO', 'LWS', 'M3', 'MD2', 'MD3', 'MD5', 'MDC', 'MDL', 'MMD', 'MS3D', //
  'NDO', 'NFF', 'OFF', 'OGRE', 'OPENGEX', 'Q3BSP', 'Q3D', 'RAW', 'SIB', //
  'SMD', 'STEPFILE', 'TERRAGEN', 'X3D', 'XGL', 'XX', 'STEP',
];

/// zlib's library sources in `third_party/zlib` (Windows only).
const _zlibSources = [
  'adler32.c', 'compress.c', 'crc32.c', 'deflate.c', 'gzclose.c', //
  'gzlib.c', 'gzread.c', 'gzwrite.c', 'inflate.c', 'infback.c', //
  'inftrees.c', 'inffast.c', 'trees.c', 'uncompr.c', 'zutil.c',
];

/// Filament's checkout (patched, with its prebuilt `out/` folders), as an
/// absolute `/`-separated path. In order:
/// 1. `LUMINA_FILAMENT_DIR` (reaches the hook only when it is run directly:
///    the hooks runner forwards an allow-list of variables, never `LUMINA_*`);
/// 2. the `filament_dir` user-define in the workspace root pubspec, relative to
///    that pubspec (`hooks: user_defines: flutter_assimp: filament_dir: filament`),
///    which is how a git dependency in the pub cache finds the app's Filament;
/// 3. `<package root>/../filament`: the repo's own gitignored `filament/` link.
///
/// Without Filament's Assimp library there the vendored sources are built.
String _filamentDir(BuildInput input) {
  final env = Platform.environment['LUMINA_FILAMENT_DIR'];
  final uri = env != null && env.isNotEmpty
      ? Uri.directory(env)
      : input.userDefines.path('filament_dir') ??
            input.packageRoot.resolve('../filament/');
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
            input.packageRoot.resolve(
              '../../lumina/flutter_filament/third_party/libcxx/',
            );
  return _dir(uri);
}

/// [_libcxxDir] when it holds libc++'s headers, else null (a package from
/// pub.dev: the compiler's own C++ standard library is used).
String? _bundledLibcxx(BuildInput input) {
  final dir = _libcxxDir(input);
  return Directory('$dir/usr/lib/llvm-21/include/c++/v1').existsSync()
      ? dir
      : null;
}

String _dir(Uri uri) {
  final path = _slash(_filePath(uri));
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

String _slash(String path) => path.replaceAll(r'\', '/');

/// A user-define such as `D:/filament` resolves to a URI whose scheme is the
/// drive letter; read it back as that Windows path.
String _filePath(Uri uri) => uri.scheme.length == 1
    ? '${uri.scheme.toUpperCase()}:${uri.path}'
    : uri.toFilePath();

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
