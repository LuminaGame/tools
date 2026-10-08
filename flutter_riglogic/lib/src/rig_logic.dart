import 'dart:ffi';
import 'package:flutter_riglogic/src/bindings.dart';
import 'package:flutter_riglogic/src/dna_reader.dart';
import 'package:flutter_riglogic/src/rig_instance.dart';

/// Evaluates MetaHuman facial rigs using machine-learned behavior,
/// PSDs (Pose-Space Deformers), and RBFs.
class RigLogic {
  final Pointer<RlRigLogic> _handle;
  bool _isDisposed = false;

  RigLogic._(this._handle);

  /// The native evaluator. Throws [StateError] after [dispose].
  Pointer<RlRigLogic> get handle {
    if (_isDisposed) {
      throw StateError('RigLogic is already disposed');
    }
    return _handle;
  }

  /// Builds the evaluator from the rig definition and behaviour in [reader].
  ///
  /// Throws [UnsupportedError] when the native library is not loaded.
  factory RigLogic.create(DnaReader reader) {
    final bindings = RigLogicBindings.instance;
    if (!bindings.isAvailable) {
      throw UnsupportedError('RigLogic native library is not available');
    }
    final handle = bindings.rigLogicCreate(reader.handle);
    if (handle == nullptr) {
      throw StateError('Failed to create RigLogic from DNA reader');
    }
    return RigLogic._(handle);
  }

  /// Evaluates the rig for [instance]'s current controls and LOD, filling its
  /// joint, blend shape and animated map outputs.
  void calculate(RigInstance instance) {
    RigLogicBindings.instance.rigLogicCalculate(handle, instance.handle);
  }

  /// Releases the native evaluator. Dispose its [RigInstance]s first.
  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      RigLogicBindings.instance.rigLogicDestroy(_handle);
    }
  }
}
