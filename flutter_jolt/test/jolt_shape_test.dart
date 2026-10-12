import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/flutter_jolt.dart';

/// Shapes: sizes, volumes, centres of mass, convex hulls, height fields and
/// compounds as Jolt builds them.
void main() {
  setUpAll(() => expect(JoltPhysics.isAvailable, isTrue));

  test('primitive volumes', () {
    final box = JoltShape.box(Vector3(1, 2, 3));
    expect(box.volume, closeTo(48, 1e-3));
    box.release();
    final sphere = JoltShape.sphere(2);
    expect(sphere.volume, closeTo(4 / 3 * math.pi * 8, 1e-2));
    sphere.release();
    final capsule = JoltShape.capsule(1, 0.5);
    expect(
      capsule.volume,
      closeTo(math.pi * 0.25 * 2 + 4 / 3 * math.pi * 0.125, 1e-3),
    );
    expect(capsule.localBounds.max.y, closeTo(1.5, 1e-5));
    capsule.release();
    final cylinder = JoltShape.cylinder(1, 0.5);
    expect(cylinder.volume, closeTo(math.pi * 0.25 * 2, 2e-2));
    cylinder.release();
  });

  test(
    'a convex hull of a cube is a 1 m³ hull centred on its points; too few points throw',
    () {
      final hull = JoltShape.convexHull([
        for (final x in [1.0, 2.0])
          for (final y in [0.0, 1.0])
            for (final z in [0.0, 1.0]) Vector3(x, y, z),
      ], maxConvexRadius: 0);
      expect(hull.volume, closeTo(1, 1e-3));
      expect(hull.centerOfMass.x, closeTo(1.5, 1e-3));
      hull.release();
      expect(
        () => JoltShape.convexHull([Vector3.zero(), Vector3(1, 0, 0)]),
        throwsArgumentError,
      );
    },
  );

  test(
    'a height field: a ball rests on a ramp at the height its samples give',
    () {
      // 9 x 9 samples 1 m apart; height = 0.25 * x (a ramp rising along +x).
      const n = 9;
      final samples = Float32List(n * n);
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          samples[y * n + x] = 0.25 * x;
        }
      }
      final world = JoltWorld(workerThreads: 0);
      addTearDown(world.dispose);
      final field = JoltShape.heightField(
        samples,
        n,
        offset: Vector3(-4, 0, -4),
        scale: Vector3(1, 1, 1),
      );
      final ground = world.createBody(
        field,
        JoltBodySettings(motionType: JoltMotionType.static_),
      );
      field.release();
      final hit = world.castRay(Vector3(0, 10, 0), Vector3(0, -20, 0))!;
      expect(hit.body, ground);
      // x = 0 is sample column 4: height 1.0 (Jolt stores samples in 8 bits
      // per block, a few millimetres here).
      expect(hit.point.y, closeTo(1.0, 5e-3));
      expect(
        () => JoltShape.heightField(Float32List(5), 3),
        throwsArgumentError,
      );
    },
  );

  test(
    'a compound reports which part a ray hit through each part\'s user data',
    () {
      final a = JoltShape.box(Vector3.all(0.5))..userData = 0;
      final b = JoltShape.sphere(0.5)..userData = 1;
      final compound = JoltShape.compound([
        (
          shape: a,
          position: Vector3(-2, 0, 0),
          rotation: Quaternion.identity(),
        ),
        (shape: b, position: Vector3(2, 0, 0), rotation: Quaternion.identity()),
      ]);
      a.release();
      b.release();
      final world = JoltWorld(workerThreads: 0);
      addTearDown(world.dispose);
      final body = world.createBody(
        compound,
        JoltBodySettings(motionType: JoltMotionType.static_),
      );
      compound.release();
      expect(world.castRay(Vector3(-2, 5, 0), Vector3(0, -10, 0))!.shape, 0);
      final right = world.castRay(Vector3(2, 5, 0), Vector3(0, -10, 0))!;
      expect(right.body, body);
      expect(right.shape, 1);
      expect(right.point.y, closeTo(0.5, 1e-4));
    },
  );

  test('scaled, rotated/translated and centre-of-mass offset decorators', () {
    final box = JoltShape.box(Vector3.all(0.5), convexRadius: 0);
    final scaled = JoltShape.scaled(box, Vector3(2, 1, 1));
    expect(scaled.volume, closeTo(2, 1e-3));
    final moved = JoltShape.rotatedTranslated(
      box,
      Vector3(0, 3, 0),
      Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 4),
    );
    expect(moved.centerOfMass.y, closeTo(3, 1e-4));
    final offset = JoltShape.offsetCenterOfMass(box, Vector3(0.1, 0, 0));
    expect(offset.centerOfMass.x, closeTo(0.1, 1e-5));
    for (final s in [box, scaled, moved, offset]) {
      s.release();
    }
    expect(box.isReleased, isTrue);
    expect(() => box.volume, throwsStateError);
  });
}
