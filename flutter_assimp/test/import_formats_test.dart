import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_assimp/flutter_assimp.dart';
import 'package:flutter_test/flutter_test.dart';

/// The formats besides FBX and OBJ that the bridge reads: each converts from
/// its file with the texture path it names kept in the report.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('assimp_formats_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, dynamic> gltf(Uint8List glb) {
    final length = ByteData.sublistView(glb).getUint32(12, Endian.little);
    return jsonDecode(utf8.decode(glb.sublist(20, 20 + length)))
        as Map<String, dynamic>;
  }

  int triangles(Map<String, dynamic> json) {
    var n = 0;
    for (final mesh in (json['meshes'] as List? ?? const [])) {
      for (final p in (mesh as Map)['primitives'] as List) {
        final indices = (p as Map)['indices'] as int?;
        n += indices == null
            ? 0
            : ((json['accessors'] as List)[indices] as Map)['count'] as int;
      }
    }
    return n ~/ 3;
  }

  List<String> texturePaths(Map<String, dynamic> report) => [
    for (final m in (report['material_details'] as List? ?? const []))
      for (final t in ((m as Map)['textures'] as List? ?? const []))
        '${(t as Map)['path']}',
  ];

  for (final (ext, texture) in [
    ('dae', 'Maps/crate.png'),
    ('3ds', 'CRATE.PNG'),
    ('ply', 'Maps/crate.png'),
    ('x', 'Maps/crate.png'),
    ('stl', null),
  ]) {
    test('a textured quad in .$ext converts from its file', () {
      if (!FlutterAssimp.isAvailable) {
        markTestSkipped('Assimp bridge not loaded');
        return;
      }
      final file = File('${dir.path}/quad.$ext');
      final content = quadIn(ext, texture);
      if (content is String) {
        file.writeAsStringSync(content);
      } else {
        file.writeAsBytesSync(content as List<int>);
      }

      final c = FlutterAssimp.convertFileForImport(
        file.path,
        options: AssimpConvertOptions.normalize,
      );

      expect(c.error, isNull);
      final json = gltf(c.glb!);
      expect(triangles(json), 2);
      if (texture != null) expect(texturePaths(c.report), contains(texture));
    });
  }

  test('the supported formats are the ones the bridge reads', () {
    for (final f in [
      'm.fbx',
      'm.OBJ',
      'm.dae',
      'm.3ds',
      'm.ply',
      'm.x',
      'm.stl',
      '.dae',
    ]) {
      expect(FlutterAssimp.isSupportedFormat(f), isTrue, reason: f);
    }
    for (final f in ['m.blend', 'm.lwo', 'm.md2', 'm.txt', 'm.glb']) {
      expect(FlutterAssimp.isSupportedFormat(f), isFalse, reason: f);
    }
    if (FlutterAssimp.isAvailable) {
      expect(
        FlutterAssimp.importExtensions,
        containsAll(['fbx', 'obj', 'dae', '3ds', 'ply', 'x', 'stl']),
      );
    }
  });
}

/// A 2 × 2 quad (two triangles, UVs, one material "Crate" sampling [texture])
/// written as a real file of format [ext].
Object quadIn(String ext, String? texture) => switch (ext) {
  'dae' => colladaQuad(texture!),
  '3ds' => threeDsQuad(texture!),
  'ply' =>
    'ply\nformat ascii 1.0\ncomment TextureFile $texture\n'
        'element vertex 4\nproperty float x\nproperty float y\nproperty float z\nproperty float s\nproperty float t\n'
        'element face 2\nproperty list uchar int vertex_indices\nend_header\n'
        '-1 0 0 0 0\n1 0 0 1 0\n1 2 0 1 1\n-1 2 0 0 1\n3 0 1 2\n3 0 2 3\n',
  'x' =>
    'xof 0303txt 0032\n'
        'Frame Quad {\n FrameTransformMatrix { 1.0,0.0,0.0,0.0, 0.0,1.0,0.0,0.0, 0.0,0.0,1.0,0.0, 0.0,0.0,0.0,1.0;; }\n'
        ' Mesh {\n  4;\n  -1.0;0.0;0.0;, 1.0;0.0;0.0;, 1.0;2.0;0.0;, -1.0;2.0;0.0;;\n'
        '  2;\n  3;0,2,1;, 3;0,3,2;;\n'
        '  MeshTextureCoords { 4; 0.0;1.0;, 1.0;1.0;, 1.0;0.0;, 0.0;0.0;; }\n'
        '  MeshMaterialList { 1; 2; 0, 0;;\n'
        '   Material Crate { 1.0;1.0;1.0;1.0;; 0.0; 0.0;0.0;0.0;; 0.0;0.0;0.0;; TextureFilename { "$texture"; } }\n'
        '  }\n }\n}\n',
  'stl' =>
    'solid quad\n'
        'facet normal 0 0 1\nouter loop\nvertex -1 0 0\nvertex 1 0 0\nvertex 1 2 0\nendloop\nendfacet\n'
        'facet normal 0 0 1\nouter loop\nvertex -1 0 0\nvertex 1 2 0\nvertex -1 2 0\nendloop\nendfacet\n'
        'endsolid quad\n',
  _ => throw ArgumentError(ext),
};

String colladaQuad(String texture) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
  <asset><unit name="meter" meter="1"/><up_axis>Y_UP</up_axis></asset>
  <library_images><image id="crate_png" name="crate_png"><init_from>$texture</init_from></image></library_images>
  <library_effects><effect id="crate-fx"><profile_COMMON>
    <newparam sid="crate-surface"><surface type="2D"><init_from>crate_png</init_from></surface></newparam>
    <newparam sid="crate-sampler"><sampler2D><source>crate-surface</source></sampler2D></newparam>
    <technique sid="common"><lambert><diffuse><texture texture="crate-sampler" texcoord="UVMap"/></diffuse></lambert></technique>
  </profile_COMMON></effect></library_effects>
  <library_materials><material id="Crate-mat" name="Crate"><instance_effect url="#crate-fx"/></material></library_materials>
  <library_geometries><geometry id="quad" name="Quad"><mesh>
    <source id="pos"><float_array id="pos-a" count="12">-1 0 0 1 0 0 1 2 0 -1 2 0</float_array>
      <technique_common><accessor source="#pos-a" count="4" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>
    <source id="uv"><float_array id="uv-a" count="8">0 0 1 0 1 1 0 1</float_array>
      <technique_common><accessor source="#uv-a" count="4" stride="2"><param name="S" type="float"/><param name="T" type="float"/></accessor></technique_common></source>
    <vertices id="verts"><input semantic="POSITION" source="#pos"/></vertices>
    <triangles material="Crate" count="2"><input semantic="VERTEX" source="#verts" offset="0"/><input semantic="TEXCOORD" source="#uv" offset="1" set="0"/>
      <p>0 0 1 1 2 2 0 0 2 2 3 3</p></triangles>
  </mesh></geometry></library_geometries>
  <library_visual_scenes><visual_scene id="scene"><node id="QuadNode" name="Quad">
    <instance_geometry url="#quad"><bind_material><technique_common>
      <instance_material symbol="Crate" target="#Crate-mat"><bind_vertex_input semantic="UVMap" input_semantic="TEXCOORD" input_set="0"/></instance_material>
    </technique_common></bind_material></instance_geometry>
  </node></visual_scene></library_visual_scenes>
  <scene><instance_visual_scene url="#scene"/></scene>
</COLLADA>
''';

/// A binary 3DS file: one mesh object with UVs and one material whose
/// diffuse map is [texture] (3DS stores bare 8.3 names).
Uint8List threeDsQuad(String texture) {
  Uint8List chunk(int id, List<Uint8List> body) {
    final length = 6 + body.fold<int>(0, (n, b) => n + b.length);
    final head = ByteData(6)
      ..setUint16(0, id, Endian.little)
      ..setUint32(2, length, Endian.little);
    return Uint8List.fromList([
      ...head.buffer.asUint8List(),
      for (final b in body) ...b,
    ]);
  }

  Uint8List cstr(String s) => Uint8List.fromList([...latin1.encode(s), 0]);
  Uint8List u16(List<int> v) {
    final d = ByteData(v.length * 2);
    for (var i = 0; i < v.length; i++) {
      d.setUint16(i * 2, v[i], Endian.little);
    }
    return d.buffer.asUint8List();
  }

  Uint8List u32(int v) =>
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();
  Uint8List f32(List<double> v) {
    final d = ByteData(v.length * 4);
    for (var i = 0; i < v.length; i++) {
      d.setFloat32(i * 4, v[i], Endian.little);
    }
    return d.buffer.asUint8List();
  }

  final material = chunk(0xAFFF, [
    chunk(0xA000, [cstr('Crate')]),
    chunk(0xA020, [
      chunk(0x0011, [
        Uint8List.fromList([255, 255, 255]),
      ]),
    ]),
    chunk(0xA200, [
      chunk(0x0030, [
        u16([100]),
      ]),
      chunk(0xA300, [cstr(texture)]),
    ]),
  ]);
  final mesh = chunk(0x4100, [
    chunk(0x4110, [
      u16([4]),
      f32([-1, 0, 0, 1, 0, 0, 1, 0, 2, -1, 0, 2]),
    ]),
    chunk(0x4140, [
      u16([4]),
      f32([0, 0, 1, 0, 1, 1, 0, 1]),
    ]),
    chunk(0x4120, [
      u16([2, 0, 1, 2, 0, 0, 2, 3, 0]),
      chunk(0x4130, [
        cstr('Crate'),
        u16([2, 0, 1]),
      ]),
    ]),
    chunk(0x4160, [
      f32([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]),
    ]),
  ]);
  return chunk(0x4D4D, [
    chunk(0x0002, [u32(3)]),
    chunk(0x3D3D, [
      chunk(0x3D3E, [u32(3)]),
      material,
      chunk(0x4000, [cstr('Quad'), mesh]),
    ]),
  ]);
}
