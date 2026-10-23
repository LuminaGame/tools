import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/src/jolt_ffi.dart';
import 'package:flutter_jolt/src/jolt_ffi_package.dart';
import 'package:flutter_jolt/src/jolt_c.dart' as b;
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
    this.volumeCompliance = 0.0,
    this.volumeCompliancePerVolume = false,
    this.edgeCompliancePerLength = false,
    this.updatePosition = true,
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

  /// Compliance of the tetrahedral volume constraints
  /// ([JoltWorldCloth.createCloth]'s `tetrahedra`): 0 keeps every
  /// tetrahedron's rest volume rigidly, larger lets it squash.
  double volumeCompliance;

  /// [volumeCompliance] per unit of each tetrahedron's size: its compliance
  /// is [volumeCompliance] times six times its rest volume (m³), so
  /// tetrahedra of any size are the same material (one compliance for all
  /// makes the small ones far softer, and squashed past flat they turn
  /// inside out).
  bool volumeCompliancePerVolume;

  /// [edgeCompliance], [shearCompliance] and a distance [bendCompliance]
  /// per centimetre of each constraint's rest length: the same material
  /// whatever the mesh's cut (one compliance for all makes finely cut skin
  /// far softer, and it buckles).
  bool edgeCompliancePerLength;

  /// Whether the body's position follows its vertices' centre of mass as
  /// they move (the default). Off, the body's frame stays where the cloth
  /// was created, so a skinned cloth's one still joint keeps meaning the
  /// same world place (its skinned targets drifted with the frame, and the
  /// cloth was dragged after them).
  bool updatePosition;

  /// How far vertices keep from other bodies' surfaces (m).
  double vertexRadius;
  double gravityFactor;
  bool allowSleeping;
  bool doubleSided;
}

/// How a cloth is skinned to a skeleton (a garment on a character), in the
/// cloth's creation frame (metres): one inverse bind matrix per joint, up to
/// four joints and weights per vertex, and per vertex how far it may leave
/// its skinned position ([maxDistances], 0 hard-skins it) and an optional
/// backstop behind it.
class JoltClothSkin {
  JoltClothSkin({
    required this.inverseBinds,
    required this.joints,
    required this.weights,
    required this.maxDistances,
    this.backstopDistances,
    this.backstopRadius = 0.4,
  });

  final List<Matrix4> inverseBinds;

  /// Four entries per vertex (indices into [inverseBinds]).
  final Uint32List joints;
  final Float32List weights;
  final Float32List maxDistances;
  final Float32List? backstopDistances;
  final double backstopRadius;
}

/// Cloth soft bodies in a [JoltWorld]. A cloth collides with the world's
/// rigid bodies (it is pushed, it does not push back on static ones) and is
/// read back as world vertex positions every frame.
extension JoltWorldCloth on JoltWorld {
  /// A cloth from [vertices] (body frame, m) and [triangles] (index triples),
  /// placed at [position] / [rotation]; [inverseMasses] per vertex (0 pins a
  /// vertex where it is; null: all 1). Returns the body id.
  ///
  /// [tetrahedra] (index quadruples) make it a volumetric soft body: each
  /// tetrahedron keeps its rest volume ([JoltClothSettings.volumeCompliance]),
  /// so soft tissue squashes and comes back instead of slumping. The
  /// triangles stay the surface; the tetrahedra may use inner vertices.
  int createCloth(
    List<Vector3> vertices,
    List<int> triangles, {
    List<double>? inverseMasses,
    Vector3? position,
    Quaternion? rotation,
    JoltClothSettings? settings,
    JoltClothSkin? skin,
    List<int>? tetrahedra,
    int userData = 0,
  }) {
    JoltPhysics.ensureAvailable();
    if (tetrahedra != null) _checkTetrahedra(tetrahedra, vertices.length);
    if (skin != null &&
        (skin.joints.length < vertices.length * 4 ||
            skin.weights.length < vertices.length * 4 ||
            skin.maxDistances.length < vertices.length)) {
      throw ArgumentError(
        'skin needs four joints and weights and a max distance per vertex',
      );
    }
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
    final tetCount = (tetrahedra?.length ?? 0) ~/ 4;
    final tets = calloc<Uint32>(tetCount == 0 ? 1 : tetCount * 4);
    try {
      for (var i = 0; i < tetCount * 4; i++) {
        tets[i] = tetrahedra![i];
      }
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
        ..volume_compliance = s.volumeCompliance
        ..volume_compliance_per_volume = s.volumeCompliancePerVolume
        ..edge_compliance_per_length = s.edgeCompliancePerLength
        ..vertex_radius = s.vertexRadius
        ..gravity_factor = s.gravityFactor
        ..update_position = s.updatePosition
        ..allow_sleeping = s.allowSleeping
        ..double_sided = s.doubleSided;
      final id = skin == null && tetCount > 0
          ? b.jolt_soft_body_create_volume(
              handle,
              pos,
              inv,
              n,
              idx,
              triangles.length,
              tets,
              tetCount,
              pose,
              pose + 3,
              cs,
              nullptr,
              userData,
            )
          : skin == null
          ? b.jolt_soft_body_create(
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
            )
          : _createSkinned(
              pos,
              inv,
              n,
              idx,
              triangles.length,
              pose,
              cs,
              skin,
              userData,
              tets,
              tetCount,
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
        ..free(cs)
        ..free(tets);
    }
  }

  static void _checkTetrahedra(List<int> tetrahedra, int vertexCount) {
    if (tetrahedra.length % 4 != 0) {
      throw ArgumentError(
        'tetrahedra needs four vertex indices per tetrahedron',
      );
    }
    for (var i = 0; i < tetrahedra.length; i += 4) {
      final q = tetrahedra.sublist(i, i + 4);
      if (q.any((v) => v < 0 || v >= vertexCount)) {
        throw ArgumentError(
          'tetrahedron ${i ~/ 4} names a vertex past the $vertexCount vertices: $q',
        );
      }
      if (q.toSet().length != 4) {
        throw ArgumentError('tetrahedron ${i ~/ 4} repeats a vertex: $q');
      }
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

  /// Carries a cloth along a rigid motion [delta] (world, metres): every free
  /// vertex moves [amount] (0..1) of the way to where [delta] takes it and
  /// its velocity turns as much. A character that moved or turned this step
  /// takes its garment along by `1 − inertia`; 1 is a teleport.
  /// [includePinned] moves the pinned vertices too (all the way).
  void carryCloth(
    int body,
    Matrix4 delta,
    double amount, {
    bool includePinned = false,
  }) {
    if (amount <= 0) return;
    final m = calloc<Float>(16);
    try {
      m.asTypedList(16).setAll(0, delta.storage);
      b.jolt_soft_body_carry(handle, body, m, amount, includePinned);
    } finally {
      calloc.free(m);
    }
  }

  /// Self-collision for cloth [body]: after every step a vertex closer than
  /// [distance] (m) to one of its triangles is pushed out (the triangle
  /// back) and stops approaching it, except where it is that close at rest.
  /// 0 switches it off.
  void setClothSelfCollision(int body, double distance) =>
      b.jolt_soft_body_set_self_collision(handle, body, distance);

  /// Pins vertex [index] where it is ([inverseMass] 0) or frees it.
  void setClothInverseMass(int body, int index, double inverseMass) =>
      b.jolt_soft_body_set_inverse_mass(handle, body, index, inverseMass);

  int _createSkinned(
    Pointer<Float> pos,
    Pointer<Float> inv,
    int n,
    Pointer<Uint32> idx,
    int indexCount,
    Pointer<Float> pose,
    Pointer<b.JoltClothSettings> cs,
    JoltClothSkin skin,
    int userData,
    Pointer<Uint32> tets,
    int tetCount,
  ) {
    final jointCount = skin.inverseBinds.length;
    final binds = calloc<Float>(math.max(1, jointCount) * 16);
    final joints = calloc<Uint32>(n * 4);
    final weights = calloc<Float>(n * 4);
    final maxD = calloc<Float>(n);
    final back = calloc<Float>(n);
    final sk = calloc<b.JoltClothSkin>();
    try {
      for (var j = 0; j < jointCount; j++) {
        binds
            .asTypedList(jointCount * 16)
            .setRange(
              16 * j,
              16 * j + 16,
              skin.inverseBinds[j].storage.map((v) => v),
            );
      }
      joints.asTypedList(n * 4).setAll(0, skin.joints.sublist(0, n * 4));
      weights.asTypedList(n * 4).setAll(0, skin.weights.sublist(0, n * 4));
      maxD.asTypedList(n).setAll(0, skin.maxDistances.sublist(0, n));
      final backstop = skin.backstopDistances;
      back
          .asTypedList(n)
          .setAll(
            0,
            backstop == null
                ? (Float32List(n)..fillRange(0, n, 1e30))
                : backstop.sublist(0, n),
          );
      sk.ref
        ..inverse_binds = binds
        ..joint_count = jointCount
        ..joints = joints
        ..weights = weights
        ..max_distances = maxD
        ..backstop_distances = back
        ..backstop_radius = skin.backstopRadius;
      return tetCount > 0
          ? b.jolt_soft_body_create_volume(
              handle,
              pos,
              inv,
              n,
              idx,
              indexCount,
              tets,
              tetCount,
              pose,
              pose + 3,
              cs,
              sk,
              userData,
            )
          : b.jolt_skinned_cloth_create(
              handle,
              pos,
              inv,
              n,
              idx,
              indexCount,
              pose,
              pose + 3,
              cs,
              sk,
              userData,
            );
    } finally {
      calloc
        ..free(binds)
        ..free(joints)
        ..free(weights)
        ..free(maxD)
        ..free(back)
        ..free(sk);
    }
  }

  /// Poses a skinned cloth's skeleton: [jointWorld] holds one column-major
  /// 4x4 matrix per joint in the world (metres), 16 floats each, in the
  /// order of [JoltClothSkin.inverseBinds]. [hardSkinAll] puts every vertex
  /// on its skinned position (after creating it, or a teleport).
  void skinCloth(int body, Float32List jointWorld, {bool hardSkinAll = false}) {
    final count = jointWorld.length ~/ 16;
    if (count == 0) return;
    final m = calloc<Float>(count * 16);
    try {
      m.asTypedList(count * 16).setAll(0, jointWorld.sublist(0, count * 16));
      b.jolt_soft_body_skin(handle, body, m, count, hardSkinAll);
    } finally {
      calloc.free(m);
    }
  }

  /// Marks [body] as a collider for cloths of its owner (a character's limb
  /// capsules for its garment); a cloth ignores its owner's other bodies.
  void setBodyClothCollider(int body, bool clothCollider) =>
      b.jolt_body_set_cloth_collider(handle, body, clothCollider);
}
