import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_assimp/flutter_assimp.dart';

void main() {
  group('FlutterAssimp Tests', () {
    test('Should check supported formats', () {
      expect(FlutterAssimp.isSupportedFormat('model.fbx'), isTrue);
      expect(FlutterAssimp.isSupportedFormat('.fbx'), isTrue);
      expect(FlutterAssimp.isSupportedFormat('mesh.OBJ'), isTrue);
      expect(FlutterAssimp.isSupportedFormat('scene.dae'), isTrue);
      expect(FlutterAssimp.isSupportedFormat('part.stl'), isTrue);
      expect(FlutterAssimp.isSupportedFormat('unsupported.txt'), isFalse);
    });

    test('Should query Assimp version string', () {
      final ver = FlutterAssimp.version;
      print('Assimp version: $ver, isAvailable: ${FlutterAssimp.isAvailable}');
      expect(ver.isNotEmpty, isTrue);
    });

    test('Should convert real blackjack_blender2.FBX to GLB file on disk', () async {
      final fbxFile = File('${Directory.current.parent.path}/test-assets/fixtures/blackjack_blender2.FBX');
      if (fbxFile.existsSync()) {
        final outGlb = File('${Directory.systemTemp.path}/test_convert_${DateTime.now().millisecondsSinceEpoch}.glb');
        final success = await FlutterAssimp.convertFileToGlb(fbxFile.path, outGlb.path);

        expect(success, isTrue);
        expect(outGlb.existsSync(), isTrue);
        expect(outGlb.lengthSync(), greaterThan(1000));

        final bytes = outGlb.readAsBytesSync();
        // Check glTF magic header "glTF" (0x67, 0x6C, 0x54, 0x46)
        expect(bytes[0], equals(0x67));
        expect(bytes[1], equals(0x6C));
        expect(bytes[2], equals(0x54));
        expect(bytes[3], equals(0x46));

        outGlb.deleteSync();
      }
    });

    test('Should convert real blackjack_blender2.FBX in-memory to GLB bytes', () async {
      final fbxFile = File('${Directory.current.parent.path}/test-assets/fixtures/blackjack_blender2.FBX');
      if (fbxFile.existsSync()) {
        final fbxBytes = fbxFile.readAsBytesSync();
        final glbBytes = await FlutterAssimp.convertMemoryToGlb(fbxBytes, hint: 'fbx');

        expect(glbBytes, isNotNull);
        expect(glbBytes!.length, greaterThan(1000));
        // Check glTF magic header "glTF"
        expect(glbBytes[0], equals(0x67));
        expect(glbBytes[1], equals(0x6C));
        expect(glbBytes[2], equals(0x54));
        expect(glbBytes[3], equals(0x46));
      }
    });
  });
}
