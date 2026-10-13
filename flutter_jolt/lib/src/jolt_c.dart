/// The C bindings: ffigen's `@Native` externals on native platforms, the
/// generated WebAssembly calls on the web (tool/ffigen_web.dart).
library;

export 'package:flutter_jolt/src/jolt_bindings.g.dart'
    if (dart.library.js_interop) 'package:flutter_jolt/src/jolt_bindings.web.g.dart';
