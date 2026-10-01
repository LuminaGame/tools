import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riglogic/flutter_riglogic.dart';

void main() {
  group('RigLogic & RigInstance Evaluation', () {
    const fixturePath = 'test/fixtures/sample.dna';

    late DnaReader reader;
    late RigLogic rigLogic;
    late RigInstance instance;

    setUp(() {
      reader = DnaReader.fromFile(fixturePath);
      rigLogic = RigLogic.create(reader);
      instance = RigInstance.create(rigLogic);
    });

    tearDown(() {
      instance.dispose();
      rigLogic.dispose();
      reader.dispose();
    });

    test('initializes outputs to zero or rest values before calculate', () {
      final blendShapes = instance.getBlendShapeOutputs();
      expect(blendShapes.length, equals(9));
      for (final val in blendShapes) {
        expect(val, equals(0.0));
      }

      final joints = instance.getJointOutputs();
      expect(joints.length, equals(81));
    });

    test(
      'evaluates controls [RA: 0.7, RB: 0.4] and computes facial channels and joint outputs',
      () {
        instance.setRawControl(0, 0.7);
        instance.setRawControl(1, 0.4);

        rigLogic.calculate(instance);

        final blendShapes = instance.getBlendShapeOutputs();
        expect(blendShapes.length, equals(9));
        // RA maps to BA (0.7), RB maps to BB (0.4)
        expect(blendShapes[0], closeTo(0.7, 0.001));
        expect(blendShapes[1], closeTo(0.4, 0.001));
        expect(blendShapes[2], closeTo(0.0, 0.001));

        final joints = instance.getJointOutputs();
        expect(joints.length, equals(81));
        // Joint A outputs: z-translation, x-rotation, z-rotation evaluated by OpenRigLogic
        expect(joints[2], closeTo(0.02, 0.001));
        expect(joints[3], closeTo(0.405, 0.001));
        expect(joints[5], closeTo(0.79, 0.001));

        final animatedMaps = instance.getAnimatedMapOutputs();
        expect(animatedMaps.length, equals(10));
        expect(animatedMaps[0], closeTo(0.7, 0.001));
        expect(animatedMaps[1], closeTo(0.86, 0.001));
        expect(animatedMaps[4], closeTo(1.0, 0.001));
        expect(animatedMaps[6], closeTo(0.4, 0.001));
        expect(animatedMaps[8], closeTo(0.2, 0.001));
      },
    );
  });
}
