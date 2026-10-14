import 'dart:math' as math;

import 'support/test_api.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/flutter_jolt.dart';

/// A real Jolt world (the native library built by tool/build_jolt.*): bodies
/// fall, rest and sleep on a ground box, contacts are reported, rays hit,
/// filters keep pairs apart.
void main() {
  setUpAll(() {
    expect(
      JoltPhysics.isAvailable,
      isTrue,
      reason: 'build the Jolt library with tool/build_jolt.bat or tool/build_jolt.sh first: ${JoltPhysics.loadError}',
    );
  });

  test('the library reports the pinned Jolt version', () {
    expect(JoltPhysics.version, '5.6.0');
  });

  group('a world with a ground box', () {
    late JoltWorld world;
    late int ground;

    setUp(() {
      world = JoltWorld(workerThreads: 2);
      final shape = JoltShape.box(Vector3(50, 0.5, 50));
      ground = world.createBody(
        shape,
        JoltBodySettings(
          motionType: JoltMotionType.static_,
          position: Vector3(0, -0.5, 0),
          userData: 7,
        ),
      );
      shape.release();
    });
    tearDown(() => world.dispose());

    test(
      'a 1 m box dropped from 2 m lands after sqrt(2 h / g) and comes to rest on the ground, then sleeps',
      () {
        final shape = JoltShape.box(Vector3.all(0.5));
        final box = world.createBody(
          shape,
          JoltBodySettings(position: Vector3(0, 2.5, 0), userData: 42),
        );
        shape.release();
        expect(world.bodyCount, 2);
        expect(world.bodyUserData(box), 42);
        // A 1 m³ box at Jolt's default density of 1000 kg/m³.
        expect(world.bodyMass(box), closeTo(1000, 1e-3));

        // Jolt lets bodies sink up to the penetration slop (2 cm by default).
        world.solverSettings = world.solverSettings..penetrationSlop = 0.002;
        expect(world.solverSettings.penetrationSlop, closeTo(0.002, 1e-6));
        const dt = 1 / 120;
        double? landed;
        for (var i = 1; i <= 240; i++) {
          world.step(dt);
          final y = world.bodyState(box).centerOfMass.y;
          if (landed == null && y - 0.5 < 0.01) landed = i * dt;
        }
        final expected = math.sqrt(2 * 2.0 / 9.81);
        expect(landed, isNotNull);
        expect(
          (landed! - expected).abs(),
          lessThan(0.03),
          reason: 'landed at $landed s, expected $expected s',
        );
        final state = world.bodyState(box);
        expect(state.centerOfMass.y, closeTo(0.5, 0.005));
        expect(state.linearVelocity.length, lessThan(0.05));
        for (var i = 0; i < 240 && world.isBodyActive(box); i++) {
          world.step(dt);
        }
        expect(
          world.isBodyActive(box),
          isFalse,
          reason: 'asleep after resting',
        );
        expect(world.activeBodyCount, 0);
      },
    );

    test(
      'a resting box reports a persisted contact with the ground carrying about its weight per step',
      () {
        final shape = JoltShape.box(Vector3.all(0.5));
        final box = world.createBody(
          shape,
          JoltBodySettings(position: Vector3(0, 0.5, 0), mass: 10),
        );
        shape.release();
        const dt = 1 / 60;
        for (var i = 0; i < 10; i++) {
          world.step(dt);
        }
        final contacts = world
            .contacts()
            .where((c) => {c.bodyA, c.bodyB}.containsAll({box, ground}))
            .toList();
        expect(contacts, hasLength(1));
        final c = contacts.single;
        expect(c.persisted, isTrue);
        expect(c.pointCount, greaterThanOrEqualTo(3));
        // The normal points from A to B: up when the ground is A.
        final up = c.bodyA == ground ? c.normal : -c.normal;
        expect(up.y, closeTo(1, 1e-3));
        expect(c.impulse, closeTo(10 * 9.81 * dt, 10 * 9.81 * dt * 0.5));
      },
    );

    test(
      'a ray down from above hits the box top, a ray beside it hits the ground, a short ray misses',
      () {
        final shape = JoltShape.box(Vector3.all(0.5))..userData = 3;
        final box = world.createBody(
          shape,
          JoltBodySettings(position: Vector3(0, 0.5, 0), startActive: false),
        );
        shape.release();
        final hit = world.castRay(Vector3(0, 10, 0), Vector3(0, -20, 0))!;
        expect(hit.body, box);
        expect(hit.shape, 3);
        expect(hit.point.y, closeTo(1.0, 1e-4));
        expect(hit.fraction, closeTo(9 / 20, 1e-5));
        expect(hit.normal.y, closeTo(1, 1e-4));
        final side = world.castRay(Vector3(5, 10, 0), Vector3(0, -20, 0))!;
        expect(side.body, ground);
        expect(side.point.y, closeTo(0, 1e-4));
        expect(world.castRay(Vector3(0, 10, 0), Vector3(0, -5, 0)), isNull);
      },
    );

    test(
      'an impulse changes velocity by impulse / mass; a force is applied for one step only',
      () {
        world.gravity = Vector3.zero();
        final shape = JoltShape.sphere(0.5);
        final ball = world.createBody(
          shape,
          JoltBodySettings(
            position: Vector3(0, 5, 0),
            mass: 4,
            linearDamping: 0,
          ),
        );
        shape.release();
        world.addImpulse(ball, Vector3(8, 0, 0));
        world.step(1 / 60);
        expect(world.bodyState(ball).linearVelocity.x, closeTo(2, 1e-4));
        world.addForce(ball, Vector3(0, 0, 240));
        world.step(1 / 60);
        world.step(1 / 60);
        // 240 N on 4 kg for 1/60 s = 1 m/s, once.
        expect(world.bodyState(ball).linearVelocity.z, closeTo(1, 1e-4));
      },
    );

    test(
      'the profile matrix keeps a body that does not block the ground falling through it',
      () {
        final shape = JoltShape.box(Vector3.all(0.5));
        final ghost = world.createBody(
          shape,
          JoltBodySettings(position: Vector3(0, 0.6, 0)),
        );
        final solid = world.createBody(
          shape,
          JoltBodySettings(position: Vector3(3, 0.6, 0)),
        );
        shape.release();
        // Profile 0 blocks everything; profile 1 blocks only itself.
        world.setProfileMatrix([
          [true, false],
          [false, true],
        ]);
        world.setBodyProfiles(ground, [0]);
        world.setBodyProfiles(ghost, [1]);
        world.setBodyProfiles(solid, [0]);
        for (var i = 0; i < 60; i++) {
          world.step(1 / 60);
        }
        expect(
          world.bodyState(ghost).centerOfMass.y,
          lessThan(-2),
          reason: 'fell through',
        );
        expect(
          world.bodyState(solid).centerOfMass.y,
          closeTo(0.5, 0.02),
          reason: 'rests',
        );
      },
    );

    test(
      'bodies of one owner pass through each other unless both allow it; ignored pairs never collide',
      () {
        world.gravity = Vector3.zero();
        final shape = JoltShape.sphere(0.5);
        int pair(double z, int owner, {bool own = false}) {
          final a = world.createBody(
            shape,
            JoltBodySettings(
              position: Vector3(-2, 2, z),
              linearVelocity: Vector3(4, 0, 0),
            ),
          );
          final b = world.createBody(
            shape,
            JoltBodySettings(
              position: Vector3(2, 2, z),
              linearVelocity: Vector3(-4, 0, 0),
            ),
          );
          world.setBodyOwner(a, owner, collidesWithOwner: own);
          world.setBodyOwner(b, owner, collidesWithOwner: own);
          return a;
        }

        final sameOwner = pair(0, 1);
        final allowed = pair(3, 2, own: true);
        final ignoredA = pair(6, 0);
        world.ignorePair(ignoredA, ignoredA + 1);
        final free = pair(9, 0);
        shape.release();
        for (var i = 0; i < 60; i++) {
          world.step(1 / 60);
        }
        // Passed through: still moving +x past the start of the other one.
        expect(world.bodyState(sameOwner).centerOfMass.x, greaterThan(1.5));
        expect(world.bodyState(ignoredA).centerOfMass.x, greaterThan(1.5));
        // Collided: bounced or stopped before the middle.
        expect(world.bodyState(allowed).centerOfMass.x, lessThan(0));
        expect(world.bodyState(free).centerOfMass.x, lessThan(0));
      },
    );

    test('a body destroyed mid-simulation leaves the world', () {
      final shape = JoltShape.sphere(0.5);
      final ball = world.createBody(
        shape,
        JoltBodySettings(position: Vector3(0, 3, 0)),
      );
      shape.release();
      world.step(1 / 60);
      world.destroyBody(ball);
      expect(world.bodyCount, 1);
      world.step(1 / 60);
      expect(
        world.castRay(Vector3(0, 10, 0), Vector3(0, -20, 0))!.body,
        ground,
      );
    });

    test('the same inputs twice give identical states after 300 steps', () {
      List<double> run() {
        final w = JoltWorld(workerThreads: 2);
        final g = JoltShape.box(Vector3(50, 0.5, 50));
        w.createBody(
          g,
          JoltBodySettings(
            motionType: JoltMotionType.static_,
            position: Vector3(0, -0.5, 0),
          ),
        );
        g.release();
        final ids = <int>[];
        for (var i = 0; i < 6; i++) {
          final s = JoltShape.box(Vector3(0.3, 0.2 + i * 0.02, 0.25));
          ids.add(
            w.createBody(
              s,
              JoltBodySettings(
                position: Vector3(i * 0.1, 0.5 + i * 0.6, i * 0.07),
                rotation: Quaternion.axisAngle(
                  Vector3(1, 0.3, 0.2).normalized(),
                  0.3 * i,
                ),
              ),
            ),
          );
          s.release();
        }
        for (var i = 0; i < 300; i++) {
          w.step(1 / 120);
        }
        w.readBodyStates(ids);
        final out = w.stateBuffer
            .sublist(0, ids.length * JoltWorld.stateStride)
            .toList();
        w.dispose();
        return out;
      }

      final a = run();
      expect(run(), a);
      expect(a.any((v) => v.isNaN), isFalse);
    });
  });
}
