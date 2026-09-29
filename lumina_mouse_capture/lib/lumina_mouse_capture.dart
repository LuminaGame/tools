/// Pointer capture for Lumina.
///
/// While a game owns the mouse the pointer is hidden and held in place, and
/// the mouse keeps reporting how far it moved: Wayland pointer constraints +
/// relative pointer, or an X11 grab with warp-to-centre. Everything goes
/// through [LuminaMouseCapture.backend], which is a
/// [RecordingMouseCaptureBackend] in every test, smoke and harness run.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import 'src/environment_stub.dart' if (dart.library.io) 'src/environment_io.dart';
import 'src/method_channel_backend.dart';
import 'src/mouse_capture_backend.dart';
import 'src/recording_backend.dart';

export 'src/method_channel_backend.dart';
export 'src/mouse_capture_backend.dart';
export 'src/recording_backend.dart';

/// Which backend [LuminaMouseCapture.chooseDefault] picked, and why.
class MouseCaptureBackendChoice {
  const MouseCaptureBackendChoice._(this.reason, this._platform);

  /// `test binding`, `LUMINA_MOUSE_CAPTURE=off`, `web`, `not Linux` or
  /// `platform channel`.
  final String reason;
  final bool _platform;

  /// Whether the choice is the real platform backend.
  bool get usesPlatform => _platform;

  /// A fresh backend of the chosen kind.
  MouseCaptureBackend createBackend() =>
      _platform ? MethodChannelMouseCaptureBackend() : RecordingMouseCaptureBackend();
}

/// The process-wide mouse-capture seam.
abstract final class LuminaMouseCapture {
  /// Set to `off` (or `record`) to keep every capture away from the pointer.
  /// The test harnesses export it; the native plugin checks it too.
  static const String environmentVariable = 'LUMINA_MOUSE_CAPTURE';

  static MouseCaptureBackend? _backend;
  static MouseCaptureBackendChoice? _choice;

  /// The backend every caller uses. Assign one to replace it (tests install a
  /// [RecordingMouseCaptureBackend] with the options they need).
  static MouseCaptureBackend get backend {
    final existing = _backend;
    if (existing != null) return existing;
    final choice = _choice = chooseDefault();
    final created = _backend = choice.createBackend();
    // A hot restart forgets the Dart side of a capture while the native side
    // still holds the pointer: the first backend of a run lets go of it.
    if (choice.usesPlatform) unawaited(created.release());
    return created;
  }

  static set backend(MouseCaptureBackend value) {
    _backend = value;
    _choice = null;
  }

  /// Why the default backend was chosen, or null when one was assigned.
  static String? get defaultBackendReason => _choice?.reason;

  /// The default backend's rule:
  /// - `LUMINA_MOUSE_CAPTURE=off|record` → recording;
  /// - a test binding (`flutter test`, `integration_test`) → recording;
  /// - the web, or not Linux → recording (nothing to capture with);
  /// - otherwise the platform channel.
  static MouseCaptureBackendChoice chooseDefault({
    Map<String, String>? environment,
    bool? isTestBinding,
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
  }) {
    final env = environment ?? processEnvironment();
    final value = env[environmentVariable]?.trim().toLowerCase();
    if (value == 'off' || value == 'record') {
      return MouseCaptureBackendChoice._('$environmentVariable=$value', false);
    }
    if (isTestBinding ?? _runningUnderTestBinding()) {
      return const MouseCaptureBackendChoice._('test binding', false);
    }
    if (isWeb) return const MouseCaptureBackendChoice._('web', false);
    if ((platform ?? defaultTargetPlatform) != TargetPlatform.linux) {
      return const MouseCaptureBackendChoice._('not Linux', false);
    }
    return const MouseCaptureBackendChoice._('platform channel', true);
  }

  /// flutter_test's bindings (`AutomatedTestWidgetsFlutterBinding`,
  /// `LiveTestWidgetsFlutterBinding`, `IntegrationTestWidgetsFlutterBinding`)
  /// all end in `TestWidgetsFlutterBinding`; the app's binding does not.
  static bool _runningUnderTestBinding() {
    try {
      return WidgetsBinding.instance.runtimeType.toString().endsWith('TestWidgetsFlutterBinding');
    } catch (_) {
      // No binding yet: not a widget test either.
      return false;
    }
  }
}
