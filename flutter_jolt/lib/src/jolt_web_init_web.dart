import 'package:flutter_jolt/src/jolt_bindings.web.g.dart' show $registerJoltBindings;
import 'package:flutter_jolt/src/web_ffi/module.dart';

bool _registered = false;

/// Registers the generated struct layouts and native addresses, then loads
/// the WebAssembly module (`flutter_jolt.js` + `.wasm` from [moduleUrl]'s
/// directory). Idempotent.
Future<void> loadJoltModule(String moduleUrl) async {
  if (!_registered) {
    _registered = true;
    $registerJoltBindings();
  }
  await FlutterJoltModule.load(scriptUrl: moduleUrl);
}

/// Whether this is a web build.
const bool joltIsWeb = true;
