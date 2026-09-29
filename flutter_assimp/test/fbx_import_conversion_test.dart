import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_assimp/flutter_assimp.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real Unreal FBX exports in `test-assets/FBX/` (see its README).
Directory get _fbxDir {
  final root = Platform.environment['LUMINA_TEST_ASSETS'] ?? '${Directory.current.parent.path}/test-assets';
  return Directory('$root/FBX');
}

File _asset(String relative) => File('${_fbxDir.path}/$relative');

Map<String, dynamic> _gltfJson(Uint8List glb) {
  final data = ByteData.sublistView(glb);
  final length = data.getUint32(12, Endian.little);
  return jsonDecode(utf8.decode(glb.sublist(20, 20 + length))) as Map<String, dynamic>;
}

/// Column-major 4×4 of a glTF node (matrix or TRS).
List<double> _local(Map node) {
  if (node['matrix'] != null) return [for (final v in node['matrix'] as List) (v as num).toDouble()];
  final t = [for (final v in (node['translation'] as List?) ?? [0, 0, 0]) (v as num).toDouble()];
  final r = [for (final v in (node['rotation'] as List?) ?? [0, 0, 0, 1]) (v as num).toDouble()];
  final s = [for (final v in (node['scale'] as List?) ?? [1, 1, 1]) (v as num).toDouble()];
  final x = r[0], y = r[1], z = r[2], w = r[3];
  return [
    (1 - 2 * (y * y + z * z)) * s[0], (2 * (x * y + z * w)) * s[0], (2 * (x * z - y * w)) * s[0], 0,
    (2 * (x * y - z * w)) * s[1], (1 - 2 * (x * x + z * z)) * s[1], (2 * (y * z + x * w)) * s[1], 0,
    (2 * (x * z + y * w)) * s[2], (2 * (y * z - x * w)) * s[2], (1 - 2 * (x * x + y * y)) * s[2], 0,
    t[0], t[1], t[2], 1,
  ];
}

List<double> _mul(List<double> a, List<double> b) => [
      for (var c = 0; c < 4; c++)
        for (var r = 0; r < 4; r++) a[r] * b[c * 4] + a[4 + r] * b[c * 4 + 1] + a[8 + r] * b[c * 4 + 2] + a[12 + r] * b[c * 4 + 3],
    ];

/// World-space bounds of every drawn mesh (accessor min/max corners).
({List<double> min, List<double> max}) _worldBounds(Map<String, dynamic> json) {
  final nodes = json['nodes'] as List;
  final meshes = json['meshes'] as List? ?? const [];
  final accessors = json['accessors'] as List;
  final lo = [double.infinity, double.infinity, double.infinity];
  final hi = [-double.infinity, -double.infinity, -double.infinity];
  void visit(int index, List<double> parent) {
    final node = nodes[index] as Map;
    final world = _mul(parent, _local(node));
    final mesh = node['mesh'] as int?;
    if (mesh != null) {
      for (final p in (meshes[mesh] as Map)['primitives'] as List) {
        final acc = accessors[((p as Map)['attributes'] as Map)['POSITION'] as int] as Map;
        final mn = [for (final v in acc['min'] as List) (v as num).toDouble()];
        final mx = [for (final v in acc['max'] as List) (v as num).toDouble()];
        for (var i = 0; i < 8; i++) {
          final c = [i & 1 == 0 ? mn[0] : mx[0], i & 2 == 0 ? mn[1] : mx[1], i & 4 == 0 ? mn[2] : mx[2]];
          for (var a = 0; a < 3; a++) {
            final v = world[a] * c[0] + world[4 + a] * c[1] + world[8 + a] * c[2] + world[12 + a];
            lo[a] = math.min(lo[a], v);
            hi[a] = math.max(hi[a], v);
          }
        }
      }
    }
    for (final child in (node['children'] as List?) ?? const []) {
      visit(child as int, world);
    }
  }

  final identity = [1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1].map((e) => e.toDouble()).toList();
  for (final root in ((json['scenes'] as List)[json['scene'] as int? ?? 0] as Map)['nodes'] as List) {
    visit(root as int, identity);
  }
  return (min: lo, max: hi);
}

void main() {
  final haveAssets = _fbxDir.existsSync();

  test('version reports major.minor and the git commit, not a decimal revision', () {
    if (!FlutterAssimp.isAvailable) return;
    expect(FlutterAssimp.version, matches(RegExp(r'^\d+\.\d+ \(commit [0-9a-f]{8}\)$')));
    expect(FlutterAssimp.version, isNot(contains('1181963359')));
  });

  test('the bridge comes from the package native-assets hook and has the normalized conversion', () {
    expect(FlutterAssimp.isAvailable, isTrue);
    expect(AssimpBindings.instance.librarySource, 'native-assets');
    expect(AssimpBindings.instance.hasExtendedConversion, isTrue);
  });

  group('convertFileForImport on real Unreal FBX exports', () {
    test('SM_Casino_Chair: cm/Z-up baked into a 1.0 m tall, upright glTF; UCX hull removed and reported', () {
      final fbx = _asset('StaticMeshes/SM_Casino_Chair.FBX');
      if (!haveAssets || !fbx.existsSync()) return markTestSkipped('test-assets/FBX missing');

      final result = FlutterAssimp.convertFileForImport(fbx.path);
      expect(result.error, isNull);
      expect(result.success, isTrue);

      final report = result.report;
      expect(report['normalized'], isTrue);
      expect((report['unit_scale'] as num).toDouble(), closeTo(0.01, 1e-9));
      expect(report['up_axis'], '+Z');
      expect(((report['source_metadata'] as Map)['UnitScaleFactor'] as num).toDouble(), closeTo(1.0, 1e-6));

      final json = _gltfJson(result.glb!);
      final bounds = _worldBounds(json);
      final height = bounds.max[1] - bounds.min[1];
      // 96.8 cm of chair along +Y (upright); the 100.7 cm the raw conversion
      // reported was the taller collision hull, now removed.
      expect(height, closeTo(0.968, 0.01), reason: 'the chair is ~0.97 m tall along +Y (upright)');
      expect(bounds.min[1], closeTo(0.0, 0.01), reason: 'it stands on the ground plane');
      // The footprint is well under a metre: nothing is still in centimetres.
      expect(bounds.max[0] - bounds.min[0], lessThan(1.0));
      expect(bounds.max[2] - bounds.min[2], lessThan(1.0));

      final names = [
        for (final n in json['nodes'] as List) (n as Map)['name'],
        for (final m in (json['meshes'] as List? ?? const [])) (m as Map)['name'],
      ].whereType<String>();
      expect(names.where((n) => n.toUpperCase().startsWith('UCX_')), isEmpty);

      final hulls = (report['collision'] as List).cast<Map>();
      expect(hulls, isNotEmpty);
      expect(hulls.first['name'], startsWith('UCX_'));
      expect(hulls.first['shape'], 'convex');
      final points = (hulls.first['points'] as List).cast<num>();
      expect(points.length, (hulls.first['vertex_count'] as num).toInt() * 3);
      final hullMaxY = ((hulls.first['max'] as List)[1] as num).toDouble();
      expect(hullMaxY, closeTo(1.007, 0.005), reason: 'hull points are in metres, Y up');
    });

    // Disconnected UCX_ pieces are separate convex
    // elements, which needs the hull faces.
    test('every reported hull carries its triangles (indices into its points)', () {
      if (!haveAssets) return markTestSkipped('test-assets/FBX missing');
      for (final name in ['SM_Casino_Chair', 'SM_Laptop', 'SM_Slot_Machine', 'SM_Table']) {
        final result = FlutterAssimp.convertFileForImport(_asset('StaticMeshes/$name.FBX').path);
        expect(result.success, isTrue, reason: result.error);
        final hulls = (result.report['collision'] as List).cast<Map>();
        expect(hulls, isNotEmpty, reason: name);
        for (final hull in hulls) {
          final vertices = (hull['vertex_count'] as num).toInt();
          final triangles = (hull['triangles'] as List?)?.cast<num>();
          expect(triangles, isNotNull, reason: '${hull['name']} has no triangles');
          expect(triangles!.length, (hull['face_count'] as num).toInt() * 3, reason: '${hull['name']}');
          expect(triangles.every((i) => i >= 0 && i < vertices), isTrue, reason: '${hull['name']}: index out of range');
        }
      }
    });

    test('AS_Poker_Dealer_Idle_01: one take of one channel per bone, in metres, bones named as in Unreal', () {
      final fbx = _asset('Animations/AS_Poker_Dealer_Idle_01.FBX');
      if (!haveAssets || !fbx.existsSync()) return markTestSkipped('test-assets/FBX missing');

      final result = FlutterAssimp.convertFileForImport(fbx.path);
      expect(result.success, isTrue, reason: result.error);
      final takes = (result.report['takes'] as List).cast<Map>();
      expect(takes, hasLength(1));
      final channels = (takes.single['channels'] as num).toInt();
      expect(channels, greaterThan(50));
      expect((takes.single['duration_seconds'] as num).toDouble(), greaterThan(0.5));

      final json = _gltfJson(result.glb!);
      // The exporter writes one glTF animation per channel, in take order.
      expect((json['animations'] as List).length, channels);
      final nodes = (json['nodes'] as List).cast<Map>();
      final pelvis = nodes.firstWhere((n) => n['name'] == 'pelvis');
      final m = [for (final v in pelvis['matrix'] as List) (v as num).toDouble()];
      // Pelvis ~0.9 m up (+Y) from root, not 92 cm along +Z.
      expect(m[13], inInclusiveRange(0.8, 1.1));
      expect(m[14].abs(), lessThan(0.1));
      expect(nodes.map((n) => n['name']), containsAll(['root', 'pelvis', 'thigh_l', 'hand_r', 'head']));
      expect(nodes.map((n) => n['name']).where((n) => '$n'.contains(r'$AssimpFbx$')), isEmpty);
    });

    test('SKM_Manny_Simple: a skinned FBX converts to a skinned glTF in metres', () {
      final fbx = _asset('SkeletalMeshes/SKM_Manny_Simple.FBX');
      if (!haveAssets || !fbx.existsSync()) return markTestSkipped('test-assets/FBX missing');

      final result = FlutterAssimp.convertFileForImport(fbx.path);
      expect(result.success, isTrue, reason: result.error);
      expect((result.report['skinned_meshes'] as num).toInt(), greaterThan(0));
      final json = _gltfJson(result.glb!);
      expect((json['skins'] as List?) ?? const [], isNotEmpty);
      final bounds = _worldBounds(json);
      // Accessor bounds of a skinned mesh are in bind space; the mannequin is ~1.8 m.
      expect(bounds.max[1] - bounds.min[1], inInclusiveRange(1.5, 2.1));
    });

    // The importer maps each FBX material to PBR itself, so
    // the report carries what Assimp read, in the GLB's material order.
    test('SM_Slot_Machine: material_details carry each material\'s FBX colours, Phong scalars and texture refs', () {
      final fbx = _asset('StaticMeshes/SM_Slot_Machine.FBX');
      if (!haveAssets || !fbx.existsSync()) return markTestSkipped('test-assets/FBX missing');

      final result = FlutterAssimp.convertFileForImport(fbx.path);
      expect(result.success, isTrue, reason: result.error);
      final details = (result.report['material_details'] as List?)?.cast<Map>();
      expect(details, isNotNull, reason: 'the report lists every material');
      final gltfNames = [for (final m in _gltfJson(result.glb!)['materials'] as List) (m as Map)['name']];
      expect([for (final d in details!) d['name']], gltfNames, reason: 'same order as the GLB materials');
      expect(gltfNames, [
        'MI_Plastic_Black_Matte_1', 'MI_Display_1', 'MI_Metal_0_3_Rough', 'MI_Light_Top',
        'M_Rubber_Foot_Rest', 'MI_Neon_Green', 'MI_Display_OFF', 'MI_Plastic_Black',
      ]);
      List<double> v(Map d, String key) => [for (final x in d[key] as List) (x as num).toDouble()];
      // Values of the raw FBX dump (Blender io_scene_fbx.parse_fbx).
      const diffuse = [
        [1.0, 0.98958, 0.98958], [0.02, 0.02, 0.02], [0.0, 0.0, 0.0], [0.8, 0.8, 0.8],
        [0.03, 0.03, 0.03], [0.8, 0.8, 0.8], [0.02, 0.02, 0.02], [0.390625, 0.386556, 0.386556],
      ];
      for (var i = 0; i < details.length; i++) {
        final d = details[i];
        for (var c = 0; c < 3; c++) {
          expect(v(d, 'diffuse')[c], closeTo(diffuse[i][c], 1e-4), reason: '${d['name']} diffuse');
          expect(v(d, 'emissive')[c], 0.0, reason: '${d['name']} emissive');
          expect(v(d, 'specular')[c], closeTo(0.2, 1e-6), reason: '${d['name']} specular');
        }
        expect((d['shininess'] as num).toDouble(), closeTo(20, 1e-6), reason: '${d['name']}');
        expect((d['opacity'] as num).toDouble(), closeTo(1, 1e-6), reason: '${d['name']}');
        expect(d['shading_model'], 'phong', reason: '${d['name']}');
      }
      final rubber = details[4]['textures'] as List;
      expect(rubber, hasLength(1));
      expect((rubber.single as Map)['type'], 'normals');
      expect((rubber.single as Map)['path'], 'W:/Warehouse/Staircase/T_Tread_Plate_Normal.png');
      expect((rubber.single as Map)['embedded'], isFalse);
      expect((rubber.single as Map)['uv'], 0);
      for (final i in [0, 1, 2, 3, 5, 6, 7]) {
        expect(details[i]['textures'], isEmpty, reason: '${details[i]['name']} references no texture');
      }
    });

    test('a missing file fails with a message instead of throwing', () {
      final result = FlutterAssimp.convertFileForImport('/nonexistent/model.fbx');
      expect(result.success, isFalse);
      expect(result.error, contains('does not exist'));
    });
  });
}
