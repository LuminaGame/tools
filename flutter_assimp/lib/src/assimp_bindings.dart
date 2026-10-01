import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'third_party/assimp_c.g.dart' as native;

// Native function typedefs (dynamic-library fallback).
typedef _StringFnNative = Pointer<Char> Function();
typedef _StringFnDart = Pointer<Char> Function();

typedef _ConvertFileNative = Int32 Function(Pointer<Char>, Pointer<Char>, Uint32);
typedef _ConvertFileDart = int Function(Pointer<Char>, Pointer<Char>, int);

typedef _ConvertFileExNative = Int32 Function(Pointer<Char>, Pointer<Char>, Uint32, Uint32);
typedef _ConvertFileExDart = int Function(Pointer<Char>, Pointer<Char>, int, int);

typedef _ConvertMemoryNative = Int32 Function(
    Pointer<Uint8>, Size, Pointer<Char>, Pointer<Pointer<Uint8>>, Pointer<Size>, Uint32);
typedef _ConvertMemoryDart = int Function(
    Pointer<Uint8>, int, Pointer<Char>, Pointer<Pointer<Uint8>>, Pointer<Size>, int);

typedef _ConvertMemoryExNative = Int32 Function(
    Pointer<Uint8>, Size, Pointer<Char>, Pointer<Pointer<Uint8>>, Pointer<Size>, Uint32, Uint32);
typedef _ConvertMemoryExDart = int Function(
    Pointer<Uint8>, int, Pointer<Char>, Pointer<Pointer<Uint8>>, Pointer<Size>, int, int);

typedef _FreeBlobNative = Void Function(Pointer<Uint8>);
typedef _FreeBlobDart = void Function(Pointer<Uint8>);

/// Option bits of the `_ex` conversions (`ASSIMP_CONVERT_*` in
/// `src/assimp_bridge.h`).
abstract final class AssimpConvertOptions {
  /// Bake the source's unit scale and axis system (FBX GlobalSettings) into
  /// the scene: the GLB comes out in metres, +Y up, +Z front.
  static const int normalize = 1 << 0;

  /// Remove Unreal collision hulls (UCX_/UBX_/USP_/UCP_) and report them.
  static const int stripCollision = 1 << 1;

  static const int all = normalize | stripCollision;
}

/// Low-level access to the native bridge.
///
/// The library is the one the package's native-assets hook builds
/// (`hook/build.dart`, asset `src/third_party/assimp_c.g.dart`), resolved
/// through `@Native` bindings. Hosts that run without native assets fall back
/// to opening a prebuilt `libflutter_assimp` by path.
class AssimpBindings {
  static final AssimpBindings instance = AssimpBindings._init();

  bool _isAvailable = false;

  /// Whether the `_ex` conversions (normalization, collision stripping,
  /// report) exist in the loaded library. A prebuilt library older than them
  /// has only the plain conversions.
  bool _hasEx = false;

  /// Where the library came from: `native-assets` or the opened path.
  String _source = 'unavailable';

  late final _StringFnDart _getVersion;
  late final _StringFnDart _getLastError;
  late final _StringFnDart _getLastReport;
  _StringFnDart? _getImportExtensions;
  late final _ConvertFileDart _convertFileToGlb;
  late final _ConvertFileExDart _convertFileToGlbEx;
  late final _ConvertMemoryDart _convertMemoryToGlb;
  late final _ConvertMemoryExDart _convertMemoryToGlbEx;
  late final _FreeBlobDart _freeBlob;

  bool get isAvailable => _isAvailable;
  bool get hasExtendedConversion => _hasEx;
  String get librarySource => _source;

  AssimpBindings._init() {
    if (_bindNativeAssets()) return;
    _bindDynamicLibrary();
  }

  bool _bindNativeAssets() {
    try {
      native.assimp_get_version(); // throws when the asset is not bundled
    } catch (_) {
      return false;
    }
    _getVersion = () => native.assimp_get_version();
    _getLastError = () => native.assimp_get_last_error();
    _getLastReport = () => native.assimp_get_last_report();
    _getImportExtensions = () => native.assimp_get_import_extensions();
    _convertFileToGlb = (a, b, f) => native.assimp_convert_file_to_glb(a, b, f);
    _convertFileToGlbEx = (a, b, f, o) => native.assimp_convert_file_to_glb_ex(a, b, f, o);
    _convertMemoryToGlb = (a, n, h, ob, ol, f) => native.assimp_convert_memory_to_glb(a, n, h, ob, ol, f);
    _convertMemoryToGlbEx =
        (a, n, h, ob, ol, f, o) => native.assimp_convert_memory_to_glb_ex(a, n, h, ob, ol, f, o);
    _freeBlob = (p) => native.assimp_free_blob(p);
    _isAvailable = true;
    _hasEx = true;
    _source = 'native-assets';
    return true;
  }

  void _bindDynamicLibrary() {
    try {
      final (dylib, path) = _loadDynamicLibrary();
      _getVersion = dylib.lookupFunction<_StringFnNative, _StringFnDart>('assimp_get_version');
      _getLastError = dylib.lookupFunction<_StringFnNative, _StringFnDart>('assimp_get_last_error');
      _convertFileToGlb = dylib.lookupFunction<_ConvertFileNative, _ConvertFileDart>('assimp_convert_file_to_glb');
      _convertMemoryToGlb =
          dylib.lookupFunction<_ConvertMemoryNative, _ConvertMemoryDart>('assimp_convert_memory_to_glb');
      _freeBlob = dylib.lookupFunction<_FreeBlobNative, _FreeBlobDart>('assimp_free_blob');
      _isAvailable = true;
      _source = path;
      try {
        _getLastReport = dylib.lookupFunction<_StringFnNative, _StringFnDart>('assimp_get_last_report');
        _convertFileToGlbEx =
            dylib.lookupFunction<_ConvertFileExNative, _ConvertFileExDart>('assimp_convert_file_to_glb_ex');
        _convertMemoryToGlbEx =
            dylib.lookupFunction<_ConvertMemoryExNative, _ConvertMemoryExDart>('assimp_convert_memory_to_glb_ex');
        _hasEx = true;
      } catch (_) {
        _hasEx = false;
      }
      try {
        _getImportExtensions = dylib.lookupFunction<_StringFnNative, _StringFnDart>('assimp_get_import_extensions');
      } catch (_) {}
    } catch (e) {
      _isAvailable = false;
    }
  }

  static (DynamicLibrary, String) _loadDynamicLibrary() {
    final List<String> candidates;
    if (Platform.isLinux) {
      candidates = [
        'libflutter_assimp.so',
        'lib/libflutter_assimp.so',
        '../flutter_assimp/lib/libflutter_assimp.so',
        '../../flutter_assimp/lib/libflutter_assimp.so',
        'flutter_assimp/lib/libflutter_assimp.so',
        'flutter_assimp/build/libflutter_assimp.so',
        '/usr/lib/libassimp.so',
        '/usr/lib64/libassimp.so',
        '/usr/local/lib/libassimp.so',
      ];
    } else if (Platform.isMacOS) {
      candidates = [
        'libflutter_assimp.dylib',
        'libassimp.dylib',
        '/usr/local/lib/libassimp.dylib',
        '/opt/homebrew/lib/libassimp.dylib',
      ];
    } else if (Platform.isWindows) {
      candidates = ['flutter_assimp.dll', 'assimp.dll'];
    } else {
      candidates = const [];
    }
    for (final path in candidates) {
      try {
        return (DynamicLibrary.open(path), path);
      } catch (_) {}
    }
    return (DynamicLibrary.process(), 'process');
  }

  String getVersion() {
    if (!_isAvailable) return 'Assimp FFI Unavailable';
    return _getVersion().cast<Utf8>().toDartString();
  }

  String getLastError() {
    if (!_isAvailable) return 'Assimp FFI Unavailable';
    return _getLastError().cast<Utf8>().toDartString();
  }

  /// The extensions the loaded library imports (`"*.fbx;*.obj;…"`), or null
  /// when it is not loaded or predates the query.
  String? getImportExtensions() {
    final fn = _getImportExtensions;
    if (!_isAvailable || fn == null) return null;
    return fn().cast<Utf8>().toDartString();
  }

  /// The JSON report of this thread's last `_ex` conversion ("{}" if none).
  String getLastReport() {
    if (!_isAvailable || !_hasEx) return '{}';
    return _getLastReport().cast<Utf8>().toDartString();
  }

  bool convertFileToGlb(String inPath, String outPath, {int flags = 0, int options = 0}) {
    if (!_isAvailable) return false;
    if (options != 0 && !_hasEx) return false;
    final inPtr = inPath.toNativeUtf8().cast<Char>();
    final outPtr = outPath.toNativeUtf8().cast<Char>();
    try {
      final result = options == 0
          ? _convertFileToGlb(inPtr, outPtr, flags)
          : _convertFileToGlbEx(inPtr, outPtr, flags, options);
      return result == 1;
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }

  List<int>? convertMemoryToGlb(List<int> inBytes, {String hint = 'fbx', int flags = 0, int options = 0}) {
    if (!_isAvailable || inBytes.isEmpty) return null;
    if (options != 0 && !_hasEx) return null;

    final inLen = inBytes.length;
    final inPtr = calloc<Uint8>(inLen);
    inPtr.asTypedList(inLen).setAll(0, inBytes);

    final hintPtr = hint.toNativeUtf8().cast<Char>();
    final outBytesPtrPtr = calloc<Pointer<Uint8>>();
    final outLenPtr = calloc<Size>();

    try {
      final result = options == 0
          ? _convertMemoryToGlb(inPtr, inLen, hintPtr, outBytesPtrPtr, outLenPtr, flags)
          : _convertMemoryToGlbEx(inPtr, inLen, hintPtr, outBytesPtrPtr, outLenPtr, flags, options);
      if (result != 1) return null;

      final outLen = outLenPtr.value;
      final outBytesPtr = outBytesPtrPtr.value;
      if (outBytesPtr == nullptr || outLen == 0) return null;

      final resultBytes = List<int>.from(outBytesPtr.asTypedList(outLen));
      _freeBlob(outBytesPtr);
      return resultBytes;
    } finally {
      calloc.free(inPtr);
      calloc.free(hintPtr);
      calloc.free(outBytesPtrPtr);
      calloc.free(outLenPtr);
    }
  }
}
