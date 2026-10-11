import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_kimodo/src/kimodo_skeleton.dart';

/// A point on the ground: x and z in metres (Kimodo's frame, Y up).
typedef KimodoGroundPoint = ({double x, double z});

/// One constraint set of NVIDIA Kimodo (`kimodo.constraints`): what it pins
/// on which frames. [KimodoConstraints.encode] turns a list of them into
/// the conditioning tensors the diffusion model follows.
sealed class KimodoConstraint {
  const KimodoConstraint(this.frames);

  /// The frames (of the whole generated timeline) the set pins.
  final List<int> frames;

  void _contribute(_Conditions c, KimodoSkeleton s);
}

/// Pins the smooth root's ground position on [frames] (a root path), and
/// optionally the heading there (radians, 0 facing +Z, positive towards +X):
/// upstream `Root2DConstraintSet`.
class KimodoRoot2DConstraint extends KimodoConstraint {
  KimodoRoot2DConstraint({
    required List<int> frames,
    required this.points,
    this.headings,
  }) : super(frames) {
    if (points.length != frames.length) {
      throw ArgumentError('needs one point per frame');
    }
    if (headings != null && headings!.length != frames.length) {
      throw ArgumentError('needs one heading per frame');
    }
  }

  final List<KimodoGroundPoint> points;
  final List<double>? headings;

  @override
  void _contribute(_Conditions c, KimodoSkeleton s) {
    for (var i = 0; i < frames.length; i++) {
      c.smoothRoot[frames[i]] = points[i];
      final h = headings;
      if (h != null) c.heading[frames[i]] = (math.cos(h[i]), math.sin(h[i]));
    }
  }
}

/// Pins whole poses on [frames]: every joint's position, the smooth root
/// ([smoothRoot], the pelvis's ground position by default), the pelvis
/// height and the heading of the pose: upstream `FullBodyConstraintSet`.
class KimodoFullBodyConstraint extends KimodoConstraint {
  KimodoFullBodyConstraint({
    required List<int> frames,
    required this.poses,
    this.smoothRoot,
  }) : super(frames) {
    _checkPoses(frames, poses, smoothRoot);
  }

  final List<KimodoPose> poses;
  final List<KimodoGroundPoint>? smoothRoot;

  @override
  void _contribute(_Conditions c, KimodoSkeleton s) {
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i], pose = poses[i];
      for (var j = 0; j < s.jointCount; j++) {
        c.positions[(f, j)] = pose.position(j);
      }
      _rootAndHeading(c, s, f, pose, smoothRoot?[i]);
    }
  }
}

/// Pins end effectors on [frames]: for each group of [joints] (`LeftHand`,
/// `RightHand`, `LeftFoot`, `RightFoot`, `Hips`) the positions of its chain
/// and the rotation of its first joint, taken from [poses], plus the smooth
/// root, pelvis height and heading of those poses: upstream
/// `EndEffectorConstraintSet` and its left/right hand/foot subclasses.
class KimodoEndEffectorConstraint extends KimodoConstraint {
  KimodoEndEffectorConstraint({
    required List<int> frames,
    required this.poses,
    required this.joints,
    this.smoothRoot,
  }) : super(frames) {
    if (joints.isEmpty) throw ArgumentError('needs at least one end effector');
    _checkPoses(frames, poses, smoothRoot);
  }

  KimodoEndEffectorConstraint.leftHand({
    required List<int> frames,
    required List<KimodoPose> poses,
    List<KimodoGroundPoint>? smoothRoot,
  }) : this(frames: frames, poses: poses, joints: const ['LeftHand'], smoothRoot: smoothRoot);

  KimodoEndEffectorConstraint.rightHand({
    required List<int> frames,
    required List<KimodoPose> poses,
    List<KimodoGroundPoint>? smoothRoot,
  }) : this(frames: frames, poses: poses, joints: const ['RightHand'], smoothRoot: smoothRoot);

  KimodoEndEffectorConstraint.leftFoot({
    required List<int> frames,
    required List<KimodoPose> poses,
    List<KimodoGroundPoint>? smoothRoot,
  }) : this(frames: frames, poses: poses, joints: const ['LeftFoot'], smoothRoot: smoothRoot);

  KimodoEndEffectorConstraint.rightFoot({
    required List<int> frames,
    required List<KimodoPose> poses,
    List<KimodoGroundPoint>? smoothRoot,
  }) : this(frames: frames, poses: poses, joints: const ['RightFoot'], smoothRoot: smoothRoot);

  final List<KimodoPose> poses;
  final List<String> joints;
  final List<KimodoGroundPoint>? smoothRoot;

  @override
  void _contribute(_Conditions c, KimodoSkeleton s) {
    final expanded = s.expand(joints);
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i], pose = poses[i];
      for (final j in expanded.positions) {
        c.positions[(f, j)] = pose.position(j);
      }
      for (final j in expanded.rotations) {
        c.rotations[(f, j)] = Float64List.sublistView(pose.rotations, j * 9, j * 9 + 9);
      }
      _rootAndHeading(c, s, f, pose, smoothRoot?[i]);
    }
  }
}

void _checkPoses(List<int> frames, List<KimodoPose> poses, List<KimodoGroundPoint>? smoothRoot) {
  if (poses.length != frames.length) throw ArgumentError('needs one pose per frame');
  if (smoothRoot != null && smoothRoot.length != frames.length) {
    throw ArgumentError('needs one smooth root point per frame');
  }
}

void _rootAndHeading(_Conditions c, KimodoSkeleton s, int f, KimodoPose pose, KimodoGroundPoint? smoothRoot) {
  final r = s.root * 3;
  c.smoothRoot[f] = smoothRoot ?? (x: pose.positions[r], z: pose.positions[r + 2]);
  c.rootY[f] = pose.positions[r + 1];
  final h = s.heading(pose);
  c.heading[f] = (math.cos(h), math.sin(h));
}

/// The constrained features, per frame (and joint): a later constraint set
/// replaces an earlier one's value for the same key, like upstream's
/// `get_unique_index_and_data`.
class _Conditions {
  final Map<int, KimodoGroundPoint> smoothRoot = {};
  final Map<int, double> rootY = {};
  final Map<int, (double, double)> heading = {};
  final Map<(int, int), List<double>> rotations = {};
  final Map<(int, int), List<double>> positions = {};
}

/// The conditioning tensors of a constraint list: [observed] and [mask],
/// `[frames, dim]` row-major, in the motion representation's unnormalised
/// feature space (upstream `create_conditions(..., to_normalize=False)`);
/// observed values are 0 wherever the mask is 0.
class KimodoConditioning {
  KimodoConditioning(this.frames, this.dim, this.observed, this.mask);

  final int frames;
  final int dim;
  final Float64List observed;
  final Float64List mask;

  /// Whether any value is constrained.
  bool get isConstrained => mask.any((m) => m != 0);

  Float32List get observedFloat32 => Float32List.fromList(observed);
  Float32List get maskFloat32 => Float32List.fromList(mask);
}

/// Constraints for one generation on [skeleton]: root paths, end effectors
/// and full-body keyframes, with frames counted over the whole generated
/// timeline (with several prompts, their frames one after another).
class KimodoConstraints {
  KimodoConstraints(this.sets, {KimodoSkeleton? skeleton})
    : skeleton = skeleton ?? KimodoSkeleton.soma30;

  final List<KimodoConstraint> sets;
  final KimodoSkeleton skeleton;

  bool get isEmpty => sets.isEmpty;

  /// The conditioning tensors for a timeline of [frames] frames: NVIDIA
  /// Kimodo's `KimodoMotionRep.create_conditions` feature layout (smooth
  /// root, heading, joint positions relative to the smooth root, global 6D
  /// rotations). Throws [RangeError] for a frame outside the timeline and
  /// [StateError] when a pinned joint position has no smooth root on its
  /// frame.
  KimodoConditioning encode(int frames) {
    final s = skeleton;
    final dim = s.motionDim;
    final joints = s.jointCount;
    final c = _Conditions();
    for (final set in sets) {
      for (final f in set.frames) {
        RangeError.checkValueInInterval(f, 0, frames - 1, 'constraint frame');
      }
      set._contribute(c, s);
    }
    final observed = Float64List(frames * dim);
    final mask = Float64List(frames * dim);
    const positionsAt = 5;
    final rotationsAt = 5 + 3 * joints;
    void put(int f, int channel, double v) {
      observed[f * dim + channel] = v;
      mask[f * dim + channel] = 1;
    }

    c.smoothRoot.forEach((f, p) {
      put(f, 0, p.x);
      put(f, 2, p.z);
    });
    c.rootY.forEach((f, y) => put(f, 1, y));
    c.heading.forEach((f, h) {
      put(f, 3, h.$1);
      put(f, 4, h.$2);
    });
    c.rotations.forEach((key, m) {
      final (f, j) = key;
      // 6D: the matrix's first two columns.
      final six = [m[0], m[3], m[6], m[1], m[4], m[7]];
      for (var d = 0; d < 6; d++) {
        put(f, rotationsAt + j * 6 + d, six[d]);
      }
    });
    c.positions.forEach((key, p) {
      final (f, j) = key;
      final root = c.smoothRoot[f];
      if (root == null) {
        throw StateError('frame $f pins a joint position but not the smooth root');
      }
      put(f, positionsAt + j * 3, p[0] - root.x);
      put(f, positionsAt + j * 3 + 1, p[1]);
      put(f, positionsAt + j * 3 + 2, p[2] - root.z);
    });
    return KimodoConditioning(frames, dim, observed, mask);
  }
}
