import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/src/jolt_ffi.dart';
import 'package:flutter_jolt/src/jolt_ffi_package.dart';
import 'package:flutter_jolt/src/jolt_c.dart' as b;
import 'package:flutter_jolt/src/jolt_constraint.dart';
import 'package:flutter_jolt/src/jolt_physics.dart';
import 'package:flutter_jolt/src/jolt_shape.dart';
import 'package:flutter_jolt/src/jolt_types.dart';

/// A Jolt Physics world: bodies, constraints, contacts and ray casts, in
/// metres, kilograms and seconds. Bodies are named by their Jolt body id.
///
/// Collision filtering: every sub-shape of a body has a profile
/// ([setBodyProfiles]) and the world's profile matrix ([setProfileMatrix])
/// says which profiles block each other; bodies of one owner
/// ([setBodyOwner]) collide only when both allow it, and [ignorePair] pairs
/// never collide.
///
/// [dispose] frees the world; a world is not shared between isolates.
class JoltWorld {
  JoltWorld._(this._handle);

  /// A world for up to [maxBodies] bodies, stepped on [workerThreads] worker
  /// threads (negative: one per hardware thread but one; 0: the calling
  /// thread only).
  factory JoltWorld({
    int maxBodies = 65536,
    int maxBodyPairs = 65536,
    int maxContactConstraints = 16384,
    int workerThreads = -1,
    Vector3? gravity,
  }) {
    JoltPhysics.ensureAvailable();
    final s = calloc<b.JoltWorldSettings>();
    try {
      s.ref
        ..max_bodies = maxBodies
        ..max_body_pairs = maxBodyPairs
        ..max_contact_constraints = maxContactConstraints
        ..worker_threads = workerThreads
        ..temp_allocator_bytes = 0;
      final world = JoltWorld._(b.jolt_world_create(s));
      world.gravity = gravity ?? Vector3(0, -9.81, 0);
      return world;
    } finally {
      calloc.free(s);
    }
  }

  Pointer<b.JoltWorld> _handle;
  final Pointer<Float> _f = calloc<Float>(16);
  Pointer<Double> _states = nullptr;
  int _stateCapacity = 0;
  Pointer<Uint32> _ids = nullptr;
  Pointer<b.JoltContact> _contacts = nullptr;
  int _contactCapacity = 0;
  final List<JoltConstraint> _constraints = [];

  Pointer<b.JoltWorld> get handle {
    if (_handle == nullptr) throw StateError('JoltWorld used after dispose()');
    return _handle;
  }

  bool get isDisposed => _handle == nullptr;

  // --- World ------------------------------------------------------------------------

  Vector3 get gravity {
    b.jolt_world_get_gravity(handle, _f);
    return Vector3(_f[0], _f[1], _f[2]);
  }

  set gravity(Vector3 g) => b.jolt_world_set_gravity(handle, g.x, g.y, g.z);

  JoltSolverSettings get solverSettings {
    final s = calloc<b.JoltSolverSettings>();
    try {
      b.jolt_world_get_solver_settings(handle, s);
      final r = s.ref;
      return JoltSolverSettings(
        velocitySteps: r.velocity_steps,
        positionSteps: r.position_steps,
        baumgarte: r.baumgarte,
        speculativeContactDistance: r.speculative_contact_distance,
        penetrationSlop: r.penetration_slop,
        timeBeforeSleep: r.time_before_sleep,
        pointVelocitySleepThreshold: r.point_velocity_sleep_threshold,
        allowSleeping: r.allow_sleeping,
      );
    } finally {
      calloc.free(s);
    }
  }

  set solverSettings(JoltSolverSettings v) {
    final s = calloc<b.JoltSolverSettings>();
    try {
      s.ref
        ..velocity_steps = v.velocitySteps
        ..position_steps = v.positionSteps
        ..baumgarte = v.baumgarte
        ..speculative_contact_distance = v.speculativeContactDistance
        ..penetration_slop = v.penetrationSlop
        ..time_before_sleep = v.timeBeforeSleep
        ..point_velocity_sleep_threshold = v.pointVelocitySleepThreshold
        ..allow_sleeping = v.allowSleeping;
      b.jolt_world_set_solver_settings(handle, s);
    } finally {
      calloc.free(s);
    }
  }

  /// Advances the world by [dt] seconds in [collisionSteps] sub-steps.
  /// Throws a [StateError] when Jolt reports an error (a full body pair or
  /// contact buffer).
  void step(double dt, {int collisionSteps = 1}) {
    final error = b.jolt_world_step(handle, dt, collisionSteps);
    if (error != 0) {
      throw StateError('Jolt step failed (EPhysicsUpdateError $error)');
    }
  }

  /// Rebuilds the broad phase after adding many bodies at once.
  void optimizeBroadPhase() => b.jolt_world_optimize_broad_phase(handle);

  int get bodyCount => b.jolt_world_body_count(handle);
  int get activeBodyCount => b.jolt_world_active_body_count(handle);

  /// [blocks] is a square matrix: blocks[a][b] when profiles a and b block.
  void setProfileMatrix(List<List<bool>> blocks) {
    final n = blocks.length;
    final p = calloc<Uint8>(n * n == 0 ? 1 : n * n);
    try {
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < n; j++) {
          p[i * n + j] = blocks[i][j] ? 1 : 0;
        }
      }
      b.jolt_world_set_profile_matrix(handle, p, n);
    } finally {
      calloc.free(p);
    }
  }

  void ignorePair(int bodyA, int bodyB, {bool ignore = true}) =>
      b.jolt_world_ignore_pair(handle, bodyA, bodyB, ignore);

  // --- Bodies -----------------------------------------------------------------------

  /// Creates and adds a body with [shape]; returns its id.
  int createBody(JoltShape shape, JoltBodySettings settings) {
    final s = calloc<b.JoltBodySettings>();
    try {
      b.jolt_body_settings_init(s);
      final r = s.ref
        ..motion_type = settings.motionType.index
        ..user_data = settings.userData
        ..friction = settings.friction
        ..restitution = settings.restitution
        ..linear_damping = settings.linearDamping
        ..angular_damping = settings.angularDamping
        ..gravity_factor = settings.gravityFactor
        ..mass = settings.mass ?? 0.0
        ..allowed_dofs = settings.allowedDofs
        ..continuous_collision = settings.continuousCollision
        ..start_active = settings.startActive
        ..is_sensor = settings.isSensor;
      _setArray(r.position, settings.position.storage);
      _setArray(r.rotation, settings.rotation.storage);
      _setArray(r.linear_velocity, settings.linearVelocity.storage);
      _setArray(r.angular_velocity, settings.angularVelocity.storage);
      final inertia = settings.inertia;
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 3; col++) {
          r.inertia[row * 3 + col] = inertia?.entry(row, col) ?? 0.0;
        }
      }
      final id = b.jolt_body_create(handle, shape.handle, s);
      if (id == JoltPhysics.invalidBodyId) {
        throw StateError('The Jolt world is full');
      }
      return id;
    } finally {
      calloc.free(s);
    }
  }

  void destroyBody(int body) {
    _constraints.removeWhere((c) {
      if (c.bodyA != body && c.bodyB != body) return false;
      c.destroyIn(this);
      return true;
    });
    b.jolt_body_destroy(handle, body);
  }

  /// [owner] 0 is none; bodies of one owner collide only when both have
  /// [collidesWithOwner].
  void setBodyOwner(int body, int owner, {bool collidesWithOwner = false}) =>
      b.jolt_body_set_owner(handle, body, owner, collidesWithOwner);

  /// The profile of each sub-shape, by the sub-shape's user data.
  void setBodyProfiles(int body, List<int> profiles) {
    final p = calloc<Uint16>(profiles.isEmpty ? 1 : profiles.length);
    try {
      for (var i = 0; i < profiles.length; i++) {
        p[i] = profiles[i];
      }
      b.jolt_body_set_profiles(handle, body, p, profiles.length);
    } finally {
      calloc.free(p);
    }
  }

  /// Friction (dynamic and static) and restitution with combine modes.
  void setBodyMaterial(
    int body, {
    required double friction,
    double? staticFriction,
    required double restitution,
    JoltCombineMode frictionMode = JoltCombineMode.average,
    JoltCombineMode restitutionMode = JoltCombineMode.average,
  }) => b.jolt_body_set_material(
    handle,
    body,
    friction,
    staticFriction ?? friction,
    restitution,
    frictionMode.index,
    restitutionMode.index,
  );

  void setBodyShape(int body, JoltShape shape, {bool updateMass = true}) =>
      b.jolt_body_set_shape(handle, body, shape.handle, updateMass);

  /// Mass (kg), inertia about the centre of mass in body axes (kg m²) and the
  /// degrees of freedom ([JoltDofs]).
  void setBodyMassProperties(
    int body,
    double mass,
    Matrix3 inertia, {
    int allowedDofs = JoltDofs.all,
  }) {
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        _f[row * 3 + col] = inertia.entry(row, col);
      }
    }
    b.jolt_body_set_mass_properties(handle, body, mass, _f, allowedDofs);
  }

  void setBodyMotionType(
    int body,
    JoltMotionType type, {
    bool activate = true,
  }) => b.jolt_body_set_motion_type(handle, body, type.index, activate);

  void setBodyDamping(int body, double linear, double angular) =>
      b.jolt_body_set_damping(handle, body, linear, angular);

  void setBodyGravityFactor(int body, double factor) =>
      b.jolt_body_set_gravity_factor(handle, body, factor);

  void setBodyContinuousCollision(int body, bool enabled) =>
      b.jolt_body_set_continuous_collision(handle, body, enabled);

  /// Places the body's shape origin (no velocity change).
  void setBodyTransform(
    int body,
    Vector3 position,
    Quaternion rotation, {
    bool activate = true,
  }) {
    _put3(0, position);
    _put4(3, rotation);
    b.jolt_body_set_transform(handle, body, _f, _f + 3, activate);
  }

  void setBodyVelocity(int body, Vector3 linear, Vector3 angular) {
    _put3(0, linear);
    _put3(3, angular);
    b.jolt_body_set_velocity(handle, body, _f, _f + 3);
  }

  /// Moves a kinematic body to the target over [dt] seconds.
  void moveKinematic(
    int body,
    Vector3 position,
    Quaternion rotation,
    double dt,
  ) {
    _put3(0, position);
    _put4(3, rotation);
    b.jolt_body_move_kinematic(handle, body, _f, _f + 3, dt);
  }

  /// A force (N) for the next step only, through the centre of mass or at
  /// [point].
  void addForce(int body, Vector3 force, {Vector3? point}) {
    _put3(0, force);
    if (point == null) {
      b.jolt_body_add_force(handle, body, _f);
    } else {
      _put3(3, point);
      b.jolt_body_add_force_at(handle, body, _f, _f + 3);
    }
  }

  void addTorque(int body, Vector3 torque) {
    _put3(0, torque);
    b.jolt_body_add_torque(handle, body, _f);
  }

  void addImpulse(int body, Vector3 impulse, {Vector3? point}) {
    _put3(0, impulse);
    if (point == null) {
      b.jolt_body_add_impulse(handle, body, _f);
    } else {
      _put3(3, point);
      b.jolt_body_add_impulse_at(handle, body, _f, _f + 3);
    }
  }

  void addAngularImpulse(int body, Vector3 impulse) {
    _put3(0, impulse);
    b.jolt_body_add_angular_impulse(handle, body, _f);
  }

  void activateBody(int body) => b.jolt_body_activate(handle, body);
  void deactivateBody(int body) => b.jolt_body_deactivate(handle, body);
  bool isBodyActive(int body) => b.jolt_body_is_active(handle, body);

  /// Mass (kg) of a dynamic body, 0 otherwise.
  double bodyMass(int body) => b.jolt_body_get_mass(handle, body);

  int bodyUserData(int body) => b.jolt_body_get_user_data(handle, body);

  JoltBodyState bodyState(int body) {
    readBodyStates([body]);
    return stateAt(0);
  }

  /// Reads the state of [bodies] in one call; read them back with [stateAt]
  /// or the raw [stateBuffer] ([stateStride] doubles per body).
  void readBodyStates(List<int> bodies) {
    final n = bodies.length;
    if (n > _stateCapacity) {
      if (_states != nullptr) calloc.free(_states);
      if (_ids != nullptr) calloc.free(_ids);
      _stateCapacity = n * 2;
      _states = calloc<Double>(_stateCapacity * stateStride);
      _ids = calloc<Uint32>(_stateCapacity);
    }
    if (n == 0) return;
    for (var i = 0; i < n; i++) {
      _ids[i] = bodies[i];
    }
    b.jolt_world_get_body_states(handle, _ids, n, _states);
  }

  /// Doubles per body in [stateBuffer]: centre of mass xyz, rotation xyzw,
  /// linear velocity xyz, angular velocity xyz, active, origin xyz.
  static const int stateStride = b.JOLT_BODY_STATE_STRIDE;

  /// The states [readBodyStates] read (valid until the next read).
  Float64List get stateBuffer => _states == nullptr
      ? Float64List(0)
      : _states.asTypedList(_stateCapacity * stateStride);

  JoltBodyState stateAt(int i) {
    final s = _states + i * stateStride;
    return JoltBodyState(
      Vector3(s[0], s[1], s[2]),
      Quaternion(s[3], s[4], s[5], s[6]),
      Vector3(s[7], s[8], s[9]),
      Vector3(s[10], s[11], s[12]),
      s[13] != 0,
      Vector3(s[14], s[15], s[16]),
    );
  }

  // --- Contacts and queries ------------------------------------------------------------

  /// The contacts of the last [step], in body order.
  List<JoltContact> contacts() {
    final n = b.jolt_world_contact_count(handle);
    if (n > _contactCapacity) {
      if (_contacts != nullptr) calloc.free(_contacts);
      _contactCapacity = n * 2;
      _contacts = calloc<b.JoltContact>(_contactCapacity);
    }
    if (n == 0) return const [];
    final got = b.jolt_world_get_contacts(handle, _contacts, n);
    return [
      for (var i = 0; i < got; i++)
        () {
          final c = (_contacts + i).ref;
          return JoltContact(
            bodyA: c.body_a,
            bodyB: c.body_b,
            shapeA: c.shape_a,
            shapeB: c.shape_b,
            point: Vector3(c.point[0], c.point[1], c.point[2]),
            normal: Vector3(c.normal[0], c.normal[1], c.normal[2]),
            impulse: c.impulse,
            penetration: c.penetration,
            pointCount: c.point_count,
            persisted: c.persisted,
          );
        }(),
    ];
  }

  /// The closest hit of the ray [origin] → [origin] + [direction] (its length
  /// is the range), or null.
  /// A broad phase proxy for the box [min]..[max] (a static body in a
  /// world used for scene queries); [userData] comes back from
  /// [broadPhaseRay] and [broadPhaseBox]. Returns the body id.
  int addBoxProxy(Vector3 min, Vector3 max, int userData) {
    _put3(0, min);
    _put3(3, max);
    return b.jolt_world_add_box_proxy(handle, _f, _f + 3, userData);
  }

  /// Moves and resizes proxy [body] to the box [min]..[max].
  void setBoxProxy(int body, Vector3 min, Vector3 max) {
    _put3(0, min);
    _put3(3, max);
    b.jolt_world_set_box_proxy(handle, body, _f, _f + 3);
  }

  Pointer<Uint64> _hits = nullptr;
  int _hitCapacity = 0;

  List<int> _collect(int Function(Pointer<Uint64> out, int max) query) {
    for (;;) {
      if (_hitCapacity == 0) {
        _hitCapacity = 256;
        _hits = calloc<Uint64>(_hitCapacity);
      }
      final n = query(_hits, _hitCapacity);
      if (n <= _hitCapacity) return List<int>.generate(n, (i) => _hits[i]);
      calloc.free(_hits);
      _hitCapacity = n * 2;
      _hits = calloc<Uint64>(_hitCapacity);
    }
  }

  /// The user data of every body whose bounds the segment [origin] ->
  /// [origin] + [delta] crosses (broad phase, any order). After proxies
  /// moved this is a superset (a moved body may still be found where it
  /// was) until [optimizeBroadPhase] rebuilds the tree; never one missed.
  List<int> broadPhaseRay(Vector3 origin, Vector3 delta) {
    _put3(0, origin);
    _put3(3, delta);
    return _collect(
      (out, max) => b.jolt_world_broad_phase_ray(handle, _f, _f + 3, out, max),
    );
  }

  /// The user data of every body whose bounds the box [min]..[max] crosses
  /// when moved by [delta] (a swept shape).
  List<int> broadPhaseBoxCast(Vector3 min, Vector3 max, Vector3 delta) {
    _put3(0, min);
    _put3(3, max);
    _put3(6, delta);
    return _collect(
      (out, n) =>
          b.jolt_world_broad_phase_box_cast(handle, _f, _f + 3, _f + 6, out, n),
    );
  }

  /// The user data of every body whose bounds overlap the box [min]..[max].
  List<int> broadPhaseBox(Vector3 min, Vector3 max) {
    _put3(0, min);
    _put3(3, max);
    return _collect(
      (out, max) => b.jolt_world_broad_phase_box(handle, _f, _f + 3, out, max),
    );
  }

  JoltRayHit? castRay(Vector3 origin, Vector3 direction) {
    final hit = calloc<b.JoltRayHit>();
    try {
      _put3(0, origin);
      _put3(3, direction);
      if (!b.jolt_world_cast_ray(handle, _f, _f + 3, hit)) return null;
      final h = hit.ref;
      return JoltRayHit(
        h.body,
        h.shape,
        h.fraction,
        Vector3(h.point[0], h.point[1], h.point[2]),
        Vector3(h.normal[0], h.normal[1], h.normal[2]),
      );
    } finally {
      calloc.free(hit);
    }
  }

  // --- Constraints ------------------------------------------------------------------

  /// The constraints of this world, in creation order.
  List<JoltConstraint> get constraints => List.unmodifiable(_constraints);

  /// A ball-and-socket joint with a swing cone and a twist range (see
  /// [JoltSwingTwistSettings]).
  JoltConstraint addSwingTwist(
    int bodyA,
    int bodyB,
    JoltSwingTwistSettings settings,
  ) {
    final c = JoltConstraint.swingTwist(this, bodyA, bodyB, settings);
    _constraints.add(c);
    return c;
  }

  /// A hinge (see [JoltHingeSettings]).
  JoltConstraint addHinge(int bodyA, int bodyB, JoltHingeSettings settings) {
    final c = JoltConstraint.hinge(this, bodyA, bodyB, settings);
    _constraints.add(c);
    return c;
  }

  void removeConstraint(JoltConstraint constraint) {
    if (!_constraints.remove(constraint)) return;
    constraint.destroyIn(this);
  }

  /// Frees the world, its bodies and constraints.
  void dispose() {
    if (_handle == nullptr) return;
    for (final c in _constraints) {
      c.detach();
    }
    _constraints.clear();
    b.jolt_world_destroy(_handle);
    _handle = nullptr;
    calloc.free(_f);
    if (_states != nullptr) calloc.free(_states);
    if (_ids != nullptr) calloc.free(_ids);
    if (_contacts != nullptr) calloc.free(_contacts);
    if (_hits != nullptr) calloc.free(_hits);
    _hits = nullptr;
    _hitCapacity = 0;
    _states = nullptr;
    _ids = nullptr;
    _contacts = nullptr;
  }

  void _put3(int at, Vector3 v) {
    _f[at] = v.x;
    _f[at + 1] = v.y;
    _f[at + 2] = v.z;
  }

  void _put4(int at, Quaternion q) {
    _f[at] = q.x;
    _f[at + 1] = q.y;
    _f[at + 2] = q.z;
    _f[at + 3] = q.w;
  }
}

void _setArray(Array<Float> a, List<double> values) {
  for (var i = 0; i < values.length; i++) {
    a[i] = values[i];
  }
}
