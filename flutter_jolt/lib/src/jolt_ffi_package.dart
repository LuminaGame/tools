/// `package:ffi` on native platforms; its web counterpart over the
/// WebAssembly module's heap on the web.
library;

export 'package:ffi/ffi.dart' if (dart.library.js_interop) 'package:flutter_jolt/src/web_ffi/package_ffi.dart';
