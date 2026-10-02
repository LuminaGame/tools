// ignore_for_file: avoid_print

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import 'kimodo_dir.dart';

/// Builds flutter_kimodo.{dll,so} from src/flutter_kimodo.c (no link-time
/// dependency on kimodo) and bundles the prebuilt kimodo + ggml runtime
/// libraries beside it: flutter_kimodo loads kimodo from its own folder at
/// run time.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final targetOS = input.config.code.targetOS;
    final arch = input.config.code.targetArchitecture;
    final os = targetOS.name;
    final version = File.fromUri(
      input.packageRoot.resolve('tool/kimodo/VERSION'),
    ).readAsStringSync().trim();
    final library = kimodoLibrary(os);
    final env = Platform.environment['LUMINA_KIMODO_DIR'];
    final dir = resolveKimodoDir(
      environment: env,
      userDefine: input.userDefines.path('kimodo_dir'),
      packageDefault: input.packageRoot.resolve(
        'third_party/kimodo/prebuilt/$version/${kimodoPlatform(os, arch.name)}/',
      ),
      library: library,
    );
    if (!File('$dir/$library').existsSync()) {
      throw StateError(
        'The kimodo prebuilt $version is missing: $dir/$library. '
        'Build it with tool/build_kimodo.ps1 (Windows) / tool/build_kimodo.sh '
        '(Linux) in flutter_kimodo, or unpack a release archive with '
        '`dart run tool/fetch_prebuilt.dart`; or point the kimodo_dir '
        'user-define (LUMINA_KIMODO_DIR for direct hook runs) at one.',
      );
    }

    await CBuilder.library(
      name: input.packageName,
      assetName: 'src/bindings/flutter_kimodo_bindings.g.dart',
      sources: ['src/flutter_kimodo.c'],
      includes: ['src'],
      flags: [
        if (targetOS == OS.windows) ...['/utf-8', '/W3'] else '-Wall',
        if (targetOS == OS.linux) '-ldl',
      ],
    ).run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => print(record.message)),
    );

    // The runtime libraries, copied next to flutter_kimodo (where it looks
    // for them) and declared as bundled code assets so apps ship them.
    final runtimeDir = Directory(
      '$dir/${targetOS == OS.windows ? 'bin' : 'lib'}',
    );
    final pattern = switch (targetOS) {
      OS.windows => RegExp(r'^(kimodo|ggml[\w-]*)\.dll$'),
      OS.macOS => RegExp(r'^lib(kimodo|ggml[\w-]*)(\.\d+)*\.dylib$'),
      _ => RegExp(r'^lib(kimodo|ggml[\w-]*)\.so(\.\d+)*$'),
    };
    final outDir = Directory.fromUri(input.outputDirectory);
    for (final entity in runtimeDir.listSync()) {
      final name = entity.uri.pathSegments.last;
      if (entity is Directory || !pattern.hasMatch(name)) continue;
      final source = File(entity.path);
      final copy = source.copySync('${outDir.path}/$name');
      output.dependencies.add(source.absolute.uri);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'kimodo/$name',
          linkMode: DynamicLoadingBundled(),
          file: copy.absolute.uri,
        ),
      );
    }
  });
}
