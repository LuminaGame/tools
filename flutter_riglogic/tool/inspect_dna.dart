import 'dart:io';
import 'package:flutter_riglogic/flutter_riglogic.dart';

void main() {
  final bytes = File('test/fixtures/sample.dna').readAsBytesSync();
  final reader = DnaReader.fromMemory(bytes);
  print('Name: ${reader.name}');
  print('LODs: ${reader.lodCount}');
  print('Joints: ${reader.jointCount}');
  for (var i = 0; i < reader.jointCount; i++) {
    print('  Joint $i: ${reader.getJointName(i)}');
  }
  print('BlendShapes: ${reader.blendShapeChannelCount}');
  for (var i = 0; i < reader.blendShapeChannelCount; i++) {
    print('  BS $i: ${reader.getBlendShapeChannelName(i)}');
  }
  print('RawControls: ${reader.rawControlCount}');
  for (var i = 0; i < reader.rawControlCount; i++) {
    print('  RC $i: ${reader.getRawControlName(i)}');
  }
  print('AnimatedMaps: ${reader.animatedMapCount}');
  for (var i = 0; i < reader.animatedMapCount; i++) {
    print('  AM $i: ${reader.getAnimatedMapName(i)}');
  }

  print('Evaluating RigLogic...');
  final rigLogic = RigLogic.create(reader);
  final instance = RigInstance.create(rigLogic);
  instance.setRawControl(0, 0.7);
  instance.setRawControl(1, 0.4);
  rigLogic.calculate(instance);
  print('BS outputs: ${instance.getBlendShapeOutputs()}');
  print('Joint outputs (${instance.getJointOutputs().length}): ${instance.getJointOutputs()}');
  print('AM outputs: ${instance.getAnimatedMapOutputs()}');
}

