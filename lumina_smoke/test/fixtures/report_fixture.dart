// Run by runner_test.dart through the report runner (not a test of its own:
// the name does not end in _test.dart, so a suite run never picks it up).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/lumina_smoke.dart';

void main() {
  test('fixture: saves a screenshot', () {
    final png = SmokeArtifacts.encodePng(4, 4, Uint8List(64)..fillRange(0, 64, 200));
    final file = SmokeArtifacts.saveScreenshot('fixture: saves a screenshot', png);
    // ignore: avoid_print
    print('saved ${file.path}');
  });

  test('fixture: second scenario', () {
    expect(1 + 1, 2);
  });
}
