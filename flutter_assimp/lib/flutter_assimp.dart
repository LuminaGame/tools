import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_assimp/src/assimp_bindings.dart';

export 'package:flutter_assimp/src/assimp_bindings.dart'
    show AssimpBindings, AssimpConvertOptions;

/// Result of [FlutterAssimp.convertFileForImport]: the GLB and the bridge's
/// report of what it did to get there.
class AssimpImportConversion {
  /// The binary glTF, or null when the conversion failed.
  final Uint8List? glb;

  /// The bridge report (`assimp_get_last_report`): `source_metadata`,
  /// `normalized`, `unit_scale`, `up_axis`, `front_axis`, `axis_rows`,
  /// `collision` (removed hulls: name, shape, points in metres and
  /// `triangles` — indices into the points, 3 per face), `takes` (name,
  /// channels, duration_seconds — in the order their per-channel glTF
  /// animations were written), `meshes`, `skinned_meshes`, `materials`,
  /// `material_details` (per material, in the GLB's order: `name`,
  /// `shading_model`, the colours `diffuse`/`emissive`/`specular`/… as Assimp
  /// read them, `shininess`, `shininess_strength`, `opacity`, `reflectivity`,
  /// raw PBR values when the source has them, and `textures` — `type`,
  /// `path` as written in the source, `embedded`, `uv`), `nodes`.
  final Map<String, dynamic> report;

  /// Why the conversion failed.
  final String? error;

  const AssimpImportConversion({this.glb, this.report = const {}, this.error});

  bool get success => glb != null;
}

/// High-performance native Assimp 3D asset conversion bridge for Dart & Flutter.
class FlutterAssimp {
  static final AssimpBindings _bindings = AssimpBindings.instance;
  static final math.Random _scratchRandom = math.Random.secure();

  /// Returns true if the native Assimp library is loaded and available.
  static bool get isAvailable => _bindings.isAvailable;

  /// The linked Assimp's version: `"major.minor (commit <git hash>)"`, e.g.
  /// `"5.0 (commit 4673545f)"`.
  static String get version => _bindings.getVersion();

  /// Returns the last error message from native Assimp operations.
  static String get lastError => _bindings.getLastError();

  /// Converts a 3D model file on disk directly to a glTF 2.0 binary file (`.glb`).
  ///
  /// Reads the formats of [importExtensions].
  static Future<bool> convertFileToGlb(
    String inputPath,
    String outputPath, {
    int flags = 0,
  }) async {
    if (!File(inputPath).existsSync()) {
      return false;
    }

    if (_bindings.isAvailable) {
      final success = _bindings.convertFileToGlb(
        inputPath,
        outputPath,
        flags: flags,
      );
      if (success && File(outputPath).existsSync()) {
        return true;
      }
    }

    // CLI Tool Fallback if FFI dynamic link is not directly available
    try {
      final res = await Process.run('assimp', [
        'export',
        inputPath,
        outputPath,
      ]);
      return res.exitCode == 0 && File(outputPath).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Converts [inputPath] for the import pipeline: through the native bridge
  /// only (no CLI fallback), with [options] (default: bake units/axes into
  /// standard glTF and strip Unreal collision hulls), returning the GLB bytes
  /// together with the bridge's report.
  ///
  /// The conversion goes through a file next to nothing in the source folder:
  /// [scratchDir] (default: the system temp dir) receives the GLB, which is
  /// read back and deleted. Converting from the file (not from memory) lets
  /// Assimp resolve textures referenced relative to the source.
  static AssimpImportConversion convertFileForImport(
    String inputPath, {
    int options = AssimpConvertOptions.all,
    int flags = 0,
    Directory? scratchDir,
  }) {
    if (!File(inputPath).existsSync()) {
      return AssimpImportConversion(
        error: 'Source file does not exist: $inputPath',
      );
    }
    if (!_bindings.isAvailable) {
      return const AssimpImportConversion(
        error: 'The native Assimp bridge is not loaded',
      );
    }
    if (options != 0 && !_bindings.hasExtendedConversion) {
      return AssimpImportConversion(
        error:
            'The loaded Assimp bridge (${_bindings.librarySource}) predates normalized conversion; rebuild flutter_assimp',
      );
    }
    final dir = scratchDir ?? Directory.systemTemp;
    // Unique per call, also between isolates of one process converting at
    // the same microsecond (the time and the process id alone collide).
    final out = File(
      '${dir.path}/assimp_import_${DateTime.now().microsecondsSinceEpoch}_${pid}_'
      '${_scratchRandom.nextInt(0x7fffffff).toRadixString(36)}.glb',
    );
    try {
      // No await between the conversion and the report read: the report is
      // thread-local on the native side.
      final ok = _bindings.convertFileToGlb(
        inputPath,
        out.path,
        flags: flags,
        options: options,
      );
      final reportJson = options != 0 ? _bindings.getLastReport() : '{}';
      final error = ok ? null : _bindings.getLastError();
      Map<String, dynamic> report = const {};
      try {
        report = jsonDecode(reportJson) as Map<String, dynamic>;
      } catch (_) {}
      if (!ok || !out.existsSync()) {
        return AssimpImportConversion(
          report: report,
          error: error ?? 'Assimp wrote no GLB',
        );
      }
      return AssimpImportConversion(glb: out.readAsBytesSync(), report: report);
    } finally {
      if (out.existsSync()) out.deleteSync();
    }
  }

  /// Converts in-memory 3D model bytes directly into a glTF 2.0 binary (`.glb`) buffer.
  static Future<Uint8List?> convertMemoryToGlb(
    Uint8List inputBytes, {
    String hint = 'fbx',
    int flags = 0,
  }) async {
    if (inputBytes.isEmpty) return null;

    if (_bindings.isAvailable) {
      final glbBytes = _bindings.convertMemoryToGlb(
        inputBytes,
        hint: hint,
        flags: flags,
      );
      if (glbBytes != null && glbBytes.isNotEmpty) {
        return Uint8List.fromList(glbBytes);
      }
    }

    // Temp file fallback using CLI if memory conversion fails
    try {
      final tempDir = Directory.systemTemp;
      final tempIn = File(
        '${tempDir.path}/temp_in_${DateTime.now().microsecondsSinceEpoch}.$hint',
      );
      final tempOut = File(
        '${tempDir.path}/temp_out_${DateTime.now().microsecondsSinceEpoch}.glb',
      );
      await tempIn.writeAsBytes(inputBytes);

      final success = await convertFileToGlb(
        tempIn.path,
        tempOut.path,
        flags: flags,
      );
      Uint8List? result;
      if (success && tempOut.existsSync()) {
        result = await tempOut.readAsBytes();
      }

      if (tempIn.existsSync()) tempIn.deleteSync();
      if (tempOut.existsSync()) tempOut.deleteSync();

      return result;
    } catch (_) {
      return null;
    }
  }

  /// The formats this package builds the bridge to read, for when the
  /// bridge cannot be asked ([importExtensions]).
  static const Set<String> _builtInExtensions = {
    'fbx',
    'obj',
    'dae',
    'zae',
    '3ds',
    'prj',
    'ply',
    'x',
    'stl',
  };

  /// The lower-case file extensions (no dot) the loaded bridge imports: FBX
  /// and OBJ, plus Collada, 3DS, PLY, DirectX and STL when the Filament
  /// checkout the hook built from has their sources.
  static Set<String> get importExtensions => _importExtensions ??= () {
    final list = _bindings.getImportExtensions();
    if (list == null) return _builtInExtensions;
    return {
      for (final e in list.split(';'))
        if (e.trim().replaceFirst('*.', '').isNotEmpty)
          e.trim().replaceFirst('*.', '').toLowerCase(),
    };
  }();
  static Set<String>? _importExtensions;

  /// Whether [pathOrExtension] (a path, `.ext` or `ext`) is a 3D format the
  /// bridge imports ([importExtensions]).
  static bool isSupportedFormat(String pathOrExtension) {
    final ext = pathOrExtension.contains('.')
        ? pathOrExtension
              .substring(pathOrExtension.lastIndexOf('.') + 1)
              .toLowerCase()
        : pathOrExtension.toLowerCase();
    return importExtensions.contains(ext);
  }
}
