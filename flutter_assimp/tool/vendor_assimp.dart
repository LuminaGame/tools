// ignore_for_file: avoid_print

/// Copies the Assimp and zlib sources the native-assets hook compiles (when no
/// Filament build is configured) from a patched Filament checkout into
/// `third_party/assimp` and `third_party/zlib`.
///
///     dart run tool/vendor_assimp.dart <filament checkout>
///
/// The checkout is Filament with Lumina's patches applied (lumina's
/// `tool/filament/build_prebuilt.*` leaves one in `build/filament-src`). The
/// tool takes the sources Filament's own Assimp build compiles
/// (`third_party/libassimp/tnt/CMakeLists.txt`), the glTF 2 exporter and the
/// extra importers the bridge uses, follows their `#include`s and copies that
/// closure plus the license files. It replaces both folders.
library;

import 'dart:io';

/// The sources beyond Filament's Assimp build: the glTF 2 exporter and the
/// Collada, 3DS, PLY, DirectX and STL importers.
const extraSources = [
  'code/glTF/glTFCommon.cpp',
  'code/glTF2/glTF2Exporter.cpp',
  'code/Collada/ColladaLoader.cpp',
  'code/Collada/ColladaParser.cpp',
  'code/Common/ZipArchiveIOSystem.cpp',
  'code/3DS/3DSLoader.cpp',
  'code/3DS/3DSConverter.cpp',
  'code/Ply/PlyLoader.cpp',
  'code/Ply/PlyParser.cpp',
  'code/X/XFileImporter.cpp',
  'code/X/XFileParser.cpp',
  'code/STL/STLLoader.cpp',
];

/// zlib's library sources (Filament's `third_party/libz/tnt/CMakeLists.txt`).
const zlibSources = [
  'adler32.c',
  'compress.c',
  'crc32.c',
  'deflate.c',
  'gzclose.c',
  'gzlib.c',
  'gzread.c',
  'gzwrite.c',
  'inflate.c',
  'infback.c',
  'inftrees.c',
  'inffast.c',
  'trees.c',
  'uncompr.c',
  'zutil.c',
];

const assimpLicenses = [
  'LICENSE',
  'contrib/clipper/License.txt',
  'contrib/poly2tri/LICENSE',
  'contrib/rapidjson/license.txt',
];

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'usage: dart run tool/vendor_assimp.dart <filament checkout>',
    );
    exit(2);
  }
  final filament = Directory(args.single).absolute.path.replaceAll(r'\', '/');
  final assimp = '$filament/third_party/libassimp';
  final zlib = '$filament/third_party/libz';
  final package = File.fromUri(
    Platform.script,
  ).parent.parent.path.replaceAll(r'\', '/');

  final cmake = File('$assimp/tnt/CMakeLists.txt').readAsStringSync();
  final srcsBlock = cmake.split('set(SRCS')[1].split(')')[0];
  final coreSources = RegExp(
    r'\$\{SRC_DIR\}/(\S+\.(?:cpp|cc|c))',
  ).allMatches(srcsBlock).map((m) => m.group(1)!).toList();

  final includeDirs = [
    assimp,
    '$assimp/code',
    '$assimp/include',
    '$assimp/contrib/irrXML',
    '$assimp/contrib/rapidjson/include',
    '$assimp/contrib/unzip',
    zlib,
  ];
  final pending = [
    for (final s in [...coreSources, ...extraSources]) '$assimp/$s',
    for (final s in zlibSources) '$zlib/$s',
    for (final f in Directory('$package/src').listSync().whereType<File>())
      f.path.replaceAll(r'\', '/'),
  ];
  final include = RegExp(
    r'^\s*#\s*include\s*([<"])([^>"]+)[>"]',
    multiLine: true,
  );
  final seen = <String>{};
  while (pending.isNotEmpty) {
    final path = _normalize(pending.removeLast());
    if (!seen.add(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    for (final m in include.allMatches(file.readAsStringSync())) {
      final dirs = [
        if (m.group(1) == '"') file.parent.path.replaceAll(r'\', '/'),
        ...includeDirs,
      ];
      for (final dir in dirs) {
        final candidate = _normalize('$dir/${m.group(2)}');
        if (File(candidate).existsSync()) {
          pending.add(candidate);
          break;
        }
      }
    }
  }

  final targets = {
    assimp: '$package/third_party/assimp',
    zlib: '$package/third_party/zlib',
  };
  for (final target in targets.values) {
    final dir = Directory(target);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
  var count = 0;
  void copy(String from) {
    for (final MapEntry(key: root, value: target) in targets.entries) {
      if (from.startsWith('$root/')) {
        final to = File('$target/${from.substring(root.length + 1)}');
        to.parent.createSync(recursive: true);
        File(from).copySync(to.path);
        count++;
        return;
      }
    }
  }

  for (final path in seen.where((p) => !p.startsWith('$package/'))) {
    copy(path);
  }
  for (final license in assimpLicenses) {
    copy('$assimp/$license');
  }
  copy('$zlib/LICENSE');
  File('$package/third_party/assimp/sources.txt').writeAsStringSync(
    '# The Assimp sources hook/build.dart compiles (written by tool/vendor_assimp.dart).\n'
    '${[...coreSources, ...extraSources].join('\n')}\n',
  );
  print('Copied $count files into third_party/assimp and third_party/zlib.');
}

String _normalize(String path) {
  final parts = <String>[];
  for (final part in path.replaceAll(r'\', '/').split('/')) {
    if (part == '..' && parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
    } else if (part != '.' && (part.isNotEmpty || parts.isEmpty)) {
      parts.add(part);
    }
  }
  return parts.join('/');
}
