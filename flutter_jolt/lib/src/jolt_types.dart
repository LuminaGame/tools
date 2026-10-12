import 'package:vector_math/vector_math_64.dart';

/// How a body moves.
enum JoltMotionType {
  /// Never moves (level geometry); can still be placed by hand.
  static_,

  /// Moved by the caller, pushes dynamic bodies, never pushed.
  kinematic,

  /// Simulated: gravity, forces, contacts and constraints move it.
  dynamic_,
}

/// Degrees of freedom a dynamic body keeps (bit flags, world axes for
/// translation, body axes for rotation).
abstract final class JoltDofs {
  static const int translationX = 1;
  static const int translationY = 2;
  static const int translationZ = 4;
  static const int rotationX = 8;
  static const int rotationY = 16;
  static const int rotationZ = 32;
  static const int all = 63;
}

/// How two touching bodies combine friction or restitution; when they ask for
/// different modes the later one in this list wins.
enum JoltCombineMode { average, min, multiply, max }

/// Everything a body is created with (metres, kilograms, seconds).
class JoltBodySettings {
  JoltBodySettings({
    this.motionType = JoltMotionType.dynamic_,
    Vector3? position,
    Quaternion? rotation,
    Vector3? linearVelocity,
    Vector3? angularVelocity,
    this.userData = 0,
    this.friction = 0.2,
    this.restitution = 0.0,
    this.linearDamping = 0.05,
    this.angularDamping = 0.05,
    this.gravityFactor = 1.0,
    this.mass,
    this.inertia,
    this.allowedDofs = JoltDofs.all,
    this.continuousCollision = false,
    this.startActive = true,
    this.isSensor = false,
  }) : position = position ?? Vector3.zero(),
       rotation = rotation ?? Quaternion.identity(),
       linearVelocity = linearVelocity ?? Vector3.zero(),
       angularVelocity = angularVelocity ?? Vector3.zero();

  JoltMotionType motionType;

  /// Where the shape's origin is (not the centre of mass).
  Vector3 position;
  Quaternion rotation;
  Vector3 linearVelocity;
  Vector3 angularVelocity;
  int userData;
  double friction;
  double restitution;
  double linearDamping;
  double angularDamping;
  double gravityFactor;

  /// When set (with [inertia]), replaces the mass Jolt computes from the
  /// shape's volume at 1000 kg/m³.
  double? mass;

  /// Inertia about the centre of mass in body axes (kg m²); a diagonal of
  /// `mass / 6 * size²`-like values when [mass] is set without it.
  Matrix3? inertia;
  int allowedDofs;
  bool continuousCollision;
  bool startActive;
  bool isSensor;
}

/// A body's state after a step: [centerOfMass] and [origin] (the shape's
/// origin) in the world, [rotation], velocities, and whether it is awake.
class JoltBodyState {
  JoltBodyState(
    this.centerOfMass,
    this.rotation,
    this.linearVelocity,
    this.angularVelocity,
    this.isActive,
    this.origin,
  );

  final Vector3 centerOfMass;
  final Quaternion rotation;
  final Vector3 linearVelocity;
  final Vector3 angularVelocity;
  final bool isActive;
  final Vector3 origin;
}

/// A contact of the last step between sub-shapes of two bodies. [normal]
/// points from [bodyA] to [bodyB]; [impulse] is Jolt's estimate of the
/// normal impulse (kg m/s) the contact needs this step.
class JoltContact {
  JoltContact({
    required this.bodyA,
    required this.bodyB,
    required this.shapeA,
    required this.shapeB,
    required this.point,
    required this.normal,
    required this.impulse,
    required this.penetration,
    required this.pointCount,
    required this.persisted,
  });

  final int bodyA;
  final int bodyB;

  /// The sub-shapes' user data.
  final int shapeA;
  final int shapeB;

  /// The mean of the contact points (world).
  final Vector3 point;
  final Vector3 normal;
  final double impulse;
  final double penetration;
  final int pointCount;

  /// Whether the bodies already touched in the step before.
  final bool persisted;
}

/// The closest hit of a ray cast.
class JoltRayHit {
  JoltRayHit(this.body, this.shape, this.fraction, this.point, this.normal);

  final int body;

  /// The sub-shape's user data.
  final int shape;

  /// Distance along the ray, as a fraction of its length.
  final double fraction;
  final Vector3 point;
  final Vector3 normal;
}

/// Solver quality and sleep settings of a world (metres, seconds).
class JoltSolverSettings {
  JoltSolverSettings({
    this.velocitySteps = 10,
    this.positionSteps = 2,
    this.baumgarte = 0.2,
    this.speculativeContactDistance = 0.02,
    this.penetrationSlop = 0.02,
    this.timeBeforeSleep = 0.5,
    this.pointVelocitySleepThreshold = 0.03,
    this.allowSleeping = true,
  });

  int velocitySteps;
  int positionSteps;
  double baumgarte;
  double speculativeContactDistance;
  double penetrationSlop;
  double timeBeforeSleep;
  double pointVelocitySleepThreshold;
  bool allowSleeping;
}
