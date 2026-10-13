import 'package:flutter_jolt/src/jolt_c.dart' as b;
import 'package:flutter_jolt/src/jolt_web_init.dart';

/// The native Jolt Physics library: whether this process has it, and its
/// version.
///
/// The native-assets hook builds the library only when a Jolt build exists
/// for the target (`tool/build_jolt.*`); without it every call into Jolt
/// would throw, so callers check [isAvailable] first and fall back. On the
/// web the library is a WebAssembly module (`tool/web/build_jolt_wasm.sh`)
/// that [ensureInitialized] loads; until then [isAvailable] is false.
abstract final class JoltPhysics {
  static bool? _available;
  static int _version = 0;

  /// Whether this is a web build (the WebAssembly module).
  static const bool isWeb = joltIsWeb;

  /// On the web, loads the WebAssembly module (`flutter_jolt.js` and
  /// `flutter_jolt.wasm` from [moduleUrl]'s directory) and registers the
  /// generated layouts; natively nothing (the library is linked). Afterwards
  /// [isAvailable] answers again. Idempotent.
  static Future<void> ensureInitialized({String moduleUrl = 'flutter_jolt.js'}) async {
    await loadJoltModule(moduleUrl);
    _available = null;
  }

  /// Whether the native library is loaded and answers.
  static bool get isAvailable {
    final known = _available;
    if (known != null) return known;
    try {
      _version = b.jolt_version();
      _available = _version > 0;
    } catch (_) {
      // ArgumentError (no code asset for this target) or a failed load.
      _available = false;
    }
    return _available!;
  }

  /// The Jolt release the library was built from, as `major.minor.patch`
  /// (empty when [isAvailable] is false).
  static String get version {
    if (!isAvailable) return '';
    return '${_version ~/ 10000}.${(_version ~/ 100) % 100}.${_version % 100}';
  }

  /// The id Jolt uses for "no body".
  static int get invalidBodyId => b.jolt_invalid_body_id();

  /// Throws a [StateError] naming the fix when [isAvailable] is false.
  static void ensureAvailable() {
    if (!isAvailable) {
      throw StateError(
        'The Jolt Physics native library is not available for this target. '
        'Build it with flutter_jolt/tool/build_jolt.bat (Windows) or '
        'tool/build_jolt.sh (Linux), or set the jolt_dir user-define.',
      );
    }
  }
}
