import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/flutter_jolt.dart';

/// Many worlds in a row, each a jointed chain of capsules of one owner
/// falling onto a ground box on two worker threads, with collision
/// profiles, ignored pairs, contacts read every step and the world disposed
/// while bodies still touch: nothing crashes and nothing becomes NaN.
void main() {
  setUpAll(() => expect(JoltPhysics.isAvailable, isTrue));

  test(
    'twenty jointed chains on worker threads stay finite and dispose cleanly',
    () {
      for (var run = 0; run < 20; run++) {
        final world = JoltWorld(workerThreads: 2);
        final ground = JoltShape.box(Vector3(20, 0.5, 20));
        final g = world.createBody(
          ground,
          JoltBodySettings(
            motionType: JoltMotionType.static_,
            position: Vector3(0, -0.5, 0),
          ),
        );
        ground.release();
        world.setProfileMatrix([
          [true, true],
          [true, false],
        ]);
        world.setBodyProfiles(g, [0]);
        final ids = <int>[];
        for (var i = 0; i < 16; i++) {
          final s = JoltShape.capsule(0.12, 0.06)..userData = 0;
          final c = JoltShape.offsetCenterOfMass(s, Vector3(0, 0.01, 0));
          s.release();
          final id = world.createBody(
            c,
            JoltBodySettings(
              position: Vector3(i * 0.3, 1.5 + (i % 3) * 0.05, 0),
              rotation: Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2),
              mass: 5,
              inertia: Matrix3.identity()..scale(0.05),
            ),
          );
          c.release();
          world.setBodyOwner(id, 7, collidesWithOwner: true);
          world.setBodyProfiles(id, [i.isEven ? 0 : 1]);
          world.setBodyMaterial(
            id,
            friction: 0.9,
            staticFriction: 1.0,
            restitution: 0,
          );
          ids.add(id);
        }
        for (var i = 1; i < ids.length; i++) {
          world.ignorePair(ids[i - 1], ids[i]);
          final settings = JoltSwingTwistSettings(
            positionA: Vector3(0, 0.15, 0),
            twistAxisA: Vector3(0, 1, 0),
            planeAxisA: Vector3(1, 0, 0),
            positionB: Vector3(0, -0.15, 0),
            twistAxisB: Vector3(0, 1, 0),
            planeAxisB: Vector3(1, 0, 0),
            normalHalfCone: 0.6,
            planeHalfCone: 0.4,
            twistMin: -0.3,
            twistMax: 0.3,
            maxFrictionTorque: 0.5,
          );
          final c = i % 4 == 0
              ? world.addHinge(
                  ids[i - 1],
                  ids[i],
                  JoltHingeSettings(
                    positionA: Vector3(0, 0.15, 0),
                    hingeAxisA: Vector3(0, 0, 1),
                    normalAxisA: Vector3(1, 0, 0),
                    positionB: Vector3(0, -0.15, 0),
                    hingeAxisB: Vector3(0, 0, 1),
                    normalAxisB: Vector3(1, 0, 0),
                    limitMin: -1,
                    limitMax: 0.5,
                  ),
                )
              : world.addSwingTwist(ids[i - 1], ids[i], settings);
          c.setSolverSteps(velocity: 20, position: 10);
          if (i.isOdd) {
            c.setPositionMotor(
              Quaternion.identity(),
              frequency: 10,
              maxTorque: 50,
            );
          }
        }
        var contacts = 0;
        for (var step = 0; step < 240; step++) {
          if (step % 30 == 0) {
            world.addImpulse(ids[step % ids.length], Vector3(0, 5, 3));
          }
          world.step(1 / 120);
          contacts += world.contacts().length;
          world.readBodyStates(ids);
        }
        final buffer = world.stateBuffer;
        for (var i = 0; i < ids.length * JoltWorld.stateStride; i++) {
          expect(buffer[i].isFinite, isTrue, reason: 'run $run value $i');
        }
        expect(contacts, greaterThan(0));
        world.dispose();
      }
    },
  );
}
