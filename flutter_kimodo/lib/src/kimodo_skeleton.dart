import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_kimodo/src/kimodo_motion.dart';

/// One posed skeleton: every joint's global position (metres, Y up) and
/// global rotation, as Kimodo's constraint sets take them.
class KimodoPose {
  KimodoPose(this.positions, this.rotations)
    : assert(positions.length * 3 == rotations.length);

  /// `[joints, 3]` global positions.
  final Float64List positions;

  /// `[joints, 3, 3]` global rotation matrices, row-major.
  final Float64List rotations;

  int get joints => positions.length ~/ 3;

  /// Joint [j]'s position as `[x, y, z]`.
  List<double> position(int j) => [
    positions[j * 3],
    positions[j * 3 + 1],
    positions[j * 3 + 2],
  ];

  /// This pose moved by ([dx], [dy], [dz]).
  KimodoPose translated(double dx, double dy, double dz) {
    final p = Float64List.fromList(positions);
    for (var j = 0; j < joints; j++) {
      p[j * 3] += dx;
      p[j * 3 + 1] += dy;
      p[j * 3 + 2] += dz;
    }
    return KimodoPose(p, Float64List.fromList(rotations));
  }

  /// This pose turned by [angle] radians about the vertical axis through
  /// [pivotX], [pivotZ] (a positive angle turns +Z towards +X).
  KimodoPose turned(double angle, {double pivotX = 0, double pivotZ = 0}) {
    final c = math.cos(angle), s = math.sin(angle);
    // R_y(angle), row-major.
    final r = [c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c];
    final p = Float64List(positions.length);
    final m = Float64List(rotations.length);
    for (var j = 0; j < joints; j++) {
      final x = positions[j * 3] - pivotX, z = positions[j * 3 + 2] - pivotZ;
      p[j * 3] = c * x + s * z + pivotX;
      p[j * 3 + 1] = positions[j * 3 + 1];
      p[j * 3 + 2] = -s * x + c * z + pivotZ;
      _mul3(r, 0, rotations, j * 9, m, j * 9);
    }
    return KimodoPose(p, m);
  }
}

/// A skeleton of a Kimodo checkpoint as the constraint encoder sees it:
/// joint names and parents, parent-local rest offsets (metres, Y up, the
/// character facing +Z with its left side at +X), the hip joints the heading
/// is measured from and the end-effector chains. [soma30] is the skeleton of
/// `kimodo-soma-rp` (names, parents and offsets of NVIDIA Kimodo's
/// `SOMASkeleton30`, Apache-2.0).
class KimodoSkeleton {
  const KimodoSkeleton._({
    required this.key,
    required this.names,
    required this.parents,
    required this.offsets,
    required this.rightHip,
    required this.leftHip,
    required this.chains,
  });

  final String key;
  final List<String> names;
  final List<int> parents;

  /// `[joints, 3]` parent-local rest offsets.
  final List<double> offsets;

  final int rightHip;
  final int leftHip;

  /// The end-effector groups (`LeftFoot`, `RightFoot`, `LeftHand`,
  /// `RightHand`, `Hips`): the joints whose positions a constraint on the
  /// group pins. Its rotation is pinned on the chain's first joint.
  final Map<String, List<String>> chains;

  int get jointCount => names.length;

  /// The root joint (the pelvis).
  int get root => 0;

  /// Values per frame of this skeleton's motion representation: smooth root
  /// (3), heading (2), joint positions (3 J), rotations (6 J), velocities
  /// (3 J), foot contacts (4).
  int get motionDim => 9 + 12 * jointCount;

  int indexOf(String name) => names.indexOf(name);

  int _index(String name) {
    final i = names.indexOf(name);
    if (i < 0) throw ArgumentError.value(name, 'joint', 'not a $key joint');
    return i;
  }

  /// The joints a constraint on the end-effector groups [groups] pins:
  /// rotations (each chain's first joint) and positions (the whole chain).
  ({List<int> rotations, List<int> positions}) expand(List<String> groups) {
    final rot = <int>[], pos = <int>[];
    for (final g in groups) {
      final chain = chains[g];
      if (chain == null) {
        throw ArgumentError.value(
          g,
          'joint_names',
          'one of ${chains.keys.join(', ')}',
        );
      }
      rot.add(_index(chain.first));
      pos.addAll(chain.map(_index));
    }
    return (rotations: rot, positions: pos);
  }

  /// Forward kinematics: the pose for parent-local rotations [localXyzw]
  /// (`[joints, 4]`, normalised on read) with the root at [root].
  KimodoPose pose(List<double> localXyzw, List<double> root) {
    final n = jointCount;
    if (localXyzw.length != n * 4 || root.length != 3) {
      throw ArgumentError('needs $n rotations and a root position');
    }
    final positions = Float64List(n * 3);
    final rotations = Float64List(n * 9);
    final local = Float64List(9);
    for (var j = 0; j < n; j++) {
      _quatToMatrix(localXyzw, j * 4, local);
      final p = parents[j];
      if (p < 0) {
        rotations.setRange(j * 9, j * 9 + 9, local);
        for (var k = 0; k < 3; k++) {
          positions[j * 3 + k] = root[k] + offsets[j * 3 + k];
        }
      } else {
        _mul3(rotations, p * 9, local, 0, rotations, j * 9);
        for (var r = 0; r < 3; r++) {
          var v = 0.0;
          for (var k = 0; k < 3; k++) {
            v += rotations[p * 9 + r * 3 + k] * offsets[j * 3 + k];
          }
          positions[j * 3 + r] = positions[p * 3 + r] + v;
        }
      }
    }
    return KimodoPose(positions, rotations);
  }

  /// Frame [frame] of [motion] (a motion of this skeleton).
  KimodoPose motionPose(KimodoMotion motion, int frame) {
    if (motion.joints != jointCount) {
      throw ArgumentError(
        'the motion has ${motion.joints} joints, $key has $jointCount',
      );
    }
    RangeError.checkValueInInterval(frame, 0, motion.frames - 1, 'frame');
    final n = jointCount;
    final r = motion.localRotationsXyzw;
    return pose(
      [for (var i = frame * n * 4; i < (frame + 1) * n * 4; i++) r[i]],
      motion.rootPosition(frame),
    );
  }

  /// The heading of [pose] in radians: the direction the hips face, from
  /// the right hip to the left one turned a quarter (0 faces +Z, a positive
  /// angle turns towards +X).
  double heading(KimodoPose pose) {
    final dx = pose.positions[rightHip * 3] - pose.positions[leftHip * 3];
    final dz = pose.positions[rightHip * 3 + 2] - pose.positions[leftHip * 3 + 2];
    return math.atan2(dz, -dx);
  }

  static final KimodoSkeleton soma30 = KimodoSkeleton._(
    key: 'somaskel30',
    names: const [
      'Hips', 'Spine1', 'Spine2', 'Chest', 'Neck1', 'Neck2', 'Head', 'Jaw', //
      'LeftEye', 'RightEye', 'LeftShoulder', 'LeftArm', 'LeftForeArm',
      'LeftHand', 'LeftHandThumbEnd', 'LeftHandMiddleEnd', 'RightShoulder',
      'RightArm', 'RightForeArm', 'RightHand', 'RightHandThumbEnd',
      'RightHandMiddleEnd', 'LeftLeg', 'LeftShin', 'LeftFoot', 'LeftToeBase',
      'RightLeg', 'RightShin', 'RightFoot', 'RightToeBase',
    ],
    parents: const [
      -1, 0, 1, 2, 3, 4, 5, 6, 6, 6, 3, 10, 11, 12, 13, 13, 3, 16, 17, 18, //
      19, 19, 0, 22, 23, 24, 0, 26, 27, 28,
    ],
    offsets: const [
      0, 0, 0, //
      -.00013727, .0500376256, -.00053726669,
      -1.86574103e-9, .0712530139, -.000298248546,
      -5.75188398e-9, .0755006305, -.00815970992,
      -.00181676517, .263112953, -.00553348292,
      -2.85102231e-8, .0770939664, .0230258546,
      -4.5975437e-8, .0612891595, .0195370861,
      2.63687901e-5, .0047559225, .0309494062,
      .0320638079, .0538020513, .0758688308,
      -.0322244017, .05361869, .0755823359,
      .0162165175, .232371641, .0511341324,
      .149198457, 2.19397873e-8, -.0550232576,
      .287393078, 2.50268389e-9, -2.58787737e-5,
      .270939812, -7.06625108e-9, 2.60897248e-5,
      .122686267, -.0322017573, .0483306876,
      .190119595, -.00312878387, -.000339570373,
      -.0138011824, .231803086, .0521415786,
      -.150371962, 1.17387901e-7, -.0554560437,
      -.287366393, 1.87628082e-8, -2.59709359e-5,
      -.271336198, -1.16767401e-9, 2.61269368e-5,
      -.122642483, -.0321145448, .0480403904,
      -.190005945, -.00306615542, -.0003157343,
      .10043214, -.0843452671, .0259565473,
      -1e-8, -.432217537, -.00802912805,
      1e-8, -.421550959, -.0348152298,
      0, -.0505947206, .132315294,
      -.10047278, -.0829525995, .0262031695,
      1e-8, -.433622059, -.00805555828,
      2e-8, -.421173943, -.0347839785,
      -3.42907669e-9, -.0507960932, .132841956,
    ],
    rightHip: 26,
    leftHip: 22,
    chains: const {
      'LeftFoot': ['LeftFoot', 'LeftToeBase'],
      'RightFoot': ['RightFoot', 'RightToeBase'],
      'LeftHand': ['LeftHand', 'LeftHandMiddleEnd'],
      'RightHand': ['RightHand', 'RightHandMiddleEnd'],
      'Hips': ['Hips'],
    },
  );
}

void _quatToMatrix(List<double> q, int o, Float64List out) {
  var x = q[o], y = q[o + 1], z = q[o + 2], w = q[o + 3];
  final n = math.sqrt(x * x + y * y + z * z + w * w);
  if (n > 0) {
    x /= n;
    y /= n;
    z /= n;
    w /= n;
  } else {
    w = 1;
  }
  out
    ..[0] = 1 - 2 * (y * y + z * z)
    ..[1] = 2 * (x * y - z * w)
    ..[2] = 2 * (x * z + y * w)
    ..[3] = 2 * (x * y + z * w)
    ..[4] = 1 - 2 * (x * x + z * z)
    ..[5] = 2 * (y * z - x * w)
    ..[6] = 2 * (x * z - y * w)
    ..[7] = 2 * (y * z + x * w)
    ..[8] = 1 - 2 * (x * x + y * y);
}

/// out[oo..] = a[ao..] · b[bo..] (3×3, row-major). [out] may alias neither.
void _mul3(
  List<double> a,
  int ao,
  List<double> b,
  int bo,
  Float64List out,
  int oo,
) {
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      var v = 0.0;
      for (var k = 0; k < 3; k++) {
        v += a[ao + i * 3 + k] * b[bo + k * 3 + j];
      }
      out[oo + i * 3 + j] = v;
    }
  }
}
