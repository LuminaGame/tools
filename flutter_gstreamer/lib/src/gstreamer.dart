import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'package:flutter_gstreamer/src/bindings/gstreamer.g.dart';
import 'package:flutter_gstreamer/src/exceptions.dart';
import 'package:flutter_gstreamer/src/libraries.dart';

/// The GStreamer version the loaded library reports (`gst_version`).
typedef GStreamerVersion = ({int major, int minor, int micro, int nano});

/// Entry point: loads and initialises GStreamer once per isolate.
///
/// ```dart
/// final gst = GStreamer.init();           // throws GStreamerNotFoundException
/// print(gst.versionString);               // GStreamer 1.28.6
/// if (!GStreamer.isAvailable()) { ... }   // non-throwing probe
/// ```
final class GStreamer {
  GStreamer._(this.libraries) : bindings = libraries.bindings;

  static GStreamer? _instance;
  static String? _instanceRoot;

  /// The opened libraries (install root, file paths, symbol lookup).
  final GStreamerLibraries libraries;

  /// The raw ffigen bindings (`package:flutter_gstreamer/bindings.dart` has
  /// the struct / constant types) for anything the Dart API does not wrap.
  final GStreamerBindings bindings;

  /// Whether [init] has succeeded in this isolate.
  static bool get isInitialized => _instance != null;

  /// The initialised instance; initialises with the default lookup on first
  /// use (and so may throw what [init] throws).
  static GStreamer get instance => _instance ?? init();

  /// Loads GStreamer (see [GStreamerLibraries.open] for where it is looked
  /// for, [root] restricts the search to one install) and runs
  /// `gst_init_check` + `gst_pb_utils_init`. Idempotent: later calls return
  /// the same instance; asking for a different [root] than the one loaded
  /// throws a [StateError].
  ///
  /// Throws [GStreamerNotFoundException] when GStreamer cannot be loaded and
  /// [GStreamerException] when it loads but fails to initialise. A failure
  /// caches nothing, so a later call may succeed.
  static GStreamer init({String? root}) {
    final existing = _instance;
    if (existing != null) {
      if (root != null && root != _instanceRoot) {
        throw StateError(
          'GStreamer is already loaded from ${existing.libraries.root ?? 'the system'}; '
          'it cannot be reloaded from $root in the same isolate.',
        );
      }
      return existing;
    }
    final libraries = GStreamerLibraries.open(root: root);
    final gst = GStreamer._(libraries);
    final b = gst.bindings;
    try {
      using((arena) {
        final err = arena<ffi.Pointer<GError>>();
        if (b.gst_init_check(ffi.nullptr, ffi.nullptr, err) == 0) {
          throw GStreamerException(
            'gst_init_check failed: ${takeError(b, err.value) ?? 'unknown error'}',
          );
        }
      });
    } on ArgumentError catch (e) {
      throw GStreamerNotFoundException(
        'The libraries at ${libraries.root} are not GStreamer 1.x.',
        searched: libraries.paths,
        cause: e,
      );
    }
    b.gst_pb_utils_init();
    _instanceRoot = root;
    return _instance = gst;
  }

  /// Whether GStreamer can be loaded and initialised; never throws.
  static bool isAvailable({String? root}) {
    try {
      init(root: root);
      return true;
    } on GStreamerNotFoundException {
      return false;
    } on GStreamerException {
      return false;
    } on StateError {
      return false;
    }
  }

  /// `gst_version`.
  GStreamerVersion get version => using((arena) {
    final v = arena<ffi.UnsignedInt>(4);
    bindings.gst_version(v, v + 1, v + 2, v + 3);
    return (major: v[0], minor: v[1], micro: v[2], nano: v[3]);
  });

  /// `gst_version_string`, e.g. `GStreamer 1.28.6`.
  String get versionString {
    final s = bindings.gst_version_string();
    try {
      return s.cast<Utf8>().toDartString();
    } finally {
      bindings.g_free(s.cast());
    }
  }

  /// Whether an element factory (e.g. `vp8enc`) is registered, i.e. its
  /// plugin is installed and was found.
  bool hasElement(String factoryName) => using((arena) {
    final factory = bindings.gst_element_factory_find(
      factoryName.toNativeUtf8(allocator: arena).cast(),
    );
    if (factory == ffi.nullptr) return false;
    bindings.gst_object_unref(factory.cast());
    return true;
  });

  /// The entries of [factoryNames] that [hasElement] does not find.
  List<String> missingElements(Iterable<String> factoryNames) => [
    for (final name in factoryNames)
      if (!hasElement(name)) name,
  ];

  /// Throws a [GStreamerException] naming the missing elements of
  /// [factoryNames] and where plugins were looked for.
  void requireElements(Iterable<String> factoryNames, {String? purpose}) {
    final missing = missingElements(factoryNames);
    if (missing.isEmpty) return;
    throw GStreamerException(
      'GStreamer ${version.major}.${version.minor}.${version.micro} at ${libraries.root ?? 'the system'} '
      'is missing the element(s) ${missing.join(', ')}${purpose == null ? '' : ' needed for $purpose'}. '
      'Install the plugin set that provides them (vp8enc: plugins-good/vpx, webmmux: plugins-good/matroska, '
      'pngdec: plugins-good/png, appsrc/videoconvert: plugins-base).',
    );
  }
}

/// Reads and frees a `GError*` (null → null).
String? takeError(GStreamerBindings b, ffi.Pointer<GError> error) {
  if (error == ffi.nullptr) return null;
  try {
    final message = error.ref.message;
    return message == ffi.nullptr
        ? 'unknown error'
        : message.cast<Utf8>().toDartString();
  } finally {
    b.g_error_free(error);
  }
}

/// Reads and `g_free`s a GLib-allocated string (null → null).
String? takeString(GStreamerBindings b, ffi.Pointer<ffi.Char> s) {
  if (s == ffi.nullptr) return null;
  try {
    return s.cast<Utf8>().toDartString();
  } finally {
    b.g_free(s.cast());
  }
}
