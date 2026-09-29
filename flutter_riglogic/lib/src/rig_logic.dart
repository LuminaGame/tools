import 'dart:ffi';
import 'bindings.dart';
import 'dna_reader.dart';
import 'rig_instance.dart';

/// Evaluates MetaHuman facial rigs using machine-learned behavior,
/// PSDs (Pose-Space Deformers), and RBFs.
class RigLogic {
  final Pointer<RlRigLogic> _handle;
  bool _isDisposed = false;

  RigLogic._(this._handle);

  Pointer<RlRigLogic> get handle {
    if (_isDisposed) {
      throw StateError('RigLogic is already disposed');
    }
    return _handle;
  }

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

  void calculate(RigInstance instance) {
    RigLogicBindings.instance.rigLogicCalculate(handle, instance.handle);
  }

  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      RigLogicBindings.instance.rigLogicDestroy(_handle);
    }
  }
}

