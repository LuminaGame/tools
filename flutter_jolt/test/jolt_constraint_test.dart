import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/flutter_jolt.dart';

/// Swing-twist and hinge constraints: anchors hold, cones and hinge limits
/// hold, motors turn.
void main() {
  setUpAll(() => expect(JoltPhysics.isAvailable, isTrue));

  late JoltWorld world;
  late int anchor;

  setUp(() {
    world = JoltWorld(workerThreads: 0);
    final s = JoltShape.box(Vector3.all(0.1));
    anchor = world.createBody(
      s,
      JoltBodySettings(
        motionType: JoltMotionType.static_,
        position: Vector3(0, 5, 0),
      ),
    );
    s.release();
  });
  tearDown(() => world.dispose());

  /// A 1 m long rod hanging from the anchor along +X (released horizontal).
  int rod() {
    final s = JoltShape.box(Vector3(0.5, 0.05, 0.05));
    final id = world.createBody(
      s,
      JoltBodySettings(
        position: Vector3(0.5, 5, 0),
        angularDamping: 0,
        linearDamping: 0,
      ),
    );
    s.release();
    // Jolt keeps colliding jointed bodies; the anchor box overlaps the rod.
    world.ignorePair(anchor, id);
    return id;
  }

  Vector3 tipDirection(int body) {
    final st = world.bodyState(body);
    return (Vector3(1, 0, 0)..applyQuaternion(st.rotation)).normalized();
  }

  test('a swing-twist joint keeps the anchor and holds a 30 degree cone', () {
    final r = rod();
    world.addSwingTwist(
      anchor,
      r,
      JoltSwingTwistSettings(
        positionA: Vector3.zero(),
        twistAxisA: Vector3(1, 0, 0),
        planeAxisA: Vector3(0, 1, 0),
        positionB: Vector3(-0.5, 0, 0),
        twistAxisB: Vector3(1, 0, 0),
        planeAxisB: Vector3(0, 1, 0),
        normalHalfCone: math.pi / 6,
        planeHalfCone: math.pi / 6,
        twistMin: -0.1,
        twistMax: 0.1,
      ),
    );
    var maxSwing = 0.0;
    var maxAnchorError = 0.0;
    for (var i = 0; i < 240; i++) {
      world.step(1 / 120);
      final st = world.bodyState(r);
      final d = tipDirection(r);
      maxSwing = math.max(maxSwing, math.acos(d.x.clamp(-1.0, 1.0)));
      final pivot = st.centerOfMass - d * 0.5;
      maxAnchorError = math.max(
        maxAnchorError,
        (pivot - Vector3(0, 5, 0)).length,
      );
    }
    expect(maxSwing * 180 / math.pi, lessThan(30 + 3));
    expect(
      maxSwing * 180 / math.pi,
      greaterThan(25),
      reason: 'it swings down to the cone',
    );
    expect(maxAnchorError, lessThan(0.01));
  });

  test(
    'a hinge about Z with limits -90..0 degrees lets the rod fall only to -90',
    () {
      final r = rod();
      world.addHinge(
        anchor,
        r,
        JoltHingeSettings(
          positionA: Vector3.zero(),
          hingeAxisA: Vector3(0, 0, 1),
          normalAxisA: Vector3(1, 0, 0),
          positionB: Vector3(-0.5, 0, 0),
          hingeAxisB: Vector3(0, 0, 1),
          normalAxisB: Vector3(1, 0, 0),
          limitMin: -math.pi / 2,
          limitMax: 0,
        ),
      );
      var lowest = 0.0;
      for (var i = 0; i < 360; i++) {
        world.step(1 / 120);
        final d = tipDirection(r);
        lowest = math.min(lowest, math.atan2(d.y, d.x));
        expect(d.z.abs(), lessThan(1e-3), reason: 'it only turns about Z');
      }
      expect(lowest * 180 / math.pi, greaterThan(-90 - 3));
      expect(lowest * 180 / math.pi, lessThan(-80));
    },
  );

  test(
    'a velocity motor turns a hinge against gravity; switching it off lets it fall',
    () {
      world.gravity = Vector3.zero();
      final r = rod();
      final c = world.addHinge(
        anchor,
        r,
        JoltHingeSettings(
          positionA: Vector3.zero(),
          hingeAxisA: Vector3(0, 0, 1),
          normalAxisA: Vector3(1, 0, 0),
          positionB: Vector3(-0.5, 0, 0),
          hingeAxisB: Vector3(0, 0, 1),
          normalAxisB: Vector3(1, 0, 0),
        ),
      );
      c.setVelocityMotor(Vector3(1, 0, 0), 1000);
      for (var i = 0; i < 60; i++) {
        world.step(1 / 120);
      }
      expect(world.bodyState(r).angularVelocity.z, closeTo(1, 0.05));
      c.setVelocityMotor(Vector3.zero(), 0);
      world.removeConstraint(c);
      expect(c.isDestroyed, isTrue);
      expect(world.constraints, isEmpty);
    },
  );

  test(
    'a position motor holds a hinged rod at 30 degrees against gravity; switched off, the rod falls',
    () {
      final r = rod();
      final c = world.addHinge(
        anchor,
        r,
        JoltHingeSettings(
          positionA: Vector3.zero(),
          hingeAxisA: Vector3(0, 0, 1),
          normalAxisA: Vector3(1, 0, 0),
          positionB: Vector3(-0.5, 0, 0),
          hingeAxisB: Vector3(0, 0, 1),
          normalAxisB: Vector3(1, 0, 0),
        ),
      );
      c.setSolverSteps(velocity: 20, position: 10);
      // 30 degrees about the hinge axis (a hinge target turns about X, the
      // hinge axis of its frame): the rod points 30 degrees up.
      c.setPositionMotor(
        Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 6),
        frequency: 10,
        maxTorque: 1000,
      );
      for (var i = 0; i < 240; i++) {
        world.step(1 / 120);
      }
      final d = tipDirection(r);
      expect(math.atan2(d.y, d.x) * 180 / math.pi, closeTo(30, 3));
      c.setPositionMotor(Quaternion.identity(), frequency: 0, maxTorque: 0);
      // A motor change does not wake a sleeping body.
      world.activateBody(r);
      // Undamped, it swings down like a pendulum.
      var lowest = 1.0;
      for (var i = 0; i < 120; i++) {
        world.step(1 / 120);
        lowest = math.min(lowest, tipDirection(r).y);
      }
      expect(
        lowest,
        lessThan(-0.9),
        reason: 'swings down once the motor is off',
      );
    },
  );

  test('destroying a body removes its constraints first', () {
    final r = rod();
    world.addSwingTwist(
      anchor,
      r,
      JoltSwingTwistSettings(
        positionA: Vector3.zero(),
        twistAxisA: Vector3(1, 0, 0),
        planeAxisA: Vector3(0, 1, 0),
        positionB: Vector3(-0.5, 0, 0),
        twistAxisB: Vector3(1, 0, 0),
        planeAxisB: Vector3(0, 1, 0),
      ),
    );
    world.destroyBody(r);
    expect(world.constraints, isEmpty);
    world.step(1 / 60);
  });
}
