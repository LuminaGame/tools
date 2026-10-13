/// The test API flutter_jolt's tests use: `package:flutter_test` natively,
/// and in the browser a small runner of the same functions
/// ([web_test_shim.dart]), so the same test files run against the
/// WebAssembly module (test/web/browser_main.dart).
library;

export 'package:flutter_test/flutter_test.dart' if (dart.library.js_interop) 'web_test_shim.dart';
