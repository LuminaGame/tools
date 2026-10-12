// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// Writes the `JPH_*` preprocessor defines Jolt was compiled with, one per
/// line (`NAME` or `NAME=VALUE`), read from a CMake `compile_commands.json`.
///
/// Code that includes Jolt's headers must see the same defines as the
/// library (object layer width, instruction sets, double precision, the
/// debug renderer and profiler), so the native-assets hook compiles the C
/// wrapper with exactly this list.
///
/// Usage: `dart run tool/write_jolt_defines.dart <compile_commands.json> <out>`
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: write_jolt_defines.dart <compile_commands.json> <out>',
    );
    exit(64);
  }
  final commands = jsonDecode(File(args[0]).readAsStringSync()) as List;
  final entry = commands.cast<Map<String, dynamic>>().firstWhere(
    (c) => (c['file'] as String).replaceAll(r'\', '/').contains('/Jolt/Core/'),
    orElse: () => throw StateError('No Jolt source in ${args[0]}'),
  );
  final command =
      (entry['command'] as String?) ?? (entry['arguments'] as List).join(' ');
  final defines = parseJoltDefines(command);
  if (defines.isEmpty) {
    throw StateError('No JPH_ defines in the Jolt compile command');
  }
  File(args[1]).writeAsStringSync('${defines.join('\n')}\n');
  print('Wrote ${defines.length} Jolt defines to ${args[1]}');
}

/// The `JPH_*` defines of one compiler command line (`-DNAME`, `/DNAME`,
/// `-DNAME=VALUE`), in order, without duplicates.
List<String> parseJoltDefines(String command) {
  final out = <String>[];
  for (final m in RegExp(
    r'(?:^|\s)[-/]D\s*"?(JPH_[A-Za-z0-9_]+(?:=[^\s"]*)?)"?',
  ).allMatches(command)) {
    final d = m.group(1)!;
    if (!out.contains(d)) out.add(d);
  }
  return out;
}
