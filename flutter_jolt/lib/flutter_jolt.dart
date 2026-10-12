/// Dart FFI bindings for Jolt Physics (https://github.com/jrouwe/JoltPhysics):
/// a native physics world with rigid bodies, shapes, constraints, contacts
/// and ray casts. Units are metres, kilograms, seconds and radians.
///
/// Check [JoltPhysics.isAvailable] before creating a [JoltWorld]: the native
/// library exists only for targets with a Jolt build (`tool/build_jolt.*`).
library;

export 'package:flutter_jolt/src/jolt_cloth.dart';
export 'package:flutter_jolt/src/jolt_constraint.dart';
export 'package:flutter_jolt/src/jolt_physics.dart';
export 'package:flutter_jolt/src/jolt_shape.dart';
export 'package:flutter_jolt/src/jolt_types.dart';
export 'package:flutter_jolt/src/jolt_world.dart';
