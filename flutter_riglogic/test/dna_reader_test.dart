import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riglogic/flutter_riglogic.dart';

void main() {
  group('DnaReader', () {
    const fixturePath = 'test/fixtures/sample.dna';

    test('verifies fixture file exists and has expected size', () {
      final file = File(fixturePath);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), equals(4164));
    });

    test('reads DNA metadata and hierarchy from file stream', () {
      final reader = DnaReader.fromFile(fixturePath);
      addTearDown(reader.dispose);

      expect(reader.name, equals('test'));
      expect(reader.lodCount, equals(2));

      expect(reader.jointCount, equals(9));
      expect(reader.getJointName(0), equals('JA'));
      expect(reader.getJointName(1), equals('JB'));
      expect(reader.getJointName(8), equals('JI'));

      expect(reader.blendShapeChannelCount, equals(9));
      expect(reader.getBlendShapeChannelName(0), equals('BA'));
      expect(reader.getBlendShapeChannelName(1), equals('BB'));
      expect(reader.getBlendShapeChannelName(8), equals('BI'));

      expect(reader.rawControlCount, equals(9));
      expect(reader.getRawControlName(0), equals('RA'));
      expect(reader.getRawControlName(1), equals('RB'));

      expect(reader.animatedMapCount, equals(10));
      expect(reader.getAnimatedMapName(0), equals('AA'));
    });

    test('reads DNA from in-memory byte buffer', () {
      final bytes = File(fixturePath).readAsBytesSync();
      final reader = DnaReader.fromMemory(bytes);
      addTearDown(reader.dispose);

      expect(reader.name, equals('test'));
      expect(reader.jointCount, equals(9));
      expect(reader.blendShapeChannelCount, equals(9));
      expect(reader.rawControlCount, equals(9));
    });
  });
}
