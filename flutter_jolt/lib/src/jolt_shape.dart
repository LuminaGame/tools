import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/src/jolt_bindings.g.dart' as b;
import 'package:flutter_jolt/src/jolt_physics.dart';

/// A Jolt collision shape (metres). Shapes are reference counted natively: a
/// body or a compound keeps its own reference, so a shape can be [release]d
/// as soon as it has been used. A shape that is never released is freed when
/// it is garbage collected.
///
/// Leaf shapes (box, sphere, capsule, cylinder, convex hull, height field)
/// carry a [userData] that contacts and ray hits report as the sub-shape
/// (`JoltContact.shapeA`, `JoltRayHit.shape`); it is 0 unless set.
/// Containers (scaled, rotated/translated, offset centre of mass, compound)
/// pass their leaves' user data through.
class JoltShape implements Finalizable {
  JoltShape._(this._handle) {
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  static final _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<b.JoltShape>)>>(
      b.jolt_shape_release,
    ).cast(),
  );

  Pointer<b.JoltShape> _handle;

  /// The native handle (null pointer after [release]).
  Pointer<b.JoltShape> get handle {
    if (_handle == nullptr) throw StateError('JoltShape used after release()');
    return _handle;
  }

  bool get isReleased => _handle == nullptr;

  static JoltShape _wrap(Pointer<b.JoltShape> p, String what) {
    if (p == nullptr) {
      throw ArgumentError('Jolt could not build the $what shape');
    }
    return JoltShape._(p);
  }

  /// A box of [halfExtents] (m) with edges rounded by [convexRadius] (clamped
  /// to the smallest half extent; 0 keeps them sharp).
  factory JoltShape.box(Vector3 halfExtents, {double convexRadius = 0.02}) {
    JoltPhysics.ensureAvailable();
    return _wrap(
      b.jolt_shape_box(
        halfExtents.x,
        halfExtents.y,
        halfExtents.z,
        convexRadius,
      ),
      'box',
    );
  }

  factory JoltShape.sphere(double radius) {
    JoltPhysics.ensureAvailable();
    return _wrap(b.jolt_shape_sphere(radius), 'sphere');
  }

  /// A capsule along local Y: [halfHeightOfCylinder] without the caps.
  factory JoltShape.capsule(double halfHeightOfCylinder, double radius) {
    JoltPhysics.ensureAvailable();
    return _wrap(b.jolt_shape_capsule(halfHeightOfCylinder, radius), 'capsule');
  }

  /// A cylinder along local Y.
  factory JoltShape.cylinder(
    double halfHeight,
    double radius, {
    double convexRadius = 0.02,
  }) {
    JoltPhysics.ensureAvailable();
    return _wrap(
      b.jolt_shape_cylinder(halfHeight, radius, convexRadius),
      'cylinder',
    );
  }

  /// The convex hull of [points] (at least 4, not coplanar).
  factory JoltShape.convexHull(
    List<Vector3> points, {
    double maxConvexRadius = 0.02,
  }) {
    JoltPhysics.ensureAvailable();
    final p = calloc<Float>(points.length * 3);
    try {
      for (var i = 0; i < points.length; i++) {
        p[3 * i] = points[i].x;
        p[3 * i + 1] = points[i].y;
        p[3 * i + 2] = points[i].z;
      }
      return _wrap(
        b.jolt_shape_convex_hull(p, points.length, maxConvexRadius),
        'convex hull',
      );
    } finally {
      calloc.free(p);
    }
  }

  /// A height field of [sampleCount]² heights, row major: vertex (x, y) is at
  /// `offset + scale * (x, samples[y * sampleCount + x], y)`. A height of
  /// [noCollision] is a hole. Static bodies only.
  factory JoltShape.heightField(
    Float32List samples,
    int sampleCount, {
    Vector3? offset,
    Vector3? scale,
  }) {
    JoltPhysics.ensureAvailable();
    if (samples.length != sampleCount * sampleCount) {
      throw ArgumentError(
        'A height field of $sampleCount² samples needs ${sampleCount * sampleCount}, got ${samples.length}',
      );
    }
    final p = calloc<Float>(samples.length);
    final o = calloc<Float>(3);
    final s = calloc<Float>(3);
    try {
      p.asTypedList(samples.length).setAll(0, samples);
      _put3(o, offset ?? Vector3.zero());
      _put3(s, scale ?? Vector3(1, 1, 1));
      return _wrap(
        b.jolt_shape_height_field(p, sampleCount, o, s),
        'height field',
      );
    } finally {
      calloc.free(p);
      calloc.free(o);
      calloc.free(s);
    }
  }

  /// The height that marks a hole in [JoltShape.heightField].
  static double get noCollision => b.jolt_heightfield_no_collision();

  /// [inner] scaled by [scale] (negative components mirror it).
  factory JoltShape.scaled(JoltShape inner, Vector3 scale) {
    return _wrap(
      b.jolt_shape_scaled(inner.handle, scale.x, scale.y, scale.z),
      'scaled',
    );
  }

  /// [inner] placed at [position] / [rotation] in the new shape's frame.
  factory JoltShape.rotatedTranslated(
    JoltShape inner,
    Vector3 position,
    Quaternion rotation,
  ) {
    final p = calloc<Float>(7);
    try {
      _put3(p, position);
      _put4(p + 3, rotation);
      return _wrap(
        b.jolt_shape_rotated_translated(inner.handle, p, p + 3),
        'rotated/translated',
      );
    } finally {
      calloc.free(p);
    }
  }

  /// [inner] with its centre of mass moved by [offset].
  factory JoltShape.offsetCenterOfMass(JoltShape inner, Vector3 offset) {
    final p = calloc<Float>(3);
    try {
      _put3(p, offset);
      return _wrap(
        b.jolt_shape_offset_center_of_mass(inner.handle, p),
        'offset centre of mass',
      );
    } finally {
      calloc.free(p);
    }
  }

  /// A static compound of [parts], each posed in the compound's frame.
  factory JoltShape.compound(
    List<({JoltShape shape, Vector3 position, Quaternion rotation})> parts,
  ) {
    if (parts.isEmpty) {
      throw ArgumentError('A compound needs at least one part');
    }
    final shapes = calloc<Pointer<b.JoltShape>>(parts.length);
    final positions = calloc<Float>(parts.length * 3);
    final rotations = calloc<Float>(parts.length * 4);
    try {
      for (var i = 0; i < parts.length; i++) {
        shapes[i] = parts[i].shape.handle;
        _put3(positions + 3 * i, parts[i].position);
        _put4(rotations + 4 * i, parts[i].rotation);
      }
      return _wrap(
        b.jolt_shape_static_compound(
          shapes,
          positions,
          rotations,
          parts.length,
        ),
        'compound',
      );
    } finally {
      calloc.free(shapes);
      calloc.free(positions);
      calloc.free(rotations);
    }
  }

  /// Sets the user data contacts and ray hits report for this leaf.
  set userData(int value) => b.jolt_shape_set_user_data(handle, value);

  /// The centre of mass in the shape's frame (m).
  Vector3 get centerOfMass {
    final p = calloc<Float>(3);
    try {
      b.jolt_shape_center_of_mass(handle, p);
      return Vector3(p[0], p[1], p[2]);
    } finally {
      calloc.free(p);
    }
  }

  /// Volume (m³).
  double get volume => b.jolt_shape_volume(handle);

  /// Local bounds (m).
  Aabb3 get localBounds {
    final p = calloc<Float>(6);
    try {
      b.jolt_shape_local_bounds(handle, p);
      return Aabb3.minMax(Vector3(p[0], p[1], p[2]), Vector3(p[3], p[4], p[5]));
    } finally {
      calloc.free(p);
    }
  }

  /// Drops this handle's reference (bodies and compounds keep theirs).
  void release() {
    if (_handle == nullptr) return;
    _finalizer.detach(this);
    b.jolt_shape_release(_handle);
    _handle = nullptr;
  }
}

void _put3(Pointer<Float> p, Vector3 v) {
  p[0] = v.x;
  p[1] = v.y;
  p[2] = v.z;
}

void _put4(Pointer<Float> p, Quaternion q) {
  p[0] = q.x;
  p[1] = q.y;
  p[2] = q.z;
  p[3] = q.w;
}
