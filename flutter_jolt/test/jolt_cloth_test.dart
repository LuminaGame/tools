import 'dart:math' as math;
import 'dart:typed_data';

import 'support/test_api.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/flutter_jolt.dart';

/// Cloth soft bodies: a pinned sheet hangs without stretching, a dropped
/// sheet drapes over a box, wind blows a free edge downwind.
void main() {
  setUpAll(() => expect(JoltPhysics.isAvailable, isTrue, reason: '${JoltPhysics.loadError}'));

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

  test(
    'a skinned strip follows its joint: hard-skinned vertices exactly, free ones within their max distance',
    () {
      final world = JoltWorld(workerThreads: 0);
      addTearDown(world.dispose);
      // A 1 m strip hanging along -Y from y = 0, in its creation frame at the
      // origin; joint 0 at the top (hard skin), joint 1 at the bottom.
      const n = 9;
      final (flat, t) = grid(n, 1.0);
      final v = [for (final p in flat) Vector3(p.x, -(p.z + 0.5), 0)];
      final count = v.length;
      final joints = Uint32List(count * 4),
          weights = Float32List(count * 4),
          maxD = Float32List(count);
      for (var i = 0; i < count; i++) {
        final down = -v[i].y; // 0 at the top, 1 at the bottom
        joints[4 * i] = 0;
        joints[4 * i + 1] = 1;
        weights[4 * i] = 1 - down;
        weights[4 * i + 1] = down;
        maxD[i] = down < 1e-6 ? 0 : 0.2 * down;
      }
      final binds = [
        Matrix4.identity(),
        Matrix4.translationValues(0, -1, 0)..invert(),
      ];
      final cloth = world.createCloth(
        v,
        t,
        skin: JoltClothSkin(
          inverseBinds: binds,
          joints: joints,
          weights: weights,
          maxDistances: maxD,
        ),
      );
      Float32List pose(double x) => Float32List.fromList([
        ...Matrix4.translationValues(x, 2, 0).storage,
        ...Matrix4.translationValues(x, 1, 0).storage,
      ]);
      world.skinCloth(cloth, pose(0), hardSkinAll: true);
      var p = world.clothVertices(cloth);
      expect(
        at(p, 0).y,
        closeTo(2, 1e-4),
        reason: 'hard skinned to the joint at y = 2',
      );
      // Move the skeleton 1 m along +X over a second.
      for (var step = 1; step <= 120; step++) {
        world.skinCloth(cloth, pose(step / 120));
        world.step(1 / 120);
      }
      p = world.clothVertices(cloth);
      for (var i = 0; i < count; i++) {
        final down = -v[i].y;
        final skinned = Vector3(v[i].x + 1, 2 + v[i].y, 0);
        expect(
          at(p, i).distanceTo(skinned),
          lessThan(0.2 * down + 0.01),
          reason: 'vertex $i within its max distance',
        );
      }
    },
  );

  test(
    'a cloth ignores the bodies of its owner unless they are its colliders',
    () {
      for (final collider in [false, true]) {
        final world = JoltWorld(workerThreads: 0);
        final box = JoltShape.box(Vector3(0.3, 0.3, 0.3));
        final boxId = world.createBody(
          box,
          JoltBodySettings(
            motionType: JoltMotionType.static_,
            position: Vector3(0, 0.3, 0),
          ),
        );
        box.release();
        world.setBodyOwner(boxId, 5);
        world.setBodyClothCollider(boxId, collider);
        final (v, t) = grid(9, 1.0);
        final cloth = world.createCloth(
          v,
          t,
          position: Vector3(0, 1.0, 0),
          settings: JoltClothSettings(tethers: JoltClothTethers.none),
        );
        world.setBodyOwner(cloth, 5);
        for (var i = 0; i < 120; i++) {
          world.step(1 / 120);
        }
        final p = world.clothVertices(cloth);
        final centre = at(p, 40);
        if (collider) {
          expect(centre.y, greaterThan(0.55), reason: 'rests on its collider');
        } else {
          expect(
            centre.y,
            lessThan(0.0),
            reason: 'falls through the box of its owner',
          );
        }
        world.dispose();
      }
    },
  );
  test(
    'carrying a cloth along a motion moves its free vertices that far and leaves pinned ones',
    () {
      final world = JoltWorld(workerThreads: 1);
      addTearDown(world.dispose);
      final (v, t) = grid(5, 1.0);
      final inv = [for (var i = 0; i < v.length; i++) i == 0 ? 0.0 : 1.0];
      final cloth = world.createCloth(
        v,
        t,
        inverseMasses: inv,
        position: Vector3(0, 3, 0),
      );
      final before = Float32List.fromList(world.clothVertices(cloth));
      // Turn 180 degrees about the vertical through (1, 0, 0), then go half way.
      final delta = Matrix4.translation(Vector3(1, 0, 0))
        ..rotateY(math.pi)
        ..translateByVector3(Vector3(-1, 0, 0));
      world.carryCloth(cloth, delta, 1);
      final full = world.clothVertices(cloth);
      expect(
        at(full, 0).distanceTo(at(before, 0)),
        lessThan(1e-5),
        reason: 'pinned',
      );
      for (var i = 1; i < v.length; i++) {
        expect(
          at(full, i).distanceTo(delta.transform3(at(before, i))),
          lessThan(1e-4),
        );
      }
      world.carryCloth(cloth, Matrix4.translation(Vector3(0, 0, 2)), 0.25);
      final quarter = world.clothVertices(cloth);
      for (var i = 1; i < v.length; i++) {
        expect(at(quarter, i).z - at(full, i).z, closeTo(0.5, 1e-4));
      }
      // A teleport takes the pinned vertex along too.
      world.carryCloth(
        cloth,
        Matrix4.translation(Vector3(5, 0, 0)),
        1,
        includePinned: true,
      );
      expect(world.clothVertices(cloth)[0] - quarter[0], closeTo(5, 1e-4));
    },
  );
  test(
    'with self-collision a sheet falling on another piece of the same cloth rests on it',
    () {
      /// The lowest the upper sheet gets above the lower one (m).
      double gap(bool selfCollision) {
        final world = JoltWorld(workerThreads: 1);
        addTearDown(world.dispose);
        const n = 9;
        final (lower, t) = grid(n, 0.6);
        final upper = [for (final v in lower) v + Vector3(0.02, 0.15, 0.03)];
        final triangles = [...t, for (final i in t) i + lower.length];
        // The lower sheet hangs flat from its four corners.
        final corners = {0, n - 1, n * (n - 1), n * n - 1};
        final cloth = world.createCloth(
          [...lower, ...upper],
          triangles,
          inverseMasses: [
            for (var i = 0; i < 2 * lower.length; i++)
              corners.contains(i) ? 0.0 : 1.0,
          ],
          position: Vector3(0, 1, 0),
          settings: JoltClothSettings(vertexRadius: 0.005),
        );
        if (selfCollision) world.setClothSelfCollision(cloth, 0.02);
        for (var i = 0; i < 240; i++) {
          world.step(1 / 120);
        }
        final p = world.clothVertices(cloth);
        var lowest = double.infinity;
        for (var i = 0; i < lower.length; i++) {
          // The upper vertex over the middle of the lower sheet.
          final u = at(p, lower.length + i), l = at(p, i);
          lowest = math.min(lowest, u.y - l.y);
        }
        return lowest;
      }

      final without = gap(false), with_ = gap(true);
      // ignore: avoid_print
      print(
        'upper above lower: without ${without.toStringAsFixed(3)} m, with ${with_.toStringAsFixed(3)} m',
      );
      expect(
        without,
        lessThan(0),
        reason: 'without it the upper sheet falls through',
      );
      expect(with_, greaterThan(0.01));
    },
  );

  group('tetrahedral volume constraints', () {
    /// A 0.4 m cube of soft tissue: its eight corners and its centre, the
    /// twelve outward surface triangles, and twelve tetrahedra (the centre
    /// and each surface triangle).
    (List<Vector3>, List<int>, List<int>) cube() {
      const h = 0.2;
      final v = <Vector3>[
        for (final z in [-h, h])
          for (final y in [-h, h])
            for (final x in [-h, h]) Vector3(x, y, z),
        Vector3.zero(),
      ];
      // Corner index: x + 2y + 4z.
      const quads = [
        [0, 2, 3, 1], [4, 5, 7, 6], // -z, +z
        [0, 1, 5, 4], [2, 6, 7, 3], // -y, +y
        [0, 4, 6, 2], [1, 3, 7, 5], // -x, +x
      ];
      final t = <int>[for (final q in quads) ...[q[0], q[1], q[2], q[0], q[2], q[3]]];
      final tets = <int>[for (var i = 0; i < t.length; i += 3) ...[8, t[i], t[i + 1], t[i + 2]]];
      return (v, t, tets);
    }

    double volume(Float32List p, List<int> tets) {
      Vector3 at(int i) => Vector3(p[3 * i], p[3 * i + 1], p[3 * i + 2]);
      var sum = 0.0;
      for (var i = 0; i < tets.length; i += 4) {
        final a = at(tets[i]);
        sum += (at(tets[i + 1]) - a).cross(at(tets[i + 2]) - a).dot(at(tets[i + 3]) - a) / 6;
      }
      return sum.abs();
    }

    /// The cube's volume after it fell on the ground and settled, as a
    /// fraction of its rest volume.
    double settle({required bool withTetrahedra}) {
      final world = JoltWorld(workerThreads: 2);
      addTearDown(world.dispose);
      final ground = JoltShape.box(Vector3(5, 0.5, 5));
      world.createBody(ground, JoltBodySettings(motionType: JoltMotionType.static_, position: Vector3(0, -0.5, 0)));
      ground.release();
      final (v, t, tets) = cube();
      // Very soft edges and no bend or shear: on its own the mesh slumps.
      final body = world.createCloth(
        v,
        t,
        position: Vector3(0, 0.5, 0),
        settings: JoltClothSettings(
          edgeCompliance: 5e-2,
          shearCompliance: null,
          bendCompliance: null,
          bend: JoltClothBend.none,
          tethers: JoltClothTethers.none,
          doubleSided: false,
          allowSleeping: false,
        ),
        tetrahedra: withTetrahedra ? tets : null,
      );
      final rest = volume(world.clothVertices(body), tets);
      for (var i = 0; i < 240; i++) {
        world.step(1 / 120);
      }
      final p = world.clothVertices(body);
      expect(p.every((x) => x.isFinite), isTrue);
      return volume(p, tets) / rest;
    }

    test('keep a soft body\'s volume when it lands; without them the same mesh slumps', () {
      final kept = settle(withTetrahedra: true);
      final slumped = settle(withTetrahedra: false);
      expect(kept, greaterThan(0.9), reason: 'volume constraints at compliance 0');
      expect(slumped, lessThan(kept - 0.2), reason: 'the edges alone do not hold the volume');
    });

    test('a compliance per volume is that compliance times six times each tetrahedron rest volume', () {
      // Every tetrahedron of the cube is the same: a twelfth of 0.4³ m³.
      const sixVolume = 6 * 0.4 * 0.4 * 0.4 / 12;
      Float32List settled({required double compliance, required bool perVolume}) {
        final world = JoltWorld(workerThreads: 0);
        addTearDown(world.dispose);
        final ground = JoltShape.box(Vector3(5, 0.5, 5));
        world.createBody(ground, JoltBodySettings(motionType: JoltMotionType.static_, position: Vector3(0, -0.5, 0)));
        ground.release();
        final (v, t, tets) = cube();
        final body = world.createCloth(
          v,
          t,
          position: Vector3(0, 0.5, 0),
          settings: JoltClothSettings(
            edgeCompliance: 5e-2,
            shearCompliance: null,
            bendCompliance: null,
            bend: JoltClothBend.none,
            tethers: JoltClothTethers.none,
            volumeCompliance: compliance,
            volumeCompliancePerVolume: perVolume,
            doubleSided: false,
            allowSleeping: false,
          ),
          tetrahedra: tets,
        );
        for (var i = 0; i < 240; i++) {
          world.step(1 / 120);
        }
        return world.clothVertices(body);
      }

      final scaled = settled(compliance: 1e-4, perVolume: true);
      final same = settled(compliance: 1e-4 * sixVolume, perVolume: false);
      final rigid = settled(compliance: 0, perVolume: false);
      var gap = 0.0, softer = 0.0;
      for (var i = 0; i < scaled.length; i++) {
        gap = math.max(gap, (scaled[i] - same[i]).abs());
        softer = math.max(softer, (scaled[i] - rigid[i]).abs());
      }
      expect(gap, lessThan(1e-4));
      expect(softer, greaterThan(1e-3), reason: 'the compliance does soften it');
    });

    test('a tetrahedron with an index past the vertices or a repeated vertex is refused', () {
      final world = JoltWorld(workerThreads: 1);
      addTearDown(world.dispose);
      final (v, t, _) = cube();
      expect(() => world.createCloth(v, t, tetrahedra: [0, 1, 2, 99]), throwsArgumentError);
      expect(() => world.createCloth(v, t, tetrahedra: [0, 1, 1, 2]), throwsArgumentError);
      expect(() => world.createCloth(v, t, tetrahedra: [0, 1, 2]), throwsArgumentError);
    });
  });
}
