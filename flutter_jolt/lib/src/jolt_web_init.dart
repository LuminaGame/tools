/// Loading the WebAssembly module on the web; nothing natively.
library;

export 'package:flutter_jolt/src/jolt_web_init_native.dart'
    if (dart.library.js_interop) 'package:flutter_jolt/src/jolt_web_init_web.dart';
