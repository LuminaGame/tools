// ignore_for_file: avoid_print

/// Installs the prebuilt kimodo runtime the native-assets hook bundles and
/// prints its folder (usable as the `kimodo_dir` user-define).
///
///   dart run tool/fetch_prebuilt.dart
///       [--version <id>]    default: tool/kimodo/VERSION
///       [--os windows|linux|macos]   default: this one
///       [--work <dir>]      default: third_party/kimodo (LUMINA_KIMODO_WORK)
///       [--base-url <url>]  default: https://github.com/LuminaGame/tools/releases/download
///       [--force]           unpack again even when installed
///
/// An archive built locally by tool/build_kimodo.* (in `<work>/dist/`) is
/// used as is; otherwise it is downloaded from the `kimodo-<version>`
/// release. Either way it is checked against its `.sha256` before unpacking.
library;

import 'dart:io';

import 'package:flutter_kimodo/src/prebuilt/kimodo_prebuilt.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final package = File.fromUri(Platform.script).parent.parent.path;
  String? opt(String name) {
    final i = args.indexOf('--$name');
    if (i < 0) return null;
    if (i + 1 >= args.length) _usage('--$name needs a value');
    return args[i + 1];
  }

  if (args.contains('-h') || args.contains('--help')) _usage(null);
  final version =
      opt('version') ??
      File(
        p.join(package, 'tool', 'kimodo', 'VERSION'),
      ).readAsStringSync().trim();
  final work = Directory(
    opt('work') ??
        Platform.environment['LUMINA_KIMODO_WORK'] ??
        p.join(package, 'third_party', 'kimodo'),
  );
  try {
    final dir = await KimodoPrebuilt.ensure(
      version: version,
      work: work,
      os: opt('os'),
      baseUrl: opt('base-url') ?? KimodoPrebuilt.defaultBaseUrl,
      force: args.contains('--force'),
      log: stderr.writeln,
    );
    print(p.normalize(dir.absolute.path));
  } on KimodoPrebuiltException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  }
}

Never _usage(String? error) {
  if (error != null) stderr.writeln(error);
  stderr.writeln(
    'usage: dart run tool/fetch_prebuilt.dart [--version <id>] '
    '[--os windows|linux|macos] [--work <dir>] [--base-url <url>] [--force]',
  );
  exit(error == null ? 0 : 2);
}
