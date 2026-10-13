import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The generated web bindings expose exactly the native bindings'
/// functions, with identical Dart signatures (tool/ffigen_web.dart must be
/// re-run after tool/ffigen.dart). Adapted from flutter_filament's.
String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r',\s*\)'), ')').replaceAll('( ', '(').replaceAll(' )', ')').trim();

Map<String, String> _native(String src) => {
      for (final m in RegExp(r'@ffi\.Native<[\s\S]*?>\([^)]*\)\s*external\s+([\s\S]*?)\s+(\w+)\s*\(([\s\S]*?)\);').allMatches(src))
        m.group(2)!: _squash('${m.group(1)} (${m.group(3)})'),
    };

Map<String, String> _web(String src) => {
      for (final m in RegExp(r'^([\w.<>, ]+?) (jolt_\w+)\(([^)]*(?:\([^)]*\)[^)]*)*)\) (?:=>|\{)', multiLine: true).allMatches(src))
        m.group(2)!: _squash('${m.group(1)} (${m.group(3)})'),
    };

void main() {
  test('jolt_bindings.web.g.dart matches jolt_bindings.g.dart function for function', () {
    final native = _native(File('lib/src/jolt_bindings.g.dart').readAsStringSync());
    final web = _web(File('lib/src/jolt_bindings.web.g.dart').readAsStringSync());
    expect(native.length, greaterThan(80));
    expect(web.keys.toSet(), native.keys.toSet(), reason: 'run dart run tool/ffigen_web.dart');
    for (final name in native.keys) {
      expect(web[name], native[name], reason: name);
    }
  });

  test('every ffi.Struct has a registered web layout', () {
    final native = File('lib/src/jolt_bindings.g.dart').readAsStringSync();
    final web = File('lib/src/jolt_bindings.web.g.dart').readAsStringSync();
    final names = RegExp(r'final class (\w+) extends ffi\.Struct').allMatches(native).map((m) => m.group(1)!).toList();
    expect(names, isNotEmpty);
    for (final n in names) {
      expect(web, contains('ffi.\$registerStruct<$n>('), reason: n);
    }
  });
}
