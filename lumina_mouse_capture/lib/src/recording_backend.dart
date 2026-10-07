import 'dart:async';
import 'dart:ui' show Offset;

import 'package:lumina_mouse_capture/src/mouse_capture_backend.dart';

/// A backend that never touches the pointer: it records what was asked, and
/// [emitMotion] / [emitLost] drive the same event path the native side does.
///
/// Every test and smoke runs on this one, so no run can
/// lock, grab or warp the pointer of the person working at the machine.
class RecordingMouseCaptureBackend implements MouseCaptureBackend {
  RecordingMouseCaptureBackend({this.simulateLock = false});

  /// Behave like a real pointer lock: [support] reports a lock with relative
  /// motion, and each capture is confirmed with [MouseCaptureLocked]. False is
  /// the hidden-cursor fallback of a platform without a lock.
  final bool simulateLock;

  /// Every request, in order: `capture(640.0,360.0)`, `capture()`, `release`.
  final List<String> requests = [];

  /// The centre of the last capture request.
  Offset? lastCentre;

  bool _captured = false;

  /// Whether a capture is in force (requested and not released or lost).
  bool get isCaptured => _captured;

  final StreamController<MouseCaptureEvent> _events = StreamController<MouseCaptureEvent>.broadcast();

  @override
  Stream<MouseCaptureEvent> get events => _events.stream;

  @override
  Future<MouseCaptureSupport> support() async => MouseCaptureSupport(
        kind: MouseCaptureBackendKind.recording,
        pointerLock: simulateLock,
        relativeMotion: simulateLock,
        detail: simulateLock ? 'recording (simulated lock)' : 'recording',
      );

  @override
  Future<bool> capture({Offset? centre}) async {
    requests.add(centre == null ? 'capture()' : 'capture(${centre.dx},${centre.dy})');
    lastCentre = centre;
    _captured = true;
    if (simulateLock) _events.add(const MouseCaptureLocked());
    return true;
  }

  @override
  Future<void> release() async {
    requests.add('release');
    _captured = false;
  }

  /// Reports a relative movement, as the compositor would.
  void emitMotion(double dx, double dy) => _events.add(MouseCaptureMotion(dx, dy));

  /// Reports that the capture was taken away (focus loss, Alt+Tab), with the
  /// platform's [reason] when it gives one.
  void emitLost([String? reason]) {
    _captured = false;
    _events.add(MouseCaptureLost(reason));
  }
}
