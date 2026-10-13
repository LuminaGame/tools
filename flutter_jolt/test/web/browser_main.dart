/// The browser entry of flutter_jolt's web tests: loads the WebAssembly
/// module (`flutter_jolt.js` beside the page), runs the world, shape,
/// constraint, cloth and broad phase test files through the browser test
/// runner (test/support/web_test_shim.dart), measures a 200-box step, and
/// posts the results as JSON to `/results` of the page's server (and shows
/// them in `<pre id="results">`). test/web/browser_tests_test.dart
/// compiles, serves and runs it in Chrome.
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_jolt/flutter_jolt.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:web/web.dart' as web;

import '../jolt_broad_phase_test.dart' as broad_phase;
import '../jolt_cloth_test.dart' as cloth;
import '../jolt_constraint_test.dart' as constraint;
import '../jolt_shape_test.dart' as shape;
import '../jolt_world_test.dart' as world;
import '../support/web_test_shim.dart';

Future<void> main() async {
  final out = web.document.getElementById('results')!;
  final report = <String, Object?>{};
  try {
    final load = Stopwatch()..start();
    await JoltPhysics.ensureInitialized(moduleUrl: 'flutter_jolt.js');
    report['loadMs'] = load.elapsedMilliseconds;
    report['available'] = JoltPhysics.isAvailable;
    report['version'] = JoltPhysics.version;

    world.main();
    shape.main();
    constraint.main();
    cloth.main();
    broad_phase.main();
    final results = await runWebTests();
    report['tests'] = [
      for (final r in results) {'name': r.name, 'passed': r.passed, 'ms': r.millis, if (r.error != null) 'error': r.error},
    ];
    report['passed'] = results.where((r) => r.passed).length;
    report['failed'] = results.where((r) => !r.passed).length;
    report['stepMicros200Boxes'] = _bench();
  } catch (e, st) {
    report['fatal'] = '$e\n$st';
  }
  final json = jsonEncode(report);
  out.textContent = json;
  await web.window.fetch('/results'.toJS, web.RequestInit(method: 'POST', body: json.toJS)).toDart;
}

/// The mean step (µs) of 200 boxes falling into a pile, after it formed.
int _bench() {
  final w = JoltWorld(workerThreads: 0);
  try {
    final ground = JoltShape.box(Vector3(20, 0.5, 20));
    w.createBody(ground, JoltBodySettings(motionType: JoltMotionType.static_, position: Vector3(0, -0.5, 0)));
    ground.release();
    final box = JoltShape.box(Vector3.all(0.25));
    for (var i = 0; i < 200; i++) {
      w.createBody(box, JoltBodySettings(position: Vector3((i % 10) * 0.6 - 3, 0.5 + (i ~/ 10) * 0.6, (i % 7) * 0.1)));
    }
    box.release();
    for (var i = 0; i < 120; i++) {
      w.step(1 / 60);
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < 120; i++) {
      w.step(1 / 60);
    }
    return watch.elapsedMicroseconds ~/ 120;
  } finally {
    w.dispose();
  }
}
