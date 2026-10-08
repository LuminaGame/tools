import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter_riglogic/src/bindings.dart';

/// Reads MetaHuman DNA files containing joint hierarchy, blend shape mappings,
/// and rig behavior parameters.
class DnaReader {
  final Pointer<RlDnaReader> _handle;
  bool _isDisposed = false;

  DnaReader._(this._handle);

  Pointer<RlDnaReader> get handle {
    if (_isDisposed) {
      throw StateError('DnaReader is already disposed');
    }
    return _handle;
  }

  /// Creates a [DnaReader] from a DNA file on disk.
  factory DnaReader.fromFile(String path) {
    final bindings = RigLogicBindings.instance;
    if (!bindings.isAvailable) {
      throw UnsupportedError('RigLogic native library is not available');
    }
    final file = File(path);
    if (!file.existsSync()) {
      throw ArgumentError('DNA file does not exist at: $path');
    }
    final absolutePath = file.absolute.path;
    final cPath = absolutePath.toNativeUtf8();
    try {
      final handle = bindings.dnaReaderCreateFromFile(cPath);
      if (handle == nullptr) {
        throw ArgumentError('Failed to read DNA file at: $absolutePath');
      }
      return DnaReader._(handle);
    } finally {
      malloc.free(cPath);
    }
  }

  /// Creates a [DnaReader] from an in-memory byte buffer.
  factory DnaReader.fromMemory(Uint8List bytes) {
    final bindings = RigLogicBindings.instance;
    if (!bindings.isAvailable) {
      throw UnsupportedError('RigLogic native library is not available');
    }
    final cBytes = malloc<Uint8>(bytes.length);
    cBytes.asTypedList(bytes.length).setAll(0, bytes);
    try {
      final handle = bindings.dnaReaderCreateFromMemory(cBytes, bytes.length);
      if (handle == nullptr) {
        throw ArgumentError('Failed to read DNA from memory buffer');
      }
      return DnaReader._(handle);
    } finally {
      malloc.free(cBytes);
    }
  }

  String get name =>
      RigLogicBindings.instance.dnaReaderGetName(handle).toDartString();

  int get lodCount => RigLogicBindings.instance.dnaReaderGetLodCount(handle);

  int get jointCount =>
      RigLogicBindings.instance.dnaReaderGetJointCount(handle);

  String getJointName(int index) {
    if (index < 0 || index >= jointCount) {
      throw RangeError.range(index, 0, jointCount - 1, 'index');
    }
    return RigLogicBindings.instance
        .dnaReaderGetJointName(handle, index)
        .toDartString();
  }

  int get blendShapeChannelCount =>
      RigLogicBindings.instance.dnaReaderGetBlendShapeChannelCount(handle);

  String getBlendShapeChannelName(int index) {
    if (index < 0 || index >= blendShapeChannelCount) {
      throw RangeError.range(index, 0, blendShapeChannelCount - 1, 'index');
    }
    return RigLogicBindings.instance
        .dnaReaderGetBlendShapeChannelName(handle, index)
        .toDartString();
  }

  int get rawControlCount =>
      RigLogicBindings.instance.dnaReaderGetRawControlCount(handle);

  String getRawControlName(int index) {
    if (index < 0 || index >= rawControlCount) {
      throw RangeError.range(index, 0, rawControlCount - 1, 'index');
    }
    return RigLogicBindings.instance
        .dnaReaderGetRawControlName(handle, index)
        .toDartString();
  }

  int get guiControlCount =>
      RigLogicBindings.instance.dnaReaderGetGuiControlCount(handle);

  String getGuiControlName(int index) {
    if (index < 0 || index >= guiControlCount) {
      throw RangeError.range(index, 0, guiControlCount - 1, 'index');
    }
    return RigLogicBindings.instance
        .dnaReaderGetGuiControlName(handle, index)
        .toDartString();
  }

  int get animatedMapCount =>
      RigLogicBindings.instance.dnaReaderGetAnimatedMapCount(handle);

  String getAnimatedMapName(int index) {
    if (index < 0 || index >= animatedMapCount) {
      throw RangeError.range(index, 0, animatedMapCount - 1, 'index');
    }
    return RigLogicBindings.instance
        .dnaReaderGetAnimatedMapName(handle, index)
        .toDartString();
  }

  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      RigLogicBindings.instance.dnaReaderDestroy(_handle);
    }
  }
}
