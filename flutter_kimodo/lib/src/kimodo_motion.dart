import 'dart:typed_data';

/// One generated motion on kimodo's skeleton (SOMA: 30 joints).
///
/// Kimodo's frame: Y up, +Z forward, metres, 30 frames per second; the root
/// starts at X = Z = 0 facing +Z. [localRotationsXyzw] holds every joint's
/// parent-local rotation per frame (`[frames, joints, 4]`, x y z w; the
/// identity is the skeleton's rest T-pose) and [rootPositions] the root
/// joint's (hips') position per frame (`[frames, 3]`).
class KimodoMotion {
  /// Frames per second of every Kimodo motion.
  static const double frameRate = 30;

  final int frames;
  final int joints;
  final Float32List localRotationsXyzw;
  final Float32List rootPositions;

  KimodoMotion({
    required this.frames,
    required this.joints,
    required this.localRotationsXyzw,
    required this.rootPositions,
  }) {
    if (frames < 0 || joints < 0) {
      throw ArgumentError('frames and joints must not be negative');
    }
    if (localRotationsXyzw.length != frames * joints * 4) {
      throw ArgumentError.value(
        localRotationsXyzw.length,
        'localRotationsXyzw',
        'needs frames * joints * 4 = ${frames * joints * 4} values',
      );
    }
    if (rootPositions.length != frames * 3) {
      throw ArgumentError.value(
        rootPositions.length,
        'rootPositions',
        'needs frames * 3 = ${frames * 3} values',
      );
    }
  }

  /// Length in seconds.
  double get duration => frames / frameRate;

  /// Joint [joint]'s local rotation at [frame] as `[x, y, z, w]`.
  List<double> rotation(int frame, int joint) {
    RangeError.checkValidIndex(frame, null, 'frame', frames);
    RangeError.checkValidIndex(joint, null, 'joint', joints);
    final i = (frame * joints + joint) * 4;
    return [
      localRotationsXyzw[i],
      localRotationsXyzw[i + 1],
      localRotationsXyzw[i + 2],
      localRotationsXyzw[i + 3],
    ];
  }

  /// The root's position at [frame] as `[x, y, z]` metres.
  List<double> rootPosition(int frame) {
    RangeError.checkValidIndex(frame, null, 'frame', frames);
    return [
      rootPositions[frame * 3],
      rootPositions[frame * 3 + 1],
      rootPositions[frame * 3 + 2],
    ];
  }
}
