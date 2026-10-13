/// `dart:ffi` on native platforms; the WebAssembly-backed layer on the web.
/// flutter_jolt's wrappers import this instead of `dart:ffi`.
library;

export 'dart:ffi' if (dart.library.js_interop) 'package:flutter_jolt/src/web_ffi/ffi.dart';
