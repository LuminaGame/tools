// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_assimp/flutter_assimp.dart';

/// Converts a 3D model to GLB and prints the conversion report.
///
/// Call it from an app that depends on flutter_assimp, for example from its
/// `main` with the path of an FBX, OBJ, Collada, 3DS, PLY, DirectX or STL
/// file. The GLB is written next to the source.
Future<void> main(List<String> args) async {
  final source = args.isNotEmpty ? args.first : 'model.fbx';
  if (!FlutterAssimp.isAvailable) {
    print('The flutter_assimp native library is not loaded.');
    return;
  }
  if (!FlutterAssimp.isSupportedFormat(source)) {
    print(
      'Not a supported format: $source '
      '(${FlutterAssimp.importExtensions.join(', ')})',
    );
    return;
  }
  print('Assimp ${FlutterAssimp.version}');

  // Bake units and axes into standard glTF and drop collision hulls.
  final result = FlutterAssimp.convertFileForImport(
    source,
    options: AssimpConvertOptions.all,
  );
  if (!result.success) {
    print('Conversion failed: ${result.error}');
    return;
  }

  final target = '${source.substring(0, source.lastIndexOf('.'))}.glb';
  await File(target).writeAsBytes(result.glb!);
  print('Wrote $target (${result.glb!.length} bytes)');
  print(
    'Meshes: ${result.report['meshes']}, '
    'materials: ${result.report['materials']}, '
    'animation takes: ${(result.report['takes'] as List?)?.length ?? 0}',
  );
  final hulls = (result.report['collision'] as List?) ?? const [];
  print('Removed collision hulls: ${hulls.length}');
  if (hulls.isNotEmpty) {
    print(const JsonEncoder.withIndent('  ').convert(hulls.first));
  }
}
