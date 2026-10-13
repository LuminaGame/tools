import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/src/jolt_ffi.dart';
import 'package:flutter_jolt/src/jolt_ffi_package.dart';
import 'package:flutter_jolt/src/jolt_c.dart' as b;
import 'package:flutter_jolt/src/jolt_world.dart';

/// A ball-and-socket joint with a swing cone and a twist range. Frames are in
/// each body's local space relative to its centre of mass: the twist axis is
/// the joint frame's X axis, the plane axis its Y axis. [planeHalfCone] is
/// the swing about Y, [normalHalfCone] the swing about Z, twist is about X
/// (radians). [maxFrictionTorque] (N m) resists turning while no motor runs.
class JoltSwingTwistSettings {
  JoltSwingTwistSettings({
    required this.positionA,
    required this.twistAxisA,
    required this.planeAxisA,
    required this.positionB,
    required this.twistAxisB,
    required this.planeAxisB,
    this.normalHalfCone = 0.0,
    this.planeHalfCone = 0.0,
    this.twistMin = 0.0,
    this.twistMax = 0.0,
    this.maxFrictionTorque = 0.0,
  });

  final Vector3 positionA;
  final Vector3 twistAxisA;
  final Vector3 planeAxisA;
  final Vector3 positionB;
  final Vector3 twistAxisB;
  final Vector3 planeAxisB;
  final double normalHalfCone;
  final double planeHalfCone;
  final double twistMin;
  final double twistMax;
  final double maxFrictionTorque;
}

/// A hinge about [hingeAxisA] / [hingeAxisB]; the normal axes are the 0 rad
/// direction. Limits in radians ([limitMin] > [limitMax]: none; Jolt keeps
/// `limitMin <= 0 <= limitMax`).
class JoltHingeSettings {
  JoltHingeSettings({
    required this.positionA,
    required this.hingeAxisA,
    required this.normalAxisA,
    required this.positionB,
    required this.hingeAxisB,
    required this.normalAxisB,
    this.limitMin = 1.0,
    this.limitMax = -1.0,
    this.maxFrictionTorque = 0.0,
  });

  final Vector3 positionA;
  final Vector3 hingeAxisA;
  final Vector3 normalAxisA;
  final Vector3 positionB;
  final Vector3 hingeAxisB;
  final Vector3 normalAxisB;
  final double limitMin;
  final double limitMax;
  final double maxFrictionTorque;
}

/// A constraint between two bodies of a [JoltWorld] (created through
/// [JoltWorld.addSwingTwist] / [JoltWorld.addHinge], freed with the world or
/// [JoltWorld.removeConstraint]).
class JoltConstraint {
  JoltConstraint._(this._handle, this.bodyA, this.bodyB, this.isHinge);

  factory JoltConstraint.swingTwist(
    JoltWorld world,
    int bodyA,
    int bodyB,
    JoltSwingTwistSettings s,
  ) {
    final p = calloc<b.JoltSwingTwistSettings>();
    try {
      final r = p.ref
        ..normal_half_cone = s.normalHalfCone
        ..plane_half_cone = s.planeHalfCone
        ..twist_min = s.twistMin
        ..twist_max = s.twistMax
        ..max_friction_torque = s.maxFrictionTorque;
      _set(r.position_a, s.positionA);
      _set(r.twist_axis_a, s.twistAxisA);
      _set(r.plane_axis_a, s.planeAxisA);
      _set(r.position_b, s.positionB);
      _set(r.twist_axis_b, s.twistAxisB);
      _set(r.plane_axis_b, s.planeAxisB);
      final h = b.jolt_constraint_swing_twist(world.handle, bodyA, bodyB, p);
      if (h == nullptr) throw ArgumentError('No such bodies: $bodyA, $bodyB');
      return JoltConstraint._(h, bodyA, bodyB, false);
    } finally {
      calloc.free(p);
    }
  }

  factory JoltConstraint.hinge(
    JoltWorld world,
    int bodyA,
    int bodyB,
    JoltHingeSettings s,
  ) {
    final p = calloc<b.JoltHingeSettings>();
    try {
      final r = p.ref
        ..limit_min = s.limitMin
        ..limit_max = s.limitMax
        ..max_friction_torque = s.maxFrictionTorque;
      _set(r.position_a, s.positionA);
      _set(r.hinge_axis_a, s.hingeAxisA);
      _set(r.normal_axis_a, s.normalAxisA);
      _set(r.position_b, s.positionB);
      _set(r.hinge_axis_b, s.hingeAxisB);
      _set(r.normal_axis_b, s.normalAxisB);
      final h = b.jolt_constraint_hinge(world.handle, bodyA, bodyB, p);
      if (h == nullptr) throw ArgumentError('No such bodies: $bodyA, $bodyB');
      return JoltConstraint._(h, bodyA, bodyB, true);
    } finally {
      calloc.free(p);
    }
  }

  Pointer<b.JoltConstraint> _handle;
  final int bodyA;
  final int bodyB;
  final bool isHinge;
  static final Pointer<Float> _f = calloc<Float>(4);

  bool get isDestroyed => _handle == nullptr;

  Pointer<b.JoltConstraint> get _h {
    if (_handle == nullptr) {
      throw StateError('JoltConstraint used after it was removed');
    }
    return _handle;
  }

  set enabled(bool value) => b.jolt_constraint_set_enabled(_h, value);

  set maxFrictionTorque(double torque) =>
      b.jolt_constraint_set_max_friction_torque(_h, torque);

  /// Solver iterations for this constraint's island (0: the world's).
  void setSolverSteps({int velocity = 0, int position = 0}) =>
      b.jolt_constraint_set_solver_steps(_h, velocity, position);

  /// Swing-twist: cones and twist range. Hinge: [twistMin] / [twistMax] are
  /// its limits.
  void setLimits({
    double normalHalfCone = 0,
    double planeHalfCone = 0,
    required double twistMin,
    required double twistMax,
  }) => b.jolt_constraint_set_limits(
    _h,
    normalHalfCone,
    planeHalfCone,
    twistMin,
    twistMax,
  );

  /// Drives body B's angular velocity relative to A toward [angularVelocity]
  /// (rad/s, B's constraint frame; a hinge reads x) with at most [maxTorque]
  /// (N m); [maxTorque] <= 0 switches the motor off.
  void setVelocityMotor(Vector3 angularVelocity, double maxTorque) {
    _f[0] = angularVelocity.x;
    _f[1] = angularVelocity.y;
    _f[2] = angularVelocity.z;
    b.jolt_constraint_set_velocity_motor(_h, _f, maxTorque);
  }

  /// Pulls body B's joint frame toward [target] (B's frame in A's frame; a
  /// hinge uses the angle about X, the hinge axis of that frame) with a spring
  /// of [frequency] Hz and
  /// [damping] ratio, at most [maxTorque] (N m); [maxTorque] <= 0 switches
  /// the motor off.
  void setPositionMotor(
    Quaternion target, {
    required double frequency,
    double damping = 1.0,
    required double maxTorque,
  }) {
    _f[0] = target.x;
    _f[1] = target.y;
    _f[2] = target.z;
    _f[3] = target.w;
    b.jolt_constraint_set_position_motor(_h, _f, frequency, damping, maxTorque);
  }

  /// The position and rotation-limit impulses of the last step.
  (double, double) get lambdas {
    b.jolt_constraint_get_lambdas(_h, _f);
    return (_f[0], _f[1]);
  }

  /// Frees it in [world] (used by [JoltWorld]).
  void destroyIn(JoltWorld world) {
    if (_handle == nullptr) return;
    b.jolt_constraint_destroy(world.handle, _handle);
    _handle = nullptr;
  }

  /// Forgets the handle after its world freed it.
  void detach() => _handle = nullptr;
}

void _set(Array<Float> a, Vector3 v) {
  a[0] = v.x;
  a[1] = v.y;
  a[2] = v.z;
}
