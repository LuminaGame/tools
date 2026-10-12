import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/src/jolt_bindings.g.dart' as b;
import 'package:flutter_jolt/src/jolt_physics.dart';
import 'package:flutter_jolt/src/jolt_world.dart';

/// How a cloth's bend constraints are built.
enum JoltClothBend { none, distance, dihedral }

/// Long range attachments: each free vertex may not move further from its
/// nearest pinned vertex than it is at rest (stops a hanging cloth from
/// stretching under its own weight).
enum JoltClothTethers { none, euclidean, geodesic }

/// How a cloth soft body is built and simulated (metres, seconds).
/// Compliances are inverse stiffness: 0 is rigid, larger is softer, null
/// switches that kind of constraint off.
class JoltClothSettings {
  JoltClothSettings({
    this.edgeCompliance = 0.0,
    this.shearCompliance = 1e-5,
    this.bendCompliance = 1e-3,
    this.bend = JoltClothBend.dihedral,
    this.tethers = JoltClothTethers.euclidean,
    this.tetherMaxDistanceMultiplier = 1.0,
    this.iterations = 8,
    this.linearDamping = 0.1,
    this.maxLinearVelocity = 100.0,
    this.friction = 0.5,
    this.restitution = 0.0,
    this.pressure = 0.0,
    this.vertexRadius = 0.01,
    this.gravityFactor = 1.0,
    this.allowSleeping = true,
    this.doubleSided = true,
  });

  double? edgeCompliance;
  double? shearCompliance;
  double? bendCompliance;
  JoltClothBend bend;
  JoltClothTethers tethers;
  double tetherMaxDistanceMultiplier;
  int iterations;
  double linearDamping;
  double maxLinearVelocity;
  double friction;
  double restitution;

  /// Gas pressure for closed meshes (0 for cloth).
  double pressure;

  /// How far vertices keep from other bodies' surfaces (m).
  double vertexRadius;
  double gravityFactor;
  bool allowSleeping;
  bool doubleSided;
}

/// Cloth soft bodies in a [JoltWorld]. A cloth collides with the world's
/// rigid bodies (it is pushed, it does not push back on static ones) and is
/// read back as world vertex positions every frame.
extension JoltWorldCloth on JoltWorld {
  /// A cloth from [vertices] (body frame, m) and [triangles] (index triples),
  /// placed at [position] / [rotation]; [inverseMasses] per vertex (0 pins a
  /// vertex where it is; null: all 1). Returns the body id.
  int createCloth(
    List<Vector3> vertices,
    List<int> triangles, {
    List<double>? inverseMasses,
    Vector3? position,
    Quaternion? rotation,
    JoltClothSettings? settings,
    int userData = 0,
  }) {
    JoltPhysics.ensureAvailable();
    if (inverseMasses != null && inverseMasses.length != vertices.length) {
      throw ArgumentError('inverseMasses needs one value per vertex');
    }
    final s = settings ?? JoltClothSettings();
    final n = vertices.length;
    final pos = calloc<Float>(n * 3);
    final inv = calloc<Float>(n);
    final idx = calloc<Uint32>(triangles.isEmpty ? 1 : triangles.length);
    final pose = calloc<Float>(7);
    final cs = calloc<b.JoltClothSettings>();
    try {
      for (var i = 0; i < n; i++) {
        pos[3 * i] = vertices[i].x;
        pos[3 * i + 1] = vertices[i].y;
        pos[3 * i + 2] = vertices[i].z;
        inv[i] = inverseMasses?[i] ?? 1.0;
      }
      for (var i = 0; i < triangles.length; i++) {
        idx[i] = triangles[i];
      }
      final p = position ?? Vector3.zero();
      final q = rotation ?? Quaternion.identity();
      pose
        ..[0] = p.x
        ..[1] = p.y
        ..[2] = p.z
        ..[3] = q.x
        ..[4] = q.y
        ..[5] = q.z
        ..[6] = q.w;
      cs.ref
        ..edge_compliance = s.edgeCompliance ?? -1
        ..shear_compliance = s.shearCompliance ?? -1
        ..bend_compliance = s.bendCompliance ?? -1
        ..bend_type = s.bend.index
        ..lra_type = s.tethers.index
        ..lra_max_distance_multiplier = s.tetherMaxDistanceMultiplier
        ..iterations = s.iterations
        ..linear_damping = s.linearDamping
        ..max_linear_velocity = s.maxLinearVelocity
        ..friction = s.friction
        ..restitution = s.restitution
        ..pressure = s.pressure
        ..vertex_radius = s.vertexRadius
        ..gravity_factor = s.gravityFactor
        ..update_position = true
        ..allow_sleeping = s.allowSleeping
        ..double_sided = s.doubleSided;
      final id = b.jolt_soft_body_create(
        handle,
        pos,
        inv,
        n,
        idx,
        triangles.length,
        pose,
        pose + 3,
        cs,
        userData,
      );
      if (id == JoltPhysics.invalidBodyId) {
        throw ArgumentError('Jolt could not build the cloth');
      }
      return id;
    } finally {
      calloc
        ..free(pos)
        ..free(inv)
        ..free(idx)
        ..free(pose)
        ..free(cs);
    }
  }

  int clothVertexCount(int body) => b.jolt_soft_body_vertex_count(handle, body);

  /// The cloth's vertex positions in the world (x, y, z per vertex, m),
  /// written into [into] when it is large enough.
  Float32List clothVertices(int body, [Float32List? into]) {
    final n = clothVertexCount(body);
    final out = into != null && into.length >= n * 3
        ? into
        : Float32List(n * 3);
    final p = calloc<Float>(n * 3 == 0 ? 1 : n * 3);
    try {
      final got = b.jolt_soft_body_get_vertices(handle, body, p, n);
      out.setRange(0, got * 3, p.asTypedList(got * 3));
      return out;
    } finally {
      calloc.free(p);
    }
  }

  /// Moves vertex [index] to world [position]; [inverseMass] 0 pins it there
  /// (an attachment that follows whatever moves it each frame). Tethers
  /// ([JoltClothTethers]) built at creation still hold a vertex within reach
  /// of the vertices pinned then.
  void setClothVertex(
    int body,
    int index,
    Vector3 position, {
    double inverseMass = 0.0,
  }) {
    final p = calloc<Float>(3);
    try {
      p
        ..[0] = position.x
        ..[1] = position.y
        ..[2] = position.z;
      b.jolt_soft_body_set_vertex(handle, body, index, p, inverseMass);
    } finally {
      calloc.free(p);
    }
  }

  /// Wind on the cloth's faces: each face is pushed along its normal by the
  /// part of [wind] (m/s, relative to the face) that hits it, at [drag] per
  /// second over [dt] (a face edge-on to the wind feels nothing, so cloth
  /// billows and flutters); call it before each step.
  void applyClothWind(
    int body,
    Vector3 wind, {
    double drag = 1.0,
    required double dt,
  }) {
    final p = calloc<Float>(3);
    try {
      p
        ..[0] = wind.x
        ..[1] = wind.y
        ..[2] = wind.z;
      b.jolt_soft_body_apply_wind(handle, body, p, drag, dt);
    } finally {
      calloc.free(p);
    }
  }

  /// Drives pinned vertices [indices] toward world [targets] (x, y, z per
  /// vertex, m) over [dt]: they arrive at the end of the next step, moving
  /// the cloth with them (an attachment that follows a moving parent).
  void driveClothVertices(
    int body,
    Uint32List indices,
    Float32List targets,
    double dt,
  ) {
    final n = indices.length;
    if (n == 0) return;
    if (targets.length < n * 3) {
      throw ArgumentError('targets needs 3 values per index');
    }
    final i = calloc<Uint32>(n);
    final t = calloc<Float>(n * 3);
    try {
      i.asTypedList(n).setAll(0, indices);
      t.asTypedList(n * 3).setAll(0, targets.sublist(0, n * 3));
      b.jolt_soft_body_drive_vertices(handle, body, i, t, n, dt);
    } finally {
      calloc
        ..free(i)
        ..free(t);
    }
  }

  /// The cloth's vertex positions and normals in another frame:
  /// [worldToLocal] takes world metres there (it may scale, e.g. to
  /// centimetres). Fills [positions] and [normals] (3 floats per vertex,
  /// grown when too small) and returns the vertex count.
  int clothLocalVertices(
    int body,
    Matrix4 worldToLocal,
    Float32List positions,
    Float32List normals,
  ) {
    final n = clothVertexCount(body);
    if (n == 0 || positions.length < n * 3 || normals.length < n * 3) return 0;
    final m = calloc<Float>(16);
    final pos = calloc<Float>(n * 3);
    final nrm = calloc<Float>(n * 3);
    try {
      for (var k = 0; k < 16; k++) {
        m[k] = worldToLocal.storage[k];
      }
      final got = b.jolt_soft_body_get_local_vertices(
        handle,
        body,
        m,
        pos,
        nrm,
        n,
      );
      positions.setRange(0, got * 3, pos.asTypedList(got * 3));
      normals.setRange(0, got * 3, nrm.asTypedList(got * 3));
      return got;
    } finally {
      calloc
        ..free(m)
        ..free(pos)
        ..free(nrm);
    }
  }

  /// Pins vertex [index] where it is ([inverseMass] 0) or frees it.
  void setClothInverseMass(int body, int index, double inverseMass) =>
      b.jolt_soft_body_set_inverse_mass(handle, body, index, inverseMass);
}
