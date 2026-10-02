import 'dart:io';
import 'dart:math' as math;

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

void main() {
  group('KimodoModel.load', () {
    test('a missing GGUF fails with the runtime reason and the path', () async {
      final dir = Directory.systemTemp.createTempSync('kimodo_missing');
      addTearDown(() => dir.deleteSync(recursive: true));
      final motion = '${dir.path}${Platform.pathSeparator}absent-motion.gguf';
      await expectLater(
        KimodoModel.load(
          motionGguf: motion,
          textGguf: '${dir.path}${Platform.pathSeparator}absent-text.gguf',
          backend: const KimodoBackend(device: KimodoDevice.cpu),
        ),
        throwsA(
          isA<KimodoException>()
              .having(
                (e) => e.message,
                'message',
                contains('cannot open GGUF file'),
              )
              .having((e) => e.message, 'message', contains(motion)),
        ),
      );
    });

    test('a file that is not GGUF is refused', () async {
      final dir = Directory.systemTemp.createTempSync('kimodo_notgguf');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bogus = File('${dir.path}${Platform.pathSeparator}model.gguf')
        ..writeAsBytesSync(List<int>.generate(4096, (i) => i % 251));
      await expectLater(
        KimodoModel.load(
          motionGguf: bogus.path,
          textGguf: bogus.path,
          backend: const KimodoBackend(device: KimodoDevice.cpu),
        ),
        throwsA(
          isA<KimodoException>().having(
            (e) => e.message,
            'message',
            contains('not a GGUF file'),
          ),
        ),
      );
    });
  });

  group('generation', skip: _skip, () {
    late KimodoModel model;
    setUpAll(() async {
      model = await KimodoModel.load(
        motionGguf: _files!.motion,
        textGguf: _files!.text,
      );
    });
    tearDownAll(() => model.dispose());

    void expectUnitQuaternions(KimodoMotion m) {
      final r = m.localRotationsXyzw;
      for (var i = 0; i < r.length; i += 4) {
        final n = math.sqrt(
          r[i] * r[i] +
              r[i + 1] * r[i + 1] +
              r[i + 2] * r[i + 2] +
              r[i + 3] * r[i + 3],
        );
        expect(n, closeTo(1, 1e-3));
      }
    }

    test(
      'a walk forward: 90 frames on the 30-joint SOMA skeleton, moving +Z',
      () async {
        final m = await model.generate(
          'a person walks forward',
          frames: 90,
          options: const KimodoGenerationOptions(seed: 7),
        );
        expect(m.frames, 90);
        expect(m.joints, 30);
        expectUnitQuaternions(m);
        final start = m.rootPosition(0), end = m.rootPosition(89);
        expect(start[0].abs(), lessThan(0.2));
        expect(start[2].abs(), lessThan(0.2));
        expect(start[1], inInclusiveRange(0.6, 1.2), reason: 'hips height, m');
        expect(end[2] - start[2], greaterThan(0.5), reason: 'walks along +Z');
        expect(m.rootPositions.every((v) => v.isFinite), isTrue);
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );

    test('the same prompt, length and seed give the same motion', () async {
      const o = KimodoGenerationOptions(seed: 3, diffusionSteps: 20);
      final a = await model.generate('a person jumps', frames: 45, options: o);
      final b = await model.generate('a person jumps', frames: 45, options: o);
      expect(a.localRotationsXyzw, b.localRotationsXyzw);
      expect(a.rootPositions, b.rootPositions);
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('a two-prompt sequence plays both in one motion', () async {
      final m = await model.generateSequence(const [
        KimodoSegment('a person walks forward', 60),
        KimodoSegment('a person waves with the right hand', 60),
      ], options: const KimodoGenerationOptions(seed: 11, diffusionSteps: 50));
      expect(m.joints, 30);
      expect(m.frames, inInclusiveRange(115, 125));
      expectUnitQuaternions(m);
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}
