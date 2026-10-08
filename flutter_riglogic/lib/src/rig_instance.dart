import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_riglogic/src/bindings.dart';
import 'package:flutter_riglogic/src/rig_logic.dart';

/// An instance of a rig driven by [RigLogic], containing runtime state, control inputs,
/// and calculated joint transforms and blend shape outputs.
class RigInstance {
  final Pointer<RlRigInstance> _handle;
  bool _isDisposed = false;

  RigInstance._(this._handle);

  /// The native instance. Throws [StateError] after [dispose].
  Pointer<RlRigInstance> get handle {
    if (_isDisposed) {
      throw StateError('RigInstance is already disposed');
    }
    return _handle;
  }

  /// Creates an instance of [rigLogic]'s rig with all controls at zero.
  ///
  /// Throws [UnsupportedError] when the native library is not loaded.
  factory RigInstance.create(RigLogic rigLogic) {
    final bindings = RigLogicBindings.instance;
    if (!bindings.isAvailable) {
      throw UnsupportedError('RigLogic native library is not available');
    }
    final handle = bindings.rigInstanceCreate(rigLogic.handle);
    if (handle == nullptr) {
      throw StateError('Failed to create RigInstance');
    }
    return RigInstance._(handle);
  }

  /// The number of raw controls (`DnaReader.rawControlCount`).
  int get rawControlCount =>
      RigLogicBindings.instance.rigInstanceGetRawControlCount(handle);

  /// The value of raw control [index].
  double getRawControl(int index) =>
      RigLogicBindings.instance.rigInstanceGetRawControl(handle, index);

  /// Sets raw control [index] to [value] (usually 0 to 1); takes effect on
  /// the next [RigLogic.calculate].
  void setRawControl(int index, double value) {
    RigLogicBindings.instance.rigInstanceSetRawControl(handle, index, value);
  }

  /// The level of detail evaluated (0 is the most detailed).
  int get lod => RigLogicBindings.instance.rigInstanceGetLod(handle);

  set lod(int value) =>
      RigLogicBindings.instance.rigInstanceSetLod(handle, value);

  /// The joint outputs of the last [RigLogic.calculate]: per joint, the
  /// translation, rotation and scale values OpenRigLogic computes.
  List<double> getJointOutputs() {
    final bindings = RigLogicBindings.instance;
    final ptrPtr = calloc<Pointer<Float>>();
    try {
      final count = bindings.rigInstanceGetJointOutputs(handle, ptrPtr);
      final ptr = ptrPtr.value;
      if (count == 0 || ptr == nullptr) {
        return const [];
      }
      final list = List<double>.filled(count, 0.0);
      for (int i = 0; i < count; i++) {
        list[i] = ptr[i];
      }
      return list;
    } finally {
      calloc.free(ptrPtr);
    }
  }

  /// The blend shape channel weights of the last [RigLogic.calculate], one per
  /// `DnaReader.getBlendShapeChannelName`.
  List<double> getBlendShapeOutputs() {
    final bindings = RigLogicBindings.instance;
    final ptrPtr = calloc<Pointer<Float>>();
    try {
      final count = bindings.rigInstanceGetBlendShapeOutputs(handle, ptrPtr);
      final ptr = ptrPtr.value;
      if (count == 0 || ptr == nullptr) {
        return const [];
      }
      final list = List<double>.filled(count, 0.0);
      for (int i = 0; i < count; i++) {
        list[i] = ptr[i];
      }
      return list;
    } finally {
      calloc.free(ptrPtr);
    }
  }

  /// The animated map values of the last [RigLogic.calculate], one per
  /// `DnaReader.getAnimatedMapName`.
  List<double> getAnimatedMapOutputs() {
    final bindings = RigLogicBindings.instance;
    final ptrPtr = calloc<Pointer<Float>>();
    try {
      final count = bindings.rigInstanceGetAnimatedMapOutputs(handle, ptrPtr);
      final ptr = ptrPtr.value;
      if (count == 0 || ptr == nullptr) {
        return const [];
      }
      final list = List<double>.filled(count, 0.0);
      for (int i = 0; i < count; i++) {
        list[i] = ptr[i];
      }
      return list;
    } finally {
      calloc.free(ptrPtr);
    }
  }

  /// Releases the native instance.
  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      RigLogicBindings.instance.rigInstanceDestroy(_handle);
    }
  }
}
