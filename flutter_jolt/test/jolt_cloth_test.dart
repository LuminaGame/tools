import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/flutter_jolt.dart';

/// Cloth soft bodies: a pinned sheet hangs without stretching, a dropped
/// sheet drapes over a box, wind blows a free edge downwind.
void main() {
  setUpAll(() => expect(JoltPhysics.isAvailable, isTrue));

  /// An [n] x [n] grid [size] m wide in the XZ plane, centred on the origin,
  /// and its triangles.
  (List<Vector3>, List<int>) grid(int n, double size) {
    final v = <Vector3>[
      for (var z = 0; z < n; z++)
        for (var x = 0; x < n; x++)
          Vector3(
            -size / 2 + size * x / (n - 1),
            0,
            -size / 2 + size * z / (n - 1),
          ),
    ];
    final t = <int>[];
    for (var z = 0; z < n - 1; z++) {
      for (var x = 0; x < n - 1; x++) {
        final i = z * n + x;
        t.addAll([i, i + n, i + 1, i + 1, i + n, i + n + 1]);
      }
    }
    return (v, t);
  }

  Vector3 at(Float32List p, int i) =>
      Vector3(p[3 * i], p[3 * i + 1], p[3 * i + 2]);

  test(
    'a 1 m sheet pinned at two corners hangs: no NaN, edges stretch under 5 %, it settles',
    () {
      final world = JoltWorld(workerThreads: 2);
      addTearDown(world.dispose);
      const n = 11;
      final (v, t) = grid(n, 1.0);
      // Hang it vertically: rotate the XZ sheet to XY, pin the top corners.
      final inv = [
        for (var i = 0; i < v.length; i++)
          (i == n * (n - 1) || i == n * n - 1) ? 0.0 : 1.0,
      ];
      final cloth = world.createCloth(
        v,
        t,
        inverseMasses: inv,
        position: Vector3(0, 2, 0),
        rotation: Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2),
      );
      expect(world.clothVertexCount(cloth), n * n);
      for (var i = 0; i < 360; i++) {
        world.step(1 / 120);
      }
      final p = world.clothVertices(cloth);
      expect(p.every((x) => x.isFinite), isTrue);
      var worst = 0.0;
      for (var i = 0; i < t.length; i += 3) {
        for (final (a, b) in [
          (t[i], t[i + 1]),
          (t[i + 1], t[i + 2]),
          (t[i + 2], t[i]),
        ]) {
          final rest = v[a].distanceTo(v[b]);
          worst = math.max(worst, at(p, a).distanceTo(at(p, b)) / rest - 1);
        }
      }
      expect(
        worst,
        lessThan(0.05),
        reason: 'worst edge stretch ${(worst * 100).toStringAsFixed(1)} %',
      );
      // The pinned corners stay put; the free bottom hangs below them.
      final pinned = at(p, n * (n - 1));
      final bottom = at(p, 0);
      expect(bottom.y, lessThan(pinned.y - 0.8));
      final before = world.clothVertices(cloth);
      for (var i = 0; i < 60; i++) {
        world.step(1 / 120);
      }
      final after = world.clothVertices(cloth);
      var moved = 0.0;
      for (var i = 0; i < n * n; i++) {
        moved = math.max(moved, at(before, i).distanceTo(at(after, i)));
      }
      expect(moved, lessThan(0.01), reason: 'settled');
    },
  );

  test('a sheet dropped onto a box drapes over it without passing through', () {
    final world = JoltWorld(workerThreads: 2);
    addTearDown(world.dispose);
    final ground = JoltShape.box(Vector3(5, 0.5, 5));
    world.createBody(
      ground,
      JoltBodySettings(
        motionType: JoltMotionType.static_,
        position: Vector3(0, -0.5, 0),
      ),
    );
    ground.release();
    final box = JoltShape.box(Vector3.all(0.25), convexRadius: 0);
    world.createBody(
      box,
      JoltBodySettings(
        motionType: JoltMotionType.static_,
        position: Vector3(0, 0.25, 0),
      ),
    );
    box.release();
    final (v, t) = grid(15, 1.2);
    final cloth = world.createCloth(
      v,
      t,
      position: Vector3(0, 0.8, 0),
      settings: JoltClothSettings(
        tethers: JoltClothTethers.none,
        bendCompliance: 1.0,
      ),
    );
    for (var i = 0; i < 360; i++) {
      world.step(1 / 120);
    }
    final p = world.clothVertices(cloth);
    var inside = 0.0, highest = -1.0, lowest = 10.0;
    for (var i = 0; i < p.length ~/ 3; i++) {
      final q = at(p, i);
      highest = math.max(highest, q.y);
      lowest = math.min(lowest, q.y);
      final d = math.min(
        0.25 - q.x.abs(),
        math.min(0.5 - q.y, 0.25 - q.z.abs()),
      );
      if (q.y > 0 && q.y < 0.5) inside = math.max(inside, d);
    }
    expect(inside, lessThan(0.02), reason: 'no vertex deep inside the box');
    expect(
      highest,
      closeTo(0.5, 0.05),
      reason: 'the middle lies on the box top',
    );
    expect(lowest, lessThan(0.2), reason: 'the edges hang down its sides');
  });

  test(
    'wind of 5 m/s along +X blows the free edge of a hanging sheet downwind; vertices can be pinned anew',
    () {
      final world = JoltWorld(workerThreads: 0);
      addTearDown(world.dispose);
      const n = 9;
      final (v, t) = grid(n, 1.0);
      final inv = [
        for (var i = 0; i < v.length; i++) i >= n * (n - 1) ? 0.0 : 1.0,
      ];
      final cloth = world.createCloth(
        v,
        t,
        inverseMasses: inv,
        position: Vector3(0, 2, 0),
        rotation:
            Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2) *
            Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2),
        // Tethers would pull a re-pinned vertex back within reach of the top.
        settings: JoltClothSettings(tethers: JoltClothTethers.none),
      );
      double edgeX() {
        final p = world.clothVertices(cloth);
        var x = 0.0;
        for (var i = 0; i < n; i++) {
          x += p[3 * i];
        }
        return x / n;
      }

      for (var i = 0; i < 120; i++) {
        world.step(1 / 120);
      }
      final calm = edgeX();
      for (var i = 0; i < 240; i++) {
        world.applyClothWind(cloth, Vector3(5, 0, 0), drag: 2, dt: 1 / 120);
        world.step(1 / 120);
      }
      expect(edgeX() - calm, greaterThan(0.2), reason: 'blown downwind');
      // Pin the bottom-left vertex 1 m below its pinned top.
      world.setClothVertex(cloth, 0, Vector3(0, 0.5, 0));
      world.step(1 / 120);
      final p = world.clothVertices(cloth);
      expect(at(p, 0).distanceTo(Vector3(0, 0.5, 0)), lessThan(1e-4));
    },
  );

  test(
    'driven pins drag a hanging sheet along; local read-back gives unit normals in the caller frame (cm)',
    () {
      final world = JoltWorld(workerThreads: 0);
      addTearDown(world.dispose);
      const n = 7;
      final (v, t) = grid(n, 1.0);
      final top = [for (var i = n * (n - 1); i < n * n; i++) i];
      final inv = [
        for (var i = 0; i < v.length; i++) top.contains(i) ? 0.0 : 1.0,
      ];
      final cloth = world.createCloth(
        v,
        t,
        inverseMasses: inv,
        position: Vector3(0, 2, 0),
        rotation: Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2),
      );
      final start = world.clothVertices(cloth);
      // Move the pins 1 m along +X over one second.
      for (var step = 1; step <= 120; step++) {
        final targets = Float32List(top.length * 3);
        for (var k = 0; k < top.length; k++) {
          final p0 = at(start, top[k]);
          targets
            ..[3 * k] = p0.x + step / 120
            ..[3 * k + 1] = p0.y
            ..[3 * k + 2] = p0.z;
        }
        world.driveClothVertices(
          cloth,
          Uint32List.fromList(top),
          targets,
          1 / 120,
        );
        world.step(1 / 120);
      }
      final moved = world.clothVertices(cloth);
      expect(
        at(moved, top.first).x - at(start, top.first).x,
        closeTo(1.0, 0.01),
      );
      // A driven pin keeps its velocity until driven again: hold it still.
      final hold = Float32List(top.length * 3);
      for (var k = 0; k < top.length; k++) {
        hold.setRange(3 * k, 3 * k + 3, at(moved, top[k]).storage);
      }
      world.driveClothVertices(cloth, Uint32List.fromList(top), hold, 1 / 120);
      for (var i = 0; i < 120; i++) {
        world.step(1 / 120);
      }
      final settled = world.clothVertices(cloth);
      expect(
        at(settled, 0).x - at(start, 0).x,
        closeTo(1.0, 0.1),
        reason: 'the bottom follows the pins',
      );
      // Read back in centimetres, shifted 2 m down.
      final toCm = Matrix4.diagonal3Values(100, 100, 100)
        ..translateByDouble(0.0, -2.0, 0.0, 1.0);
      final pos = Float32List(n * n * 3), nrm = Float32List(n * n * 3);
      expect(world.clothLocalVertices(cloth, toCm, pos, nrm), n * n);
      expect(
        pos[3 * top.first + 1],
        closeTo((at(settled, top.first).y - 2) * 100, 0.01),
      );
      for (var i = 0; i < n * n; i++) {
        expect(at(nrm, i).length, closeTo(1, 1e-4));
      }
      // A hanging sheet faces horizontally.
      expect(at(nrm, n * 3 + 3).y.abs(), lessThan(0.3));
      world.setClothInverseMass(cloth, 0, 0);
      world.step(1 / 120);
    },
  );
}
