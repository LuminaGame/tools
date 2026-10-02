import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The bindings in lib/src/bindings/ are written in ffigen's style (ffigen
/// needs libclang); this keeps them and the C headers in step.
void main() {
  final root = Directory.current.path;
  String read(String relative) =>
      File(p.join(root, relative)).readAsStringSync();

  test('every flutter_kimodo_* function of the header has a binding', () {
    final header = read('src/flutter_kimodo.h');
    final bindings = read('lib/src/bindings/flutter_kimodo_bindings.g.dart');
    final declared = RegExp(
      r'FFI_PLUGIN_EXPORT[^;(]*?\b(flutter_kimodo_\w+)\s*\(',
    ).allMatches(header).map((m) => m.group(1)!).toSet();
    final bound = RegExp(
      r'external [^;(]*?\b(flutter_kimodo_\w+)\s*\(',
    ).allMatches(bindings).map((m) => m.group(1)!).toSet();
    expect(declared, hasLength(greaterThan(15)));
    expect(bound, declared);
  });

  test('every flutter_kimodo_* function is implemented in the C source', () {
    final header = read('src/flutter_kimodo.h');
    final source = read('src/flutter_kimodo.c');
    for (final m in RegExp(
      r'FFI_PLUGIN_EXPORT[^;(]*?\b(flutter_kimodo_\w+)\s*\(',
    ).allMatches(header)) {
      expect(source, contains('${m.group(1)}('), reason: m.group(1));
    }
  });

  test('the generation options struct matches kimodo_capi.h', () {
    final capi = read('src/kimodo/kimodo_capi.h');
    final bindings = read('lib/src/bindings/flutter_kimodo_bindings.g.dart');
    final body = RegExp(
      r'typedef struct kimodo_generation_options \{(.*?)\}',
      dotAll: true,
    ).firstMatch(capi)!.group(1)!;
    final fields = RegExp(r'(\w+);').allMatches(body).map((m) => m.group(1));
    expect(fields, [
      'size',
      'seed',
      'frames',
      'diffusion_steps',
      'text_cfg_weight',
      'constraint_cfg_weight',
    ]);
    for (final f in fields) {
      expect(
        bindings,
        contains(
          'external ${f == 'text_cfg_weight' || f == 'constraint_cfg_weight' ? 'double' : 'int'} $f;',
        ),
      );
    }
    expect(capi, contains('#define KIMODO_CAPI_ABI_VERSION 1'));
    expect(bindings, contains('const int KIMODO_CAPI_ABI_VERSION = 1;'));
  });

  test('the vendored kimodo_capi.h is the prebuilt one', () {
    final version = read('tool/kimodo/VERSION').trim();
    final os = Platform.isWindows ? 'windows' : 'linux';
    final prebuilt = File(
      p.join(
        root,
        'third_party',
        'kimodo',
        'prebuilt',
        version,
        '$os-x64',
        'include',
        'kimodo',
        'kimodo_capi.h',
      ),
    );
    if (!prebuilt.existsSync()) {
      markTestSkipped('no local prebuilt ${prebuilt.path}');
      return;
    }
    String normal(String s) => s.replaceAll('\r\n', '\n');
    expect(
      normal(read('src/kimodo/kimodo_capi.h')),
      normal(prebuilt.readAsStringSync()),
    );
  });
}
