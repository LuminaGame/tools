import 'dart:ui' show Offset;

/// Which implementation answers a [MouseCaptureBackend].
enum MouseCaptureBackendKind {
  /// Wayland pointer constraints + relative pointer on GDK's connection.
  wayland,

  /// An X11 seat grab with warp-to-centre.
  x11,

  /// Windows raw mouse input, with the cursor hidden and clipped to the
  /// capture centre.
  windows,

  /// The platform has no way to capture the pointer (or the plugin is not
  /// built into this app).
  unsupported,

  /// The native side refused: `LUMINA_MOUSE_CAPTURE` is `off` or `record`.
  disabled,

  /// [RecordingMouseCaptureBackend]: requests are recorded, the pointer is
  /// never touched.
  recording,
}

/// What a backend can do.
class MouseCaptureSupport {
  const MouseCaptureSupport({
    required this.kind,
    this.pointerLock = false,
    this.relativeMotion = false,
    this.detail = '',
  });

  final MouseCaptureBackendKind kind;

  /// Whether a capture really holds the pointer: it cannot leave the window,
  /// and clicks land wherever it was held (so the host must shield its UI).
  final bool pointerLock;

  /// Whether [MouseCaptureMotion] events carry the mouse's movement. When
  /// false, the host reads deltas from its own pointer events.
  final bool relativeMotion;

  /// Why, in words: the protocols found, or what was missing.
  final String detail;

  static const MouseCaptureSupport none = MouseCaptureSupport(kind: MouseCaptureBackendKind.unsupported);

  @override
  String toString() =>
      'MouseCaptureSupport(${kind.name}, lock: $pointerLock, relative: $relativeMotion${detail.isEmpty ? '' : ', $detail'})';
}

/// Something the capture reported.
sealed class MouseCaptureEvent {
  const MouseCaptureEvent();
}

/// The mouse moved by ([dx], [dy]) logical pixels while captured, however far
/// the (held) pointer is from any edge.
final class MouseCaptureMotion extends MouseCaptureEvent {
  const MouseCaptureMotion(this.dx, this.dy);

  final double dx;
  final double dy;

  @override
  bool operator ==(Object other) => other is MouseCaptureMotion && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'MouseCaptureMotion(${dx.toDouble()}, ${dy.toDouble()})';
}

/// The platform confirmed the lock (Wayland's `locked` event).
final class MouseCaptureLocked extends MouseCaptureEvent {
  const MouseCaptureLocked();

  @override
  bool operator ==(Object other) => other is MouseCaptureLocked;

  @override
  int get hashCode => (MouseCaptureLocked).hashCode;

  @override
  String toString() => 'MouseCaptureLocked()';
}

/// The capture ended without being asked: the window lost focus, the
/// compositor broke the lock, or the window went away.
final class MouseCaptureLost extends MouseCaptureEvent {
  const MouseCaptureLost([this.reason]);

  /// Why, when the platform says: `focus` (another window was activated),
  /// `minimized` or `window` (the window went away). Null when the platform
  /// gives no reason (Linux).
  final String? reason;

  @override
  bool operator ==(Object other) => other is MouseCaptureLost && other.reason == reason;

  @override
  int get hashCode => Object.hash(MouseCaptureLost, reason);

  @override
  String toString() => 'MouseCaptureLost(${reason ?? ''})';
}

/// Captures the pointer for a game: hidden, held in place, reporting motion.
abstract class MouseCaptureBackend {
  /// What this backend can do on this machine.
  Future<MouseCaptureSupport> support();

  /// Captures the pointer. [centre] is in the Flutter view's logical
  /// coordinates: on X11 the pointer is warped there, on Wayland it is where
  /// the pointer reappears when released, on Windows the cursor is held there
  /// (and returns to where it was on release). Returns whether a capture was
  /// requested.
  Future<bool> capture({Offset? centre});

  /// Releases the pointer; a no-op when not captured.
  Future<void> release();

  /// Motion, lock confirmations and losses.
  Stream<MouseCaptureEvent> get events;
}
