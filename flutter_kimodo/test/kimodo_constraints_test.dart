import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_kimodo/flutter_kimodo.dart';
import 'package:flutter_test/flutter_test.dart';

/// The model files in KIMODO_MODELS_DIR (or the Kimodo plugin's model
/// folder); the generation tests skip without them.
final KimodoModelFiles? _files = KimodoModelFiles.find(
  KimodoModelFiles.defaultDirectory(),
);
final String? _skip = _files == null
    ? 'Kimodo weights not found in ${KimodoModelFiles.defaultDirectory().path} '
          '(set KIMODO_MODELS_DIR)'
    : null;

/// test/fixtures/constraints_parity.json, written by
/// tool/kimodo/constraints_parity_fixture.py from NVIDIA Kimodo's Python
/// reference: random poses and the conditioning tensors the reference builds
/// for constraint sets on them.
final Map<String, dynamic> _fixture =
    jsonDecode(File('test/fixtures/constraints_parity.json').readAsStringSync()) as Map<String, dynamic>;

List<double> _doubles(Object? list) => [for (final v in list! as List) (v as num).toDouble()];

KimodoPose _fixturePose(int frame) {
  final pose = _fixture['pose'] as Map<String, dynamic>;
  final positions = (pose['positions'] as List)[frame] as List;
  final rotations = (pose['global_rotations'] as List)[frame] as List;
  return KimodoPose(
    Float64List.fromList([for (final p in positions) ..._doubles(p)]),
    Float64List.fromList([
      for (final m in rotations)
        for (final row in m as List) ..._doubles(row),
    ]),
  );
}

List<KimodoGroundPoint>? _points(Object? list) =>
    list == null ? null : [for (final p in list as List) (x: (p[0] as num).toDouble(), z: (p[1] as num).toDouble())];

KimodoConstraint _fixtureConstraint(Map<String, dynamic> c) {
  final frames = (c['frames'] as List).cast<int>();
  final poses = [for (final f in frames) _fixturePose(f)];
  final smooth = _points(c['smooth_root_2d']);
  return switch (c['type']) {
    'Root2DConstraintSet' => KimodoRoot2DConstraint(
      frames: frames,
      points: smooth!,
      headings: c['global_root_heading'] == null
          ? null
          : [for (final h in c['global_root_heading'] as List) math.atan2((h[1] as num).toDouble(), (h[0] as num).toDouble())],
    ),
    'FullBodyConstraintSet' => KimodoFullBodyConstraint(frames: frames, poses: poses, smoothRoot: smooth),
    'LeftHandConstraintSet' => KimodoEndEffectorConstraint.leftHand(frames: frames, poses: poses, smoothRoot: smooth),
    'RightHandConstraintSet' => KimodoEndEffectorConstraint.rightHand(frames: frames, poses: poses, smoothRoot: smooth),
    'LeftFootConstraintSet' => KimodoEndEffectorConstraint.leftFoot(frames: frames, poses: poses, smoothRoot: smooth),
    'RightFootConstraintSet' => KimodoEndEffectorConstraint.rightFoot(frames: frames, poses: poses, smoothRoot: smooth),
    'EndEffectorConstraintSet' => KimodoEndEffectorConstraint(
      frames: frames,
      poses: poses,
      joints: (c['joint_names'] as List).cast<String>(),
      smoothRoot: smooth,
    ),
    _ => throw StateError('unknown constraint ${c['type']}'),
  };
}

double _distance(List<double> a, List<double> b) =>
    math.sqrt([for (var i = 0; i < 3; i++) (a[i] - b[i]) * (a[i] - b[i])].reduce((x, y) => x + y));

void main() {
  final skeleton = KimodoSkeleton.soma30;

  group('the conditioning matches NVIDIA Kimodo\'s Python reference', () {
    test('the SOMA30 skeleton has the reference\'s joints and hips', () {
      final s = _fixture['skeleton'] as Map<String, dynamic>;
      expect(skeleton.names, s['names']);
      expect([skeleton.rightHip, skeleton.leftHip], s['hips']);
      expect(skeleton.motionDim, 369);
    });

    test('forward kinematics gives the reference\'s positions and rotations', () {
      final pose = _fixture['pose'] as Map<String, dynamic>;
      final length = _fixture['length'] as int;
      for (var f = 0; f < length; f++) {
        final local = [for (final q in (pose['local_xyzw'] as List)[f] as List) ..._doubles(q)];
        final mine = skeleton.pose(local, _doubles((pose['roots'] as List)[f]));
        final ref = _fixturePose(f);
        for (var i = 0; i < mine.positions.length; i++) {
          expect(mine.positions[i], closeTo(ref.positions[i], 1e-6), reason: 'frame $f position $i');
        }
        for (var i = 0; i < mine.rotations.length; i++) {
          expect(mine.rotations[i], closeTo(ref.rotations[i], 1e-6), reason: 'frame $f rotation $i');
        }
      }
    });

    final cases = (_fixture['cases'] as Map<String, dynamic>).entries.toList();
    for (final entry in cases) {
      test('constraint set "${entry.key}"', () {
        final c = entry.value as Map<String, dynamic>;
        final constraints = KimodoConstraints([
          for (final set in c['constraints'] as List) _fixtureConstraint(set as Map<String, dynamic>),
        ]);
        final encoded = constraints.encode(_fixture['length'] as int);
        final expected = {for (final m in c['masked'] as List) m[0] as int: (m[1] as num).toDouble()};
        final masked = <int>{
          for (var i = 0; i < encoded.mask.length; i++)
            if (encoded.mask[i] != 0) i,
        };
        expect(masked, expected.keys.toSet());
        for (var i = 0; i < encoded.observed.length; i++) {
          final want = expected[i] ?? 0.0;
          expect(encoded.observed[i], closeTo(want, 1e-9), reason: 'value $i (frame ${i ~/ 369}, channel ${i % 369})');
          expect(encoded.mask[i], expected.containsKey(i) ? 1.0 : 0.0);
        }
      });
    }

    test('a frame outside the timeline and a joint without a smooth root are refused', () {
      final pose = _fixturePose(0);
      expect(
        () => KimodoConstraints([KimodoEndEffectorConstraint.leftHand(frames: [40], poses: [pose])]).encode(40),
        throwsRangeError,
      );
      expect(() => KimodoEndEffectorConstraint(frames: [1], poses: [pose], joints: ['Head']), returnsNormally);
      expect(
        () => KimodoConstraints([KimodoEndEffectorConstraint(frames: [1], poses: [pose], joints: ['Head'])]).encode(4),
        throwsArgumentError,
      );
    });
  });

  group('constrained generation', skip: _skip, () {
    late KimodoModel model;
    setUpAll(() async {
      model = await KimodoModel.load(motionGguf: _files!.motion, textGguf: _files!.text);
    });
    tearDownAll(() => model.dispose());

    test('a straight 3 m root path over 4 s ends within 0.3 m of its goal', () async {
      const frames = 120;
      // To the character's left (+X): an unconstrained walk goes forward (+Z).
      final path = KimodoRoot2DConstraint(
        frames: [for (var f = 0; f < frames; f++) f],
        points: [for (var f = 0; f < frames; f++) (x: 3.0 * f / (frames - 1), z: 0.0)],
      );
      final motion = await model.generate(
        'a person walks forward',
        frames: frames,
        constraints: KimodoConstraints([path]),
        options: const KimodoGenerationOptions(seed: 11),
      );
      expect(motion.frames, frames);
      final end = motion.rootPosition(frames - 1);
      final miss = math.sqrt(math.pow(end[0] - 3.0, 2) + math.pow(end[2], 2));
      expect(miss, lessThan(0.3), reason: 'root ends at (${end[0]}, ${end[2]})');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('a left-hand target at frame 60 is reached within 0.1 m', () async {
      const frames = 90, at = 60;
      const options = KimodoGenerationOptions(seed: 5);
      final base = await model.generate('a person stands and looks around', frames: frames, options: options);
      final pose = skeleton.motionPose(base, at);
      // Raise the left hand 25 cm and bring it 15 cm forward.
      final hand = skeleton.indexOf('LeftHand');
      final moved = Float64List.fromList(pose.positions);
      for (final j in skeleton.expand(const ['LeftHand']).positions) {
        moved[j * 3 + 1] += 0.25;
        moved[j * 3 + 2] += 0.15;
      }
      final target = [moved[hand * 3], moved[hand * 3 + 1], moved[hand * 3 + 2]];
      final motion = await model.generate(
        'a person stands and looks around',
        frames: frames,
        constraints: KimodoConstraints([
          KimodoEndEffectorConstraint.leftHand(frames: const [at], poses: [KimodoPose(moved, pose.rotations)]),
        ]),
        options: options,
      );
      final reached = skeleton.motionPose(motion, at).position(hand);
      expect(_distance(reached, target), lessThan(0.1), reason: 'hand at $reached, target $target');
      expect(_distance(pose.position(hand), target), greaterThan(0.25), reason: 'the target moved away from the base pose');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('constraints across two prompts steer the second one too', () async {
      const segments = [KimodoSegment('a person walks forward', 60), KimodoSegment('a person walks forward', 60)];
      final motion = await model.generateSequence(
        segments,
        constraints: KimodoConstraints([
          KimodoRoot2DConstraint(frames: const [0, 119], points: const [(x: 0.0, z: 0.0), (x: 2.0, z: 2.0)]),
        ]),
        options: const KimodoGenerationOptions(seed: 2),
      );
      expect(motion.frames, 120);
      final end = motion.rootPosition(119);
      final miss = math.sqrt(math.pow(end[0] - 2.0, 2) + math.pow(end[2] - 2.0, 2));
      expect(miss, lessThan(0.4), reason: 'root ends at (${end[0]}, ${end[2]})');
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}
