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

  Pointer<RlRigInstance> get handle {
    if (_isDisposed) {
      throw StateError('RigInstance is already disposed');
    }
    return _handle;
  }

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

  int get rawControlCount =>
      RigLogicBindings.instance.rigInstanceGetRawControlCount(handle);

  double getRawControl(int index) =>
      RigLogicBindings.instance.rigInstanceGetRawControl(handle, index);

  void setRawControl(int index, double value) {
    RigLogicBindings.instance.rigInstanceSetRawControl(handle, index, value);
  }

  int get lod => RigLogicBindings.instance.rigInstanceGetLod(handle);

  set lod(int value) =>
      RigLogicBindings.instance.rigInstanceSetLod(handle, value);

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

  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      RigLogicBindings.instance.rigInstanceDestroy(_handle);
    }
  }
}
