import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_assimp/flutter_assimp.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_formats_test.dart' show colladaQuad;

/// OBJ, FBX and Collada store V up (0 = bottom row of the image), glTF V down
/// (0 = top row). A converted GLB must therefore hold `1 - v`, exactly like a
/// glTF written by hand for the same quad.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('assimp_uv_'));
  tearDown(() => dir.deleteSync(recursive: true));

  // The quad every source below describes: corner positions with their UVs
  // in the source's V-up convention. Asymmetric in U and V.
  const corners = [
    ([-1.0, 0.0, 0.0], [0.0, 0.0]),
    ([1.0, 0.0, 0.0], [1.0, 0.0]),
    ([1.0, 2.0, 0.0], [1.0, 1.0]),
    ([-1.0, 2.0, 0.0], [0.0, 1.0]),
  ];

  /// The same quad written as glTF by hand: V down, so `1 - v`.
  final reference = texcoordsByPosition(handBuiltGlb(corners));

  File write(String name, Object content) {
    final file = File('${dir.path}/$name');
    content is String
        ? file.writeAsStringSync(content)
        : file.writeAsBytesSync(content as List<int>);
    return file;
  }

  void expectGltfUvs(
    Uint8List? glb, {
    int set = 0,
    Map<String, List<double>>? expected,
  }) {
    expect(glb, isNotNull, reason: FlutterAssimp.lastError);
    final uvs = texcoordsByPosition(glb!, set: set);
    final want = expected ?? reference;
    expect(uvs.keys, unorderedEquals(want.keys));
    for (final key in want.keys) {
      expect(uvs[key]![0], closeTo(want[key]![0], 1e-5), reason: 'u at $key');
      expect(uvs[key]![1], closeTo(want[key]![1], 1e-5), reason: 'v at $key');
    }
  }

  test(
    'the hand-built reference glTF puts V = 1 at the bottom-left corner',
    () {
      expect(reference['0,0,0'], [0.0, 1.0]);
      expect(reference['0,1,0'], [0.0, 0.0]);
    },
  );

  test('an OBJ quad converts from its file with glTF UVs', () {
    if (!FlutterAssimp.isAvailable) {
      return markTestSkipped('Assimp bridge not loaded');
    }
    final obj = write('quad.obj', objQuad);
    for (final options in [0, AssimpConvertOptions.all]) {
      final c = FlutterAssimp.convertFileForImport(obj.path, options: options);
      expect(c.error, isNull);
      expectGltfUvs(c.glb);
    }
  });

  test('an OBJ quad converts from memory with glTF UVs', () async {
    if (!FlutterAssimp.isAvailable) {
      return markTestSkipped('Assimp bridge not loaded');
    }
    expectGltfUvs(
      await FlutterAssimp.convertMemoryToGlb(
        Uint8List.fromList(utf8.encode(objQuad)),
        hint: 'obj',
      ),
    );
  });

  test('an OBJ quad converts file to file with glTF UVs', () async {
    if (!FlutterAssimp.isAvailable) {
      return markTestSkipped('Assimp bridge not loaded');
    }
    final obj = write('quad.obj', objQuad);
    final out = File('${dir.path}/quad.glb');
    expect(await FlutterAssimp.convertFileToGlb(obj.path, out.path), isTrue);
    expectGltfUvs(out.readAsBytesSync());
  });

  test('an FBX quad converts with glTF UVs on both UV sets', () async {
    if (!FlutterAssimp.isAvailable) {
      return markTestSkipped('Assimp bridge not loaded');
    }
    final fbx = write('quad.fbx', fbxQuad);
    // The second UV set (a lightmap layout) is the first one scaled by half.
    final lightmap = {
      for (final e in reference.entries)
        e.key: [e.value[0] / 2, 1 - (1 - e.value[1]) / 2],
    };
    for (final options in [0, AssimpConvertOptions.all]) {
      final c = FlutterAssimp.convertFileForImport(fbx.path, options: options);
      expect(c.error, isNull);
      expectGltfUvs(c.glb);
      expectGltfUvs(c.glb, set: 1, expected: lightmap);
    }
    expectGltfUvs(
      await FlutterAssimp.convertMemoryToGlb(
        Uint8List.fromList(utf8.encode(fbxQuad)),
        hint: 'fbx',
      ),
    );
  });

  test('a Collada quad converts with glTF UVs', () {
    if (!FlutterAssimp.isAvailable) {
      return markTestSkipped('Assimp bridge not loaded');
    }
    if (!FlutterAssimp.importExtensions.contains('dae')) {
      return markTestSkipped('bridge built without Collada');
    }
    final dae = write('quad.dae', colladaQuad('crate.png'));
    final c = FlutterAssimp.convertFileForImport(dae.path, options: 0);
    expect(c.error, isNull);
    expectGltfUvs(c.glb);
  });
}

const objQuad =
    'v -1 0 0\nv 1 0 0\nv 1 2 0\nv -1 2 0\n'
    'vt 0 0\nvt 1 0\nvt 1 1\nvt 0 1\n'
    'f 1/1 2/2 3/3\nf 1/1 3/3 4/4\n';

/// An ASCII FBX 7.4 quad (Y up, centimetres) with two UV sets: the quad's
/// UVs and the same scaled by half.
const fbxQuad = '''; FBX 7.4.0 project file
FBXHeaderExtension:  {
	FBXHeaderVersion: 1003
	FBXVersion: 7400
}
GlobalSettings:  {
	Version: 1000
	Properties70:  {
		P: "UpAxis", "int", "Integer", "",1
		P: "UpAxisSign", "int", "Integer", "",1
		P: "FrontAxis", "int", "Integer", "",2
		P: "FrontAxisSign", "int", "Integer", "",1
		P: "CoordAxis", "int", "Integer", "",0
		P: "CoordAxisSign", "int", "Integer", "",1
		P: "UnitScaleFactor", "double", "Number", "",100
	}
}
Objects:  {
	Geometry: 1000, "Geometry::Quad", "Mesh" {
		Vertices: *12 {
			a: -1,0,0,1,0,0,1,2,0,-1,2,0
		}
		PolygonVertexIndex: *4 {
			a: 0,1,2,-4
		}
		GeometryVersion: 124
		LayerElementUV: 0 {
			Version: 101
			Name: "UVMap"
			MappingInformationType: "ByPolygonVertex"
			ReferenceInformationType: "IndexToDirect"
			UV: *8 {
				a: 0,0,1,0,1,1,0,1
			}
			UVIndex: *4 {
				a: 0,1,2,3
			}
		}
		LayerElementUV: 1 {
			Version: 101
			Name: "Lightmap"
			MappingInformationType: "ByPolygonVertex"
			ReferenceInformationType: "IndexToDirect"
			UV: *8 {
				a: 0,0,0.5,0,0.5,0.5,0,0.5
			}
			UVIndex: *4 {
				a: 0,1,2,3
			}
		}
		LayerElementMaterial: 0 {
			Version: 101
			Name: ""
			MappingInformationType: "AllSame"
			ReferenceInformationType: "IndexToDirect"
			Materials: *1 {
				a: 0
			}
		}
		Layer: 0 {
			Version: 100
			LayerElement:  {
				Type: "LayerElementUV"
				TypedIndex: 0
			}
			LayerElement:  {
				Type: "LayerElementMaterial"
				TypedIndex: 0
			}
		}
		Layer: 1 {
			Version: 100
			LayerElement:  {
				Type: "LayerElementUV"
				TypedIndex: 1
			}
		}
	}
	Model: 2000, "Model::Quad", "Mesh" {
		Version: 232
		Properties70:  {
		}
		Shading: T
		Culling: "CullingOff"
	}
	Material: 3000, "Material::Crate", "" {
		Version: 102
		ShadingModel: "lambert"
		MultiLayer: 0
		Properties70:  {
			P: "DiffuseColor", "Color", "", "A",1,1,1
		}
	}
}
Connections:  {
	C: "OO",2000,0
	C: "OO",1000,2000
	C: "OO",3000,2000
}
''';

/// A GLB of [corners] (two triangles) written by hand in glTF's convention:
/// the source's V-up `v` stored as `1 - v`.
Uint8List handBuiltGlb(List<(List<double>, List<double>)> corners) {
  final bin = ByteData(corners.length * 20 + 12);
  var o = 0;
  for (final (p, _) in corners) {
    for (final c in p) {
      bin.setFloat32(o, c, Endian.little);
      o += 4;
    }
  }
  for (final (_, uv) in corners) {
    bin.setFloat32(o, uv[0], Endian.little);
    bin.setFloat32(o + 4, 1 - uv[1], Endian.little);
    o += 8;
  }
  for (final i in [0, 1, 2, 0, 2, 3]) {
    bin.setUint16(o, i, Endian.little);
    o += 2;
  }
  final n = corners.length;
  final json = {
    'asset': {'version': '2.0'},
    'buffers': [
      {'byteLength': bin.lengthInBytes},
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': n * 12},
      {'buffer': 0, 'byteOffset': n * 12, 'byteLength': n * 8},
      {'buffer': 0, 'byteOffset': n * 20, 'byteLength': 12},
    ],
    'accessors': [
      {'bufferView': 0, 'componentType': 5126, 'count': n, 'type': 'VEC3'},
      {'bufferView': 1, 'componentType': 5126, 'count': n, 'type': 'VEC2'},
      {'bufferView': 2, 'componentType': 5123, 'count': 6, 'type': 'SCALAR'},
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0, 'TEXCOORD_0': 1},
            'indices': 2,
          },
        ],
      },
    ],
    'nodes': [
      {'mesh': 0},
    ],
    'scenes': [
      {
        'nodes': [0],
      },
    ],
  };
  var jsonBytes = utf8.encode(jsonEncode(json));
  jsonBytes = Uint8List.fromList([
    ...jsonBytes,
    ...List.filled((4 - jsonBytes.length % 4) % 4, 0x20),
  ]);
  final total = 12 + 8 + jsonBytes.length + 8 + bin.lengthInBytes;
  final head = ByteData(12)
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, total, Endian.little);
  ByteData chunkHead(int length, int type) => ByteData(8)
    ..setUint32(0, length, Endian.little)
    ..setUint32(4, type, Endian.little);
  return Uint8List.fromList([
    ...head.buffer.asUint8List(),
    ...chunkHead(jsonBytes.length, 0x4E4F534A).buffer.asUint8List(),
    ...jsonBytes,
    ...chunkHead(bin.lengthInBytes, 0x004E4942).buffer.asUint8List(),
    ...bin.buffer.asUint8List(),
  ]);
}

/// `TEXCOORD_<set>` of every vertex in [glb], keyed by its corner of the
/// mesh's bounding box (`"0,1,0"` = min x, max y, min z).
Map<String, List<double>> texcoordsByPosition(Uint8List glb, {int set = 0}) {
  final data = ByteData.sublistView(glb);
  final jsonLength = data.getUint32(12, Endian.little);
  final json =
      jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
          as Map<String, dynamic>;
  final binStart = 20 + jsonLength + 8;

  List<List<double>> read(int accessorIndex) {
    final acc = (json['accessors'] as List)[accessorIndex] as Map;
    final view = (json['bufferViews'] as List)[acc['bufferView'] as int] as Map;
    final width = acc['type'] == 'VEC3' ? 3 : 2;
    final stride = (view['byteStride'] as int?) ?? width * 4;
    final start =
        binStart +
        ((view['byteOffset'] as int?) ?? 0) +
        ((acc['byteOffset'] as int?) ?? 0);
    return [
      for (var i = 0; i < (acc['count'] as int); i++)
        [
          for (var c = 0; c < width; c++)
            data.getFloat32(start + i * stride + c * 4, Endian.little),
        ],
    ];
  }

  final out = <String, List<double>>{};
  for (final mesh in json['meshes'] as List) {
    for (final p in (mesh as Map)['primitives'] as List) {
      final attributes = (p as Map)['attributes'] as Map;
      final positions = read(attributes['POSITION'] as int);
      final uvs = read(attributes['TEXCOORD_$set'] as int);
      // Keyed by the corner within the bounding box, so a unit scale baked
      // into the vertices does not change the key.
      final lo = [
        for (var c = 0; c < 3; c++)
          positions.map((q) => q[c]).reduce((a, b) => a < b ? a : b),
      ];
      final hi = [
        for (var c = 0; c < 3; c++)
          positions.map((q) => q[c]).reduce((a, b) => a > b ? a : b),
      ];
      for (var i = 0; i < positions.length; i++) {
        final key = [
          for (var c = 0; c < 3; c++)
            hi[c] - lo[c] < 1e-9
                ? 0
                : ((positions[i][c] - lo[c]) / (hi[c] - lo[c])).round(),
        ].join(',');
        out[key] = uvs[i];
      }
    }
  }
  return out;
}
